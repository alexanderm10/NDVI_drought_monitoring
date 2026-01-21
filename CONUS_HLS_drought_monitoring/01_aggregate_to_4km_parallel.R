# ==============================================================================
# PARALLEL AGGREGATION: NDVI to 4km with Disk Checkpointing
# ==============================================================================
# Purpose: Aggregate HLS NDVI scenes using parallel processing
#
# Key improvements over test version:
#   - Each worker writes to disk incrementally (not holding all in RAM)
#   - Batch writes every N scenes for I/O efficiency
#   - Resume capability from partial runs
#   - Configurable years
#   - Production-ready for full dataset
#
# Strategy:
#   - Group files by tile for disk cache performance
#   - Each worker creates its own 4km grid (terra objects don't serialize)
#   - Workers write to individual temp CSV files
#   - Main process combines and deduplicates at end
# ==============================================================================

library(terra)
library(dplyr)
library(lubridate)
library(future)
library(future.apply)

# Source path configuration
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

cat("=== PARALLEL 4KM AGGREGATION (Disk Checkpointing) ===\n")
cat("Started:", as.character(Sys.time()), "\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  target_resolution = 4000,
  aggregation_method = "median",
  years = 2013:2024,  # Full dataset
  min_pixels_per_cell = 5,
  n_workers = 8,
  batch_size = 100,  # Write to disk every N scenes per worker

  # Directories
  temp_dir = file.path(hls_paths$gam_models, "aggregation_temp"),
  output_file = file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.csv"),

  # Grid parameters
  midwest_bbox = c(-104.5, 37.0, -82.0, 47.5)
)

# Create temp directory
if (!dir.exists(config$temp_dir)) {
  dir.create(config$temp_dir, recursive = TRUE)
}

cat("Configuration:\n")
cat("  Workers:", config$n_workers, "\n")
cat("  Years:", paste(range(config$years), collapse = "-"), "\n")
cat("  min_pixels_per_cell:", config$min_pixels_per_cell, "\n")
cat("  Batch size:", config$batch_size, "scenes\n")
cat("  Temp directory:", config$temp_dir, "\n")
cat("  Output:", config$output_file, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

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

  df <- data.frame(pixel_id = pixel_ids, ndvi = ndvi_vals)
  df <- df[!is.na(df$pixel_id) & !is.na(df$ndvi), ]

  if (nrow(df) == 0) return(NULL)

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

  if (nrow(agg_result) == 0) return(NULL)
  return(agg_result)
}

# ==============================================================================
# WORKER FUNCTION WITH DISK CHECKPOINTING
# ==============================================================================

