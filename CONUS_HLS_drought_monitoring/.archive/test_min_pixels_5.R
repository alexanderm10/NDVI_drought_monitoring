# ==============================================================================
# TEST: Re-aggregate 2024 data with min_pixels = 5
# ==============================================================================
# Purpose: Test if lowering the minimum pixel threshold increases obs/pixel/year
# Current: min_pixels = 10 (requires 10 clear 30m pixels per 4km cell)
# Test:    min_pixels = 5 (more lenient, accepts marginal data)
# ==============================================================================

library(terra)
library(sf)
library(dplyr)
library(lubridate)

# Source dependencies
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

# Source aggregation functions from main script
source("01_aggregate_to_4km.R")

cat("=== TESTING MIN_PIXELS THRESHOLD ===\n\n")
cat("Current setting: min_pixels_per_cell = 10\n")
cat("Test setting:    min_pixels_per_cell = 5\n\n")

# Configuration for test
test_config <- list(
  years = 2024,  # Only test 2024
  target_resolution = 4000,  # 4km in meters
  aggregation_method = "median",
  min_pixels_per_cell = 5  # ← LOWERED FROM 10
)

cat("Configuration:\n")
cat("  Year: 2024\n")
cat("  Resolution: 4km\n")
cat("  Aggregation: median\n")
cat("  Min pixels per cell: ", test_config$min_pixels_per_cell, "\n\n")

# Get list of 2024 NDVI files
ndvi_files <- list.files(
  file.path(hls_paths$processed_ndvi, "daily", "2024"),
  pattern = "_NDVI\\.tif$",
  full.names = TRUE
)

cat("Found", length(ndvi_files), "NDVI scenes for 2024\n\n")

# Create 4km reference grid
cat("Creating 4km reference grid...\n")
midwest_bbox <- c(-104.5, 37.0, -82.0, 47.5)
grid_4km <- create_4km_grid(test_config$target_resolution, midwest_bbox)
cat("Grid created:", ncell(grid_4km), "cells\n\n")

# Process all 2024 scenes
cat("Aggregating scenes to 4km (min_pixels = 5)...\n")
cat("Started at:", as.character(Sys.time()), "\n\n")

timeseries_list <- list()
n_processed <- 0
n_failed <- 0
start_time <- Sys.time()

for (i in seq_along(ndvi_files)) {

  ndvi_path <- ndvi_files[i]

  # Parse metadata
  meta <- tryCatch({
    parse_hls_filename(ndvi_path)
  }, error = function(e) {
    n_failed <<- n_failed + 1
    return(NULL)
  })

  if (is.null(meta)) next

  # Aggregate to 4km with min_pixels = 5
  agg_result <- tryCatch({
    aggregate_scene_to_4km(
      ndvi_path,
      grid_4km,
      method = test_config$aggregation_method,
      min_pixels = test_config$min_pixels_per_cell  # ← 5 instead of 10
    )
  }, error = function(e) {
    cat("  ⚠ Aggregation failed:", basename(ndvi_path), "\n")
    n_failed <<- n_failed + 1
    return(NULL)
  })

  if (is.null(agg_result) || nrow(agg_result) == 0) next

  # Add metadata
  agg_result$sensor <- meta$sensor
  agg_result$date <- meta$date
  agg_result$year <- meta$year
  agg_result$yday <- meta$yday

  timeseries_list[[i]] <- agg_result
  n_processed <- n_processed + 1

  # Progress report every 100 scenes
  if (n_processed %% 100 == 0) {
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
    rate <- n_processed / elapsed
    remaining <- (length(ndvi_files) - n_processed) / rate
    cat(sprintf("  Progress: %d/%d scenes (%.1f%%) | %.1f min elapsed | %.1f min remaining\n",
                n_processed, length(ndvi_files),
                n_processed/length(ndvi_files)*100,
                elapsed, remaining))
  }
}

# Combine all results
cat("\nCombining results...\n")
timeseries_df <- bind_rows(timeseries_list)

# Select columns
timeseries_df <- timeseries_df %>%
  select(pixel_id, sensor, date, year, yday, ndvi = ndvi_agg, n_pixels) %>%
  arrange(pixel_id, date)

cat("\n=== AGGREGATION COMPLETE ===\n")
cat("Processed:", n_processed, "scenes\n")
cat("Failed:", n_failed, "scenes\n")
cat("Total observations:", nrow(timeseries_df), "\n")
cat("Unique pixels:", length(unique(timeseries_df$pixel_id)), "\n")
cat("Unique dates:", length(unique(timeseries_df$date)), "\n\n")

# Save test results
output_file <- file.path(hls_paths$gam_models, "test_2024_min_pixels_5.rds")
saveRDS(timeseries_df, output_file)
cat("Saved to:", output_file, "\n\n")

# ==============================================================================
# COMPARISON ANALYSIS
# ==============================================================================

