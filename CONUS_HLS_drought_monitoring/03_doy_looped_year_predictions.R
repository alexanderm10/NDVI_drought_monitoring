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

  # Output (year-by-year files)
  output_dir = file.path(hls_paths$gam_models, "modeled_ndvi"),
  stats_file = file.path(hls_paths$gam_models, "modeled_ndvi_stats.rds"),

  # Posterior simulation
  n_posterior_sims = 100,

  # Parallelization (conservative for shared systems)
  n_cores = 4
)

# Create output directory
if (!dir.exists(config$output_dir)) {
  dir.create(config$output_dir, recursive = TRUE)
}

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

# Get pixel coordinates (used for all years)
pixel_coords <- timeseries_df %>%
  group_by(pixel_id) %>%
  summarise(x = first(x), y = first(y), .groups = "drop") %>%
  as.data.frame()

# Check for existing year files (resume capability)
existing_years <- character(0)
for (yr in years) {
  year_file <- file.path(config$output_dir, sprintf("modeled_ndvi_%d.rds", yr))
  if (file.exists(year_file)) {
    existing_years <- c(existing_years, yr)
  }
}

if (length(existing_years) > 0) {
  cat("Found existing results for", length(existing_years), "years:", paste(existing_years, collapse=", "), "\n")
  years_to_process <- setdiff(years, existing_years)
} else {
  years_to_process <- years
}

if (length(years_to_process) == 0) {
  cat("All years already processed!\n")
  quit(save = "no")
}

cat("Will process", length(years_to_process), "years:", paste(years_to_process, collapse=", "), "\n\n")

# ==============================================================================
# MAIN PROCESSING - YEAR-BY-YEAR
# ==============================================================================

cat("Processing year predictions...\n")
cat("======================================\n\n")

overall_start <- Sys.time()

# Merge timeseries with norms once
timeseries_with_norms <- merge(
  timeseries_df,
  norms_df[, c("pixel_id", "yday", "mean")],
  by = c("pixel_id", "yday"),
  all.x = TRUE
)
names(timeseries_with_norms)[names(timeseries_with_norms) == "mean"] <- "norm"

# Initialize overall stats tracking
all_model_stats <- list()

# Process each year sequentially
for (yr in years_to_process) {

  cat("\n=== Processing Year", yr, "===\n")
  year_start <- Sys.time()

  # Don't create full year_grid upfront - save memory

  # Define function to process a single DOY for this year
  process_doy <- function(day) {
    tryCatch({
      # Get trailing window dates
      window_dates <- get_trailing_window(yr, day, config$window_size)

      # Filter data
      df_subset <- timeseries_with_norms %>%
        filter(date %in% window_dates) %>%
        filter(!is.na(NDVI) & !is.na(norm))

      # Check data requirement
      n_pixels_with_data <- length(unique(df_subset$pixel_id))
      if (n_pixels_with_data < n_pixels * config$min_pixel_coverage) {
        return(list(yday = day, result = NULL, stats = NULL, n_obs = nrow(df_subset)))
      }

      # Build prediction grid on-the-fly for just this DOY (141K rows)
      # Get norms for this DOY
      norms_for_doy <- norms_df[norms_df$yday == day, c("pixel_id", "mean")]
      names(norms_for_doy)[names(norms_for_doy) == "mean"] <- "norm"

      # Merge with pixel coords
      pred_grid <- merge(pixel_coords, norms_for_doy, by = "pixel_id", all.x = TRUE)
      pred_grid <- pred_grid[, c("pixel_id", "x", "y", "norm")]

      # Fit model
      fit_result <- fit_year_spatial_gam(df_subset, pred_grid, config$n_posterior_sims)

      return(list(
        yday = day,
        result = fit_result$result,
        stats = fit_result$stats,
        n_obs = nrow(df_subset)
      ))
    }, error = function(e) {
      return(list(yday = day, result = NULL, stats = NULL, n_obs = 0, error = as.character(e)))
    })
  }

  # Process all DOYs for this year in parallel
  cat("  Processing 365 DOYs with", config$n_cores, "cores...\n")

  results_list <- mclapply(
    1:365,
    process_doy,
    mc.cores = config$n_cores
  )

  # Combine results for this year
  cat("  Combining results...\n")

  year_stats <- data.frame(
    year = yr,
    yday = 1:365,
    R2 = NA_real_,
    NormCoef = NA_real_,
    SplineP = NA_real_,
    RMSE = NA_real_,
    n_obs = NA_integer_
  )

  # Build year_grid from results
  year_results_list <- list()

  for (i in seq_along(results_list)) {
    res <- results_list[[i]]

    # Update stats
    year_stats$n_obs[i] <- res$n_obs
    if (!is.null(res$stats)) {
      year_stats$R2[i] <- res$stats$R2
      year_stats$NormCoef[i] <- res$stats$NormCoef
      year_stats$SplineP[i] <- res$stats$SplineP
      year_stats$RMSE[i] <- res$stats$RMSE
    }

    # Store results if present
    if (!is.null(res$result)) {
      doy_df <- data.frame(
        pixel_id = pixel_coords$pixel_id,
        yday = res$yday,
        mean = res$result$mean,
        lwr = res$result$lwr,
        upr = res$result$upr
      )
      year_results_list[[i]] <- doy_df
    }
  }

  # Combine all DOYs into year_grid
  year_grid <- do.call(rbind, year_results_list)
  year_grid <- merge(year_grid, pixel_coords, by = "pixel_id", all.x = TRUE)

  # Save this year's results
  year_file <- file.path(config$output_dir, sprintf("modeled_ndvi_%d.rds", yr))
  cat("  Saving to:", year_file, "\n")
  saveRDS(year_grid, year_file)

  # Track stats
  all_model_stats[[as.character(yr)]] <- year_stats

  # Summary for this year
  n_complete <- sum(!is.na(year_grid$mean))
  n_total <- nrow(year_grid)
  pct_complete <- 100 * n_complete / n_total

  year_elapsed <- as.numeric(difftime(Sys.time(), year_start, units = "mins"))
  cat(sprintf("  Year %d: %.1f%% complete in %.1f minutes\n", yr, pct_complete, year_elapsed))
}

# ==============================================================================
# FINAL SAVE
# ==============================================================================

cat("\n======================================\n")
cat("All years complete!\n\n")

# Save combined stats
cat("Saving model statistics...\n")
combined_stats <- do.call(rbind, all_model_stats)
saveRDS(combined_stats, config$stats_file)

# Overall summary
cat("\nSummary:\n")
cat("  Years processed:", paste(years_to_process, collapse=", "), "\n")
cat("  Output directory:", config$output_dir, "\n")
cat("  Model stats saved to:", config$stats_file, "\n")

cat("\nModel Statistics Summary:\n")
cat("  Mean R²:", round(mean(combined_stats$R2, na.rm = TRUE), 3), "\n")
cat("  Mean Norm Coef:", round(mean(combined_stats$NormCoef, na.rm = TRUE), 3), "\n")
cat("  Mean RMSE:", round(mean(combined_stats$RMSE, na.rm = TRUE), 4), "\n")

elapsed_total <- as.numeric(difftime(Sys.time(), overall_start, units = "mins"))
cat(sprintf("\nTotal time: %.1f minutes\n", elapsed_total))
