# ==============================================================================
# PARALLEL AGGREGATION: NDVI to 4km with Disk Checkpointing
# ==============================================================================
# Purpose: Aggregate HLS NDVI scenes using parallel processing
#
# Usage:
#   Rscript 01_aggregate_to_4km_parallel.R              # All years (2013-2024)
#   Rscript 01_aggregate_to_4km_parallel.R 2013         # Single year
#   Rscript 01_aggregate_to_4km_parallel.R 2013 2015    # Year range
#   Rscript 01_aggregate_to_4km_parallel.R --workers=4  # Specify worker count
#
# Features:
#   - Each worker writes to disk incrementally (not holding all in RAM)
#   - Batch writes every N scenes as numbered RDS files for efficiency
#   - Resume capability from partial runs (tracks processed scenes in text file)
#   - Skips years that already have completed output files
#   - Year-specific temp directories for parallel year processing
#
# Strategy:
#   - Group files by tile for disk cache performance
#   - Each worker creates its own 4km grid (terra objects don't serialize)
#   - Workers write numbered RDS batches: worker_01_batch_001.rds, etc.
#   - Main process combines and deduplicates at end
#
# Storage efficiency:
#   - RDS with compression is ~15x smaller than CSV
#   - Batched writes reduce I/O overhead
# ==============================================================================

library(terra)
library(dplyr)
library(lubridate)
library(future)
library(future.apply)

# Source path configuration
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

# ==============================================================================
# PARSE COMMAND LINE ARGUMENTS
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)

# Default values
requested_years <- 2013:2024
n_workers <- 8

# Parse arguments
numeric_args <- c()
for (arg in args) {
  if (grepl("^--workers=", arg)) {
    n_workers <- as.integer(sub("^--workers=", "", arg))
  } else if (grepl("^[0-9]+$", arg)) {
    numeric_args <- c(numeric_args, as.integer(arg))
  }
}

# Handle year arguments
if (length(numeric_args) == 1) {
  requested_years <- numeric_args[1]
} else if (length(numeric_args) == 2) {
  requested_years <- numeric_args[1]:numeric_args[2]
} else if (length(numeric_args) > 2) {
  requested_years <- numeric_args
}

cat("=== PARALLEL 4KM AGGREGATION (Disk Checkpointing) ===\n")
cat("Started:", as.character(Sys.time()), "\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  target_resolution = 4000,
  aggregation_method = "median",
  min_pixels_per_cell = 5,
  n_workers = n_workers,
  batch_size = 100,  # Write to disk every N scenes per worker

  # Directories (year-specific temp dirs created below)
  output_dir = file.path(hls_paths$gam_models, "aggregated_years"),

  # Grid parameters
  midwest_bbox = c(-104.5, 37.0, -82.0, 47.5)
)

# Create output directory
if (!dir.exists(config$output_dir)) {
  dir.create(config$output_dir, recursive = TRUE)
}

# ==============================================================================
# CHECK FOR COMPLETED YEARS
# ==============================================================================

cat("Checking for completed years...\n")
years_to_process <- c()
years_skipped <- c()

for (yr in requested_years) {
  output_file <- file.path(config$output_dir, sprintf("ndvi_4km_%d.rds", yr))
  if (file.exists(output_file)) {
    years_skipped <- c(years_skipped, yr)
  } else {
    years_to_process <- c(years_to_process, yr)
  }
}

if (length(years_skipped) > 0) {
  cat("  Skipping completed years:", paste(years_skipped, collapse = ", "), "\n")
}

if (length(years_to_process) == 0) {
  cat("\nAll requested years already completed!\n")
  quit(save = "no", status = 0)
}

cat("  Will process years:", paste(years_to_process, collapse = ", "), "\n\n")