#' Process a chunk of NDVI files with incremental disk writes
#'
#' @param file_chunk Character vector of file paths
#' @param worker_id Integer worker identifier
#' @param config Configuration list
#' @param temp_dir Directory for worker output files
#' @return List with stats (actual data written to disk)
process_file_chunk_disk <- function(file_chunk, worker_id, config, temp_dir) {

  # Each worker creates its own grid
  grid_4km <- create_4km_grid(config$target_resolution, config$midwest_bbox)

  # Get grid coordinates
  grid_coords <- as.data.frame(grid_4km, xy = TRUE, cells = TRUE)
  names(grid_coords) <- c("pixel_id", "x", "y")

  # Worker output file
  worker_file <- file.path(temp_dir, sprintf("worker_%02d.csv", worker_id))

  # Check for existing partial results (resume capability)
  if (file.exists(worker_file)) {
    existing <- read.csv(worker_file, stringsAsFactors = FALSE)
    processed_scenes <- unique(paste(existing$sensor, existing$date, sep = "_"))
    cat(sprintf("Worker %d: Resuming with %d existing scenes\n", worker_id, length(processed_scenes)))
  } else {
    processed_scenes <- character(0)
  }

  # Batch buffer
  batch_buffer <- list()
  batch_count <- 0
  n_success <- 0
  n_failed <- 0
  n_skipped <- 0

  # Helper to flush buffer to disk
  flush_buffer <- function() {
    if (length(batch_buffer) > 0) {
      batch_df <- bind_rows(batch_buffer)

      # Append to worker file
      write.table(
        batch_df,
        worker_file,
        sep = ",",
        row.names = FALSE,
        col.names = !file.exists(worker_file),
        append = file.exists(worker_file)
      )
    }
    # Clear buffer
    list()
  }

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

    # Check if already processed (resume)
    scene_id <- paste(meta$sensor, as.character(meta$date), sep = "_")
    if (scene_id %in% processed_scenes) {
      n_skipped <- n_skipped + 1
      next
    }

    # Aggregate scene
    agg_result <- tryCatch({
      aggregate_scene_to_4km(ndvi_path, grid_4km,
                            config$aggregation_method,
                            config$min_pixels_per_cell)
    }, error = function(e) NULL)

    if (is.null(agg_result) || nrow(agg_result) == 0) {
      n_failed <- n_failed + 1
      next
    }

    # Add metadata
    agg_result$sensor <- meta$sensor
    agg_result$date <- as.character(meta$date)
    agg_result$year <- meta$year
    agg_result$yday <- meta$yday

    names(agg_result)[names(agg_result) == "ndvi_agg"] <- "NDVI"

    # Add coordinates
    agg_result <- merge(agg_result, grid_coords, by = "pixel_id", all.x = TRUE)
    agg_result <- agg_result[, c("pixel_id", "x", "y", "sensor", "date", "year", "yday", "NDVI")]

    # Add to batch buffer
    batch_count <- batch_count + 1
    batch_buffer[[batch_count]] <- agg_result
    n_success <- n_success + 1

    # Flush buffer when batch size reached
    if (batch_count >= config$batch_size) {
      batch_buffer <- flush_buffer()
      batch_count <- 0
      batch_buffer <- list()
    }

    # Progress every 500 scenes
    if ((n_success + n_failed + n_skipped) %% 500 == 0) {
      cat(sprintf("Worker %d: %d/%d processed\n", worker_id,
                  n_success + n_failed + n_skipped, length(file_chunk)))
    }
  }

  # Final flush
  if (length(batch_buffer) > 0) {
    batch_df <- bind_rows(batch_buffer)
    write.table(
      batch_df,
      worker_file,
      sep = ",",
      row.names = FALSE,
      col.names = !file.exists(worker_file),
      append = file.exists(worker_file)
    )
  }

  cat(sprintf("Worker %d complete: %d success, %d failed, %d skipped\n",
              worker_id, n_success, n_failed, n_skipped))

  return(list(
    worker_id = worker_id,
    n_success = n_success,
    n_failed = n_failed,
    n_skipped = n_skipped,
    output_file = worker_file
  ))
}

# ==============================================================================
# MAIN EXECUTION
# ==============================================================================

# Get all NDVI files for configured years
cat("Scanning for NDVI files...\n")
all_files <- c()

for (yr in config$years) {
  year_dir <- file.path(hls_paths$processed_ndvi, "daily", yr)
  if (dir.exists(year_dir)) {
    year_files <- list.files(year_dir, pattern = "_NDVI\\.tif$", full.names = TRUE)
    all_files <- c(all_files, year_files)
    cat("  ", yr, ":", length(year_files), "files\n")
  }
}

cat("\nTotal files:", length(all_files), "\n")

if (length(all_files) == 0) {
  stop("No NDVI files found!")
}

# Extract tiles for grouping
file_tiles <- sapply(all_files, function(f) {
  parts <- strsplit(basename(f), "\\.")[[1]]
  parts[3]
})

file_info <- data.frame(
  path = all_files,
  tile = file_tiles,
  stringsAsFactors = FALSE
)

unique_tiles <- unique(file_info$tile)
cat("Unique tiles:", length(unique_tiles), "\n")

# Assign tiles to workers (round-robin)
tile_assignments <- data.frame(
  tile = unique_tiles,
  worker = rep(1:config$n_workers, length.out = length(unique_tiles))
)

file_info <- merge(file_info, tile_assignments, by = "tile")
file_info <- file_info[order(file_info$worker, file_info$tile), ]

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

