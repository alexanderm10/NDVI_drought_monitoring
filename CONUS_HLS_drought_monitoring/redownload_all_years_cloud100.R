# ==============================================================================
# REDOWNLOAD ALL YEARS WITH cloud_cover_max=100%
# ==============================================================================
# Purpose: Download all HLS scenes regardless of scene-level cloud cover
#          Pixel-level Fmask filtering will handle cloud removal
#
# Based on 2018 test results:
#   - 7x more scenes available at cloud_cover_max=100% vs 40%
#   - After Fmask filtering: 13.9 obs/pixel vs 11.3 baseline (23% improvement)
#   - Most extra scenes are heavily clouded but some contribute valid pixels
#
# This script uses existing skip logic - already-downloaded NDVI files will
# be skipped, so only new scenes will be downloaded.
# ==============================================================================

# Source the parallel acquisition script
source("01a_midwest_data_acquisition_parallel.R")

cat("=== REDOWNLOAD ALL YEARS WITH cloud_cover_max=100% ===\n")
cat("Started:", as.character(Sys.time()), "\n\n")

cat("NOTE: This will download ALL scenes regardless of cloud cover.\n")
cat("Existing NDVI files will be skipped (resume capability).\n")
cat("Pixel-level Fmask filtering handles cloud removal during aggregation.\n\n")

# Run acquisition for all years with cloud_cover_max=100
result <- acquire_conus_data(
  start_year = 2013,
  end_year = 2024,
  cloud_cover_max = 100  # Download ALL scenes regardless of cloud cover
)

cat("\n=== REDOWNLOAD COMPLETE ===\n")
cat("Finished:", as.character(Sys.time()), "\n")

# Print summary
cat("\nSummary:\n")
cat("  Years processed:", result$years_processed, "\n")
cat("  Total scenes found:", result$total_scenes_found, "\n")
cat("  Total scenes downloaded:", result$total_scenes_downloaded, "\n")
cat("  Total NDVI processed:", result$total_ndvi_processed, "\n")
cat("  Landsat scenes:", result$landsat_scenes, "\n")
cat("  Sentinel scenes:", result$sentinel_scenes, "\n")
