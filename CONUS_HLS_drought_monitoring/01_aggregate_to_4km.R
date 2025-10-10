# ==============================================================================
# PHASE 1: SPATIAL AGGREGATION (30m → 4km)
# ==============================================================================
# Purpose: Aggregate HLS NDVI from 30m to 4km using median for CONUS GAM analysis
# Input: Processed NDVI files in U:/datasets/ndvi_monitor/processed_ndvi/daily/
# Output: Timeseries CSV with pixel_id, x, y, sensor, date, year, yday, NDVI
# ==============================================================================

library(terra)
library(dplyr)
library(lubridate)

# Source path configuration
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

cat("=== PHASE 1: SPATIAL AGGREGATION TO 4KM ===\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  target_resolution = 4000,  # 4km in meters
  aggregation_method = "median",  # Robust to outliers
  years = 2013:2024,
  min_pixels_per_cell = 10,  # Minimum 30m pixels required for valid 4km median
  output_file = file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.csv"),
  checkpoint_interval = 100,  # Save progress every N scenes
  resume_from_checkpoint = TRUE
)

# Ensure output directory exists
ensure_directory(hls_paths$gam_models)

cat("Configuration:\n")
cat("  Target resolution:", config$target_resolution, "m\n")
cat("  Aggregation method:", config$aggregation_method, "\n")
cat("  Years:", paste(range(config$years), collapse = "-"), "\n")
cat("  Output:", config$output_file, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Create 4km reference grid covering CONUS extent
#'
#' @param template_raster A sample 30m HLS raster for CRS reference
#' @param resolution Target resolution in meters (4000)
#' @return SpatRaster with 4km grid
create_4km_grid <- function(template_raster, resolution = 4000) {

  cat("Creating 4km reference grid...\n")

  # Get CRS from template
  target_crs <- crs(template_raster)

  # CONUS extent in UTM (approximate - will refine based on actual data)
  # This will be updated dynamically as we process scenes
  conus_extent <- ext(template_raster)

  # Create empty raster at 4km resolution
  grid_4km <- rast(
    extent = conus_extent,
    resolution = resolution,
    crs = target_crs
  )

  # Assign pixel IDs
  values(grid_4km) <- 1:ncell(grid_4km)

  cat("  Grid dimensions:", paste(dim(grid_4km), collapse = " x "), "\n")
  cat("  Total 4km cells:", ncell(grid_4km), "\n\n")

  return(grid_4km)
}

#' Aggregate a single 30m NDVI raster to 4km grid
#'
#' @param ndvi_path Path to 30m NDVI GeoTIFF
#' @param grid_4km Reference 4km grid (SpatRaster)
#' @param method Aggregation method ("median" or "mean")
#' @param min_pixels Minimum 30m pixels required per 4km cell
#' @return Data frame with pixel_id, NDVI_agg, n_pixels
aggregate_scene_to_4km <- function(ndvi_path, grid_4km, method = "median", min_pixels = 10) {

  # Load 30m NDVI
  ndvi_30m <- rast(ndvi_path)

  # Check if rasters overlap
  if (!same.crs(ndvi_30m, grid_4km)) {
    warning("CRS mismatch - reprojecting 4km grid to match scene")
    grid_4km <- project(grid_4km, crs(ndvi_30m))
  }

  # Resample 4km grid to 30m resolution to get pixel assignments
  grid_30m <- resample(grid_4km, ndvi_30m, method = "near")

  # Extract pixel IDs and NDVI values
  pixel_ids <- values(grid_30m, mat = FALSE)
  ndvi_vals <- values(ndvi_30m, mat = FALSE)

  # Create dataframe
  df <- data.frame(
    pixel_id = pixel_ids,
    ndvi = ndvi_vals
  )

  # Remove NAs
  df <- df[!is.na(df$pixel_id) & !is.na(df$ndvi), ]

  # Aggregate by pixel_id
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

  # Filter by minimum pixel count
  agg_result <- agg_result %>%
    filter(n_pixels >= min_pixels)

  return(agg_result)
}

#' Extract metadata from HLS scene filename
#'
#' @param filepath Full path to HLS NDVI file
#' @return List with sensor, tile, date, year, yday
parse_hls_filename <- function(filepath) {

  filename <- basename(filepath)

  # HLS filename format: HLS.S30.T15TXM.2020007T170659.v2.0_NDVI.tif
  parts <- strsplit(filename, "\\.")[[1]]

  sensor <- parts[2]  # L30 or S30
  tile <- parts[3]    # e.g., T15TXM
  datetime_part <- parts[4]  # e.g., 2020007T170659

  # Extract year and day of year
  year <- as.integer(substr(datetime_part, 1, 4))
  yday <- as.integer(substr(datetime_part, 5, 7))

  # Construct date
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
# MAIN PROCESSING WORKFLOW
# ==============================================================================

#' Process all NDVI scenes and aggregate to 4km timeseries
#'
#' @param config Configuration list
#' @return Data frame with full timeseries
process_ndvi_to_4km <- function(config) {

  cat("=== STARTING 4KM AGGREGATION ===\n\n")

  # Get list of all processed NDVI files
  cat("Scanning for NDVI files...\n")

  ndvi_files <- c()
  for (year in config$years) {
    year_dir <- file.path(hls_paths$processed_ndvi, "daily", year)
    if (dir.exists(year_dir)) {
      year_files <- list.files(year_dir, pattern = "_NDVI\\.tif$", full.names = TRUE)
      ndvi_files <- c(ndvi_files, year_files)
      cat("  ", year, ":", length(year_files), "scenes\n")
    }
  }

  cat("\nTotal scenes found:", length(ndvi_files), "\n\n")

  if (length(ndvi_files) == 0) {
    stop("No NDVI files found. Check processed_ndvi directory structure.")
  }

  # Check for existing checkpoint
  checkpoint_file <- sub("\\.csv$", "_checkpoint.csv", config$output_file)

  if (config$resume_from_checkpoint && file.exists(checkpoint_file)) {
    cat("Found checkpoint file - loading previous progress...\n")
    timeseries_df <- read.csv(checkpoint_file, stringsAsFactors = FALSE)
    timeseries_df$date <- as.Date(timeseries_df$date)

    # Determine which files already processed
    processed_files <- unique(paste0(timeseries_df$sensor, ".",
                                     format(timeseries_df$date, "%Y%j")))

    ndvi_files <- ndvi_files[!sapply(ndvi_files, function(f) {
      meta <- parse_hls_filename(f)
      paste0(meta$sensor, ".", format(meta$date, "%Y%j")) %in% processed_files
    })]

    cat("  Resuming from", nrow(timeseries_df), "existing observations\n")
    cat("  ", length(ndvi_files), "scenes remaining\n\n")
  } else {
    timeseries_df <- data.frame()
  }

  # Create 4km reference grid from first scene
  cat("Initializing 4km reference grid...\n")
  template_raster <- rast(ndvi_files[1])
  grid_4km <- create_4km_grid(template_raster, config$target_resolution)

  # Get grid coordinates for pixel IDs
  grid_coords <- as.data.frame(grid_4km, xy = TRUE, cells = TRUE)
  names(grid_coords) <- c("pixel_id", "x", "y")

  # Track progress
  n_processed <- 0
  n_failed <- 0
  start_time <- Sys.time()

  # Process each NDVI scene
  for (i in seq_along(ndvi_files)) {

    ndvi_path <- ndvi_files[i]

    # Parse metadata
    meta <- tryCatch({
      parse_hls_filename(ndvi_path)
    }, error = function(e) {
      cat("  ⚠ Failed to parse filename:", basename(ndvi_path), "\n")
      n_failed <<- n_failed + 1
      return(NULL)
    })

    if (is.null(meta)) next

    # Aggregate to 4km
    agg_result <- tryCatch({
      aggregate_scene_to_4km(ndvi_path, grid_4km,
                            config$aggregation_method,
                            config$min_pixels_per_cell)
    }, error = function(e) {
      cat("  ⚠ Aggregation failed:", basename(ndvi_path), "\n")
      cat("    Error:", e$message, "\n")
      n_failed <<- n_failed + 1
      return(NULL)
    })

    if (is.null(agg_result) || nrow(agg_result) == 0) next

    # Add metadata
    agg_result$sensor <- meta$sensor
    agg_result$date <- meta$date
    agg_result$year <- meta$year
    agg_result$yday <- meta$yday

    # Rename NDVI column
    names(agg_result)[names(agg_result) == "ndvi_agg"] <- "NDVI"

    # Add coordinates
    agg_result <- agg_result %>%
      left_join(grid_coords, by = "pixel_id")

    # Append to timeseries
    timeseries_df <- bind_rows(timeseries_df,
                               agg_result[, c("pixel_id", "x", "y", "sensor",
                                             "date", "year", "yday", "NDVI")])

    n_processed <- n_processed + 1

    # Progress update
    if (n_processed %% 50 == 0) {
      elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
      scenes_per_min <- n_processed / elapsed
      remaining <- length(ndvi_files) - n_processed
      eta_mins <- remaining / scenes_per_min

      cat(sprintf("  Progress: %d/%d scenes (%.1f%%) | %.1f scenes/min | ETA: %.0f min\n",
                  n_processed, length(ndvi_files),
                  100 * n_processed / length(ndvi_files),
                  scenes_per_min, eta_mins))
    }

    # Save checkpoint
    if (n_processed %% config$checkpoint_interval == 0) {
      cat("  Saving checkpoint...\n")
      write.csv(timeseries_df, checkpoint_file, row.names = FALSE)
    }
  }

  # Final summary
  cat("\n=== AGGREGATION COMPLETE ===\n")
  cat("Scenes processed:", n_processed, "\n")
  cat("Scenes failed:", n_failed, "\n")
  cat("Total observations:", nrow(timeseries_df), "\n")
  cat("Unique 4km pixels:", length(unique(timeseries_df$pixel_id)), "\n")
  cat("Date range:", paste(range(timeseries_df$date), collapse = " to "), "\n")

  # Save final output
  cat("\nSaving final timeseries to:", config$output_file, "\n")
  write.csv(timeseries_df, config$output_file, row.names = FALSE)

  # Remove checkpoint
  if (file.exists(checkpoint_file)) {
    file.remove(checkpoint_file)
  }

  cat("✓ Phase 1 complete\n\n")

  return(timeseries_df)
}

# ==============================================================================
# EXECUTION
# ==============================================================================

cat("=== READY TO AGGREGATE TO 4KM ===\n")
cat("This will process all NDVI scenes from", paste(range(config$years), collapse = "-"), "\n")
cat("Estimated time: 2-4 hours depending on scene count\n")
cat("Output will be saved to:", config$output_file, "\n\n")
cat("To run:\n")
cat("  timeseries_4km <- process_ndvi_to_4km(config)\n\n")
