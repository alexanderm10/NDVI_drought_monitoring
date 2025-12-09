# ==============================================================================
# 04_calculate_anomalies.R
#
# Purpose: Calculate anomalies (year predictions - norms)
# Based on: Juliana's spatial_analysis/07_yday_looped_anomalies.R
#
# Approach:
#   - Load norms from script 02
#   - For each year from script 03:
#     - Merge year predictions with norms on (pixel_id, yday)
#     - Calculate anomalies with uncertainty:
#         anoms_mean = year_mean - norm_mean
#         anoms_lwr = year_lwr - norm_mean
#         anoms_upr = year_upr - norm_mean
#     - Save anomalies for each year
#
# Input:
#   - Script 02 norms output: doy_looped_norms.rds
#   - Script 03 year predictions: modeled_ndvi/modeled_ndvi_YYYY.rds
# Output:
#   - Anomalies for each year: modeled_ndvi_anomalies/anomalies_YYYY.rds
#
# ==============================================================================

# Limit BLAS/LAPACK threads to be a good neighbor on shared systems
Sys.setenv(OMP_NUM_THREADS = 2)
Sys.setenv(OPENBLAS_NUM_THREADS = 2)

library(dplyr)
library(lubridate)

# Source utility functions
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Input files
  norms_file = file.path(hls_paths$gam_models, "doy_looped_norms.rds"),
  year_dir = file.path(hls_paths$gam_models, "modeled_ndvi"),
  valid_pixels_file = file.path(hls_paths$gam_models, "valid_pixels_landcover_filtered.rds"),

  # Output
  output_dir = file.path(hls_paths$gam_models, "modeled_ndvi_anomalies"),
  stats_file = file.path(hls_paths$gam_models, "modeled_ndvi_anomalies_stats.rds")
)

# ==============================================================================
# MAIN
# ==============================================================================

cat("=== Calculate NDVI Anomalies ===\n")
cat("Output:", config$output_dir, "\n\n")

# Create output directory
if (!dir.exists(config$output_dir)) {
  dir.create(config$output_dir, recursive = TRUE)
  cat("Created output directory\n")
}

# Load valid pixels (land cover filtered)
cat("Loading valid pixels mask...\n")
if (!file.exists(config$valid_pixels_file)) {
  stop("Valid pixels file not found. Run script 02 first.")
}
valid_pixels_df <- readRDS(config$valid_pixels_file)
valid_pixels <- valid_pixels_df$pixel_id
cat("  Valid pixels (land cover filtered):", length(valid_pixels), "\n\n")

# Load norms from script 02
cat("Loading norms...\n")
if (!file.exists(config$norms_file)) {
  stop("Norms file not found. Run script 02 first.")
}
norms_df <- readRDS(config$norms_file)

# Verify norms are filtered
unique_norm_pixels <- unique(norms_df$pixel_id)
if (length(unique_norm_pixels) != length(valid_pixels)) {
  warning(sprintf("Norms pixel count (%d) differs from valid pixels (%d)",
                  length(unique_norm_pixels), length(valid_pixels)))
}

# Prepare norms: keep only pixel_id, yday, mean (rename to 'norm')
norms_df <- norms_df %>%
  select(pixel_id, yday, mean) %>%
  rename(norm = mean)

cat("  Norms loaded:", nrow(norms_df), "pixel-DOY combinations\n")
cat("  Unique pixels in norms:", length(unique_norm_pixels), "\n\n")

# Get list of year files from script 03
year_files <- list.files(config$year_dir, pattern = "modeled_ndvi_\\d{4}\\.rds", full.names = TRUE)
if (length(year_files) == 0) {
  stop("No year prediction files found. Run script 03 first.")
}

# Extract years from filenames
years <- as.integer(gsub(".*modeled_ndvi_(\\d{4})\\.rds", "\\1", basename(year_files)))
years <- sort(years)

cat("Found", length(years), "years to process:", paste(years, collapse = ", "), "\n\n")

