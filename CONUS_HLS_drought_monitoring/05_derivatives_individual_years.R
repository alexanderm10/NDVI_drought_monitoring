# ==============================================================================
# PHASE 5: INDIVIDUAL YEAR DERIVATIVE ANALYSIS
# ==============================================================================
# Purpose: Calculate derivatives of year-specific GAMs to identify actual
#          timing of phenological transitions and detect anomalies vs baseline
# Input: conus_4km_ndvi_timeseries.csv (Phase 1) + year splines (Phase 4)
# Output: Year derivatives (pixel_id, year, yday, deriv_mean, deriv_lwr, deriv_upr, sig)
# ==============================================================================

library(mgcv)
library(dplyr)
library(parallel)

# Source configuration and utility functions
source("00_setup_paths.R")
source("00_gam_utility_functions.R")
hls_paths <- get_hls_paths()

cat("=== PHASE 5: INDIVIDUAL YEAR DERIVATIVE ANALYSIS ===\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Input files
  timeseries_file = file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.csv"),
  year_splines_file = file.path(hls_paths$gam_models, "conus_4km_year_splines.csv"),

  # Years to process
  target_years = 2013:2024,

  # Edge padding (must match Phase 4)
  edge_padding_days = 31,

  # GAM parameters (must match Phase 4)
  gam_knots = 12,
  gam_basis = "tp",  # Thin plate (not cyclic for padded data)

  # Derivative parameters
  n_posterior_sims = 1000,
  alpha_level = 0.05,

  # Output
  output_file = file.path(hls_paths$gam_models, "conus_4km_year_derivatives.csv"),
  derivatives_archive = file.path(hls_paths$gam_models, "derivatives", "individual_years"),

  # Quality control
  min_observations = 15,

  # Parallel processing
  n_cores = 1,

  # Checkpointing
  checkpoint_interval = 50,
  resume_from_checkpoint = TRUE
)

# Ensure output directories exist
ensure_directory(hls_paths$gam_models)
ensure_directory(config$derivatives_archive)