cat("Configuration:\n")
cat("  Workers:", config$n_workers, "\n")
cat("  Years to process:", paste(years_to_process, collapse = ", "), "\n")
cat("  min_pixels_per_cell:", config$min_pixels_per_cell, "\n")
cat("  Batch size:", config$batch_size, "scenes\n")
cat("  Output directory:", config$output_dir, "\n\n")

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
#' @return List with stats (actual data written to disk as RDS batches)
process_file_chunk_disk <- function(file_chunk, worker_id, config, temp_dir) {

  # Each worker creates its own grid
  grid_4km <- create_4km_grid(config$target_resolution, config$midwest_bbox)

  # Get grid coordinates
  grid_coords <- as.data.frame(grid_4km, xy = TRUE, cells = TRUE)
  names(grid_coords) <- c("pixel_id", "x", "y")

  # Worker tracking file (small text file for fast resume check)
  tracker_file <- file.path(temp_dir, sprintf("worker_%02d_processed.txt", worker_id))

  # Check for existing partial results (resume capability)
  if (file.exists(tracker_file)) {
    processed_scenes <- readLines(tracker_file)
    cat(sprintf("Worker %d: Resuming with %d existing scenes\n", worker_id, length(processed_scenes)))
    # Find next batch number
    existing_batches <- list.files(temp_dir, pattern = sprintf("^worker_%02d_batch_.*\\.rds$", worker_id))
    batch_num <- length(existing_batches) + 1
  } else {
    processed_scenes <- character(0)
    batch_num <- 1
  }

  # Batch buffer
  batch_buffer <- list()
  batch_count <- 0
  n_success <- 0
  n_failed <- 0
  n_skipped <- 0
  new_scenes <- character(0)  # Track scenes processed in this run

  # Helper to flush buffer to disk as RDS

  flush_buffer <- function(batch_buffer, batch_num, new_scenes) {
    if (length(batch_buffer) > 0) {
      batch_df <- bind_rows(batch_buffer)

      # Write RDS batch
      batch_file <- file.path(temp_dir, sprintf("worker_%02d_batch_%04d.rds", worker_id, batch_num))
      saveRDS(batch_df, batch_file, compress = "gzip")

      # Append new scene IDs to tracker file
      cat(new_scenes, file = tracker_file, sep = "\n", append = TRUE)
    }
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
    new_scenes <- c(new_scenes, scene_id)
    n_success <- n_success + 1

    # Flush buffer when batch size reached
    if (batch_count >= config$batch_size) {
      flush_buffer(batch_buffer, batch_num, new_scenes)
      batch_num <- batch_num + 1
      batch_count <- 0
      batch_buffer <- list()
      new_scenes <- character(0)
    }

    # Progress every 500 scenes
    if ((n_success + n_failed + n_skipped) %% 500 == 0) {
      cat(sprintf("Worker %d: %d/%d processed\n", worker_id,
                  n_success + n_failed + n_skipped, length(file_chunk)))
    }
  }

  # Final flush
  if (length(batch_buffer) > 0) {
    flush_buffer(batch_buffer, batch_num, new_scenes)
  }

  cat(sprintf("Worker %d complete: %d success, %d failed, %d skipped\n",
              worker_id, n_success, n_failed, n_skipped))

  return(list(
    worker_id = worker_id,
    n_success = n_success,
    n_failed = n_failed,
    n_skipped = n_skipped
  ))
}

# ==============================================================================
# MAIN EXECUTION - PROCESS EACH YEAR
# ==============================================================================

overall_start <- Sys.time()

