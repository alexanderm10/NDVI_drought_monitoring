# ==============================================================================
# PARALLEL AGGREGATION: 2018 NDVI to 4km (8 workers)
# ==============================================================================
# Purpose: Aggregate 36,402 NDVI scenes using parallel processing
# Strategy:
#   - Group files by tile for better disk cache performance
#   - Each worker creates its own 4km grid (terra objects don't serialize)
#   - Use progressr for progress tracking across workers
#   - Robust error handling - failed scenes don't crash workers
# ==============================================================================

# Load packages
library(terra)
library(dplyr)
library(lubridate)
library(future)
library(future.apply)
library(progressr)

# Source path configuration
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

cat("=== PARALLEL AGGREGATION: 2018 (8 workers) ===\n")
cat("Started:", as.character(Sys.time()), "\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  target_resolution = 4000,
  aggregation_method = "median",
  year = 2018,
  min_pixels_per_cell = 5,
  n_workers = 8,
  output_file = file.path(hls_paths$gam_models, "test_2018_parallel_timeseries.csv"),
  midwest_bbox = c(-104.5, 37.0, -82.0, 47.5)
)

cat("Configuration:\n")
cat("  Workers:", config$n_workers, "\n")
cat("  min_pixels_per_cell:", config$min_pixels_per_cell, "\n")
cat("  Output:", config$output_file, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS (defined at top level for worker access)
# ==============================================================================

#' Parse HLS filename to extract metadata
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

#' Create 4km reference grid in Albers Equal Area
#' Each worker calls this to create its own grid instance
create_4km_grid <- function(resolution = 4000, bbox_latlon = c(-104.5, 37.0, -82.0, 47.5)) {

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

  return(grid_4km)
}

#' Aggregate a single scene to 4km
#' Returns data.frame or NULL on failure
aggregate_scene_to_4km <- function(ndvi_path, grid_4km, method = "median", min_pixels = 5) {

  # Load 30m NDVI
  ndvi_30m <- rast(ndvi_path)

  # Reproject grid to match scene CRS
  if (!same.crs(ndvi_30m, grid_4km)) {
    grid_4km_reproj <- project(grid_4km, crs(ndvi_30m), method = "near")
  } else {
    grid_4km_reproj <- grid_4km
  }

  # Resample to 30m to get pixel assignments
  grid_30m <- resample(grid_4km_reproj, ndvi_30m, method = "near")

  # Extract values
  pixel_ids <- values(grid_30m, mat = FALSE)
  ndvi_vals <- values(ndvi_30m, mat = FALSE)

  # Create and filter data frame
  df <- data.frame(pixel_id = pixel_ids, ndvi = ndvi_vals)
  df <- df[!is.na(df$pixel_id) & !is.na(df$ndvi), ]

  if (nrow(df) == 0) return(NULL)

  # Aggregate
  if (method == "median") {
    agg_result <- df %>%
      group_by(pixel_id) %>%
      summarise(ndvi_agg = median(ndvi, na.rm = TRUE), n_pixels = n(), .groups = "drop")
  } else {
    agg_result <- df %>%
      group_by(pixel_id) %>%
      summarise(ndvi_agg = mean(ndvi, na.rm = TRUE), n_pixels = n(), .groups = "drop")
  }

  # Filter by minimum pixels
  agg_result <- agg_result %>% filter(n_pixels >= min_pixels)

  if (nrow(agg_result) == 0) return(NULL)

  return(agg_result)
}

# ==============================================================================
# WORKER FUNCTION
# ==============================================================================

#' Process a chunk of NDVI files
#' Called by each parallel worker
#' @param file_chunk Character vector of file paths
#' @param worker_id Integer worker identifier
#' @param config Configuration list
#' @param p Progressor function for progress updates
#' @return Data frame with aggregated results
process_file_chunk <- function(file_chunk, worker_id, config, p = NULL) {

  # Each worker creates its own grid (terra objects don't serialize)
  grid_4km <- create_4km_grid(config$target_resolution, config$midwest_bbox)

  # Get grid coordinates for pixel IDs
  grid_coords <- as.data.frame(grid_4km, xy = TRUE, cells = TRUE)
  names(grid_coords) <- c("pixel_id", "x", "y")

  # Initialize results storage
  results_list <- vector("list", length(file_chunk))
  n_success <- 0
  n_failed <- 0

  for (i in seq_along(file_chunk)) {

    ndvi_path <- file_chunk[i]

    # Parse metadata
    meta <- tryCatch({
      parse_hls_filename(ndvi_path)
    }, error = function(e) NULL)

    if (is.null(meta)) {
      n_failed <- n_failed + 1
      next
    }

    # Aggregate scene
    agg_result <- tryCatch({
      aggregate_scene_to_4km(ndvi_path, grid_4km,
                            config$aggregation_method,
                            config$min_pixels_per_cell)
    }, error = function(e) {
      NULL
    })

    if (is.null(agg_result) || nrow(agg_result) == 0) {
      n_failed <- n_failed + 1
      next
    }

    # Add metadata
    agg_result$sensor <- meta$sensor
    agg_result$date <- meta$date
    agg_result$year <- meta$year
    agg_result$yday <- meta$yday

    names(agg_result)[names(agg_result) == "ndvi_agg"] <- "NDVI"

    # Store result
    results_list[[i]] <- agg_result
    n_success <- n_success + 1

    # Update progress (every scene)
    if (!is.null(p)) p()
  }

  # Combine results
  results_df <- bind_rows(results_list)

  if (nrow(results_df) > 0) {
    # Add coordinates
    results_df <- merge(results_df, grid_coords, by = "pixel_id", all.x = TRUE)
    results_df <- results_df[, c("pixel_id", "x", "y", "sensor", "date", "year", "yday", "NDVI")]
  }

  # Log worker completion
  cat(sprintf("Worker %d: %d/%d scenes successful\n", worker_id, n_success, length(file_chunk)))

  return(results_df)
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

# Get all 2018 NDVI files
year_dir <- file.path(hls_paths$processed_ndvi, "daily", config$year)
all_files <- list.files(year_dir, pattern = "_NDVI\\.tif$", full.names = TRUE)

cat("Total files found:", length(all_files), "\n")

# Extract tile from each filename for grouping
file_tiles <- sapply(all_files, function(f) {
  parts <- strsplit(basename(f), "\\.")[[1]]
  parts[3]  # Tile ID (e.g., T15TXM)
})

# Create file info data frame
file_info <- data.frame(
  path = all_files,
  tile = file_tiles,
  stringsAsFactors = FALSE
)

# Group tiles into balanced chunks for workers
unique_tiles <- unique(file_info$tile)
cat("Unique tiles:", length(unique_tiles), "\n")

# Assign tiles to workers (round-robin for balance)
tile_assignments <- data.frame(
  tile = unique_tiles,
  worker = rep(1:config$n_workers, length.out = length(unique_tiles))
)

# Merge to get worker assignment for each file
file_info <- merge(file_info, tile_assignments, by = "tile")

# Sort by worker and tile for cache efficiency
file_info <- file_info[order(file_info$worker, file_info$tile), ]

# Split into chunks by worker
file_chunks <- split(file_info$path, file_info$worker)

cat("\nFiles per worker:\n")
for (i in seq_along(file_chunks)) {
  cat(sprintf("  Worker %d: %d files\n", i, length(file_chunks[[i]])))
}

# ==============================================================================
# PARALLEL EXECUTION
# ==============================================================================

cat("\n=== STARTING PARALLEL PROCESSING ===\n")
cat("Time:", as.character(Sys.time()), "\n\n")

# Set up parallel backend
plan(multisession, workers = config$n_workers)
cat("Parallel backend: multisession with", config$n_workers, "workers\n")

# Set up progress handler
handlers(global = TRUE)
handlers("txtprogressbar")

# Track timing
start_time <- Sys.time()

# Run parallel processing with progress
results <- with_progress({

  p <- progressor(steps = length(all_files))

  future_lapply(seq_along(file_chunks), function(worker_id) {

    # Load required packages in worker
    library(terra)
    library(dplyr)

    # Process this worker's chunk
    process_file_chunk(
      file_chunk = file_chunks[[worker_id]],
      worker_id = worker_id,
      config = config,
      p = p
    )

  }, future.seed = TRUE)
})

# Shut down workers
plan(sequential)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
cat("\n=== PARALLEL PROCESSING COMPLETE ===\n")
cat("Elapsed time:", round(elapsed, 1), "minutes\n")
cat("Speed:", round(length(all_files) / elapsed, 1), "scenes/min\n\n")

# ==============================================================================
# COMBINE AND DEDUPLICATE RESULTS
# ==============================================================================

cat("Combining results from all workers...\n")
combined_df <- bind_rows(results)
cat("Total observations (before dedup):", nrow(combined_df), "\n")

# Deduplicate tile overlaps
cat("Deduplicating tile overlaps...\n")
n_before <- nrow(combined_df)

combined_df <- combined_df %>%
  group_by(pixel_id, x, y, sensor, date, year, yday) %>%
  summarise(NDVI = median(NDVI, na.rm = TRUE), .groups = "drop")

n_after <- nrow(combined_df)
cat("Removed", n_before - n_after, "duplicates (",
    round(100 * (n_before - n_after) / n_before, 1), "%)\n", sep = "")
cat("Final observations:", n_after, "\n")

# ==============================================================================
# SUMMARY STATISTICS
# ==============================================================================

cat("\n=== 2018 PARALLEL TEST RESULTS ===\n")

obs_per_pixel <- combined_df %>%
  group_by(pixel_id) %>%
  summarise(n_obs = n(), .groups = "drop")

cat("\nObservations per pixel:\n")
cat("  Mean:", round(mean(obs_per_pixel$n_obs), 1), "\n")
cat("  Median:", median(obs_per_pixel$n_obs), "\n")
cat("  Min:", min(obs_per_pixel$n_obs), "\n")
cat("  Max:", max(obs_per_pixel$n_obs), "\n")
cat("  5th percentile:", quantile(obs_per_pixel$n_obs, 0.05), "\n")
cat("  95th percentile:", quantile(obs_per_pixel$n_obs, 0.95), "\n")

unique_days <- combined_df %>% distinct(date) %>% nrow()
cat("\nUnique observation days:", unique_days, "\n")

by_sensor <- combined_df %>%
  group_by(sensor) %>%
  summarise(n_obs = n(), .groups = "drop")
cat("\nObservations by sensor:\n")
print(by_sensor)

cat("\n=== BASELINE COMPARISON ===\n")
cat("Baseline 2018 (cloud_cover_max=40%, min_pixels=10): ~11.3 obs/pixel\n")
cat("New 2018 (cloud_cover_max=100%, min_pixels=5):", round(mean(obs_per_pixel$n_obs), 1), "obs/pixel\n")
improvement <- (mean(obs_per_pixel$n_obs) / 11.3 - 1) * 100
cat("Improvement:", round(improvement, 0), "%\n")

# ==============================================================================
# SAVE OUTPUT
# ==============================================================================

cat("\nSaving to:", config$output_file, "\n")
write.csv(combined_df, config$output_file, row.names = FALSE)

cat("\n=== COMPLETE ===\n")
cat("Finished:", as.character(Sys.time()), "\n")
cat("Total time:", round(elapsed, 1), "minutes\n")
