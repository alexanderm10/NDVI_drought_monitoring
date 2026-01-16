# ==============================================================================
# TEST: Re-aggregate 2024 data with min_pixels = 5 (STANDALONE VERSION)
# ==============================================================================
# Purpose: Test if lowering the minimum pixel threshold increases obs/pixel/year
# Current: min_pixels = 10 (requires 10 clear 30m pixels per 4km cell)
# Test:    min_pixels = 5 (more lenient, accepts marginal data)
# ==============================================================================

library(terra)
library(sf)
library(dplyr)
library(lubridate)

# Source ONLY path setup
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

cat("=== TESTING MIN_PIXELS THRESHOLD ===\n\n")
cat("Current setting: min_pixels_per_cell = 10\n")
cat("Test setting:    min_pixels_per_cell = 5\n\n")

# ==============================================================================
# INLINE FUNCTIONS (copied from 01_aggregate_to_4km.R)
# ==============================================================================

create_4km_grid <- function(resolution = 4000, bbox_latlon) {
  target_crs <- "EPSG:5070"  # Albers Equal Area

  bbox_sf <- st_as_sfc(st_bbox(c(xmin = bbox_latlon[1], ymin = bbox_latlon[2],
                                   xmax = bbox_latlon[3], ymax = bbox_latlon[4]),
                                 crs = st_crs(4326)))
  bbox_albers <- st_transform(bbox_sf, crs = target_crs)
  albers_extent <- ext(st_bbox(bbox_albers))

  grid_4km <- rast(extent = albers_extent, resolution = resolution, crs = target_crs)
  values(grid_4km) <- 1:ncell(grid_4km)

  cat("  CRS: Albers Equal Area (EPSG:5070)\n")
  cat("  Grid dimensions:", paste(dim(grid_4km), collapse = " x "), "\n")
  cat("  Total 4km cells:", ncell(grid_4km), "\n\n")

  return(grid_4km)
}

aggregate_scene_to_4km <- function(ndvi_path, grid_4km, method = "median", min_pixels = 10) {
  ndvi_30m <- rast(ndvi_path)

  if (!same.crs(ndvi_30m, grid_4km)) {
    grid_4km_reproj <- project(grid_4km, crs(ndvi_30m), method = "near")
  } else {
    grid_4km_reproj <- grid_4km
  }

  grid_30m <- resample(grid_4km_reproj, ndvi_30m, method = "near")

  pixel_ids <- values(grid_30m, mat = FALSE)
  ndvi_vals <- values(ndvi_30m, mat = FALSE)

  df <- data.frame(pixel_id = pixel_ids, ndvi = ndvi_vals)
  df <- df[!is.na(df$pixel_id) & !is.na(df$ndvi), ]

  if (method == "median") {
    agg_result <- df %>%
      group_by(pixel_id) %>%
      summarise(ndvi_agg = median(ndvi, na.rm = TRUE), n_pixels = n(), .groups = "drop")
  } else {
    agg_result <- df %>%
      group_by(pixel_id) %>%
      summarise(ndvi_agg = mean(ndvi, na.rm = TRUE), n_pixels = n(), .groups = "drop")
  }

  agg_result <- agg_result %>% filter(n_pixels >= min_pixels)

  return(agg_result)
}

parse_hls_filename <- function(filepath) {
  filename <- basename(filepath)
  parts <- strsplit(filename, "\\.")[[1]]

  sensor <- parts[2]
  tile <- parts[3]
  datetime_part <- parts[4]

  year <- as.integer(substr(datetime_part, 1, 4))
  yday <- as.integer(substr(datetime_part, 5, 7))
  date <- as.Date(paste0(year, "-01-01")) + (yday - 1)

  return(list(sensor = sensor, tile = tile, date = date, year = year, yday = yday))
}

# ==============================================================================
# MAIN TEST
# ==============================================================================

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
grid_4km <- create_4km_grid(4000, midwest_bbox)

# Process all 2024 scenes with min_pixels = 5
cat("Aggregating scenes to 4km (min_pixels = 5)...\n")
cat("Started at:", as.character(Sys.time()), "\n\n")

timeseries_list <- list()
n_processed <- 0
n_failed <- 0
start_time <- Sys.time()

for (i in seq_along(ndvi_files)) {

  ndvi_path <- ndvi_files[i]

  meta <- tryCatch({
    parse_hls_filename(ndvi_path)
  }, error = function(e) {
    n_failed <<- n_failed + 1
    return(NULL)
  })

  if (is.null(meta)) next

  agg_result <- tryCatch({
    aggregate_scene_to_4km(ndvi_path, grid_4km, method = "median", min_pixels = 5)
  }, error = function(e) {
    cat("  ⚠ Aggregation failed:", basename(ndvi_path), "\n")
    n_failed <<- n_failed + 1
    return(NULL)
  })

  if (is.null(agg_result) || nrow(agg_result) == 0) next

  agg_result$sensor <- meta$sensor
  agg_result$date <- meta$date
  agg_result$year <- meta$year
  agg_result$yday <- meta$yday

  timeseries_list[[i]] <- agg_result
  n_processed <- n_processed + 1

  if (n_processed %% 500 == 0) {
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
    rate <- n_processed / elapsed
    remaining <- (length(ndvi_files) - n_processed) / rate
    cat(sprintf("  Progress: %d/%d scenes (%.1f%%) | %.1f min elapsed | %.1f min remaining\n",
                n_processed, length(ndvi_files),
                n_processed/length(ndvi_files)*100,
                elapsed, remaining))
  }
}

# Combine results
cat("\nCombining results...\n")
timeseries_df <- bind_rows(timeseries_list)