for (current_year in years_to_process) {

  cat("\n")
  cat("##############################################################################\n")
  cat("# PROCESSING YEAR:", current_year, "\n")
  cat("##############################################################################\n\n")

  year_start <- Sys.time()

  # Year-specific temp directory
  temp_dir <- file.path(hls_paths$gam_models, "aggregation_temp", as.character(current_year))
  if (!dir.exists(temp_dir)) {
    dir.create(temp_dir, recursive = TRUE)
  }

  # Get NDVI files for this year
  cat("Scanning for NDVI files...\n")
  year_dir <- file.path(hls_paths$processed_ndvi, "daily", current_year)

  if (!dir.exists(year_dir)) {
    cat("  WARNING: Directory not found:", year_dir, "\n")
    cat("  Skipping year", current_year, "\n")
    next
  }

  year_files <- list.files(year_dir, pattern = "_NDVI\\.tif$", full.names = TRUE)
  cat("  Found", length(year_files), "files for", current_year, "\n")

  if (length(year_files) == 0) {
    cat("  No files found, skipping year", current_year, "\n")
    next
  }

  # Extract tiles for grouping
  file_tiles <- sapply(year_files, function(f) {
    parts <- strsplit(basename(f), "\\.")[[1]]
    parts[3]
  })

  file_info <- data.frame(
    path = year_files,
    tile = file_tiles,
    stringsAsFactors = FALSE
  )

  unique_tiles <- unique(file_info$tile)
  cat("  Unique tiles:", length(unique_tiles), "\n")

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
  # PARALLEL EXECUTION FOR THIS YEAR
  # ==============================================================================

  cat("\n=== STARTING PARALLEL PROCESSING ===\n")
  cat("Time:", as.character(Sys.time()), "\n")
  cat("Temp directory:", temp_dir, "\n\n")

  plan(multisession, workers = config$n_workers)

  proc_start <- Sys.time()

  # Run workers
  results <- future_lapply(seq_along(file_chunks), function(worker_id) {

    library(terra)
    library(dplyr)

    process_file_chunk_disk(
      file_chunk = file_chunks[[worker_id]],
      worker_id = worker_id,
      config = config,
      temp_dir = temp_dir
    )

  }, future.seed = TRUE)

  plan(sequential)

  proc_elapsed <- as.numeric(difftime(Sys.time(), proc_start, units = "mins"))

  # Summarize worker results
  total_success <- sum(sapply(results, function(r) r$n_success))
  total_failed <- sum(sapply(results, function(r) r$n_failed))
  total_skipped <- sum(sapply(results, function(r) r$n_skipped))

  cat("\nProcessing complete:\n")
  cat("  Success:", total_success, ", Failed:", total_failed, ", Skipped:", total_skipped, "\n")
  cat("  Speed:", round(total_success / proc_elapsed, 1), "scenes/min\n")

  # ==============================================================================
  # COMBINE WORKER FILES FOR THIS YEAR
  # ==============================================================================

  cat("\nCombining worker batch files...\n")

  batch_files <- list.files(temp_dir, pattern = "^worker_.*_batch_.*\\.rds$", full.names = TRUE)
  cat("  Found", length(batch_files), "RDS batch files\n")

  if (length(batch_files) == 0) {
    cat("  ERROR: No batch files found!\n")
    next
  }

  # Load and combine all batches
  combined_list <- lapply(batch_files, readRDS)
  combined_df <- bind_rows(combined_list)
  combined_df$date <- as.Date(combined_df$date)

  cat("  Total observations (before dedup):", nrow(combined_df), "\n")

  # Deduplicate tile overlaps
  n_before <- nrow(combined_df)

  combined_df <- combined_df %>%
    group_by(pixel_id, x, y, sensor, date, year, yday) %>%
    summarise(NDVI = median(NDVI, na.rm = TRUE), .groups = "drop")

  n_after <- nrow(combined_df)
  if (n_before > n_after) {
    cat("  Removed", n_before - n_after, "duplicates (",
        round(100 * (n_before - n_after) / n_before, 1), "%)\n", sep = "")
  }
  cat("  Final observations:", n_after, "\n")

  # ==============================================================================
  # SUMMARY STATISTICS FOR THIS YEAR
  # ==============================================================================

  obs_per_pixel <- combined_df %>%
    group_by(pixel_id) %>%
    summarise(n_obs = n(), .groups = "drop")

  cat("\n=== YEAR", current_year, "RESULTS ===\n")
  cat("Observations per pixel:\n")
  cat("  Mean:", round(mean(obs_per_pixel$n_obs), 1), "\n")
  cat("  Median:", median(obs_per_pixel$n_obs), "\n")
  cat("  5th percentile:", quantile(obs_per_pixel$n_obs, 0.05), "\n")
  cat("  95th percentile:", quantile(obs_per_pixel$n_obs, 0.95), "\n")

  # ==============================================================================
  # SAVE OUTPUT FOR THIS YEAR
  # ==============================================================================

  output_file <- file.path(config$output_dir, sprintf("ndvi_4km_%d.rds", current_year))
  cat("\nSaving to:", output_file, "\n")
  saveRDS(combined_df, output_file, compress = "gzip")

  # Clean up temp files for this year
  cat("Cleaning up temp files...\n")
  unlink(temp_dir, recursive = TRUE)

  year_elapsed <- as.numeric(difftime(Sys.time(), year_start, units = "mins"))
  cat("\nYear", current_year, "complete in", round(year_elapsed, 1), "minutes\n")

  # Clean up memory

  rm(combined_df, combined_list, results, file_info, file_chunks)
  gc()
}

# ==============================================================================
# FINAL SUMMARY
# ==============================================================================

overall_elapsed <- as.numeric(difftime(Sys.time(), overall_start, units = "mins"))

cat("\n")
cat("##############################################################################\n")
cat("# ALL YEARS COMPLETE\n")
cat("##############################################################################\n")
cat("\nFinished:", as.character(Sys.time()), "\n")
cat("Total time:", round(overall_elapsed, 1), "minutes\n")
cat("Years processed:", paste(years_to_process, collapse = ", "), "\n")
cat("Output directory:", config$output_dir, "\n")
