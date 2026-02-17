#!/usr/bin/env Rscript
# ==============================================================================
# PROCESS BULK DOWNLOADED HLS BANDS TO NDVI
# ==============================================================================
# Purpose: Process raw bands from getHLS_bands.sh and calculate NDVI
#          Saves to location that current download script expects
#          Enables current script to skip already-processed scenes
#
# Input:  bulk_downloads/raw/L30/ and bulk_downloads/raw/S30/
#         (organized by year/tile as: L30/YYYY/##/L/T/G/granule_name/)
#
# Output: /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/YYYY/
#         (filename: HLS.*.NDVI.tif - same pattern as current script)
#
# Usage:  Rscript process_bulk_ndvi.R [year] [--workers=N]
# Example: Rscript process_bulk_ndvi.R 2019 --workers=8
# ==============================================================================

library(terra)
library(future)
library(future.apply)

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  cat("Usage: Rscript process_bulk_ndvi.R [year] [--workers=N]\n")
  cat("Example: Rscript process_bulk_ndvi.R 2019 --workers=8\n")
  quit(status = 1)
}

year_to_process <- as.numeric(args[1])
n_workers <- 8  # Default

# Check for --workers flag
for (arg in args) {
  if (grepl("^--workers=", arg)) {
    n_workers <- as.numeric(sub("^--workers=", "", arg))
  }
}

cat("\n=== BULK DOWNLOAD NDVI PROCESSING ===\n")
cat("Year:", year_to_process, "\n")
cat("Workers:", n_workers, "\n\n")

# Paths (raw data on server, not local repo)
bulk_raw_dir <- "/mnt/malexander/datasets/ndvi_monitor/bulk_downloads_raw"
output_base <- "/mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily"
output_dir <- file.path(output_base, year_to_process)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Function to calculate NDVI from HLS bands
calculate_ndvi_bulk <- function(granule_dir, sensor_type, output_dir) {

  granule_name <- basename(granule_dir)

  # Expected output filename
  ndvi_file <- file.path(output_dir, paste0(granule_name, "_NDVI.tif"))

  # Skip if already processed
  if (file.exists(ndvi_file)) {
    return(list(status = "skipped", granule = granule_name))
  }

  # Find band files
  b04_file <- list.files(granule_dir, pattern = "\\.B04\\.tif$", full.names = TRUE)
  fmask_file <- list.files(granule_dir, pattern = "\\.Fmask\\.tif$", full.names = TRUE)

  # NIR band differs by sensor
  if (sensor_type == "L30") {
    nir_file <- list.files(granule_dir, pattern = "\\.B05\\.tif$", full.names = TRUE)
  } else {
    nir_file <- list.files(granule_dir, pattern = "\\.B8A\\.tif$", full.names = TRUE)
  }

  # Check all required files exist
  if (length(b04_file) == 0 || length(nir_file) == 0) {
    return(list(status = "missing_bands", granule = granule_name))
  }

  tryCatch({
    # Read bands
    red <- rast(b04_file[1])
    nir <- rast(nir_file[1])

    # Calculate NDVI
    ndvi <- (nir - red) / (nir + red)

    # Apply Fmask if available
    if (length(fmask_file) > 0) {
      fmask <- rast(fmask_file[1])

      # Fmask values:
      # 0 = Clear land/water
      # 1 = Cloud shadow
      # 2 = Snow/ice
      # 3 = Cloud
      # 4 = Water
      # 255 = Fill value

      # Mask out clouds (3), cloud shadow (1), snow (2), and fill (255)
      # Keep: 0 (clear land/water) and 4 (water)
      mask_invalid <- fmask %in% c(1, 2, 3, 255)
      ndvi[mask_invalid] <- NA
      rm(fmask, mask_invalid)
    }

    # Save NDVI
    writeRaster(ndvi, ndvi_file, overwrite = TRUE,
                datatype = "FLT4S", gdal = c("COMPRESS=LZW"))

    rm(red, nir, ndvi)
    gc(verbose = FALSE)

    return(list(status = "success", granule = granule_name))

  }, error = function(e) {
    return(list(status = "error", granule = granule_name,
                message = conditionMessage(e)))
  })
}

# Find all granule directories for the year
cat("Scanning for granules in year", year_to_process, "...\n")

