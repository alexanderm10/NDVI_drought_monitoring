# HLS Data Pull Execution Controller
# Master script to orchestrate NIDIS Midwest DEWS data acquisition
# Provides structured workflow with progress tracking and error recovery

library(lubridate)

# Source required scripts
source("00_setup_paths.R")
source("01_HLS_data_acquisition_FINAL.R")
source("02_midwest_pilot.R")

######################
# Execution Configuration
######################

# Data pull configuration
DATA_PULL_CONFIG <- list(
  # Domain settings
  domain = "NIDIS_Midwest_DEWS",
  
  # Time range settings
  start_year = 2020,          # Start with recent years first
  end_year = 2024,            # Up to current year
  current_year_cutoff = "2024-10-31",  # Don't process incomplete current year data
  
  # Quality settings
  cloud_cover_max = 40,       # Slightly higher for better temporal coverage
  
  # Processing settings
  batch_size_years = 1,       # Process one year at a time
  retry_failed_downloads = TRUE,
  
  # Storage settings
  storage_path = hls_paths$base,
  backup_logs = TRUE
)

######################
# Execution Status Management
######################

# Initialize or load execution status
initialize_execution_status <- function(config = DATA_PULL_CONFIG) {
  
  status_file <- file.path(hls_paths$logs, "execution_status.json")
  
  if (file.exists(status_file)) {
    cat("Loading existing execution status...\n")
    status <- jsonlite::fromJSON(status_file)
  } else {
    cat("Initializing new execution status...\n")
    status <- list(
      execution_id = paste0("MIDWEST_", format(Sys.time(), "%Y%m%d_%H%M%S")),
      start_time = Sys.time(),
      domain = config$domain,
      total_years = config$end_year - config$start_year + 1,
      years_completed = character(0),
      years_failed = character(0),
      current_year = NULL,
      total_scenes_found = 0,
      total_scenes_downloaded = 0,
      total_ndvi_processed = 0,
      total_data_gb = 0,
      last_update = Sys.time(),
      status = "initialized"
    )
  }
  
  return(status)
}

# Save execution status
save_execution_status <- function(status) {
  status_file <- file.path(hls_paths$logs, "execution_status.json")
  dir.create(dirname(status_file), recursive = TRUE, showWarnings = FALSE)
  
  status$last_update <- Sys.time()
  jsonlite::write_json(status, status_file, pretty = TRUE, auto_unbox = TRUE)
  
  cat("Execution status saved to:", status_file, "\n")
}

# Display execution status
display_status <- function(status) {
  cat("\n=== EXECUTION STATUS ===\n")
  cat("Execution ID:", status$execution_id, "\n")
  cat("Domain:", status$domain, "\n")
  cat("Progress:", length(status$years_completed), "/", status$total_years, "years completed\n")
  cat("Current status:", status$status, "\n")
  
  if (length(status$years_completed) > 0) {
    cat("Completed years:", paste(status$years_completed, collapse = ", "), "\n")
  }
  
  if (length(status$years_failed) > 0) {
    cat("Failed years:", paste(status$years_failed, collapse = ", "), "\n")
  }
  
  cat("Total scenes found:", status$total_scenes_found, "\n")
  cat("Total scenes downloaded:", status$total_scenes_downloaded, "\n")
  cat("Total NDVI processed:", status$total_ndvi_processed, "\n")
  cat("Estimated data volume:", round(status$total_data_gb, 1), "GB\n")
  cat("Last update:", as.character(status$last_update), "\n")
  cat("========================\n\n")
}

######################
# Pre-flight Checks
######################

