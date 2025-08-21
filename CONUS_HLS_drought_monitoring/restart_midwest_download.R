# Restart Midwest DEWS Data Download
# Simple script to resume interrupted data acquisition

cat("=== MIDWEST DEWS DATA DOWNLOAD RESTART ===\n")
cat("Checking for existing execution status...\n\n")

# Source the execution controller
source("00_execute_data_pull.R")

# Check current status
current_status <- check_execution_status()

if (!is.null(current_status)) {
  cat("\nFound existing execution status. Resuming...\n")
  
  # Show what's left to do
  all_years <- DATA_PULL_CONFIG$start_year:DATA_PULL_CONFIG$end_year
  completed_years <- as.numeric(current_status$years_completed)
  remaining_years <- all_years[!all_years %in% completed_years]
  
  if (length(remaining_years) > 0) {
    cat("Remaining years to process:", paste(remaining_years, collapse = ", "), "\n")
    cat("Starting resume in 5 seconds... (Ctrl+C to cancel)\n")
    Sys.sleep(5)
    
    # Resume execution
    resume_execution()
    
  } else {
    cat("✅ All years already completed!\n")
  }
  
} else {
  cat("No previous execution found. Starting fresh...\n")
  cat("Starting in 5 seconds... (Ctrl+C to cancel)\n")
  Sys.sleep(5)
  
  # Start fresh execution
  execute_midwest_data_pull()
}

cat("\n=== RESTART COMPLETE ===\n")