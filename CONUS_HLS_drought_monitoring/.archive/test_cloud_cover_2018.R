# ==============================================================================
# TEST: Download ALL 2018 scenes (cloud_cover_max = 100%)
# ==============================================================================
# Purpose: Test if removing the cloud_cover filter increases observations
#
# This script uses the existing download infrastructure with:
#   - start_year = 2018, end_year = 2018 (single year)
#   - cloud_cover_max = 100 (no cloud filtering at download)
#   - Existing skip logic will avoid re-downloading scenes we already have
#
# After download completes:
#   1. New scenes will be processed to NDVI with standard Fmask filtering
#   2. Run aggregation to compare obs/pixel with vs without cloud_cover filter
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

# Source acquisition functions
source("01_HLS_data_acquisition_FINAL.R")
source("01a_midwest_data_acquisition_parallel.R")

cat("=== TEST: CLOUD_COVER_MAX = 100% FOR 2018 ===\n\n")

cat("Configuration:\n")
cat("  Year: 2018 only\n")
cat("  Cloud cover max: 100% (no filtering)\n")
cat("  Skip existing: YES (will only download new scenes)\n")
cat("  Fmask filtering: Still applied at pixel level\n\n")

# Count existing 2018 scenes before download
existing_ndvi <- length(list.files(
  file.path(hls_paths$processed_ndvi, "daily", "2018"),
  pattern = "_NDVI\\.tif$"
))
cat("Existing 2018 NDVI scenes:", existing_ndvi, "\n\n")

# Run acquisition for 2018 only with cloud_cover_max = 100
cat("Starting download of additional 2018 scenes...\n")
cat("This will download scenes with 41-100% cloud cover that we don't have yet.\n")
cat("Existing scenes will be skipped.\n\n")

start_time <- Sys.time()

result <- acquire_conus_data(
  start_year = 2018,
  end_year = 2018,
  cloud_cover_max = 100  # Download ALL scenes regardless of cloud cover
)

end_time <- Sys.time()
elapsed <- difftime(end_time, start_time, units = "hours")

cat("\n=== DOWNLOAD COMPLETE ===\n")
cat("Time elapsed:", round(as.numeric(elapsed), 2), "hours\n\n")

# Count new 2018 scenes after download
new_ndvi <- length(list.files(
  file.path(hls_paths$processed_ndvi, "daily", "2018"),
  pattern = "_NDVI\\.tif$"
))

cat("Results:\n")
cat("  Before:", existing_ndvi, "NDVI scenes\n")
cat("  After:", new_ndvi, "NDVI scenes\n")
cat("  New scenes added:", new_ndvi - existing_ndvi, "\n")
cat("  Percent increase:", round((new_ndvi - existing_ndvi) / existing_ndvi * 100, 1), "%\n\n")

cat("=== NEXT STEPS ===\n")
cat("1. Run aggregation to 4km with min_pixels=5\n")
cat("2. Compare obs/pixel/year: before vs after\n")
cat("3. If significant gain, consider redownloading all years at higher threshold\n")