granules <- list()
for (sensor in c("L30", "S30")) {
  sensor_dir <- file.path(bulk_raw_dir, sensor, year_to_process)

  if (dir.exists(sensor_dir)) {
    # Walk through the tile subdirectories (##/L/T/G/)
    tile_dirs <- list.dirs(sensor_dir, recursive = TRUE, full.names = TRUE)

    for (tile_dir in tile_dirs) {
      # Check if this directory contains actual granule files (has .tif files)
      tif_files <- list.files(tile_dir, pattern = "\\.tif$", full.names = FALSE)

      if (length(tif_files) > 0) {
        # This is a granule directory
        granules[[length(granules) + 1]] <- list(
          path = tile_dir,
          sensor = sensor
        )
      }
    }
  }
}

cat("Found", length(granules), "granules to process\n\n")

if (length(granules) == 0) {
  cat("No granules found. Make sure bulk download completed successfully.\n")
  cat("Expected directory structure:\n")
  cat("  ", file.path(bulk_raw_dir, "L30", year_to_process), "\n")
  cat("  ", file.path(bulk_raw_dir, "S30", year_to_process), "\n")
  quit(status = 0)
}

# Allow large globals for terra raster objects
options(future.globals.maxSize = 2 * 1024^3)  # 2 GB

# Process in chunks to limit memory accumulation and enable recovery
chunk_size <- 5000
n_chunks <- ceiling(length(granules) / chunk_size)
cat("Processing with", n_workers, "parallel workers in", n_chunks, "chunks of", chunk_size, "\n\n")

all_results <- list()

for (chunk_idx in seq_len(n_chunks)) {
  chunk_start <- (chunk_idx - 1) * chunk_size + 1
  chunk_end <- min(chunk_idx * chunk_size, length(granules))
  chunk_indices <- chunk_start:chunk_end

  cat("=== Chunk", chunk_idx, "/", n_chunks, " (granules", chunk_start, "-", chunk_end, ") ===\n")

  # Fresh worker pool each chunk to prevent memory buildup
  plan(multisession, workers = n_workers)

  chunk_results <- tryCatch({
    future_lapply(chunk_indices, function(i) {
      granule <- granules[[i]]
      if (i %% 500 == 0) {
        cat("Progress:", i, "/", length(granules), "\n")
      }
      calculate_ndvi_bulk(granule$path, granule$sensor, output_dir)
    }, future.seed = TRUE)
  }, error = function(e) {
    cat("WARNING: Chunk", chunk_idx, "failed:", conditionMessage(e), "\n")
    cat("Falling back to sequential processing for this chunk...\n")

    # Sequential fallback for failed chunks
    lapply(chunk_indices, function(i) {
      granule <- granules[[i]]
      tryCatch(
        calculate_ndvi_bulk(granule$path, granule$sensor, output_dir),
        error = function(e2) {
          list(status = "error", granule = basename(granule$path),
               message = conditionMessage(e2))
        }
      )
    })
  })

  all_results <- c(all_results, chunk_results)

  # Clean up between chunks
  plan(sequential)
  gc(verbose = FALSE)

  cat("Chunk", chunk_idx, "complete.",
      sum(sapply(chunk_results, function(x) x$status == "success")), "succeeded,",
      sum(sapply(chunk_results, function(x) x$status == "skipped")), "skipped,",
      sum(sapply(chunk_results, function(x) x$status == "error")), "errors\n\n")
}

results <- all_results

# Summarize results
status_counts <- table(sapply(results, function(x) x$status))

cat("\n=== PROCESSING COMPLETE ===\n")
cat("Total granules:", length(granules), "\n")
cat("Success:", ifelse("success" %in% names(status_counts), status_counts["success"], 0), "\n")
cat("Skipped (already exists):", ifelse("skipped" %in% names(status_counts), status_counts["skipped"], 0), "\n")
cat("Missing bands:", ifelse("missing_bands" %in% names(status_counts), status_counts["missing_bands"], 0), "\n")
cat("Errors:", ifelse("error" %in% names(status_counts), status_counts["error"], 0), "\n")

# Show errors if any
errors <- Filter(function(x) x$status == "error", results)
if (length(errors) > 0) {
  cat("\nError details (first 10):\n")
  for (i in 1:min(10, length(errors))) {
    cat("  ", errors[[i]]$granule, ": ", errors[[i]]$message, "\n", sep = "")
  }
}

# Check output
output_files <- list.files(output_dir, pattern = "_NDVI\\.tif$")
cat("\nOutput directory:", output_dir, "\n")
cat("NDVI files created:", length(output_files), "\n")

cat("\n✓ Processing complete for year", year_to_process, "\n")
cat("These NDVI files will be automatically skipped by the current download script.\n\n")