plan(multisession, workers = config$n_workers)
cat("Parallel backend: multisession with", config$n_workers, "workers\n")
cat("Workers write incrementally to:", config$temp_dir, "\n\n")

start_time <- Sys.time()

# Run workers
results <- future_lapply(seq_along(file_chunks), function(worker_id) {

  library(terra)
  library(dplyr)

  process_file_chunk_disk(
    file_chunk = file_chunks[[worker_id]],
    worker_id = worker_id,
    config = config,
    temp_dir = config$temp_dir
  )

}, future.seed = TRUE)

plan(sequential)

elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

cat("\n=== PARALLEL PROCESSING COMPLETE ===\n")
cat("Elapsed time:", round(elapsed, 1), "minutes\n")

# Summarize worker results
total_success <- sum(sapply(results, function(r) r$n_success))
total_failed <- sum(sapply(results, function(r) r$n_failed))
total_skipped <- sum(sapply(results, function(r) r$n_skipped))

cat("Total scenes: success =", total_success, ", failed =", total_failed,
    ", skipped =", total_skipped, "\n")
cat("Speed:", round(total_success / elapsed, 1), "scenes/min\n\n")

# ==============================================================================
# COMBINE WORKER FILES
# ==============================================================================

cat("Combining worker files...\n")

worker_files <- list.files(config$temp_dir, pattern = "^worker_.*\\.csv$", full.names = TRUE)
cat("  Found", length(worker_files), "worker files\n")

combined_list <- lapply(worker_files, function(f) {
  read.csv(f, stringsAsFactors = FALSE)
})

combined_df <- bind_rows(combined_list)
combined_df$date <- as.Date(combined_df$date)

cat("  Total observations (before dedup):", nrow(combined_df), "\n")

# Deduplicate tile overlaps
cat("  Deduplicating tile overlaps...\n")
n_before <- nrow(combined_df)

combined_df <- combined_df %>%
  group_by(pixel_id, x, y, sensor, date, year, yday) %>%
  summarise(NDVI = median(NDVI, na.rm = TRUE), .groups = "drop")

n_after <- nrow(combined_df)
cat("  Removed", n_before - n_after, "duplicates (",
    round(100 * (n_before - n_after) / n_before, 1), "%)\n", sep = "")
cat("  Final observations:", n_after, "\n")

# ==============================================================================
# SUMMARY STATISTICS
# ==============================================================================

cat("\n=== AGGREGATION RESULTS ===\n")

obs_per_pixel <- combined_df %>%
  group_by(pixel_id) %>%
  summarise(n_obs = n(), .groups = "drop")

n_years <- length(unique(combined_df$year))

cat("\nObservations per pixel (across", n_years, "years):\n")
cat("  Mean:", round(mean(obs_per_pixel$n_obs), 1), "\n")
cat("  Mean per year:", round(mean(obs_per_pixel$n_obs) / n_years, 1), "\n")
cat("  Median:", median(obs_per_pixel$n_obs), "\n")
cat("  5th percentile:", quantile(obs_per_pixel$n_obs, 0.05), "\n")
cat("  95th percentile:", quantile(obs_per_pixel$n_obs, 0.95), "\n")

cat("\nBy year:\n")
by_year <- combined_df %>%
  group_by(year) %>%
  summarise(n_obs = n(), n_pixels = n_distinct(pixel_id), .groups = "drop") %>%
  mutate(obs_per_pixel = round(n_obs / n_pixels, 1))
print(by_year)

# ==============================================================================
# SAVE OUTPUT
# ==============================================================================

cat("\nSaving final output to:", config$output_file, "\n")
write.csv(combined_df, config$output_file, row.names = FALSE)

# Also save as RDS for faster loading
rds_file <- sub("\\.csv$", ".rds", config$output_file)
cat("Saving RDS version to:", rds_file, "\n")
saveRDS(combined_df, rds_file)

# Clean up temp files (optional - comment out to keep for debugging)
# cat("Cleaning up temp files...\n")
# unlink(config$temp_dir, recursive = TRUE)

cat("\n=== COMPLETE ===\n")
cat("Finished:", as.character(Sys.time()), "\n")
cat("Total time:", round(elapsed, 1), "minutes\n")