cat("Configuration:\n")
cat("  Years:", paste(range(config$target_years), collapse = "-"), "\n")
cat("  Edge padding:", config$edge_padding_days, "days\n")
cat("  Posterior simulations:", config$n_posterior_sims, "\n")
cat("  Output:", config$output_file, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Apply edge padding to year data (from Phase 4)
#'
#' @param timeseries_df Full timeseries
#' @param pixel_id Pixel ID
#' @param target_year Year to fit
#' @param padding_days Days to pad
#' @return Padded data frame
apply_edge_padding <- function(timeseries_df, pixel_id, target_year, padding_days = 31) {

  # Target year data
  year_data <- timeseries_df %>%
    filter(pixel_id == !!pixel_id, year == target_year)

  # Previous December
  prev_dec <- timeseries_df %>%
    filter(
      pixel_id == !!pixel_id,
      year == target_year - 1,
      yday > (365 - padding_days)
    ) %>%
    mutate(
      year = target_year,
      yday = yday - 366  # Negative DOY
    )

  # Next January
  next_jan <- timeseries_df %>%
    filter(
      pixel_id == !!pixel_id,
      year == target_year + 1,
      yday <= padding_days
    ) %>%
    mutate(
      year = target_year,
      yday = yday + 365  # Extended DOY
    )

  # Combine
  padded_data <- bind_rows(year_data, prev_dec, next_jan)

  return(padded_data)
}

#' Fit year-specific GAM and calculate derivatives for single pixel-year
#'
#' @param pixel_year_data Padded data for one pixel-year
#' @param pixel_id Pixel identifier
#' @param target_year Year identifier
#' @param config Configuration list
#' @return Data frame with derivatives
fit_pixel_year_derivatives <- function(pixel_year_data, pixel_id, target_year, config) {

  # Check minimum observations in target year range
  n_target_obs <- sum(pixel_year_data$yday >= 1 & pixel_year_data$yday <= 365)

  if (n_target_obs < config$min_observations) {
    return(NULL)
  }

  # Fit year-specific GAM on padded data
  gam_model <- tryCatch({
    gam(NDVI ~ s(yday, k = config$gam_knots, bs = config$gam_basis),
        data = pixel_year_data)
  }, error = function(e) {
    return(NULL)
  })

  if (is.null(gam_model)) return(NULL)

  # Check convergence
  if (!gam_model$converged) {
    return(NULL)
  }

  # Calculate derivatives for yday 1-365 only
  newdata <- data.frame(yday = 1:365)

  derivs <- tryCatch({
    calc.derivs(
      model.gam = gam_model,
      newdata = newdata,
      vars = "yday",
      n = config$n_posterior_sims,
      alpha = config$alpha_level
    )
  }, error = function(e) {
    return(NULL)
  })

  if (is.null(derivs)) return(NULL)

  # Format output
  result <- data.frame(
    pixel_id = pixel_id,
    year = target_year,
    yday = derivs$yday,
    deriv_mean = derivs$mean,
    deriv_lwr = derivs$lwr,
    deriv_upr = derivs$upr,
    sig = as.character(derivs$sig)
  )

  return(result)
}

#' Process pixel-year combinations
#'
#' @param batch_indices Indices into pixel_years dataframe
#' @param pixel_years Dataframe with pixel_id, year combinations
#' @param timeseries_df Full timeseries
#' @param config Configuration list
#' @return Batch of derivative results
process_pixel_year_batch_derivatives <- function(batch_indices, pixel_years,
                                                 timeseries_df, config) {

  batch_results <- list()

  for (idx in batch_indices) {

    pixel_id <- pixel_years$pixel_id[idx]
    target_year <- pixel_years$year[idx]

    # Apply edge padding
    padded_data <- apply_edge_padding(
      timeseries_df,
      pixel_id,
      target_year,
      config$edge_padding_days
    )

    # Skip if insufficient data
    if (nrow(padded_data) < config$min_observations) {
      next
    }

    # Fit and calculate derivatives
    year_derivs <- fit_pixel_year_derivatives(
      padded_data,
      pixel_id,
      target_year,
      config
    )

    if (!is.null(year_derivs)) {
      batch_results[[length(batch_results) + 1]] <- year_derivs
    }
  }

  if (length(batch_results) > 0) {
    return(bind_rows(batch_results))
  } else {
    return(NULL)
  }
}

# ==============================================================================
# MAIN PROCESSING WORKFLOW
# ==============================================================================

#' Calculate year-specific derivatives for all pixel-years
#'
#' @param timeseries_df Full timeseries dataframe
#' @param config Configuration list
#' @return Year derivatives dataframe
calculate_year_derivatives <- function(timeseries_df, config) {

  cat("=== CALCULATING YEAR-SPECIFIC DERIVATIVES ===\n\n")

  # Get all pixel-year combinations
  pixel_years <- timeseries_df %>%
    filter(year %in% config$target_years) %>%
    distinct(pixel_id, year)

  n_combinations <- nrow(pixel_years)

  cat("Total pixel-year combinations:", n_combinations, "\n")
  cat("  Pixels:", length(unique(pixel_years$pixel_id)), "\n")
  cat("  Years:", paste(range(config$target_years), collapse = "-"), "\n\n")

  # Check for checkpoint
  checkpoint_file <- sub("\\.csv$", "_checkpoint.csv", config$output_file)

  if (config$resume_from_checkpoint && file.exists(checkpoint_file)) {
    cat("Found checkpoint - loading previous progress...\n")
    derivatives_df <- read.csv(checkpoint_file, stringsAsFactors = FALSE)

    processed_combinations <- derivatives_df %>%
      distinct(pixel_id, year)

    pixel_years <- pixel_years %>%
      anti_join(processed_combinations, by = c("pixel_id", "year"))

    cat("  Resuming from", nrow(processed_combinations), "completed pixel-years\n")
    cat("  ", nrow(pixel_years), "pixel-years remaining\n\n")
  } else {
    derivatives_df <- data.frame()
  }

  if (nrow(pixel_years) == 0) {
    cat("All pixel-years already processed!\n")
    return(derivatives_df)
  }

  # Split into batches
  batch_size <- ceiling(nrow(pixel_years) / config$n_cores)
  batch_indices <- split(1:nrow(pixel_years),
                        ceiling(seq_len(nrow(pixel_years)) / batch_size))

  cat("Processing", length(batch_indices), "batches...\n")
  cat("Batch size:", batch_size, "pixel-years\n")
  cat("Using", config$n_cores, "core(s)\n\n")

  start_time <- Sys.time()

  if (config$n_cores == 1) {
    # Sequential processing with progress tracking
    batch_counter <- 0

    for (batch in batch_indices) {
      batch_result <- process_pixel_year_batch_derivatives(
        batch, pixel_years, timeseries_df, config
      )

      if (!is.null(batch_result) && nrow(batch_result) > 0) {
        derivatives_df <- bind_rows(derivatives_df, batch_result)
      }

      batch_counter <- batch_counter + 1

      # Progress update
      if (batch_counter %% 10 == 0 || batch_counter == length(batch_indices)) {
        elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
        pct_complete <- 100 * batch_counter / length(batch_indices)
        eta <- elapsed / batch_counter * (length(batch_indices) - batch_counter)

        cat(sprintf("  Progress: %d/%d batches (%.1f%%) | Elapsed: %.1f min | ETA: %.1f min\n",
                    batch_counter, length(batch_indices), pct_complete, elapsed, eta))

        # Checkpoint
        if (batch_counter %% config$checkpoint_interval == 0) {
          cat("  Saving checkpoint...\n")
          write.csv(derivatives_df, checkpoint_file, row.names = FALSE)
        }
      }
    }

  } else {
    # Parallel processing
    cl <- makeCluster(config$n_cores)
    clusterEvalQ(cl, {
      library(mgcv)
      library(dplyr)
      library(MASS)
    })
    clusterExport(cl, c("pixel_years", "timeseries_df", "config",
                       "apply_edge_padding",
                       "fit_pixel_year_derivatives",
                       "process_pixel_year_batch_derivatives",
                       "calc.derivs"),
                  envir = environment())

    batch_results <- parLapply(cl, batch_indices, function(batch) {
      process_pixel_year_batch_derivatives(batch, pixel_years, timeseries_df, config)
    })

    stopCluster(cl)

    # Combine results
    batch_results <- batch_results[!sapply(batch_results, is.null)]

    if (length(batch_results) > 0) {
      new_derivatives <- do.call(rbind, batch_results)

      if (nrow(derivatives_df) > 0) {
        derivatives_df <- rbind(derivatives_df, new_derivatives)
      } else {
        derivatives_df <- new_derivatives
      }
    }
  }

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "hours"))

  cat("\n=== YEAR-SPECIFIC DERIVATIVES COMPLETE ===\n")
  cat("Time elapsed:", round(elapsed, 2), "hours\n")
  cat("Pixel-years processed:",
      length(unique(paste(derivatives_df$pixel_id, derivatives_df$year))), "\n")
  cat("Total derivative records:", nrow(derivatives_df), "\n")
  cat("Significant changes:", sum(derivatives_df$sig == "*", na.rm = TRUE),
      "(", round(100 * mean(derivatives_df$sig == "*", na.rm = TRUE), 1), "%)\n\n")

  # Save final output
  cat("Saving year derivatives to:", config$output_file, "\n")
  write.csv(derivatives_df, config$output_file, row.names = FALSE)

  # Remove checkpoint
  if (file.exists(checkpoint_file)) {
    file.remove(checkpoint_file)
  }

  cat("✓ Phase 5 complete\n\n")

  return(derivatives_df)
}

