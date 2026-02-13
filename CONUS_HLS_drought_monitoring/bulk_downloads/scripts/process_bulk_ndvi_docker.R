#!/usr/bin/env Rscript
# ==============================================================================
# PROCESS BULK DOWNLOADED HLS BANDS TO NDVI (DOCKER VERSION)
# ==============================================================================
# Same as process_bulk_ndvi.R but uses Docker-internal paths.
# Runs inside Docker container where terra is available.
#
# Input:  /data/bulk_downloads_raw/L30/ and S30/
# Output: /data/processed_ndvi/daily/YYYY/
#
# Usage:  Rscript process_bulk_ndvi_docker.R [year] [--workers=N]
# ==============================================================================

library(terra)
library(future)
library(future.apply)

# Parse command line arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  cat("Usage: Rscript process_bulk_ndvi_docker.R [year] [--workers=N]\n")
  quit(status = 1)
}

year_to_process <- as.numeric(args[1])
n_workers <- 8

for (arg in args) {
  if (grepl("^--workers=", arg)) {
    n_workers <- as.numeric(sub("^--workers=", "", arg))
  }
}

cat("\n=== BULK DOWNLOAD NDVI PROCESSING (DOCKER) ===\n")
cat("Year:", year_to_process, "\n")
cat("Workers:", n_workers, "\n\n")

# Docker-internal paths
bulk_raw_dir <- "/data/bulk_downloads_raw"
output_base <- "/data/processed_ndvi/daily"
output_dir <- file.path(output_base, year_to_process)
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Function to calculate NDVI from HLS bands
calculate_ndvi_bulk <- function(granule_dir, sensor_type, output_dir) {

  granule_name <- basename(granule_dir)
  ndvi_file <- file.path(output_dir, paste0(granule_name, "_NDVI.tif"))

  if (file.exists(ndvi_file)) {
    return(list(status = "skipped", granule = granule_name))
  }

  b04_file <- list.files(granule_dir, pattern = "\\.B04\\.tif$", full.names = TRUE)
  fmask_file <- list.files(granule_dir, pattern = "\\.Fmask\\.tif$", full.names = TRUE)

  if (sensor_type == "L30") {
    nir_file <- list.files(granule_dir, pattern = "\\.B05\\.tif$", full.names = TRUE)
  } else {
    nir_file <- list.files(granule_dir, pattern = "\\.B8A\\.tif$", full.names = TRUE)
  }

  if (length(b04_file) == 0 || length(nir_file) == 0) {
    return(list(status = "missing_bands", granule = granule_name))
  }

  tryCatch({
    red <- rast(b04_file[1])
    nir <- rast(nir_file[1])
    ndvi <- (nir - red) / (nir + red)

    if (length(fmask_file) > 0) {
      fmask <- rast(fmask_file[1])
      mask_invalid <- fmask %in% c(1, 2, 3, 255)
      ndvi[mask_invalid] <- NA
    }

    writeRaster(ndvi, ndvi_file, overwrite = TRUE,
                datatype = "FLT4S", gdal = c("COMPRESS=LZW"))

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
    tile_dirs <- list.dirs(sensor_dir, recursive = TRUE, full.names = TRUE)

    for (tile_dir in tile_dirs) {
      tif_files <- list.files(tile_dir, pattern = "\\.tif$", full.names = FALSE)

      if (length(tif_files) > 0) {
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
  cat("No granules found.\n")
  cat("Expected:", file.path(bulk_raw_dir, "L30", year_to_process), "\n")
  cat("Expected:", file.path(bulk_raw_dir, "S30", year_to_process), "\n")
  quit(status = 0)
}

plan(multisession, workers = n_workers)
cat("Processing with", n_workers, "parallel workers...\n\n")

results <- future_lapply(seq_along(granules), function(i) {
  granule <- granules[[i]]
  if (i %% 1000 == 0) {
    cat("Progress:", i, "/", length(granules), "\n")
  }
  calculate_ndvi_bulk(granule$path, granule$sensor, output_dir)
}, future.seed = TRUE)

status_counts <- table(sapply(results, function(x) x$status))

cat("\n=== PROCESSING COMPLETE ===\n")
cat("Total granules:", length(granules), "\n")
cat("Success:", ifelse("success" %in% names(status_counts), status_counts["success"], 0), "\n")
cat("Skipped (already exists):", ifelse("skipped" %in% names(status_counts), status_counts["skipped"], 0), "\n")
cat("Missing bands:", ifelse("missing_bands" %in% names(status_counts), status_counts["missing_bands"], 0), "\n")
cat("Errors:", ifelse("error" %in% names(status_counts), status_counts["error"], 0), "\n")

errors <- Filter(function(x) x$status == "error", results)
if (length(errors) > 0) {
  cat("\nError details (first 10):\n")
  for (i in 1:min(10, length(errors))) {
    cat("  ", errors[[i]]$granule, ": ", errors[[i]]$message, "\n", sep = "")
  }
}

output_files <- list.files(output_dir, pattern = "_NDVI\\.tif$")
cat("\nOutput directory:", output_dir, "\n")
cat("NDVI files created:", length(output_files), "\n")
cat("\n✓ Processing complete for year", year_to_process, "\n")