timeseries_df <- timeseries_df %>%
  select(pixel_id, sensor, date, year, yday, ndvi = ndvi_agg, n_pixels) %>%
  arrange(pixel_id, date)

cat("\n=== AGGREGATION COMPLETE ===\n")
cat("Processed:", n_processed, "scenes\n")
cat("Failed:", n_failed, "scenes\n")
cat("Total observations:", nrow(timeseries_df), "\n")
cat("Unique pixels:", length(unique(timeseries_df$pixel_id)), "\n")
cat("Unique dates:", length(unique(timeseries_df$date)), "\n\n")

# Save results
output_file <- file.path(hls_paths$gam_models, "test_2024_min_pixels_5.rds")
saveRDS(timeseries_df, output_file)
cat("Saved to:", output_file, "\n\n")

# ==============================================================================
# COMPARISON ANALYSIS
# ==============================================================================

cat("=== COMPARING MIN_PIXELS = 10 vs MIN_PIXELS = 5 ===\n\n")

# Load original data
original_ts <- readRDS(file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.rds"))
original_2024 <- original_ts %>% filter(year(date) == 2024)

# Compare observation counts per pixel
obs_original <- original_2024 %>%
  group_by(pixel_id) %>%
  summarise(n_obs_original = n(), .groups = "drop")

obs_new <- timeseries_df %>%
  group_by(pixel_id) %>%
  summarise(n_obs_new = n(), .groups = "drop")

comparison <- full_join(obs_original, obs_new, by = "pixel_id") %>%
  mutate(
    n_obs_original = ifelse(is.na(n_obs_original), 0, n_obs_original),
    n_obs_new = ifelse(is.na(n_obs_new), 0, n_obs_new),
    gain = n_obs_new - n_obs_original,
    gain_pct = ifelse(n_obs_original > 0, (gain / n_obs_original) * 100, NA)
  )

# Summary
cat("OBSERVATION COUNTS PER PIXEL (2024 only):\n\n")
cat("  Original (min_pixels=10):\n")
cat("    Median:", median(comparison$n_obs_original), "obs\n")
cat("    Mean:  ", round(mean(comparison$n_obs_original), 1), "obs\n")
cat("    Range: ", min(comparison$n_obs_original), "-", max(comparison$n_obs_original), "obs\n\n")

cat("  New (min_pixels=5):\n")
cat("    Median:", median(comparison$n_obs_new), "obs\n")
cat("    Mean:  ", round(mean(comparison$n_obs_new), 1), "obs\n")
cat("    Range: ", min(comparison$n_obs_new), "-", max(comparison$n_obs_new), "obs\n\n")

cat("GAIN PER PIXEL:\n")
cat("  Median gain:  +", median(comparison$gain), "obs (",
    sprintf("%.1f%%", median(comparison$gain_pct, na.rm=TRUE)), ")\n")
cat("  Mean gain:    +", round(mean(comparison$gain), 1), "obs (",
    sprintf("%.1f%%", mean(comparison$gain_pct, na.rm=TRUE)), ")\n")
cat("  Pixels improved:", sum(comparison$gain > 0), "/", nrow(comparison),
    " (", sprintf("%.1f%%", sum(comparison$gain > 0)/nrow(comparison)*100), ")\n\n")

# Total observations
cat("TOTAL OBSERVATIONS (all pixels × all dates):\n")
cat("  Original: ", format(nrow(original_2024), big.mark=","), "\n")
cat("  New:      ", format(nrow(timeseries_df), big.mark=","), "\n")
cat("  Gain:     +", format(nrow(timeseries_df) - nrow(original_2024), big.mark=","),
    " (+", sprintf("%.1f%%", (nrow(timeseries_df) - nrow(original_2024))/nrow(original_2024)*100), ")\n\n")

# Implications
cat("=== IMPLICATIONS FOR GAM SPATIAL RESOLUTION ===\n\n")
original_median <- median(comparison$n_obs_original)
new_median <- median(comparison$n_obs_new)
improvement_pct <- ((new_median - original_median) / original_median) * 100

cat("Current (min_pixels=10): ", original_median, "obs/pixel/year → supports k≈30-80\n")
cat("New (min_pixels=5):      ", new_median, "obs/pixel/year → supports k≈",
    round(sqrt(new_median / 13) * 80), "\n")
cat("Improvement:             +", new_median - original_median, "obs (+",
    sprintf("%.1f%%", improvement_pct), ")\n\n")

if (new_median >= 16) {
  cat("✓ EXCELLENT! With ", new_median, " obs/pixel/year:\n")
  cat("  - k=120-150 feasible without overfitting\n")
  cat("  - STRONG RECOMMENDATION: Reprocess full dataset with min_pixels=5\n\n")
} else if (new_median >= 15) {
  cat("✓ SIGNIFICANT IMPROVEMENT! With ", new_median, " obs/pixel/year:\n")
  cat("  - k=100-120 should be feasible\n")
  cat("  - RECOMMENDATION: Reprocess full dataset with min_pixels=5\n\n")
} else if (new_median >= 14) {
  cat("~ MODERATE IMPROVEMENT. With ", new_median, " obs/pixel/year:\n")
  cat("  - k=80-100 feasible\n")
  cat("  - Consider reprocessing if k=80 test shows good results\n\n")
} else {
  cat("✗ MINIMAL IMPROVEMENT. With ", new_median, " obs/pixel/year:\n")
  cat("  - Still limited to k=30-80 range\n")
  cat("  - Not worth full reprocessing effort\n")
  cat("  - Consider alternatives: increase cloud_cover_max or multi-year pooling\n\n")
}

cat("=== TEST COMPLETE ===\n")
cat("Completed at:", as.character(Sys.time()), "\n")
cat("Results saved to:", output_file, "\n")