# Check for existing output files (resume capability)
existing_years <- integer(0)
for (yr in years) {
  output_file <- file.path(config$output_dir, sprintf("anomalies_%d.rds", yr))
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

cat("Processing anomalies...\n")
cat("======================================\n\n")

start_time_total <- Sys.time()
year_stats <- list()

for (yr in years) {
  cat(sprintf("=== Processing Year %d ===\n", yr))
  start_time <- Sys.time()

  # Load year predictions from script 03
  year_file <- file.path(config$year_dir, sprintf("modeled_ndvi_%d.rds", yr))

  if (!file.exists(year_file)) {
    cat("  WARNING: Year file not found, skipping\n\n")
    next
  }

  year_preds <- readRDS(year_file)
  cat(sprintf("  Loaded predictions: %d rows\n", nrow(year_preds)))

  # Verify year predictions are filtered
  unique_year_pixels <- unique(year_preds$pixel_id)
  cat(sprintf("  Unique pixels in predictions: %d\n", length(unique_year_pixels)))
  if (length(unique_year_pixels) != length(valid_pixels)) {
    warning(sprintf("Year predictions pixel count (%d) differs from valid pixels (%d)",
                    length(unique_year_pixels), length(valid_pixels)))
  }

  # Merge with norms on (pixel_id, yday)
  cat("  Merging with norms...\n")
  merged_df <- year_preds %>%
    left_join(norms_df, by = c("pixel_id", "yday"))

  # Check for missing norms
  n_missing_norms <- sum(is.na(merged_df$norm))
  if (n_missing_norms > 0) {
    cat(sprintf("  WARNING: %d rows missing norms (%.2f%%)\n",
                n_missing_norms, 100 * n_missing_norms / nrow(merged_df)))
  }

  # Calculate anomalies
  cat("  Calculating anomalies...\n")
  anomalies_df <- merged_df %>%
    mutate(
      anoms_mean = mean - norm,
      anoms_lwr = lwr - norm,
      anoms_upr = upr - norm
    ) %>%
    select(pixel_id, yday, x, y, anoms_mean, anoms_lwr, anoms_upr)

  # Calculate statistics
  n_complete <- sum(complete.cases(anomalies_df[, c("anoms_mean", "anoms_lwr", "anoms_upr")]))
  pct_complete <- 100 * n_complete / nrow(anomalies_df)

  mean_anom <- mean(anomalies_df$anoms_mean, na.rm = TRUE)
  sd_anom <- sd(anomalies_df$anoms_mean, na.rm = TRUE)

  # Save anomalies
  output_file <- file.path(config$output_dir, sprintf("anomalies_%d.rds", yr))
  cat(sprintf("  Saving to: %s \n", output_file))
  saveRDS(anomalies_df, output_file)

  # Record statistics
  elapsed_time <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  year_stats[[as.character(yr)]] <- data.frame(
    year = yr,
    n_rows = nrow(anomalies_df),
    n_complete = n_complete,
    pct_complete = pct_complete,
    mean_anom = mean_anom,
    sd_anom = sd_anom,
    elapsed_mins = elapsed_time
  )

  cat(sprintf("  Year %d: %.1f%% complete in %.1f minutes\n\n",
              yr, pct_complete, elapsed_time))
}

# ==============================================================================
# SUMMARY
# ==============================================================================

elapsed_total <- as.numeric(difftime(Sys.time(), start_time_total, units = "mins"))

cat("======================================\n")
cat("All years complete!\n\n")

# Combine and save statistics
if (length(year_stats) > 0) {
  cat("Saving anomaly statistics...\n")
  stats_df <- do.call(rbind, year_stats)
  rownames(stats_df) <- NULL
  saveRDS(stats_df, config$stats_file)

  cat("\nSummary:\n")
  cat("  Years processed:", paste(stats_df$year, collapse = ", "), "\n")
  cat("  Output directory:", config$output_dir, "\n")
  cat("  Anomaly stats saved to:", config$stats_file, "\n\n")

  cat("Anomaly Statistics Summary:\n")
  cat(sprintf("  Mean anomaly range: %.4f to %.4f \n",
              min(stats_df$mean_anom), max(stats_df$mean_anom)))
  cat(sprintf("  Mean SD: %.4f \n", mean(stats_df$sd_anom)))
  cat(sprintf("  Average completion: %.1f%% \n", mean(stats_df$pct_complete)))
}

cat(sprintf("\nTotal time: %.1f minutes\n", elapsed_total))
