# ==============================================================================
# 02_doy_looped_norms.R
#
# Purpose: Calculate DOY-looped spatial norms (baseline) for NDVI
# Based on: Juliana's spatial_analysis/05_norms_looped_by_yday.R
#
# Approach:
#   For each day of year (1-365):
#     - Pull observations from +/- 7 day window around that DOY
#     - Pool ALL years together
#     - Fit spatial GAM: gam(NDVI ~ s(x, y))
#     - Use post.distns() to get uncertainty (mean, lwr, upr)
#
# Input: Phase 1 aggregated timeseries (01_aggregate_to_4km output)
# Output: Norm predictions for each pixel-DOY with uncertainty
#
# ==============================================================================

# Limit BLAS/LAPACK threads to be a good neighbor on shared systems
Sys.setenv(OMP_NUM_THREADS = 2)
Sys.setenv(OPENBLAS_NUM_THREADS = 2)

library(mgcv)
library(dplyr)
library(MASS)
library(parallel)

# Source utility functions
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()
source("00_posterior_functions.R")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Window parameters
  window_size = 7,  # +/- days around target DOY

  # GAM parameters (may need tuning for CONUS scale)
  gam_knots = -1,  # -1 lets mgcv choose automatically

  # Output
  output_file = file.path(hls_paths$gam_models, "doy_looped_norms.rds"),
  checkpoint_file = file.path(hls_paths$gam_models, "doy_looped_norms_checkpoint.rds"),
  checkpoint_interval = 50,  # Save every N DOYs

  # Posterior simulation
  n_posterior_sims = 100,  # Number of simulations for uncertainty

  # Parallelization (conservative for shared systems)
  n_cores = 2  # Reduced further for resume run
)

