# ==============================================================================
# EXECUTE FULL HLS DATA ACQUISITION
# ==============================================================================
# Purpose: Download complete HLS dataset (all months, all years)
# Current: Only January data exists
# Target: Full year coverage for 2013-2024
# ==============================================================================

source("01_HLS_data_acquisition_FINAL.R")
source("01a_midwest_data_acquisition.R")

cat("=== HLS FULL DATA ACQUISITION ===\n\n")
cat("Current status: Only January data downloaded (testing phase)\n")
cat("Target: Full year coverage 2013-2024\n\n")

cat("This will:\n")
cat("  - Download ALL months for 2013-2024\n")
cat("  - Skip existing files (won't re-download January)\n")
cat("  - Take ~12-24 hours\n")
cat("  - Require ~100-150 GB storage\n\n")

# Run the acquisition
result <- acquire_midwest_pilot_data(
  start_year = 2013,
  end_year = 2024,
  cloud_cover_max = 40
)

cat("\n=== ACQUISITION COMPLETE ===\n")
cat("Scenes downloaded:", result$total_scenes_downloaded, "\n")
cat("NDVI processed:", result$total_ndvi_processed, "\n")
