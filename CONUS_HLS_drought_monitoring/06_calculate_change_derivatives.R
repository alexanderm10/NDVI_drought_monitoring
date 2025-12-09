# ==============================================================================
# 06_calculate_change_derivatives.R
#
# Purpose: Calculate change derivatives (rate of change anomalies) using
#          posteriors from baseline norms and year predictions
#
# Approach:
#   - For multiple time windows (3, 7, 14, 30 days):
#     - Calculate baseline change: baseline[day] - baseline[day-k]
#     - Calculate year change: year[day] - year[day-k]
#     - Calculate change anomaly: year_change - baseline_change
#   - Use full posterior distributions for uncertainty propagation
#   - Test significance: 95% CI excludes zero
#
# Input:
#   - Baseline posteriors from script 02: baseline_posteriors/doy_*.rds
#   - Year posteriors from script 03: year_predictions_posteriors/YYYY/doy_*.rds
#   - Valid pixels: valid_pixels_landcover_filtered.rds
#
# Output:
#   - Summary stats for each year: change_derivatives/derivatives_YYYY.rds
#   - Posteriors: change_derivatives_posteriors/YYYY/doy_XXX_window_YY.rds
#
# ==============================================================================

# Limit BLAS/LAPACK threads
Sys.setenv(OMP_NUM_THREADS = 2)
Sys.setenv(OPENBLAS_NUM_THREADS = 2)

library(dplyr)
library(parallel)

# Source utility functions
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Input directories
  baseline_posteriors_dir = file.path(hls_paths$gam_models, "baseline_posteriors"),
  year_posteriors_dir = file.path(hls_paths$gam_models, "year_predictions_posteriors"),
  valid_pixels_file = file.path(hls_paths$gam_models, "valid_pixels_landcover_filtered.rds"),

  # Time windows for change calculation (days)
  window_sizes = c(3, 7, 14, 30),

  # Output directories
  output_dir = file.path(hls_paths$gam_models, "change_derivatives"),
  posteriors_dir = file.path(hls_paths$gam_models, "change_derivatives_posteriors"),
  stats_file = file.path(hls_paths$gam_models, "change_derivatives_stats.rds"),

  # Posterior simulation count (must match scripts 02/03)
  n_posterior_sims = 100,

  # Parallelization (conservative for memory with posterior saving)
  n_cores = 3
)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Wrap DOY to valid range [1, 365]
wrap_doy <- function(doy) {
  while (doy < 1) doy <- doy + 365
  while (doy > 365) doy <- doy - 365
  return(doy)
}

#' Check if posterior file exists
posterior_exists <- function(year, doy, posteriors_dir, is_baseline = FALSE) {
  if (is_baseline) {
    file_path <- file.path(posteriors_dir, sprintf("doy_%03d.rds", doy))
  } else {
    file_path <- file.path(posteriors_dir, as.character(year), sprintf("doy_%03d.rds", doy))
  }
  return(file.exists(file_path))
}

#' Load posterior array for a specific DOY
#' Returns: matrix with pixels as rows, simulations as columns
load_posteriors <- function(year, doy, posteriors_dir, is_baseline = FALSE) {
  if (is_baseline) {
    file_path <- file.path(posteriors_dir, sprintf("doy_%03d.rds", doy))
  } else {
    file_path <- file.path(posteriors_dir, as.character(year), sprintf("doy_%03d.rds", doy))
  }

  if (!file.exists(file_path)) {
    return(NULL)
  }

  return(readRDS(file_path))
}

#' Calculate summary statistics from posterior simulations
#' @param sims Matrix with pixels as rows, simulations as columns
calculate_stats <- function(sims) {
  data.frame(
    mean = rowMeans(sims, na.rm = TRUE),
    lwr = apply(sims, 1, quantile, 0.025, na.rm = TRUE),
    upr = apply(sims, 1, quantile, 0.975, na.rm = TRUE)
  )
}