#' Summarize year-specific derivatives
#'
#' @param derivatives_df Derivatives dataframe
#' @return Summary statistics
summarize_year_derivatives <- function(derivatives_df) {

  cat("=== YEAR-SPECIFIC DERIVATIVES SUMMARY ===\n\n")

  # Overall
  cat("Total pixel-years:",
      length(unique(paste(derivatives_df$pixel_id, derivatives_df$year))), "\n")
  cat("Total records:", nrow(derivatives_df), "\n\n")

  # By year
  year_summary <- derivatives_df %>%
    group_by(year) %>%
    summarise(
      n_pixels = length(unique(pixel_id)),
      mean_deriv = mean(deriv_mean),
      pct_sig = round(100 * mean(sig == "*", na.rm = TRUE), 1),
      .groups = "drop"
    )

  cat("By-year summary:\n")
  print(year_summary, n = Inf)
  cat("\n")

  return(year_summary)
}

# ==============================================================================
# EXECUTION
# ==============================================================================

# Check if running as main script
if (!interactive() || exists("run_phase5")) {

  cat("\n=== EXECUTING PHASE 5: YEAR-SPECIFIC DERIVATIVES ===\n")
  cat("Started at:", as.character(Sys.time()), "\n\n")

  # Load timeseries
  cat("Loading Phase 1 timeseries data...\n")
  timeseries_4km <- read.csv(config$timeseries_file, stringsAsFactors = FALSE)
  timeseries_4km$date <- as.Date(timeseries_4km$date)

  cat("  Total observations:", nrow(timeseries_4km), "\n")
  cat("  Years:", paste(sort(unique(timeseries_4km$year)), collapse = ", "), "\n\n")

  # Calculate year derivatives
  start_time <- Sys.time()
  year_derivs <- calculate_year_derivatives(timeseries_4km, config)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "hours"))

  # Summarize
  cat("\nGenerating summary statistics...\n")
  year_summary <- summarize_year_derivatives(year_derivs)

  # Final summary
  cat("\n=== PHASE 5 COMPLETE ===\n")
  cat("Total time:", round(elapsed, 2), "hours\n")
  cat("Output saved to:", config$output_file, "\n\n")
  cat("Next steps:\n")
  cat("  - Compare to baseline derivatives (Phase 3) to detect timing anomalies\n")
  cat("  - Calculate magnitude anomalies (Phase 6)\n")
  cat("  - Visualize phenological shifts\n\n")

} else {
  cat("\n=== PHASE 5 FUNCTIONS LOADED ===\n")
  cat("Ready to calculate year-specific derivatives with edge padding\n")
  cat("Estimated time: ~8-12 hours with", config$n_cores, "core(s)\n")
  cat("Output will be saved to:", config$output_file, "\n\n")
  cat("To run manually:\n")
  cat("  timeseries_4km <- read.csv(config$timeseries_file, stringsAsFactors = FALSE)\n")
  cat("  timeseries_4km$date <- as.Date(timeseries_4km$date)\n")
  cat("  year_derivs <- calculate_year_derivatives(timeseries_4km, config)\n\n")
}
