# ==============================================================================
# PHASE 3: YEAR-SPECIFIC SPLINES WITH EDGE PADDING
# ==============================================================================
# Purpose: Fit pixel-by-pixel GAMs for each year with 31-day edge padding
# Input: conus_4km_ndvi_timeseries.csv from Phase 1
# Output: Year-specific curves (pixel_id, year, yday, year_mean, year_se)
# ==============================================================================

library(mgcv)
library(dplyr)
library(parallel)

# Source path configuration
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

cat("=== PHASE 3: YEAR-SPECIFIC SPLINES ===\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Years to process
  target_years = 2013:2024,

  # Edge padding parameters
  edge_padding_days = 31,  # Days to extend from prev Dec and next Jan

  # GAM parameters
  gam_knots = 12,
  gam_basis = "tp",  # Thin plate (not cyclic for padded data)

  # Input/output
  input_file = file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.csv"),
  output_file = file.path(hls_paths$gam_models, "conus_4km_year_splines.csv"),
  model_archive = file.path(hls_paths$gam_models, "individual_years"),

  # Quality control
  min_observations = 15,  # Minimum obs per pixel-year for reliable fit

  # Parallel processing
  n_cores = parallel::detectCores() - 1,

  # Checkpointing
  checkpoint_interval = 50,
  resume_from_checkpoint = TRUE
)

# Ensure output directories exist
ensure_directory(hls_paths$gam_models)
ensure_directory(config$model_archive)

cat("Configuration:\n")
cat("  Years to process:", paste(range(config$target_years), collapse = "-"), "\n")
cat("  Edge padding:", config$edge_padding_days, "days\n")
cat("  GAM knots:", config$gam_knots, "\n")
cat("  Minimum observations per pixel-year:", config$min_observations, "\n")
cat("  Parallel cores:", config$n_cores, "\n")
cat("  Output:", config$output_file, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Apply 31-day edge padding to year-specific data
#'
#' @param timeseries_df Full timeseries dataframe
#' @param pixel_id Pixel ID to process
#' @param target_year Year to fit
#' @param padding_days Number of days to pad (31)
#' @return Data frame with target year + padded edges
apply_edge_padding <- function(timeseries_df, pixel_id, target_year, padding_days = 31) {

  # Get data for target year
  year_data <- timeseries_df %>%
    filter(pixel_id == !!pixel_id, year == target_year)

  # Get previous December (last 31 days)
  prev_dec <- timeseries_df %>%
    filter(
      pixel_id == !!pixel_id,
      year == target_year - 1,
      yday > (365 - padding_days)
    ) %>%
    mutate(
      year = target_year,
      yday = yday - 366  # Negative DOY: -30 to 0
    )

  # Get next January (first 31 days)
  next_jan <- timeseries_df %>%
    filter(
      pixel_id == !!pixel_id,
      year == target_year + 1,
      yday <= padding_days
    ) %>%
    mutate(
      year = target_year,
      yday = yday + 365  # Extended DOY: 366-396
    )

  # Combine
  padded_data <- bind_rows(year_data, prev_dec, next_jan)

  return(padded_data)
}

#' Fit year-specific GAM for a single pixel-year
#'
#' @param pixel_year_data Data frame with yday and NDVI for one pixel-year (padded)
#' @param k Number of knots
#' @param bs Basis type
#' @return Data frame with yday (1-365), year_mean, year_se
fit_pixel_year_gam <- function(pixel_year_data, k = 12, bs = "tp") {

  # Check minimum observations
  # Count only observations in target year range (yday 1-365)
  n_target_year_obs <- sum(pixel_year_data$yday >= 1 & pixel_year_data$yday <= 365)

  if (n_target_year_obs < 10) {
    return(NULL)
  }

  # Fit GAM on padded data
  gam_model <- tryCatch({
    gam(NDVI ~ s(yday, k = k, bs = bs), data = pixel_year_data)
  }, error = function(e) {
    return(NULL)
  })

  if (is.null(gam_model)) return(NULL)

  # Check convergence
  if (!gam_model$converged) {
    return(NULL)
  }

  # Predict for yday 1-365 only (discard padding in output)
  newdata <- data.frame(yday = 1:365)

  pred <- predict(gam_model, newdata = newdata, se.fit = TRUE)

  result <- data.frame(
    yday = 1:365,
    year_mean = pred$fit,
    year_se = pred$se.fit
  )

  return(result)
}

#' Process all pixel-year combinations
#'
#' @param timeseries_df Full timeseries dataframe
#' @param config Configuration list
#' @return Year-specific splines dataframe
fit_all_year_gams <- function(timeseries_df, config) {

  cat("=== FITTING YEAR-SPECIFIC GAMS ===\n\n")

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
    year_splines_df <- read.csv(checkpoint_file, stringsAsFactors = FALSE)

    processed_combinations <- year_splines_df %>%
      distinct(pixel_id, year)

    pixel_years <- pixel_years %>%
      anti_join(processed_combinations, by = c("pixel_id", "year"))

    cat("  Resuming from", nrow(processed_combinations), "completed pixel-years\n")
    cat("  ", nrow(pixel_years), "pixel-years remaining\n\n")
  } else {
    year_splines_df <- data.frame()
  }

  if (nrow(pixel_years) == 0) {
    cat("All pixel-years already processed!\n")
    return(year_splines_df)
  }

  # Parallel processing function
  process_pixel_year_batch <- function(batch_indices) {

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

      # Fit year-specific GAM
      year_spline <- fit_pixel_year_gam(
        padded_data,
        k = config$gam_knots,
        bs = config$gam_basis
      )

      if (!is.null(year_spline)) {
        year_spline$pixel_id <- pixel_id
        year_spline$year <- target_year
        batch_results[[length(batch_results) + 1]] <- year_spline
      }
    }

    if (length(batch_results) > 0) {
      return(bind_rows(batch_results))
    } else {
      return(NULL)
    }
  }

  # Split into batches for parallel processing
  batch_size <- ceiling(nrow(pixel_years) / config$n_cores)
  batch_indices <- split(1:nrow(pixel_years),
                        ceiling(seq_len(nrow(pixel_years)) / batch_size))

  cat("Processing", length(batch_indices), "batches in parallel...\n")
  cat("Batch size:", batch_size, "pixel-years per batch\n\n")

  start_time <- Sys.time()

  # Set up cluster
  cl <- makeCluster(config$n_cores)
  clusterEvalQ(cl, {
    library(mgcv)
    library(dplyr)
  })
  clusterExport(cl, c("timeseries_df", "pixel_years", "config",
                     "apply_edge_padding", "fit_pixel_year_gam"),
                envir = environment())

  # Process batches with progress tracking
  n_batches <- length(batch_indices)
  batch_counter <- 0

  for (batch in batch_indices) {
    batch_result <- parLapply(cl, list(batch), process_pixel_year_batch)[[1]]

    if (!is.null(batch_result) && nrow(batch_result) > 0) {
      year_splines_df <- bind_rows(year_splines_df, batch_result)
    }

    batch_counter <- batch_counter + 1

    # Progress update
    if (batch_counter %% 10 == 0 || batch_counter == n_batches) {
      elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
      pct_complete <- 100 * batch_counter / n_batches
      eta <- elapsed / batch_counter * (n_batches - batch_counter)

      cat(sprintf("  Progress: %d/%d batches (%.1f%%) | Elapsed: %.1f min | ETA: %.1f min\n",
                  batch_counter, n_batches, pct_complete, elapsed, eta))

      # Checkpoint save
      if (batch_counter %% config$checkpoint_interval == 0) {
        cat("  Saving checkpoint...\n")
        write.csv(year_splines_df, checkpoint_file, row.names = FALSE)
      }
    }
  }

  stopCluster(cl)

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  cat("\n=== YEAR-SPECIFIC GAMS COMPLETE ===\n")
  cat("Time elapsed:", round(elapsed, 1), "minutes\n")
  cat("Pixel-years processed:", length(unique(paste(year_splines_df$pixel_id, year_splines_df$year))), "\n")
  cat("Total spline records:", nrow(year_splines_df), "\n\n")

  # Save final output
  cat("Saving year splines to:", config$output_file, "\n")
  write.csv(year_splines_df, config$output_file, row.names = FALSE)

  # Remove checkpoint
  if (file.exists(checkpoint_file)) {
    file.remove(checkpoint_file)
  }

  cat("✓ Phase 3 complete\n\n")

  return(year_splines_df)
}