cat("=== COMPARING MIN_PIXELS = 10 vs MIN_PIXELS = 5 ===\n\n")

# Load original data (min_pixels = 10)
original_ts <- readRDS(file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.rds"))
original_2024 <- original_ts %>% filter(year(date) == 2024)

# Compare observation counts per pixel
obs_original <- original_2024 %>%
  group_by(pixel_id) %>%
  summarise(n_obs_original = n(), .groups = "drop")

obs_new <- timeseries_df %>%
  group_by(pixel_id) %>%
  summarise(n_obs_new = n(), .groups = "drop")

# Join for comparison
comparison <- full_join(obs_original, obs_new, by = "pixel_id") %>%
  mutate(
    n_obs_original = ifelse(is.na(n_obs_original), 0, n_obs_original),
    n_obs_new = ifelse(is.na(n_obs_new), 0, n_obs_new),
    gain = n_obs_new - n_obs_original,
    gain_pct = (gain / n_obs_original) * 100
  )

# Summary statistics
cat("OBSERVATION COUNTS PER PIXEL (2024):\n")
cat("  Original (min_pixels=10):\n")
cat("    Median:", median(comparison$n_obs_original), "obs\n")
cat("    Mean:  ", round(mean(comparison$n_obs_original), 1), "obs\n")
cat("    Range: ", min(comparison$n_obs_original), "-", max(comparison$n_obs_original), "obs\n\n")

cat("  New (min_pixels=5):\n")
cat("    Median:", median(comparison$n_obs_new), "obs\n")
cat("    Mean:  ", round(mean(comparison$n_obs_new), 1), "obs\n")
cat("    Range: ", min(comparison$n_obs_new), "-", max(comparison$n_obs_new), "obs\n\n")

cat("GAIN:\n")
cat("  Median gain:  +", median(comparison$gain), "obs (",
    sprintf("%.1f%%", median(comparison$gain_pct[!is.infinite(comparison$gain_pct)])), ")\n")
cat("  Mean gain:    +", round(mean(comparison$gain), 1), "obs (",
    sprintf("%.1f%%", mean(comparison$gain_pct[!is.infinite(comparison$gain_pct)])), ")\n")
cat("  Pixels improved:", sum(comparison$gain > 0), "/", nrow(comparison),
    " (", sprintf("%.1f%%", sum(comparison$gain > 0)/nrow(comparison)*100), ")\n\n")

# Date-level comparison
cat("UNIQUE DATES:\n")
cat("  Original: ", length(unique(original_2024$date)), "dates\n")
cat("  New:      ", length(unique(timeseries_df$date)), "dates\n")
cat("  Gain:     +", length(unique(timeseries_df$date)) - length(unique(original_2024$date)), "dates\n\n")

# Total observations
cat("TOTAL OBSERVATIONS (all pixels × all dates):\n")
cat("  Original: ", nrow(original_2024), "\n")
cat("  New:      ", nrow(timeseries_df), "\n")
cat("  Gain:     +", nrow(timeseries_df) - nrow(original_2024),
    " (", sprintf("%.1f%%", (nrow(timeseries_df) - nrow(original_2024))/nrow(original_2024)*100), ")\n\n")

# Predicted impact on k capacity
cat("=== IMPLICATIONS FOR GAM SPATIAL RESOLUTION ===\n\n")
original_median <- median(comparison$n_obs_original)
new_median <- median(comparison$n_obs_new)
improvement <- (new_median - original_median) / original_median

cat("Original: ", original_median, "obs/pixel/year → supports k=30-80\n")
cat("New:      ", new_median, "obs/pixel/year → supports k=",
    round(30 + improvement * 70), "-", round(80 + improvement * 70), "\n\n")

if (new_median >= 15) {
  cat("✓ SIGNIFICANT IMPROVEMENT! With ", new_median, " obs/pixel/year:\n")
  cat("  - k=100-120 should be feasible\n")
  cat("  - Spatial resolution: ~8-10 km\n")
  cat("  - Recommend reprocessing full dataset with min_pixels=5\n")
} else if (new_median >= 14) {
  cat("~ MODERATE IMPROVEMENT. With ", new_median, " obs/pixel/year:\n")
  cat("  - k=80-100 should be feasible\n")
  cat("  - Spatial resolution: ~10-12 km\n")
  cat("  - Consider reprocessing, borderline benefit\n")
} else {
  cat("✗ MINIMAL IMPROVEMENT. With ", new_median, " obs/pixel/year:\n")
  cat("  - Still limited to k=30-80\n")
  cat("  - Not worth reprocessing full dataset\n")
  cat("  - Consider other strategies (cloud_cover_max increase, multi-year pooling)\n")
}

cat("\n=== TEST COMPLETE ===\n")
cat("Test results saved to:", output_file, "\n")