#' Calculate change anomalies for a specific year-DOY-window combination
#' Returns list with summary stats and posteriors
calculate_change_anomaly <- function(year, yday, window, valid_pixel_ids,
                                      baseline_post_dir, year_post_dir) {

  # Calculate lagged DOY
  yday_lagged <- wrap_doy(yday - window)

  # Check if we need previous year's data (for early DOYs with long windows)
  year_current <- year
  year_lagged <- if (yday_lagged > yday) year - 1 else year

  # Check if all required files exist
  baseline_t_exists <- posterior_exists(NULL, yday, baseline_post_dir, is_baseline = TRUE)
  baseline_t_lag_exists <- posterior_exists(NULL, yday_lagged, baseline_post_dir, is_baseline = TRUE)
  year_t_exists <- posterior_exists(year_current, yday, year_post_dir)
  year_t_lag_exists <- posterior_exists(year_lagged, yday_lagged, year_post_dir)

  if (!all(c(baseline_t_exists, baseline_t_lag_exists, year_t_exists, year_t_lag_exists))) {
    # Missing data - return NULL
    return(NULL)
  }

  # Load all 4 posterior arrays
  baseline_t <- load_posteriors(NULL, yday, baseline_post_dir, is_baseline = TRUE)
  baseline_t_lag <- load_posteriors(NULL, yday_lagged, baseline_post_dir, is_baseline = TRUE)
  year_t <- load_posteriors(year_current, yday, year_post_dir)
  year_t_lag <- load_posteriors(year_lagged, yday_lagged, year_post_dir)

  # Verify dimensions match
  if (is.null(baseline_t) || is.null(baseline_t_lag) ||
      is.null(year_t) || is.null(year_t_lag)) {
    return(NULL)
  }

  # Calculate changes (for each simulation)
  # Change = current - lagged (positive = increasing, negative = decreasing)
  baseline_change_sims <- baseline_t - baseline_t_lag
  year_change_sims <- year_t - year_t_lag

  # Calculate anomaly (difference of differences)
  # Positive anomaly = year increasing faster than baseline (or decreasing slower)
  # Negative anomaly = year decreasing faster than baseline (drought stress signal)
  anomaly_sims <- year_change_sims - baseline_change_sims

  # Calculate summary statistics
  baseline_change_stats <- calculate_stats(baseline_change_sims)
  year_change_stats <- calculate_stats(year_change_sims)
  anomaly_stats <- calculate_stats(anomaly_sims)

  # Test significance (95% CI excludes zero)
  significant <- (anomaly_stats$lwr > 0) | (anomaly_stats$upr < 0)

  # Calculate posterior probabilities
  prob_slower <- rowMeans(anomaly_sims < 0, na.rm = TRUE)  # Year changing slower
  prob_faster <- rowMeans(anomaly_sims > 0, na.rm = TRUE)  # Year changing faster

  # Combine summary statistics
  summary_df <- data.frame(
    pixel_id = valid_pixel_ids,

    # Baseline change
    baseline_change_mean = baseline_change_stats$mean,
    baseline_change_lwr = baseline_change_stats$lwr,
    baseline_change_upr = baseline_change_stats$upr,

    # Year change
    year_change_mean = year_change_stats$mean,
    year_change_lwr = year_change_stats$lwr,
    year_change_upr = year_change_stats$upr,

    # Anomaly
    anomaly_change_mean = anomaly_stats$mean,
    anomaly_change_lwr = anomaly_stats$lwr,
    anomaly_change_upr = anomaly_stats$upr,

    # Significance
    significant = significant,
    prob_slower = prob_slower,
    prob_faster = prob_faster
  )

  return(list(
    summary = summary_df,
    posteriors = anomaly_sims
  ))
}

#' Process all windows for a specific year-DOY combination
process_year_doy <- function(year, yday, window_sizes, valid_pixel_ids,
                               baseline_post_dir, year_post_dir, posteriors_output_dir) {

  results_list <- list()

  for (window in window_sizes) {
    # Calculate change anomaly
    result <- tryCatch({
      calculate_change_anomaly(year, yday, window, valid_pixel_ids,
                                baseline_post_dir, year_post_dir)
    }, error = function(e) {
      warning(sprintf("Error in year %d, DOY %d, window %d: %s",
                      year, yday, window, e$message))
      return(NULL)
    })

    if (is.null(result)) {
      next  # Skip if data missing or error
    }

    # Save posteriors immediately to avoid memory buildup
    year_post_dir_out <- file.path(posteriors_output_dir, as.character(year))
    if (!dir.exists(year_post_dir_out)) {
      dir.create(year_post_dir_out, recursive = TRUE)
    }

    posterior_file <- file.path(year_post_dir_out,
                                 sprintf("doy_%03d_window_%02d.rds", yday, window))
    saveRDS(result$posteriors, posterior_file, compress = "xz")

    # Add metadata and store summary
    result$summary$yday <- yday
    result$summary$window <- window
    results_list[[as.character(window)]] <- result$summary
  }

  # Combine all windows for this DOY
  if (length(results_list) > 0) {
    return(do.call(rbind, results_list))
  } else {
    return(NULL)
  }
}

# ==============================================================================
# MAIN
# ==============================================================================

cat("=== Calculate Change Derivatives ===\n")
cat("Windows:", paste(config$window_sizes, "days"), "\n")
cat("Output:", config$output_dir, "\n")
cat("Posteriors:", config$posteriors_dir, "\n\n")

# Create output directories
if (!dir.exists(config$output_dir)) {
  dir.create(config$output_dir, recursive = TRUE)
}
if (!dir.exists(config$posteriors_dir)) {
  dir.create(config$posteriors_dir, recursive = TRUE)
}

# Load valid pixels
cat("Loading valid pixels...\n")
if (!file.exists(config$valid_pixels_file)) {
  stop("Valid pixels file not found. Run script 02 first.")
}
valid_pixels_df <- readRDS(config$valid_pixels_file)
valid_pixel_ids <- valid_pixels_df$pixel_id
cat("  Valid pixels:", length(valid_pixel_ids), "\n\n")