run_preflight_checks <- function(config = DATA_PULL_CONFIG) {
  
  cat("=== PRE-FLIGHT CHECKS ===\n")
  
  checks_passed <- 0
  total_checks <- 6
  
  # Check 1: NASA authentication
  cat("1. Checking NASA Earthdata authentication...\n")
  auth_result <- try(create_nasa_session(), silent = TRUE)
  if (!inherits(auth_result, "try-error")) {
    cat("   ✓ NASA authentication working\n")
    checks_passed <- checks_passed + 1
  } else {
    cat("   ❌ NASA authentication failed\n")
    cat("   Please check your _netrc file\n")
  }
  
  # Check 2: Storage space
  cat("2. Checking storage space...\n")
  tryCatch({
    check_storage_space(config$storage_path)
    cat("   ✓ Storage path accessible\n")
    checks_passed <- checks_passed + 1
  }, error = function(e) {
    cat("   ❌ Storage check failed:", e$message, "\n")
  })
  
  # Check 3: Directory structure
  cat("3. Checking directory structure...\n")
  create_hls_directory_structure(hls_paths)
  cat("   ✓ Directory structure ready\n")
  checks_passed <- checks_passed + 1
  
  # Check 4: API connectivity
  cat("4. Testing NASA API connectivity...\n")
  api_test <- test_midwest_search(year = 2024, month = 7)
  if (api_test) {
    cat("   ✓ NASA API accessible\n")
    checks_passed <- checks_passed + 1
  } else {
    cat("   ❌ NASA API test failed\n")
  }
  
  # Check 5: Download test
  cat("5. Testing download functionality...\n")
  download_test <- test_hls_pipeline()
  if (download_test) {
    cat("   ✓ Download pipeline working\n")
    checks_passed <- checks_passed + 1
  } else {
    cat("   ❌ Download test failed\n")
  }
  
  # Check 6: Time range validation
  cat("6. Validating time range...\n")
  if (config$start_year >= 2013 && config$end_year <= year(Sys.Date())) {
    cat("   ✓ Time range valid (", config$start_year, "-", config$end_year, ")\n")
    checks_passed <- checks_passed + 1
  } else {
    cat("   ❌ Invalid time range\n")
  }
  
  # Summary
  cat("\nPRE-FLIGHT SUMMARY: ", checks_passed, "/", total_checks, " checks passed\n")
  
  if (checks_passed == total_checks) {
    cat("🎉 ALL CHECKS PASSED - Ready for data acquisition!\n\n")
    return(TRUE)
  } else {
    cat("❌ CHECKS FAILED - Please resolve issues before proceeding\n\n")
    return(FALSE)
  }
}

######################
# Main Execution Function
######################

execute_midwest_data_pull <- function(config = DATA_PULL_CONFIG, 
                                     run_preflight = TRUE,
                                     resume_from_status = TRUE) {
  
  cat("=== NIDIS MIDWEST DEWS DATA PULL EXECUTION ===\n")
  cat("Execution started at:", as.character(Sys.time()), "\n\n")
  
  # Run pre-flight checks
  if (run_preflight) {
    if (!run_preflight_checks(config)) {
      stop("Pre-flight checks failed. Aborting execution.")
    }
  }
  
  # Initialize or load status
  status <- initialize_execution_status(config)
  display_status(status)
  
  # Determine years to process
  all_years <- config$start_year:config$end_year
  
  if (resume_from_status && length(status$years_completed) > 0) {
    remaining_years <- all_years[!all_years %in% as.numeric(status$years_completed)]
    cat("Resuming execution. Remaining years:", paste(remaining_years, collapse = ", "), "\n\n")
  } else {
    remaining_years <- all_years
    cat("Starting fresh execution for years:", paste(remaining_years, collapse = ", "), "\n\n")
  }
  
  if (length(remaining_years) == 0) {
    cat("✅ All years already completed!\n")
    return(status)
  }
  
  status$status <- "running"
  save_execution_status(status)
  
  # Process each year
  for (year in remaining_years) {
    
    cat("=== PROCESSING YEAR", year, "===\n")
    status$current_year <- year
    status$status <- paste("processing_year", year)
    save_execution_status(status)
    
    # Run year-specific acquisition
    year_result <- try({
      acquire_midwest_pilot_data(
        start_year = year,
        end_year = year,
        cloud_cover_max = config$cloud_cover_max
      )
    }, silent = FALSE)
    
    if (!inherits(year_result, "try-error")) {
      # Year completed successfully
      status$years_completed <- c(status$years_completed, as.character(year))
      status$total_scenes_found <- status$total_scenes_found + year_result$total_scenes_found
      status$total_scenes_downloaded <- status$total_scenes_downloaded + year_result$total_scenes_downloaded
      status$total_ndvi_processed <- status$total_ndvi_processed + year_result$total_ndvi_processed
      
      # Estimate data volume (rough)
      year_gb <- (year_result$total_scenes_downloaded * 2 * 15 + year_result$total_ndvi_processed * 15) / 1024
      status$total_data_gb <- status$total_data_gb + year_gb
      
      cat("✅ Year", year, "completed successfully\n")
      cat("   Scenes downloaded:", year_result$total_scenes_downloaded, "\n")
      cat("   NDVI processed:", year_result$total_ndvi_processed, "\n\n")
      
    } else {
      # Year failed
      status$years_failed <- c(status$years_failed, as.character(year))
      cat("❌ Year", year, "failed with error:\n")
      print(year_result)
      cat("\n")
    }
    
    status$current_year <- NULL
    save_execution_status(status)
    display_status(status)
  }
  
  # Final status
  if (length(status$years_failed) == 0) {
    status$status <- "completed"
    cat("🎉 EXECUTION COMPLETED SUCCESSFULLY!\n")
  } else {
    status$status <- "completed_with_errors"
    cat("⚠ EXECUTION COMPLETED WITH ERRORS\n")
    cat("Failed years:", paste(status$years_failed, collapse = ", "), "\n")
  }
  
  status$end_time <- Sys.time()
  execution_time <- difftime(status$end_time, status$start_time, units = "hours")
  cat("Total execution time:", round(as.numeric(execution_time), 2), "hours\n")
  
  save_execution_status(status)
  display_status(status)
  
  return(status)
}

