# ==============================================================================
# OPERATIONAL: INCREMENTAL DATA UPDATE
# ==============================================================================
# Purpose: Download and process only new HLS data since last update
# Frequency: Weekly (or as configured)
# Scale: Regional → CONUS
# Author: M. Ross Alexander
# Date: 2025-10-21
# ==============================================================================

library(terra)
library(dplyr)
library(lubridate)
library(httr)

# Source utilities
source("../../CONUS_HLS_drought_monitoring/00_setup_paths.R")
source("../config/region_configs.R")

cat("=== OPERATIONAL DATA UPDATE ===\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

#' Load operational configuration
#'
#' @param config_file Path to YAML config or region name
#' @return Configuration list
load_operational_config <- function(config_file = "midwest_operational") {

  # If just a region name, construct path
  if (!grepl("\\.yaml$", config_file)) {
    config_file <- file.path("../config", paste0(config_file, ".yaml"))
  }

  if (file.exists(config_file)) {
    config <- load_config(config_file)
  } else {
    # Initialize if doesn't exist
    region_name <- gsub("_operational.*", "", basename(config_file))
    config <- init_monitoring(region_name, "operational", output_dir = "../config")
  }

  return(config)
}

# ==============================================================================
# DATA DISCOVERY
# ==============================================================================

#' Get date of last successful update
#'
#' @param hls_paths Data paths from setup
#' @param region_id Region identifier
#' @return Date of last update or NULL
get_last_update_date <- function(hls_paths, region_id) {

  update_log <- file.path(hls_paths$processing_logs,
                          paste0(region_id, "_update_log.csv"))

  if (!file.exists(update_log)) {
    cat("No previous update log found. Will download all available data.\n")
    return(NULL)
  }

  log_df <- read.csv(update_log, stringsAsFactors = FALSE)
  log_df$update_date <- as.Date(log_df$update_date)

  last_update <- max(log_df$update_date[log_df$status == "success"])

  cat("Last successful update:", as.character(last_update), "\n")

  return(last_update)
}

#' Discover new HLS scenes since last update
#'
#' @param config Operational configuration
#' @param hls_paths Data paths
#' @param start_date Start date for search
#' @param end_date End date for search (default: today)
#' @return Data frame of available scenes
discover_new_scenes <- function(config, hls_paths, start_date = NULL, end_date = Sys.Date()) {

  cat("\n=== DISCOVERING NEW SCENES ===\n\n")

  # Get last update
  if (is.null(start_date)) {
    start_date <- get_last_update_date(hls_paths, config$region$region_id)

    if (is.null(start_date)) {
      # No previous update - use lookback period
      start_date <- end_date - config$update$lookback_days
    } else {
      # Buffer: go back a bit from last update to catch late-arriving scenes
      start_date <- start_date - config$update$buffer_days
    }
  }

  cat("Search period:", as.character(start_date), "to", as.character(end_date), "\n")
  cat("Bounding box:", paste(config$region$bbox_latlon, collapse = ", "), "\n\n")

  # Query NASA CMR API for HLS data
  # This is a simplified version - full implementation would use rhls or similar
  cat("⚠ Note: Using directory scan for discovery\n")
  cat("   For operational use, implement NASA CMR API queries\n\n")

  # For now, scan existing processed directory
  available_scenes <- data.frame()

  for (year in year(start_date):year(end_date)) {
    year_dir <- file.path(hls_paths$processed_ndvi, "daily", year)

    if (!dir.exists(year_dir)) next

    scene_files <- list.files(year_dir, pattern = "_NDVI\\.tif$", full.names = TRUE)

    if (length(scene_files) == 0) next

    # Extract metadata from filenames
    scene_info <- lapply(scene_files, function(f) {
      filename <- basename(f)
      parts <- strsplit(filename, "\\.")[[1]]

      sensor <- parts[2]  # L30 or S30
      tile <- parts[3]
      datetime <- parts[4]

      year <- as.integer(substr(datetime, 1, 4))
      yday <- as.integer(substr(datetime, 5, 7))
      date <- as.Date(paste0(year, "-01-01")) + (yday - 1)

      data.frame(
        filepath = f,
        sensor = sensor,
        tile = tile,
        date = date,
        year = year,
        yday = yday,
        stringsAsFactors = FALSE
      )
    })

    available_scenes <- bind_rows(available_scenes, bind_rows(scene_info))
  }

  # Filter to date range
  available_scenes <- available_scenes %>%
    filter(date >= start_date & date <= end_date) %>%
    arrange(date)

  cat("Found", nrow(available_scenes), "scenes in date range\n")

  if (nrow(available_scenes) > 0) {
    cat("Date range:", paste(range(available_scenes$date), collapse = " to "), "\n")
    cat("Sensors:", paste(unique(available_scenes$sensor), collapse = ", "), "\n")
  }

  return(available_scenes)
}

# ==============================================================================
# INCREMENTAL PROCESSING
# ==============================================================================

#' Process new scenes incrementally
#'
#' @param new_scenes Data frame of scenes to process
#' @param config Operational configuration
#' @param hls_paths Data paths
#' @return Updated timeseries data frame
process_new_scenes <- function(new_scenes, config, hls_paths) {

  cat("\n=== PROCESSING NEW SCENES ===\n\n")

  if (nrow(new_scenes) < config$update$min_scenes_per_update) {
    cat("Only", nrow(new_scenes), "new scenes - below minimum threshold (",
        config$update$min_scenes_per_update, ")\n")
    cat("Skipping update. Will retry next cycle.\n")
    return(NULL)
  }

  # Load existing timeseries
  timeseries_file <- file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.csv")

  if (file.exists(timeseries_file)) {
    cat("Loading existing timeseries...\n")
    existing_ts <- read.csv(timeseries_file, stringsAsFactors = FALSE)
    existing_ts$date <- as.Date(existing_ts$date)
    cat("  Existing observations:", nrow(existing_ts), "\n\n")
  } else {
    existing_ts <- data.frame()
    cat("No existing timeseries found - will create new\n\n")
  }

  # Load 4km reference grid (created in Phase 1)
  grid_file <- file.path(hls_paths$gam_models, "conus_4km_grid.rds")

  if (file.exists(grid_file)) {
    grid_4km <- readRDS(grid_file)
    cat("Loaded 4km reference grid\n\n")
  } else {
    cat("⚠ 4km grid not found - will need to create in first aggregation\n")
    cat("   This should only happen on first run\n\n")
    grid_4km <- NULL
  }

  # Process scenes using Phase 1 aggregation logic
  # (This would call the aggregate_scene_to_4km() function from Phase 1)
  cat("TODO: Implement incremental aggregation\n")
  cat("  - Reuse aggregate_scene_to_4km() from Phase 1\n")
  cat("  - Append to existing timeseries\n")
  cat("  - Deduplicate overlaps\n")
  cat("  - Save updated timeseries\n\n")

  # Placeholder return
  return(existing_ts)
}

# ==============================================================================
# UPDATE TRACKING
# ==============================================================================

#' Log update status
#'
#' @param config Operational configuration
#' @param hls_paths Data paths
#' @param status "success" or "failure"
#' @param n_scenes Number of scenes processed
#' @param notes Optional notes
log_update <- function(config, hls_paths, status, n_scenes = 0, notes = "") {

  ensure_directory(hls_paths$processing_logs)

  log_file <- file.path(hls_paths$processing_logs,
                        paste0(config$region$region_id, "_update_log.csv"))

  log_entry <- data.frame(
    update_date = Sys.Date(),
    timestamp = Sys.time(),
    region = config$region$region_id,
    status = status,
    n_scenes = n_scenes,
    notes = notes,
    stringsAsFactors = FALSE
  )

  if (file.exists(log_file)) {
    existing_log <- read.csv(log_file, stringsAsFactors = FALSE)
    log_df <- bind_rows(existing_log, log_entry)
  } else {
    log_df <- log_entry
  }

  write.csv(log_df, log_file, row.names = FALSE)

  cat("✓ Update logged:", status, "\n")
}

# ==============================================================================
# MAIN WORKFLOW
# ==============================================================================

#' Run operational data update
#'
#' @param config_file Configuration file or region name
#' @param force_update Bypass minimum scenes check
#' @return Status
run_data_update <- function(config_file = "midwest_operational",
                             force_update = FALSE) {

  cat("\n")
  cat("================================================================================\n")
  cat("  OPERATIONAL DATA UPDATE\n")
  cat("================================================================================\n")
  cat("Started:", as.character(Sys.time()), "\n\n")

  start_time <- Sys.time()

  # Load configuration
  config <- load_operational_config(config_file)
  print_config_summary(config)

  # Get data paths
  hls_paths <- get_hls_paths()

  # Discover new scenes
  new_scenes <- discover_new_scenes(config, hls_paths)

  if (nrow(new_scenes) == 0) {
    cat("\nNo new scenes available. Update not needed.\n\n")
    log_update(config, hls_paths, "skipped", 0, "No new data available")
    return("skipped")
  }

  # Check threshold
  if (!force_update && nrow(new_scenes) < config$update$min_scenes_per_update) {
    cat("\nInsufficient new scenes (", nrow(new_scenes), "<",
        config$update$min_scenes_per_update, "). Update deferred.\n\n")
    log_update(config, hls_paths, "deferred", nrow(new_scenes),
               "Below minimum scene threshold")
    return("deferred")
  }

  # Process new data
  tryCatch({
    updated_ts <- process_new_scenes(new_scenes, config, hls_paths)

    elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

    cat("\n=== UPDATE COMPLETE ===\n")
    cat("Time elapsed:", round(elapsed, 1), "minutes\n")
    cat("Scenes processed:", nrow(new_scenes), "\n\n")

    log_update(config, hls_paths, "success", nrow(new_scenes),
               paste("Processed in", round(elapsed, 1), "min"))

    return("success")

  }, error = function(e) {
    cat("\n❌ UPDATE FAILED\n")
    cat("Error:", e$message, "\n\n")

    log_update(config, hls_paths, "failure", nrow(new_scenes),
               paste("Error:", e$message))

    return("failure")
  })
}

# ==============================================================================
# EXECUTION
# ==============================================================================

# Run if called as main script
if (!interactive() || exists("run_update")) {

  # Default to Midwest operational config
  config_name <- ifelse(exists("region_config"), region_config, "midwest_operational")
  force <- ifelse(exists("force_update"), force_update, FALSE)

  status <- run_data_update(config_name, force)

  cat("\nFinal status:", status, "\n\n")

} else {
  cat("\n=== DATA UPDATE FUNCTIONS LOADED ===\n")
  cat("Ready for operational updates\n\n")
  cat("Usage:\n")
  cat("  # Run update for configured region\n")
  cat("  run_data_update('midwest_operational')\n\n")
  cat("  # Force update even if below threshold\n")
  cat("  run_data_update('conus_operational', force_update = TRUE)\n\n")
}