cat("=== DOY-Looped Spatial Norms ===\n")
cat("Window size: +/-", config$window_size, "days\n")
cat("Output:", config$output_file, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Get DOY window handling year wrap-around
#'
#' @param target_day Target day of year (1-365)
#' @param window_size Days before and after target
#' @return Vector of DOYs in the window
get_doy_window <- function(target_day, window_size = 7) {
  start <- target_day - window_size
  end <- target_day + window_size

  # Handle wrap-around at year boundaries
  if (start < 1) {
    start_section <- c((start + 365):365, 1:target_day)
  } else {
    start_section <- start:target_day
  }

  if (end > 365) {
    end_section <- c(target_day:365, 1:(end - 365))
  } else {
    end_section <- target_day:end
  }

  return(unique(c(start_section, end_section)))
}

#' Fit spatial GAM for a single DOY
#'
#' @param df_doy Data frame with NDVI, x, y for this DOY window
#' @param pred_grid Prediction grid (unique pixels)
#' @param n_sims Number of posterior simulations
#' @return Data frame with mean, lwr, upr for each pixel
fit_doy_spatial_gam <- function(df_doy, pred_grid, n_sims = 100) {

  # Check minimum data requirements
  if (nrow(df_doy) < 50) {
    warning("Insufficient data for spatial GAM")
    return(NULL)
  }

  # Fit spatial GAM
  gam_model <- tryCatch({
    gam(NDVI ~ s(x, y), data = df_doy)
  }, error = function(e) {
    warning("GAM fitting failed: ", e$message)
    return(NULL)
  })

  if (is.null(gam_model)) return(NULL)

  # Get predictions with uncertainty using post.distns
  result <- tryCatch({
    post.distns(
      model.gam = gam_model,
      newdata = pred_grid,
      vars = c("x", "y"),
      n = n_sims
    )
  }, error = function(e) {
    warning("Posterior calculation failed: ", e$message)
    # Fall back to simple prediction without uncertainty
    pred <- predict(gam_model, newdata = pred_grid, se.fit = TRUE)
    data.frame(
      mean = pred$fit,
      lwr = pred$fit - 1.96 * pred$se.fit,
      upr = pred$fit + 1.96 * pred$se.fit
    )
  })

  return(result)
}

# ==============================================================================
# LOAD DATA
# ==============================================================================

cat("Loading Phase 1 timeseries data...\n")

# Check for RDS first (faster)
rds_file <- file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.rds")
csv_file <- file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.csv")

if (file.exists(rds_file)) {
  cat("  Using RDS format...\n")
  timeseries_df <- readRDS(rds_file)
} else if (file.exists(csv_file)) {
  cat("  Using CSV format...\n")
  timeseries_df <- read.csv(csv_file, stringsAsFactors = FALSE)
  timeseries_df$date <- as.Date(timeseries_df$date)
} else {
  stop("No timeseries data found. Run script 01 first.")
}

# Fix year column from date (handles any parsing issues)
timeseries_df$year <- as.integer(format(timeseries_df$date, "%Y"))

cat("  Total observations:", nrow(timeseries_df), "\n")
cat("  Unique pixels:", length(unique(timeseries_df$pixel_id)), "\n")
cat("  Year range:", min(timeseries_df$year), "-", max(timeseries_df$year), "\n\n")

# ==============================================================================
# CREATE PREDICTION GRID
# ==============================================================================

cat("Creating prediction grid...\n")

# Get unique pixel locations
pixel_coords <- timeseries_df %>%
  group_by(pixel_id) %>%
  summarise(
    x = first(x),
    y = first(y),
    .groups = "drop"
  ) %>%
  as.data.frame()

cat("  Unique pixel locations:", nrow(pixel_coords), "\n\n")

# Create output structure: one row per pixel-DOY
norms_df <- expand.grid(
  pixel_id = unique(pixel_coords$pixel_id),
  yday = 1:365
)

# Add coordinates
norms_df <- merge(norms_df, pixel_coords, by = "pixel_id")

# Add columns for results
norms_df$mean <- NA_real_
norms_df$lwr <- NA_real_
norms_df$upr <- NA_real_

cat("Output structure:", nrow(norms_df), "rows (",
    length(unique(norms_df$pixel_id)), "pixels x 365 days)\n\n")

# ==============================================================================
# CHECK FOR EXISTING RESULTS (RESUME MODE)
# ==============================================================================

days_to_process <- 1:365

if (file.exists(config$output_file)) {
  cat("Found existing results, checking for missing DOYs...\n")
  existing_norms <- readRDS(config$output_file)

  # Find DOYs with all NAs (failed cores)
  doy_status <- tapply(existing_norms$mean, existing_norms$yday, function(x) sum(!is.na(x)))
  missing_doys <- as.integer(names(doy_status[doy_status == 0]))

  if (length(missing_doys) > 0) {
    cat("  Found", length(missing_doys), "missing DOYs\n")
    cat("  Will resume with existing data and process missing DOYs only\n\n")
    norms_df <- existing_norms
    days_to_process <- missing_doys
  } else {
    cat("  All DOYs complete! Nothing to process.\n")
    days_to_process <- integer(0)
  }
}

# ==============================================================================
# MAIN PROCESSING - PARALLEL
# ==============================================================================

if (length(days_to_process) > 0) {
  cat("Processing DOY-looped spatial norms...\n")
  cat("Using", config$n_cores, "cores\n")
  cat("======================================\n\n")

  start_time <- Sys.time()

  # Define function to process a single DOY
  process_single_doy <- function(day) {
    # Get DOY window
    doy_window <- get_doy_window(day, config$window_size)

    # Filter data for this window (all years pooled)
    df_doy <- timeseries_df %>%
      filter(yday %in% doy_window) %>%
      filter(!is.na(NDVI))

    # Skip if insufficient data
    if (nrow(df_doy) < 50) {
      return(list(day = day, result = NULL, n_obs = nrow(df_doy)))
    }

    # Fit spatial GAM and get predictions
    result <- fit_doy_spatial_gam(df_doy, pixel_coords, config$n_posterior_sims)

    return(list(day = day, result = result, n_obs = nrow(df_doy)))
  }

  # Run parallel processing
  cat("Processing", length(days_to_process), "DOYs...\n\n")

  results_list <- mclapply(
    days_to_process,
    process_single_doy,
    mc.cores = config$n_cores
  )

  # Combine results into norms_df
  cat("Combining results...\n")
  for (res in results_list) {
    if (!is.null(res$result)) {
      idx <- which(norms_df$yday == res$day)
      norms_df$mean[idx] <- res$result$mean
      norms_df$lwr[idx] <- res$result$lwr
      norms_df$upr[idx] <- res$result$upr
    }
  }

  elapsed_total <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
} else {
  elapsed_total <- 0
}

# ==============================================================================
# FINAL SAVE
# ==============================================================================

cat("\n======================================\n")
cat("Processing complete!\n\n")

# Save final output
cat("Saving final output...\n")
saveRDS(norms_df, config$output_file)

# Summary statistics
n_complete <- sum(!is.na(norms_df$mean))
n_total <- nrow(norms_df)
pct_complete <- 100 * n_complete / n_total

cat("\nSummary:\n")
cat("  Total pixel-DOY combinations:", n_total, "\n")
cat("  Successfully fitted:", n_complete, sprintf("(%.1f%%)\n", pct_complete))
cat("  Output saved to:", config$output_file, "\n")

# Clean up checkpoint
if (file.exists(config$checkpoint_file)) {
  file.remove(config$checkpoint_file)
  cat("  Checkpoint file removed\n")
}

cat(sprintf("\nTotal time: %.1f minutes\n", elapsed_total))
