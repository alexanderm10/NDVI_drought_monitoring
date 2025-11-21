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

  # Parallel processing (capped for shared server - max 10 cores)
  n_cores = 8,  # Use 8 cores for good balance (set to 1 for sequential)

  # Checkpointing (RDS format for faster I/O and smaller files)
  checkpoint_interval = 100,  # Save progress every N pixels
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

#' Apply 31-day edge padding to year-specific data
#'
#' @param pixel_data Full timeseries for ONE pixel (all years)
#' @param target_year Year to fit
#' @param padding_days Number of days to pad (31)
#' @return Data frame with target year + padded edges
#'
#' @details
#' Edge padding helps reduce end effects in GAM fitting by borrowing data from
#' adjacent years. For edge years (first/last in timeseries), padding will be
#' incomplete or absent:
#' - First year (2013): No previous December data available
#' - Last year (2024): No next January data available
#' These years will fit with reduced/no padding but will still converge.
apply_edge_padding <- function(pixel_data, target_year, padding_days = 31) {

  # Get data for target year
  year_data <- pixel_data %>%
    filter(year == target_year)

  # Get previous December (last 31 days)
  # For first year in timeseries, this will return empty dataframe (no padding)
  prev_dec <- pixel_data %>%
    filter(
      year == target_year - 1,
      yday > (365 - padding_days)
    ) %>%
    mutate(
      year = target_year,
      yday = yday - 366  # Negative DOY: -30 to 0
    )

  # Get next January (first 31 days)
  # For last year in timeseries, this will return empty dataframe (no padding)
  next_jan <- pixel_data %>%
    filter(
      year == target_year + 1,
      yday <= padding_days
    ) %>%
    mutate(
      year = target_year,
      yday = yday + 365  # Extended DOY: 366-396
    )

  # Combine (empty dataframes from missing years will be silently dropped)
  padded_data <- bind_rows(year_data, prev_dec, next_jan)

  return(padded_data)
}

