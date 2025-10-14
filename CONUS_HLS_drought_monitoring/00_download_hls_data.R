# ==============================================================================
# PHASE 0: HLS DATA ACQUISITION
# ==============================================================================
# Purpose: Download HLS (Harmonized Landsat Sentinel-2) satellite data
# Domain: Midwest DEWS (Drought Early Warning System)
# Output: Raw bands + Fmask + processed NDVI files in /data/processed_ndvi/daily/
# ==============================================================================

library(httr)
library(jsonlite)
library(terra)
library(sf)

# Source dependencies
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

# Source acquisition functions
source("01_HLS_data_acquisition_FINAL.R")
source("01a_midwest_data_acquisition.R")

cat("=== PHASE 0: HLS DATA ACQUISITION ===\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Years to download (2013 = first HLS data, 2024 = current partial year)
  start_year = 2013,
  end_year = 2024,

  # Cloud cover threshold (higher = more scenes but more clouds)
  cloud_cover_max = 40,

  # Spatial domain
  domain = "Midwest DEWS",
  bbox = c(xmin = -104.5, ymin = 37.0, xmax = -82.0, ymax = 47.5)
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
  cat("  - Search NASA archives for HLS scenes\n")
  cat("  - Download Red, NIR, and Fmask bands\n")
  cat("  - Calculate NDVI with cloud masking\n")
  cat("  - Skip existing files (resumable)\n\n")

  cat("Expected time: 12-24 hours for full acquisition\n")
  cat("Expected data: ~100-150 GB\n\n")

  # Run acquisition
  result <- acquire_midwest_pilot_data(
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
  cat("=== PHASE 0 FUNCTIONS LOADED ===\n")
  cat("To run acquisition manually:\n")
  cat("  run_phase0 <- TRUE\n")
  cat("  source('00_download_hls_data.R')\n\n")
  cat("Or use the launcher script:\n")
  cat("  ./run_phase0.sh\n\n")
}
