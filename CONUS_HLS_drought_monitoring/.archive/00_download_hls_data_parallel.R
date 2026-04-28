# ==============================================================================
# PHASE 0: HLS DATA ACQUISITION (PARALLEL VERSION)
# ==============================================================================
# Purpose: Download HLS (Harmonized Landsat Sentinel-2) satellite data
# Domain: Midwest DEWS (Drought Early Warning System)
# Output: Raw bands + Fmask + processed NDVI files in /data/processed_ndvi/daily/
#
# PARALLELIZATION: Uses 4 workers to process tiles simultaneously
# - Each worker has its own NASA Earthdata session
# - Significantly faster than sequential processing
# - Resource-limited to avoid overwhelming the system
# ==============================================================================

library(httr)
library(jsonlite)
library(terra)
library(sf)
library(future)
library(future.apply)

# Source dependencies
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

# Source acquisition functions (parallel version)
source("01_HLS_data_acquisition_FINAL.R")
source("01a_midwest_data_acquisition_parallel.R")

cat("=== PHASE 0: HLS DATA ACQUISITION (PARALLEL) ===\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Years to download (2013 = first HLS data, 2025 = current year)
  start_year = 2013,
  end_year = 2025,

  # Cloud cover threshold (higher = more scenes but more clouds)
  cloud_cover_max = 40,

  # Spatial domain - FULL CONUS
  domain = "CONUS",
  bbox = c(xmin = -125, ymin = 25, xmax = -66, ymax = 49)
)

cat("Configuration:\n")
cat("  Years:", config$start_year, "-", config$end_year, "\n")
cat("  Domain:", config$domain, "\n")
cat("  Cloud cover threshold:", config$cloud_cover_max, "%\n")
cat("  Bbox:", paste(config$bbox, collapse = ", "), "\n\n")

# ==============================================================================
# EXECUTION
# ==============================================================================

# Check if running as main script (not being sourced)
if (!interactive() || exists("run_phase0")) {

  cat("=== EXECUTING PHASE 0: DATA ACQUISITION ===\n")
  cat("Started at:", as.character(Sys.time()), "\n\n")

  cat("This will:\n")
  cat("  - Search NASA archives for HLS scenes (FULL CONUS DOMAIN)\n")
  cat("  - Download Red, NIR, and Fmask bands in PARALLEL (4 workers)\n")
  cat("  - Calculate NDVI with cloud masking\n")
  cat("  - Skip existing files (resumable)\n\n")

  cat("CONUS SCALE ACQUISITION:\n")
  cat("  Expected time: 2-3 days for full acquisition (2013-2025, 40 tiles)\n")
  cat("  Expected data: ~500-800 GB\n")
  cat("  Resource usage: 4 cores max to avoid system overload\n")
  cat("  Processing: 40 tiles in batches of 4 (10 batches per month)\n\n")

  # Run acquisition
  result <- acquire_conus_data(
    start_year = config$start_year,
    end_year = config$end_year,
    cloud_cover_max = config$cloud_cover_max
  )

  cat("\n=== PHASE 0 COMPLETE ===\n")
  cat("Total scenes found:", result$total_scenes_found, "\n")
  cat("Total downloaded:", result$total_scenes_downloaded, "\n")
  cat("Total NDVI processed:", result$total_ndvi_processed, "\n")
  cat("  Landsat scenes:", result$landsat_scenes, "\n")
  cat("  Sentinel scenes:", result$sentinel_scenes, "\n")
  cat("Data location:", hls_paths$processed_ndvi, "\n\n")

  cat("Next step: Run Phase 1 (01_aggregate_to_4km.R)\n")

} else {
  cat("=== PHASE 0 FUNCTIONS LOADED (PARALLEL VERSION) ===\n")
  cat("To run acquisition manually:\n")
  cat("  run_phase0 <- TRUE\n")
  cat("  source('00_download_hls_data_parallel.R')\n\n")
  cat("Or use directly from Docker:\n")
  cat("  docker exec conus-hls-drought-monitor Rscript 00_download_hls_data_parallel.R\n\n")
  cat("Note: Uses 4 workers for parallel tile processing\n")
}
