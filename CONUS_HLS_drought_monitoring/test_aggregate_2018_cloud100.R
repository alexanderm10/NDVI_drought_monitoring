# ==============================================================================
# TEST: Aggregate 2018 NDVI with cloud_cover_max=100% data
# ==============================================================================
# Purpose: Compare observation density with relaxed cloud pre-filter
# - Uses min_pixels_per_cell = 5 (from earlier test showing +23% improvement)
# - Processes only 2018 data (downloaded with cloud_cover_max=100%)
# - Outputs to separate test file for comparison
# ==============================================================================

library(terra)
library(dplyr)
library(lubridate)

# Source path configuration
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

cat("=== TEST: 2018 AGGREGATION (cloud_cover_max=100%, min_pixels=5) ===\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  target_resolution = 4000,  # 4km in meters
  aggregation_method = "median",
  years = 2018,  # Only 2018 for this test
  min_pixels_per_cell = 5,  # Reduced from 10 based on earlier test
  output_file = file.path(hls_paths$gam_models, "test_2018_cloud100_min5_timeseries.csv"),
  checkpoint_interval = 500,
  resume_from_checkpoint = TRUE
)

cat("Configuration:\n")
cat("  Target resolution:", config$target_resolution, "m\n")
cat("  Aggregation method:", config$aggregation_method, "\n")
cat("  Year:", config$years, "\n")
cat("  min_pixels_per_cell:", config$min_pixels_per_cell, "\n")
cat("  Output:", config$output_file, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS (copied from main script)
# ==============================================================================

create_4km_grid <- function(resolution = 4000, bbox_latlon = c(-104.5, 37.0, -82.0, 47.5)) {
  cat("Creating 4km reference grid in Albers Equal Area projection...\n")
  target_crs <- "EPSG:5070"

  bbox_latlon_vect <- vect(
    data.frame(x = bbox_latlon[c(1,3,3,1,1)],
               y = bbox_latlon[c(2,2,4,4,2)]),
    geom = c("x", "y"),
    crs = "EPSG:4326"
  )
  bbox_albers <- project(bbox_latlon_vect, target_crs)
  albers_extent <- ext(bbox_albers)

  grid_4km <- rast(
    extent = albers_extent,
    resolution = resolution,
    crs = target_crs
  )

  values(grid_4km) <- 1:ncell(grid_4km)

  cat("  Grid dimensions:", paste(dim(grid_4km), collapse = " x "), "\n")
  cat("  Total 4km cells:", ncell(grid_4km), "\n\n")

  return(grid_4km)
}

aggregate_scene_to_4km <- function(ndvi_path, grid_4km, method = "median", min_pixels = 5) {
  ndvi_30m <- rast(ndvi_path)

  if (!same.crs(ndvi_30m, grid_4km)) {
    grid_4km_reproj <- project(grid_4km, crs(ndvi_30m), method = "near")
  } else {
    grid_4km_reproj <- grid_4km
  }

  grid_30m <- resample(grid_4km_reproj, ndvi_30m, method = "near")

  pixel_ids <- values(grid_30m, mat = FALSE)
  ndvi_vals <- values(ndvi_30m, mat = FALSE)

  df <- data.frame(
    pixel_id = pixel_ids,
    ndvi = ndvi_vals
  )

  df <- df[!is.na(df$pixel_id) & !is.na(df$ndvi), ]

  if (method == "median") {
    agg_result <- df %>%
      group_by(pixel_id) %>%
      summarise(
        ndvi_agg = median(ndvi, na.rm = TRUE),
        n_pixels = n(),
        .groups = "drop"
      )
  } else {
    agg_result <- df %>%
      group_by(pixel_id) %>%
      summarise(
        ndvi_agg = mean(ndvi, na.rm = TRUE),
        n_pixels = n(),
        .groups = "drop"
      )
  }

  agg_result <- agg_result %>%
    filter(n_pixels >= min_pixels)

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

  return(list(
    sensor = sensor,
    tile = tile,
    date = date,
    year = year,
    yday = yday
  ))
}

# ==============================================================================
# MAIN PROCESSING
# ==============================================================================

cat("=== STARTING 2018 AGGREGATION TEST ===\n\n")

# Get 2018 NDVI files
year_dir <- file.path(hls_paths$processed_ndvi, "daily", 2018)
ndvi_files <- list.files(year_dir, pattern = "_NDVI\\.tif$", full.names = TRUE)

cat("2018 NDVI files found:", length(ndvi_files), "\n")
cat("  Landsat:", sum(grepl("HLS.L30", ndvi_files)), "\n")
cat("  Sentinel:", sum(grepl("HLS.S30", ndvi_files)), "\n\n")

# Check for checkpoint
checkpoint_file <- sub("\\.csv$", "_checkpoint.rds", config$output_file)

if (config$resume_from_checkpoint && file.exists(checkpoint_file)) {
  cat("Found checkpoint - loading...\n")
  timeseries_df <- readRDS(checkpoint_file)

  processed_files <- unique(paste0(timeseries_df$sensor, ".", format(timeseries_df$date, "%Y%j")))

  ndvi_files <- ndvi_files[!sapply(ndvi_files, function(f) {
    meta <- parse_hls_filename(f)
    paste0(meta$sensor, ".", format(meta$date, "%Y%j")) %in% processed_files
  })]

  cat("  Resuming from", nrow(timeseries_df), "existing observations\n")
  cat("  ", length(ndvi_files), "scenes remaining\n\n")
} else {
  timeseries_df <- data.frame()
}

# Create 4km grid
midwest_bbox <- c(-104.5, 37.0, -82.0, 47.5)
grid_4km <- create_4km_grid(config$target_resolution, midwest_bbox)

grid_coords <- as.data.frame(grid_4km, xy = TRUE, cells = TRUE)
names(grid_coords) <- c("pixel_id", "x", "y")

# Process scenes
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
    aggregate_scene_to_4km(ndvi_path, grid_4km,
                          config$aggregation_method,
                          config$min_pixels_per_cell)
  }, error = function(e) {
    cat("  Failed:", basename(ndvi_path), "-", e$message, "\n")
    n_failed <<- n_failed + 1
    return(NULL)
  })

  if (is.null(agg_result) || nrow(agg_result) == 0) next

  agg_result$sensor <- meta$sensor
  agg_result$date <- meta$date
  agg_result$year <- meta$year
  agg_result$yday <- meta$yday

  names(agg_result)[names(agg_result) == "ndvi_agg"] <- "NDVI"

  agg_result <- merge(agg_result, grid_coords, by = "pixel_id", all.x = TRUE)
  agg_result <- agg_result[, c("pixel_id", "x", "y", "sensor", "date", "year", "yday", "NDVI")]

  timeseries_df <- bind_rows(timeseries_df, agg_result)

  n_processed <- n_processed + 1

  if (n_processed %% 100 == 0) {
    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
    scenes_per_min <- n_processed / elapsed
    remaining <- length(ndvi_files) - n_processed
    eta_mins <- remaining / scenes_per_min

    cat(sprintf("  Progress: %d/%d scenes (%.1f%%) | %.1f scenes/min | ETA: %.0f min\n",
                n_processed, length(ndvi_files),
                100 * n_processed / length(ndvi_files),
                scenes_per_min, eta_mins))
  }

  if (n_processed %% config$checkpoint_interval == 0) {
    cat("  Saving checkpoint...\n")
    saveRDS(timeseries_df, checkpoint_file, compress = "gzip")
  }
}