# Get list of years from year posteriors directory
year_dirs <- list.dirs(config$year_posteriors_dir, full.names = FALSE, recursive = FALSE)
years <- as.integer(year_dirs)
years <- sort(years[!is.na(years)])

if (length(years) == 0) {
  stop("No year posterior directories found. Run script 03 first.")
}

cat("Found", length(years), "years:", paste(years, collapse = ", "), "\n\n")

# Check for existing results (resume capability)
existing_years <- integer(0)
for (yr in years) {
  output_file <- file.path(config$output_dir, sprintf("derivatives_%d.rds", yr))
  if (file.exists(output_file)) {
    existing_years <- c(existing_years, yr)
  }
}

if (length(existing_years) > 0) {
  cat("Found existing results for", length(existing_years), "years:",
      paste(existing_years, collapse = ", "), "\n")
  years <- setdiff(years, existing_years)

  if (length(years) == 0) {
    cat("All years already processed!\n")
    quit(save = "no", status = 0)
  }

  cat("Will process", length(years), "years:", paste(years, collapse = ", "), "\n\n")
}

# ==============================================================================
# PROCESS EACH YEAR
# ==============================================================================

cat("Processing change derivatives...\n")
cat("======================================\n\n")

start_time_total <- Sys.time()
year_stats <- list()

for (yr in years) {
  cat(sprintf("=== Processing Year %d ===\n", yr))
  start_time <- Sys.time()

  # Get list of DOYs available for this year
  year_doy_dir <- file.path(config$year_posteriors_dir, as.character(yr))
  if (!dir.exists(year_doy_dir)) {
    cat("  WARNING: Year directory not found, skipping\n\n")
    next
  }

  doy_files <- list.files(year_doy_dir, pattern = "doy_\\d{3}\\.rds")
  available_doys <- as.integer(gsub("doy_(\\d{3})\\.rds", "\\1", doy_files))
  available_doys <- sort(available_doys)

  cat(sprintf("  Available DOYs: %d\n", length(available_doys)))
  cat(sprintf("  Processing with %d cores...\n", config$n_cores))

  # Process all DOYs in parallel
  doy_results <- mclapply(available_doys, function(yday) {
    process_year_doy(yr, yday, config$window_sizes, valid_pixel_ids,
                      config$baseline_posteriors_dir, config$year_posteriors_dir,
                      config$posteriors_dir)
  }, mc.cores = config$n_cores)

  # Combine results
  cat("  Combining results...\n")
  valid_results <- doy_results[!sapply(doy_results, is.null)]

  if (length(valid_results) == 0) {
    cat("  WARNING: No valid results for this year\n\n")
    next
  }

  year_df <- do.call(rbind, valid_results)
  year_df$year <- yr

  # Calculate statistics
  n_complete <- nrow(year_df)
  n_significant <- sum(year_df$significant, na.rm = TRUE)
  pct_significant <- 100 * n_significant / n_complete

  # Save year results
  output_file <- file.path(config$output_dir, sprintf("derivatives_%d.rds", yr))
  cat(sprintf("  Saving to: %s\n", output_file))
  saveRDS(year_df, output_file, compress = "xz")

  # Record statistics
  elapsed_time <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  year_stats[[as.character(yr)]] <- data.frame(
    year = yr,
    n_results = n_complete,
    n_significant = n_significant,
    pct_significant = pct_significant,
    mean_anomaly = mean(year_df$anomaly_change_mean, na.rm = TRUE),
    elapsed_mins = elapsed_time
  )

  cat(sprintf("  Year %d: %.1f%% significant in %.1f minutes\n\n",
              yr, pct_significant, elapsed_time))
}

# ==============================================================================
# SUMMARY
# ==============================================================================

elapsed_total <- as.numeric(difftime(Sys.time(), start_time_total, units = "mins"))

cat("======================================\n")
cat("All years complete!\n\n")

# Combine and save statistics
if (length(year_stats) > 0) {
  cat("Saving derivative statistics...\n")
  stats_df <- do.call(rbind, year_stats)
  rownames(stats_df) <- NULL
  saveRDS(stats_df, config$stats_file)

  cat("\nSummary:\n")
  cat("  Years processed:", paste(stats_df$year, collapse = ", "), "\n")
  cat("  Output directory:", config$output_dir, "\n")
  cat("  Posteriors directory:", config$posteriors_dir, "\n")
  cat("  Stats saved to:", config$stats_file, "\n\n")

  cat("Change Derivative Statistics:\n")
  cat(sprintf("  Mean significant results: %.1f%%\n", mean(stats_df$pct_significant)))
  cat(sprintf("  Mean anomaly: %.6f\n", mean(stats_df$mean_anomaly)))
}

cat(sprintf("\nTotal time: %.1f minutes\n", elapsed_total))