######################
# Utility Functions
######################

# Quick status check
check_execution_status <- function() {
  status_file <- file.path(hls_paths$logs, "execution_status.json")
  if (file.exists(status_file)) {
    status <- jsonlite::fromJSON(status_file)
    display_status(status)
    return(status)
  } else {
    cat("No execution status found. Run execute_midwest_data_pull() to start.\n")
    return(NULL)
  }
}

# Resume failed execution
resume_execution <- function() {
  cat("Resuming from last saved status...\n")
  execute_midwest_data_pull(resume_from_status = TRUE, run_preflight = FALSE)
}

# Reset execution (start fresh)
reset_execution <- function() {
  status_file <- file.path(hls_paths$logs, "execution_status.json")
  if (file.exists(status_file)) {
    backup_file <- paste0(status_file, ".backup_", format(Sys.time(), "%Y%m%d_%H%M%S"))
    file.copy(status_file, backup_file)
    file.remove(status_file)
    cat("Previous execution status backed up to:", backup_file, "\n")
  }
  cat("Execution reset. Run execute_midwest_data_pull() to start fresh.\n")
}

######################
# Instructions
######################

cat("=== HLS DATA PULL EXECUTION CONTROLLER LOADED ===\n")
cat("Master orchestration script for NIDIS Midwest DEWS data acquisition\n")
cat("Domain: Midwest agricultural drought region\n")
cat("Storage:", DATA_PULL_CONFIG$storage_path, "\n")
cat("Time range:", DATA_PULL_CONFIG$start_year, "-", DATA_PULL_CONFIG$end_year, "\n\n")

cat("EXECUTION WORKFLOW:\n")
cat("1. run_preflight_checks() - Verify system readiness\n")
cat("2. execute_midwest_data_pull() - Start full data acquisition\n")
cat("3. check_execution_status() - Monitor progress\n")
cat("4. resume_execution() - Resume after interruption\n")
cat("5. reset_execution() - Start fresh (clears status)\n\n")

cat("QUICK START:\n")
cat("execute_midwest_data_pull()  # Run everything with checks\n\n")

cat("Estimated completion time: 8-12 hours for full 2020-2024 range\n")
cat("Estimated data volume: ~130 GB for 5-year period\n")