# Deduplication
cat("\n=== AGGREGATION COMPLETE ===\n")
cat("Scenes processed:", n_processed, "\n")
cat("Scenes failed:", n_failed, "\n")
cat("Total observations (before deduplication):", nrow(timeseries_df), "\n")

cat("\nApplying deduplication for tile overlaps...\n")
n_before <- nrow(timeseries_df)

timeseries_df <- timeseries_df %>%
  group_by(pixel_id, x, y, sensor, date, year, yday) %>%
  summarise(NDVI = median(NDVI, na.rm = TRUE), .groups = "drop")

n_after <- nrow(timeseries_df)
cat("  Removed", n_before - n_after, "duplicates\n")
cat("  Final observations:", n_after, "\n")

# Save
write.csv(timeseries_df, config$output_file, row.names = FALSE)

# Clean up checkpoint
if (file.exists(checkpoint_file)) {
  file.remove(checkpoint_file)
}

# ==============================================================================
# SUMMARY STATISTICS
# ==============================================================================

cat("\n=== 2018 TEST RESULTS ===\n")

# Observations per pixel
obs_per_pixel <- timeseries_df %>%
  group_by(pixel_id) %>%
  summarise(n_obs = n(), .groups = "drop")

cat("\nObservations per pixel:\n")
cat("  Mean:", round(mean(obs_per_pixel$n_obs), 1), "\n")
cat("  Median:", median(obs_per_pixel$n_obs), "\n")
cat("  Min:", min(obs_per_pixel$n_obs), "\n")
cat("  Max:", max(obs_per_pixel$n_obs), "\n")
cat("  5th percentile:", quantile(obs_per_pixel$n_obs, 0.05), "\n")
cat("  95th percentile:", quantile(obs_per_pixel$n_obs, 0.95), "\n")

# Unique observation days
unique_days <- timeseries_df %>%
  distinct(date) %>%
  nrow()
cat("\nUnique observation days:", unique_days, "\n")

# By sensor
by_sensor <- timeseries_df %>%
  group_by(sensor) %>%
  summarise(n_obs = n(), .groups = "drop")
cat("\nObservations by sensor:\n")
print(by_sensor)

cat("\n=== BASELINE COMPARISON ===\n")
cat("Baseline 2018 (cloud_cover_max=40%, min_pixels=10): ~11.3 obs/pixel\n")
cat("New 2018 (cloud_cover_max=100%, min_pixels=5):", round(mean(obs_per_pixel$n_obs), 1), "obs/pixel\n")
cat("Improvement:", round((mean(obs_per_pixel$n_obs) / 11.3 - 1) * 100, 0), "%\n")

cat("\nOutput saved to:", config$output_file, "\n")
cat("Done!\n")