#' Fit year-specific GAM and calculate derivatives for single pixel-year
#'
#' @param pixel_year_data Padded data for one pixel-year
#' @param pixel_id Pixel identifier
#' @param target_year Year identifier
#' @param k_knots Number of knots to use (may be reduced for edge years)
#' @param config Configuration list
#' @return Data frame with derivatives
fit_pixel_year_derivatives <- function(pixel_year_data, pixel_id, target_year, k_knots, config) {

  # Check minimum observations in target year range
  n_target_obs <- sum(pixel_year_data$yday >= 1 & pixel_year_data$yday <= 365)

  if (n_target_obs < config$min_observations) {
    return(NULL)
  }

  # Fit year-specific GAM on padded data
  gam_model <- tryCatch({
    gam(NDVI ~ s(yday, k = k_knots, bs = config$gam_basis),
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

#' Process all years for a single pixel and calculate derivatives
#'
#' @param pixel_data Full timeseries for one pixel (all years)
#' @param pixel_id Pixel identifier
#' @param config Configuration list
#' @return Data frame with year derivatives for all target years
process_pixel_all_years_derivatives <- function(pixel_data, pixel_id, config) {

  pixel_results <- list()

  # Determine edge years (first and last in config$target_years)
  edge_years <- c(min(config$target_years), max(config$target_years))

  # Loop through each target year
  for (target_year in config$target_years) {

    # Apply edge padding
    padded_data <- apply_edge_padding(
      pixel_data,
      target_year,
      config$edge_padding_days
    )

    # Skip if insufficient data
    if (nrow(padded_data) < config$min_observations) {
      next
    }

    # Reduce knots for edge years (incomplete padding)
    # Following Juliana's approach: use k-1 for first/last years
    k_year <- if (target_year %in% edge_years) {
      config$gam_knots - 1
    } else {
      config$gam_knots
    }

    # Fit year-specific GAM and calculate derivatives
    year_derivs <- fit_pixel_year_derivatives(
      padded_data,
      pixel_id,
      target_year,
      k_year,
      config
    )

    if (!is.null(year_derivs)) {
      pixel_results[[length(pixel_results) + 1]] <- year_derivs
    }
  }

  if (length(pixel_results) > 0) {
    return(bind_rows(pixel_results))
  } else {
    return(NULL)
  }
}

# ==============================================================================
# MAIN PROCESSING WORKFLOW
# ==============================================================================

#' Calculate year-specific derivatives for all pixels
#'
#' @param timeseries_df Full timeseries dataframe
#' @param config Configuration list
#' @return Year derivatives dataframe
calculate_year_derivatives <- function(timeseries_df, config) {

  cat("=== CALCULATING YEAR-SPECIFIC DERIVATIVES ===\n\n")

  # Get unique pixels
  pixel_ids <- unique(timeseries_df$pixel_id)
  n_pixels <- length(pixel_ids)

  cat("Unique pixels:", n_pixels, "\n")
  cat("Target years:", paste(range(config$target_years), collapse = "-"),
      "(", length(config$target_years), "years)\n")
  cat("Total pixel-year combinations:", n_pixels * length(config$target_years), "\n\n")

  # Check for checkpoint (RDS format for faster I/O)
  checkpoint_file <- sub("\\.csv$", "_checkpoint.rds", config$output_file)

  if (config$resume_from_checkpoint && file.exists(checkpoint_file)) {
    cat("Found checkpoint - loading previous progress...\n")
    derivatives_df <- readRDS(checkpoint_file)

    processed_pixels <- unique(derivatives_df$pixel_id)
    pixel_ids <- setdiff(pixel_ids, processed_pixels)

    cat("  Resuming from", length(processed_pixels), "completed pixels\n")
    cat("  ", length(pixel_ids), "pixels remaining\n\n")
  } else {
    derivatives_df <- data.frame()
  }

  if (length(pixel_ids) == 0) {
    cat("All pixels already processed!\n")
    return(derivatives_df)
  }

  # Process pixels with incremental checkpointing
  cat("Processing pixels with incremental checkpointing...\n")
  cat("Checkpoint interval:", config$checkpoint_interval, "pixels\n")
  cat("Parallel cores:", config$n_cores, "\n\n")

  start_time <- Sys.time()
  n_processed <- 0
  n_failed <- 0

  # Split pixels into small batches for better checkpointing
  # Each batch = config$n_cores pixels (one per core)
  batch_size <- config$n_cores
  pixel_batches <- split(pixel_ids, ceiling(seq_along(pixel_ids) / batch_size))

  cat("Split into", length(pixel_batches), "batches of ~", batch_size, "pixels each\n\n")

  # Set up cluster if using parallel processing
  if (config$n_cores > 1) {
    cl <- makeCluster(config$n_cores)
    clusterEvalQ(cl, {
      library(mgcv)
      library(dplyr)
      library(MASS)
      # CRITICAL: Prevent nested parallelism - constrain each worker to 1 thread
      # This prevents 8 workers × N threads = core explosion
      Sys.setenv(OMP_NUM_THREADS = 1)
      Sys.setenv(MKL_NUM_THREADS = 1)
      Sys.setenv(OPENBLAS_NUM_THREADS = 1)
    })
    # Export required objects: timeseries_df, config, and functions
    # timeseries_df IS exported but accessed per-pixel (not duplicated per worker)
    clusterExport(cl, c("timeseries_df", "config",
                       "process_pixel_all_years_derivatives",
                       "apply_edge_padding",
                       "fit_pixel_year_derivatives",
                       "calc.derivs"),
                  envir = environment())
  }

  # Accumulate results in a list to avoid repeated rbind (MUCH faster)
  all_results <- list()
  result_counter <- 0

  # Process batches with incremental checkpointing
  for (i in seq_along(pixel_batches)) {
    batch_pixels <- pixel_batches[[i]]

    # Process batch (parallel or sequential)
    if (config$n_cores > 1) {
      # For parallel: each worker gets ONLY data for its assigned pixel
      batch_results <- parLapply(cl, batch_pixels, function(pixel_id) {
        # Each worker gets ONLY data for its assigned pixel (all years)
        pixel_data <- timeseries_df[timeseries_df$pixel_id == pixel_id, ]

        # Skip if insufficient data
        if (nrow(pixel_data) < config$min_observations) {
          return(NULL)
        }

        # Process all years for this pixel
        pixel_result <- process_pixel_all_years_derivatives(pixel_data, pixel_id, config)

        if (!is.null(pixel_result)) {
          return(pixel_result)
        } else {
          return(NULL)
        }
      })
    } else {
      # Sequential processing
      batch_results <- lapply(batch_pixels, function(pixel_id) {
        pixel_data <- timeseries_df[timeseries_df$pixel_id == pixel_id, ]

        if (nrow(pixel_data) < config$min_observations) {
          return(NULL)
        }

        pixel_result <- process_pixel_all_years_derivatives(pixel_data, pixel_id, config)

        if (!is.null(pixel_result)) {
          return(pixel_result)
        } else {
          return(NULL)
        }
      })
    }

    # Store successful results in list (avoid repeated rbind)
    batch_results <- batch_results[!sapply(batch_results, is.null)]

    if (length(batch_results) > 0) {
      for (result in batch_results) {
        result_counter <- result_counter + 1
        all_results[[result_counter]] <- result
      }
      n_processed <- n_processed + length(batch_results)
    }

    n_failed <- n_failed + (length(batch_pixels) - length(batch_results))

    # Progress reporting
    if (n_processed %% 50 == 0 || i == length(pixel_batches)) {
      elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
      pixels_per_min <- n_processed / elapsed
      remaining <- length(pixel_ids) - n_processed - n_failed
      eta_mins <- remaining / pixels_per_min

      cat(sprintf("  Progress: %d/%d pixels (%.1f%%) | %.1f pixels/min | ETA: %.0f min\n",
                  n_processed, length(pixel_ids),
                  100 * n_processed / length(pixel_ids),
                  pixels_per_min, eta_mins))
    }

    # Save checkpoint every N pixels (convert list to df only when checkpointing)
    if (n_processed %% config$checkpoint_interval == 0) {
      cat("  Saving checkpoint...\n")
      derivatives_df <- do.call(rbind, all_results)
      saveRDS(derivatives_df, checkpoint_file, compress = "gzip")
    }
  }

  # Final conversion to dataframe
  cat("\nCombining all results...\n")
  derivatives_df <- do.call(rbind, all_results)

  # Clean up cluster
  if (config$n_cores > 1) {
    stopCluster(cl)
  }

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  cat("\n=== YEAR-SPECIFIC DERIVATIVES COMPLETE ===\n")
  cat("Time elapsed:", round(elapsed, 1), "minutes\n")
  cat("Pixels processed:", n_processed, "\n")
  cat("Pixels failed:", n_failed, "\n")
  cat("Pixel-year combinations:", length(unique(paste(derivatives_df$pixel_id, derivatives_df$year))), "\n")
  cat("Expected combinations (pixels × years):", n_processed * length(config$target_years), "\n")
  cat("Total derivative records:", nrow(derivatives_df), "\n")
  cat("Expected records (pixels × years × 365 days):", n_processed * length(config$target_years) * 365, "\n")
  cat("Significant changes:", sum(derivatives_df$sig == "*", na.rm = TRUE),
      "(", round(100 * mean(derivatives_df$sig == "*", na.rm = TRUE), 1), "%)\n\n")

  # Save final output (CSV for compatibility)
  cat("Saving year derivatives to:", config$output_file, "\n")
  write.csv(derivatives_df, config$output_file, row.names = FALSE)

  # Remove checkpoint
  if (file.exists(checkpoint_file)) {
    file.remove(checkpoint_file)
    cat("Checkpoint file removed\n")
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
  cat("Years:", paste(range(config$target_years), collapse = "-"), "\n")
  cat("Estimated time: ~90-120 minutes with", config$n_cores, "cores\n")
  cat("Output will be saved to:", config$output_file, "\n\n")
  cat("To run manually:\n")
  cat("  timeseries_4km <- read.csv(config$timeseries_file, stringsAsFactors = FALSE)\n")
  cat("  timeseries_4km$date <- as.Date(timeseries_4km$date)\n")
  cat("  year_derivs <- calculate_year_derivatives(timeseries_4km, config)\n\n")
}