#' Summarize year-specific splines
#'
#' @param year_splines_df Year splines dataframe
#' @return Summary statistics
summarize_year_splines <- function(year_splines_df) {

  cat("=== YEAR-SPECIFIC SPLINES SUMMARY ===\n\n")

  # Overall counts
  cat("Total pixel-years:", length(unique(paste(year_splines_df$pixel_id, year_splines_df$year))), "\n")
  cat("Total records:", nrow(year_splines_df), "\n\n")

  # By year
  year_summary <- year_splines_df %>%
    group_by(year) %>%
    summarise(
      n_pixels = length(unique(pixel_id)),
      mean_ndvi = mean(year_mean),
      sd_ndvi = sd(year_mean),
      .groups = "drop"
    )

  cat("Pixels per year:\n")
  print(year_summary, n = Inf)
  cat("\n")

  # Uncertainty
  cat("Prediction uncertainty (SE):\n")
  cat("  Median SE:", round(median(year_splines_df$year_se), 4), "\n")
  cat("  95th percentile SE:", round(quantile(year_splines_df$year_se, 0.95), 4), "\n\n")

  return(year_summary)
}

# ==============================================================================
# EXECUTION
# ==============================================================================

cat("=== READY TO FIT YEAR-SPECIFIC GAMS ===\n")
cat("This will fit GAMs for all pixel-year combinations with 31-day edge padding\n")
cat("Estimated time: ~6 hours with", config$n_cores, "cores\n")
cat("Output will be saved to:", config$output_file, "\n\n")
cat("To run:\n")
cat("  # Load timeseries from Phase 1\n")
cat("  timeseries_4km <- read.csv(config$input_file, stringsAsFactors = FALSE)\n")
cat("  timeseries_4km$date <- as.Date(timeseries_4km$date)\n\n")
cat("  # Fit year-specific GAMs\n")
cat("  year_splines <- fit_all_year_gams(timeseries_4km, config)\n\n")
cat("  # Summarize results\n")
cat("  year_summary <- summarize_year_splines(year_splines)\n\n")
