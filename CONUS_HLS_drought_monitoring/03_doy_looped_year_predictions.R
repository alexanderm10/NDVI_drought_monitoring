# ==============================================================================
# 03_doy_looped_year_predictions.R
#
# Purpose: Calculate DOY-looped year-specific predictions
# Based on: Juliana's spatial_analysis/06_year_splines_yday_looped_.R
#
# Approach:
#   For each year-DOY combination:
#     - Pull 16-day trailing window of observations
#     - Merge with norms from script 02
#     - Fit spatial GAM: gam(NDVI ~ norm + s(x, y) - 1)
#     - Use post.distns() to get uncertainty (mean, lwr, upr)
#
# Input:
#   - Phase 1 aggregated timeseries
#   - Script 02 norms output
# Output: Year predictions for each pixel-year-DOY with uncertainty
#
# ==============================================================================

# Limit BLAS/LAPACK threads to be a good neighbor on shared systems
Sys.setenv(OMP_NUM_THREADS = 2)
Sys.setenv(OPENBLAS_NUM_THREADS = 2)

library(mgcv)
library(dplyr)
library(MASS)
library(parallel)
library(lubridate)

# Source utility functions
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()
source("00_posterior_functions.R")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Window parameters
  window_size = 16,  # Trailing window (days before target)

  # Minimum data requirement
  min_pixel_coverage = 0.33,  # Require 33% of pixels to have data

  # Output
  output_file = file.path(hls_paths$gam_models, "doy_looped_year_predictions.rds"),
  stats_file = file.path(hls_paths$gam_models, "year_prediction_model_stats.rds"),

  # Posterior simulation
  n_posterior_sims = 100,


  # Parallelization (conservative for shared systems)
  n_cores = 4  # Reduced further due to memory constraints
)

