# Step 1: Verify Fmask Coverage

source("match_ndvi_fmask.R")
matched <- run_matching_report()

# This will show you the matching statistics. You should see something close to 100% match rate (4,863 NDVI files with Fmask).

# Step 2: Run NDVI Reprocessing

source("reprocess_ndvi_with_fmask.R")
results <- run_ndvi_reprocessing(overwrite = TRUE)

# This will:
#   - Show a progress bar as it processes ~4,863 scenes
# - Create backups in U:/datasets/ndvi_monitor/processed_ndvi/daily_unmasked_backup/
#   - Recalculate NDVI with Fmask quality filtering
# - Take approximately 30-60 minutes
# 
# The results object will contain summary counts (success, skipped, failed).


# retrying failed downloads.
source("recover_failed_scenes.R")
results <- run_scene_recovery()

# rerun sensor diagnostic to check for parity
source("diagnostic_hls_sensor_comparison_v2.R")
results <- run_hls_sensor_diagnostic()

