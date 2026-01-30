#!/usr/bin/env Rscript
# ==============================================================================
# MONTHLY INCREMENTAL UPDATE SCRIPT
# ==============================================================================
# Purpose: Operational script to download, aggregate, and process new HLS data
#          on a monthly basis for near-real-time drought monitoring
#
# Usage:
#   Rscript 00_monthly_update.R YYYY MM
#   Rscript 00_monthly_update.R 2026 02       # Update February 2026
#   Rscript 00_monthly_update.R current       # Update current/previous month
#
# Requirements:
#   - Baseline climatology must exist (02_doy_looped_norms.R complete)
#   - Previous months of current year already processed
#
# What it does:
#   1. Downloads new HLS scenes for specified month
#   2. Aggregates new scenes to 4km grid
#   3. Appends to yearly timeseries
#   4. Refits year-specific GAMs for current year
#   5. Recalculates anomalies for current year
#
# What it does NOT do:
#   - Recalculate baseline climatology (only done annually on Jan 1)
#   - Process historical years (use full pipeline scripts for that)
#
# Runtime: ~4-6 hours for typical month (depending on scene count)
# ==============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(lubridate)
})

# ==============================================================================
# PARSE COMMAND-LINE ARGUMENTS
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)

if (length(args) == 0 || args[1] == "current") {
  # Default: Process previous complete month
  current_date <- Sys.Date()
  target_year <- year(current_date %m-% months(1))
  target_month <- month(current_date %m-% months(1))
  cat("No arguments provided. Processing previous month:", target_year, "-",
      sprintf("%02d", target_month), "\n")
} else if (length(args) >= 2) {
  target_year <- as.integer(args[1])
  target_month <- as.integer(args[2])

  # Validate inputs
  if (is.na(target_year) || target_year < 2013 || target_year > 2100) {
    stop("Invalid year. Must be between 2013 and 2100.")
  }
  if (is.na(target_month) || target_month < 1 || target_month > 12) {
    stop("Invalid month. Must be between 1 and 12.")
  }
} else {
  stop("Usage: Rscript 00_monthly_update.R YYYY MM\n",
       "   or: Rscript 00_monthly_update.R current")
}

# Calculate date range
start_date <- as.Date(sprintf("%d-%02d-01", target_year, target_month))
end_date <- ceiling_date(start_date, "month") - days(1)

cat("\n=== MONTHLY UPDATE ===\n")
cat("Target period:", format(start_date, "%Y-%m-%d"), "to",
    format(end_date, "%Y-%m-%d"), "\n")
cat("Started:", as.character(Sys.time()), "\n\n")

# ==============================================================================
# SETUP PATHS
# ==============================================================================

source("00_setup_paths.R")
hls_paths <- get_hls_paths()

# Check that baseline exists
baseline_file <- file.path(hls_paths$gam_models, "doy_looped_norms.rds")
if (!file.exists(baseline_file)) {
  stop("ERROR: Baseline climatology not found.\n",
       "Please run 02_doy_looped_norms.R first to create the baseline.")
}

# Create log file
log_file <- file.path(hls_paths$base,
                      sprintf("monthly_update_%d_%02d.log",
                              target_year, target_month))
log_conn <- file(log_file, open = "wt")
sink(log_conn, type = "output", split = TRUE)
sink(log_conn, type = "message")

cat("=== MONTHLY UPDATE LOG ===\n")
cat("Target period:", format(start_date, "%Y-%m-%d"), "to",
    format(end_date, "%Y-%m-%d"), "\n")
cat("Log file:", log_file, "\n\n")

# ==============================================================================
# STEP 1: DOWNLOAD NEW HLS SCENES
# ==============================================================================

cat("\n##############################################################################\n")
cat("# STEP 1: DOWNLOAD NEW HLS SCENES\n")
cat("##############################################################################\n\n")

cat("Downloading HLS scenes from", format(start_date, "%Y-%m-%d"), "to",
    format(end_date, "%Y-%m-%d"), "...\n")

# Source the parallel acquisition script
source("01a_midwest_data_acquisition_parallel.R")

tryCatch({
  download_result <- acquire_conus_data_daterange(
    start_date = format(start_date, "%Y-%m-%d"),
    end_date = format(end_date, "%Y-%m-%d"),
    cloud_cover_max = 100  # Download all scenes, Fmask handles cloud removal
  )

  cat("✓ Download complete\n")
  cat("  Scenes found:", download_result$total_scenes_found, "\n")
  cat("  NDVI processed:", download_result$total_ndvi_processed, "\n")
}, error = function(e) {
  cat("✗ ERROR during download:", e$message, "\n")
  stop("Download failed. Cannot proceed with monthly update.")
})

# ==============================================================================
# STEP 2: AGGREGATE NEW SCENES TO 4KM
# ==============================================================================

cat("\n##############################################################################\n")
cat("# STEP 2: AGGREGATE NEW SCENES TO 4KM\n")
cat("##############################################################################\n\n")

cat("Aggregating", target_year, "data to 4km grid...\n")

# Run aggregation script for target year
aggregation_cmd <- sprintf(
  "Rscript 01_aggregate_to_4km_parallel.R %d --workers=4",
  target_year
)

cat("Running:", aggregation_cmd, "\n")
aggregation_status <- system(aggregation_cmd, intern = FALSE)

if (aggregation_status != 0) {
  stop("ERROR: Aggregation failed with exit code ", aggregation_status)
}

cat("✓ Aggregation complete\n")

# Check output file
year_file <- file.path(hls_paths$gam_models, "aggregated_years",
                       sprintf("ndvi_4km_%d.rds", target_year))
if (!file.exists(year_file)) {
  stop("ERROR: Expected output file not found: ", year_file)
}