cat("=== DOY-Looped Year Predictions ===\n")
cat("Trailing window:", config$window_size, "days\n")
cat("Using", config$n_cores, "cores\n")
cat("Output:", config$output_file, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Get trailing window dates for a specific year-DOY
#'
#' @param year Target year
#' @param target_day Target day of year (1-365)
#' @param window_size Days before target (inclusive)
#' @return Vector of dates in the window
get_trailing_window <- function(year, target_day, window_size = 16) {
  target_date <- as.Date(paste(year, target_day, sep = "-"), format = "%Y-%j")
  start_date <- target_date - (window_size - 1)
  seq.Date(start_date, target_date, by = "day")
}

#' Fit year-specific spatial GAM
#'
#' @param df_subset Data frame with NDVI, norm, x, y for this window
#' @param pred_grid Prediction grid (with norm values)
#' @param n_sims Number of posterior simulations
#' @return List with predictions and model stats
fit_year_spatial_gam <- function(df_subset, pred_grid, n_sims = 100) {

  # Fit spatial GAM with norm as covariate
  gam_model <- tryCatch({
    gam(NDVI ~ norm + s(x, y) - 1, data = df_subset)
  }, error = function(e) {
    return(NULL)
  })

  if (is.null(gam_model)) {
    return(list(result = NULL, stats = NULL))
  }

  # Extract model statistics
  gam_summary <- summary(gam_model)
  stats <- list(
    R2 = gam_summary$r.sq,
    NormCoef = gam_summary$p.table["norm", "Estimate"],
    SplineP = gam_summary$s.table[1, "p-value"],
    RMSE = sqrt(mean(residuals(gam_model)^2))
  )

  # Get predictions with uncertainty
  result <- tryCatch({
    post.distns(
      model.gam = gam_model,
      newdata = pred_grid,
      vars = c("x", "y"),
      n = n_sims
    )
  }, error = function(e) {
    # Fall back to simple prediction
    pred <- predict(gam_model, newdata = pred_grid, se.fit = TRUE)
    data.frame(
      mean = pred$fit,
      lwr = pred$fit - 1.96 * pred$se.fit,
      upr = pred$fit + 1.96 * pred$se.fit
    )
  })

  return(list(result = result, stats = stats))
}

# ==============================================================================
# LOAD DATA
# ==============================================================================

cat("Loading data...\n")

# Load timeseries
rds_file <- file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.rds")
if (file.exists(rds_file)) {
  timeseries_df <- readRDS(rds_file)
} else {
  stop("Timeseries data not found. Run script 01 first.")
}

# Fix year column from date (handles any parsing issues)
timeseries_df$year <- as.integer(format(timeseries_df$date, "%Y"))

cat("  Timeseries observations:", nrow(timeseries_df), "\n")

# Load norms from script 02
norms_file <- file.path(hls_paths$gam_models, "doy_looped_norms.rds")
if (!file.exists(norms_file)) {
  stop("Norms not found. Run script 02 first.")
}
norms_df <- readRDS(norms_file)
cat("  Norms loaded:", nrow(norms_df), "pixel-DOY combinations\n")

# Get unique years and pixels
years <- sort(unique(timeseries_df$year))
n_pixels <- length(unique(timeseries_df$pixel_id))

cat("  Years:", min(years), "-", max(years), "(", length(years), "years)\n")
cat("  Pixels:", n_pixels, "\n\n")

# ==============================================================================
# CREATE PREDICTION GRID
# ==============================================================================

cat("Creating prediction grid...\n")

# Get pixel coordinates
pixel_coords <- timeseries_df %>%
  group_by(pixel_id) %>%
  summarise(x = first(x), y = first(y), .groups = "drop") %>%
  as.data.frame()

# Create output structure: pixel × year × DOY
year_preds_df <- expand.grid(
  pixel_id = unique(pixel_coords$pixel_id),
  year = years,
  yday = 1:365
)

# Add coordinates
year_preds_df <- merge(year_preds_df, pixel_coords, by = "pixel_id")

# Add norm values
year_preds_df <- merge(
  year_preds_df,
  norms_df[, c("pixel_id", "yday", "mean")],
  by = c("pixel_id", "yday"),
  all.x = TRUE
)
names(year_preds_df)[names(year_preds_df) == "mean"] <- "norm"

# Add columns for results
year_preds_df$mean <- NA_real_
year_preds_df$lwr <- NA_real_
year_preds_df$upr <- NA_real_

# Sort for efficient indexing
year_preds_df <- year_preds_df[order(year_preds_df$year, year_preds_df$yday, year_preds_df$pixel_id), ]

cat("  Output structure:", nrow(year_preds_df), "rows\n")
cat("  (", n_pixels, "pixels ×", length(years), "years × 365 days)\n\n")

# ==============================================================================
# CREATE YEAR-DOY JOB LIST
# ==============================================================================

# Create all year-DOY combinations
job_list <- expand.grid(year = years, yday = 1:365)
job_list <- job_list[order(job_list$year, job_list$yday), ]
n_jobs <- nrow(job_list)

cat("Total jobs:", n_jobs, "\n\n")

# ==============================================================================
# MAIN PROCESSING - PARALLEL
# ==============================================================================

cat("Processing year predictions...\n")
cat("======================================\n\n")

start_time <- Sys.time()

# Merge timeseries with norms for the window calculations
timeseries_with_norms <- merge(
  timeseries_df,
  norms_df[, c("pixel_id", "yday", "mean")],
  by = c("pixel_id", "yday"),
  all.x = TRUE
)
names(timeseries_with_norms)[names(timeseries_with_norms) == "mean"] <- "norm"

# Define function to process a single year-DOY
process_year_doy <- function(job_idx) {
  yr <- job_list$year[job_idx]
  day <- job_list$yday[job_idx]

  # Get trailing window dates
  window_dates <- get_trailing_window(yr, day, config$window_size)

  # Filter data for this window
  df_subset <- timeseries_with_norms %>%
    filter(date %in% window_dates) %>%
    filter(!is.na(NDVI) & !is.na(norm))

  # Check minimum data requirement
  n_pixels_with_data <- length(unique(df_subset$pixel_id))
  if (n_pixels_with_data < n_pixels * config$min_pixel_coverage) {
    return(list(
      year = yr,
      yday = day,
      result = NULL,
      stats = NULL,
      n_obs = nrow(df_subset)
    ))
  }

  # Create prediction grid with norms for this DOY
  pred_grid <- year_preds_df %>%
    filter(year == yr & yday == day) %>%
    select(pixel_id, x, y, norm)

  # Fit model
  fit_result <- fit_year_spatial_gam(df_subset, pred_grid, config$n_posterior_sims)

  return(list(
    year = yr,
    yday = day,
    result = fit_result$result,
    stats = fit_result$stats,
    n_obs = nrow(df_subset)
  ))
}

# Run parallel processing
cat("Processing", n_jobs, "year-DOY combinations...\n\n")

results_list <- mclapply(
  1:n_jobs,
  process_year_doy,
  mc.cores = config$n_cores
)

# ==============================================================================
# COMBINE RESULTS
# ==============================================================================

cat("Combining results...\n")

# Initialize model stats data frame
model_stats <- data.frame(
  year = job_list$year,
  yday = job_list$yday,
  R2 = NA_real_,
  NormCoef = NA_real_,
  SplineP = NA_real_,
  RMSE = NA_real_,
  n_obs = NA_integer_
)

# Process results
for (i in seq_along(results_list)) {
  res <- results_list[[i]]

  if (!is.null(res$result)) {
    # Update predictions
    idx <- which(year_preds_df$year == res$year & year_preds_df$yday == res$yday)
    year_preds_df$mean[idx] <- res$result$mean
    year_preds_df$lwr[idx] <- res$result$lwr
    year_preds_df$upr[idx] <- res$result$upr
  }

  # Update stats
  model_stats$n_obs[i] <- res$n_obs
  if (!is.null(res$stats)) {
    model_stats$R2[i] <- res$stats$R2
    model_stats$NormCoef[i] <- res$stats$NormCoef
    model_stats$SplineP[i] <- res$stats$SplineP
    model_stats$RMSE[i] <- res$stats$RMSE
  }
}

# ==============================================================================
# FINAL SAVE
# ==============================================================================

cat("\n======================================\n")
cat("Processing complete!\n\n")

# Save predictions
cat("Saving year predictions...\n")
saveRDS(year_preds_df, config$output_file)

# Save model stats
cat("Saving model statistics...\n")
saveRDS(model_stats, config$stats_file)

# Summary statistics
n_complete <- sum(!is.na(year_preds_df$mean))
n_total <- nrow(year_preds_df)
pct_complete <- 100 * n_complete / n_total

cat("\nSummary:\n")
cat("  Total pixel-year-DOY combinations:", n_total, "\n")
cat("  Successfully fitted:", n_complete, sprintf("(%.1f%%)\n", pct_complete))
cat("  Predictions saved to:", config$output_file, "\n")
cat("  Model stats saved to:", config$stats_file, "\n")

# Model stats summary
cat("\nModel Statistics Summary:\n")
cat("  Mean R²:", round(mean(model_stats$R2, na.rm = TRUE), 3), "\n")
cat("  Mean Norm Coef:", round(mean(model_stats$NormCoef, na.rm = TRUE), 3), "\n")
cat("  Mean RMSE:", round(mean(model_stats$RMSE, na.rm = TRUE), 4), "\n")

elapsed_total <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
cat(sprintf("\nTotal time: %.1f minutes\n", elapsed_total))
