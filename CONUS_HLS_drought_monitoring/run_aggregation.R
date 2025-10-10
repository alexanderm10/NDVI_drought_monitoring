#!/usr/bin/env Rscript
# ==============================================================================
# RUN PHASE 1: 4KM AGGREGATION
# ==============================================================================
# This script runs the full 30m -> 4km aggregation for all years
# Designed to be run with nohup for long-running processes
# ==============================================================================

cat("=== STARTING PHASE 1: 4KM AGGREGATION ===\n")
cat("Started at:", as.character(Sys.time()), "\n\n")

# Source required scripts
source("00_setup_paths.R")
source("01_aggregate_to_4km.R")

# Display configuration
cat("Configuration summary:\n")
cat("  Years:", paste(range(config$years), collapse = "-"), "\n")
cat("  Target resolution:", config$target_resolution, "m\n")
cat("  Aggregation method:", config$aggregation_method, "\n")
cat("  Output file:", config$output_file, "\n")
cat("  Checkpoint interval:", config$checkpoint_interval, "scenes\n\n")

# Run aggregation
cat("Starting aggregation...\n")
cat("This may take 2-4 hours. Progress will be displayed every 50 scenes.\n\n")

start_time <- Sys.time()

result <- tryCatch({
  timeseries_4km <- process_ndvi_to_4km(config)
  timeseries_4km
}, error = function(e) {
  cat("\n❌ ERROR during aggregation:\n")
  cat(e$message, "\n")
  cat("\nStack trace:\n")
  print(traceback())
  return(NULL)
})

end_time <- Sys.time()
elapsed <- difftime(end_time, start_time, units = "hours")

# Summary
cat("\n=== PHASE 1 COMPLETE ===\n")
cat("Started:", as.character(start_time), "\n")
cat("Finished:", as.character(end_time), "\n")
cat("Total time:", round(as.numeric(elapsed), 2), "hours\n")

if (!is.null(result)) {
  cat("\n✅ SUCCESS!\n")
  cat("Output file:", config$output_file, "\n")
  cat("Total observations:", nrow(result), "\n")
  cat("Unique 4km pixels:", length(unique(result$pixel_id)), "\n")
  cat("Date range:", paste(range(result$date), collapse = " to "), "\n")

  # Save summary
  summary_file <- file.path(hls_paths$processing_logs, "phase1_aggregation_summary.txt")
  sink(summary_file)
  cat("PHASE 1: 4KM AGGREGATION SUMMARY\n")
  cat("================================\n\n")
  cat("Completed:", as.character(end_time), "\n")
  cat("Elapsed time:", round(as.numeric(elapsed), 2), "hours\n")
  cat("Total observations:", nrow(result), "\n")
  cat("Unique 4km pixels:", length(unique(result$pixel_id)), "\n")
  cat("Date range:", paste(range(result$date), collapse = " to "), "\n")
  cat("Years:", paste(range(result$year), collapse = "-"), "\n")
  cat("\nOutput file:", config$output_file, "\n")
  sink()

  cat("\nSummary saved to:", summary_file, "\n")
} else {
  cat("\n❌ FAILED - Check error messages above\n")
  cat("Checkpoint file may contain partial results\n")
}

cat("\n=== SCRIPT COMPLETE ===\n")