# Get file info
file_info <- file.info(year_file)
cat("  Output file:", year_file, "\n")
cat("  File size:", round(file_info$size / 1024^2, 2), "MB\n")

# ==============================================================================
# STEP 3: UPDATE COMBINED TIMESERIES (OPTIONAL)
# ==============================================================================

cat("\n##############################################################################\n")
cat("# STEP 3: UPDATE COMBINED TIMESERIES\n")
cat("##############################################################################\n\n")

# Check if combined timeseries exists
combined_file <- file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.rds")

if (file.exists(combined_file)) {
  cat("Updating combined timeseries...\n")

  tryCatch({
    # Load existing timeseries
    cat("  Loading existing timeseries...\n")
    existing <- readRDS(combined_file)

    # Load new year data
    cat("  Loading new data for", target_year, "...\n")
    new_data <- readRDS(year_file)

    # Combine and deduplicate
    cat("  Combining and deduplicating...\n")
    combined <- bind_rows(existing, new_data) %>%
      distinct(pixel_id, date, .keep_all = TRUE) %>%
      arrange(pixel_id, date)

    # Save updated timeseries
    cat("  Saving updated timeseries...\n")
    saveRDS(combined, combined_file, compress = "xz")

    cat("✓ Combined timeseries updated\n")
    cat("  Total observations:", nrow(combined), "\n")
  }, error = function(e) {
    cat("⚠ WARNING: Could not update combined timeseries:", e$message, "\n")
    cat("  This is not critical - year-specific file exists.\n")
  })
} else {
  cat("ℹ Combined timeseries does not exist yet.\n")
  cat("  This is normal if still processing historical data.\n")
  cat("  Year-specific file is available:", year_file, "\n")
}

# ==============================================================================
# STEP 4: REFIT YEAR-SPECIFIC GAMS
# ==============================================================================

cat("\n##############################################################################\n")
cat("# STEP 4: REFIT YEAR-SPECIFIC GAMS\n")
cat("##############################################################################\n\n")

cat("Refitting GAMs for year", target_year, "...\n")

# NOTE: This assumes Script 03 has been modified to accept --year argument
# If not, this will refit ALL years (which is okay but slower)
gam_cmd <- sprintf(
  "Rscript 03_doy_looped_year_predictions.R --year=%d",
  target_year
)

cat("Running:", gam_cmd, "\n")
cat("This may take 2-3 hours...\n\n")

gam_status <- system(gam_cmd, intern = FALSE)

if (gam_status != 0) {
  cat("⚠ WARNING: GAM fitting failed or Script 03 doesn't support --year flag.\n")
  cat("  You may need to run Script 03 manually or update it to accept --year.\n")
  cat("  For now, continuing to anomaly calculation...\n")
} else {
  cat("✓ GAM fitting complete\n")
}

# Check output
gam_output <- file.path(hls_paths$gam_models, "modeled_ndvi",
                        sprintf("modeled_ndvi_%d.rds", target_year))
if (file.exists(gam_output)) {
  cat("  Output file:", gam_output, "\n")
} else {
  cat("  ⚠ Expected output not found. Check logs.\n")
}

# ==============================================================================
# STEP 5: RECALCULATE ANOMALIES
# ==============================================================================

cat("\n##############################################################################\n")
cat("# STEP 5: RECALCULATE ANOMALIES\n")
cat("##############################################################################\n\n")

cat("Recalculating anomalies for year", target_year, "...\n")

# NOTE: This assumes Script 04 has been modified to accept --year argument
anomaly_cmd <- sprintf(
  "Rscript 04_calculate_anomalies.R --year=%d",
  target_year
)

cat("Running:", anomaly_cmd, "\n")
anomaly_status <- system(anomaly_cmd, intern = FALSE)

if (anomaly_status != 0) {
  cat("⚠ WARNING: Anomaly calculation failed or Script 04 doesn't support --year flag.\n")
  cat("  You may need to run Script 04 manually or update it to accept --year.\n")
} else {
  cat("✓ Anomaly calculation complete\n")
}

# Check output
anomaly_output <- file.path(hls_paths$gam_models, "modeled_ndvi_anomalies",
                            sprintf("anomalies_%d.rds", target_year))
if (file.exists(anomaly_output)) {
  cat("  Output file:", anomaly_output, "\n")
} else {
  cat("  ⚠ Expected output not found. Check logs.\n")
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n##############################################################################\n")
cat("# MONTHLY UPDATE COMPLETE\n")
cat("##############################################################################\n\n")

cat("Finished:", as.character(Sys.time()), "\n\n")

cat("Summary:\n")
cat("  Period processed:", format(start_date, "%Y-%m-%d"), "to",
    format(end_date, "%Y-%m-%d"), "\n")
cat("  Scenes downloaded:", download_result$total_ndvi_processed, "\n")
cat("  Year file updated:", year_file, "\n")

if (file.exists(gam_output)) {
  cat("  GAMs updated: ✓\n")
} else {
  cat("  GAMs updated: ✗ (check logs)\n")
}

if (file.exists(anomaly_output)) {
  cat("  Anomalies updated: ✓\n")
} else {
  cat("  Anomalies updated: ✗ (check logs)\n")
}

cat("\nLog file:", log_file, "\n")

cat("\n=== NEXT STEPS ===\n")
cat("1. Review log file for any warnings or errors\n")
cat("2. Visualize updated anomalies (Script 05)\n")
cat("3. Archive/backup monthly outputs\n")
cat("4. Update web dashboard (if applicable)\n\n")

# Close log
sink(type = "output")
sink(type = "message")
close(log_conn)

cat("Monthly update complete. Log saved to:", log_file, "\n")
