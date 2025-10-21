# ==============================================================================
# OPERATIONAL: ROLLING BASELINE UPDATE
# ==============================================================================
# Purpose: Maintain and update climatological baseline as new years complete
# Frequency: Annual (typically January) or as configured
# Strategy: Fixed period (2013-2024) vs Rolling N-year window
# Author: M. Ross Alexander
# Date: 2025-10-21
# ==============================================================================

library(dplyr)

# Source utilities
source("../../CONUS_HLS_drought_monitoring/00_setup_paths.R")
source("../../CONUS_HLS_drought_monitoring/00_gam_utility_functions.R")
source("../config/region_configs.R")

cat("=== OPERATIONAL BASELINE UPDATE ===\n\n")

# ==============================================================================
# BASELINE MANAGEMENT LOGIC
# ==============================================================================

#' Determine if baseline should be recalculated
#'
#' @param config Operational configuration
#' @param hls_paths Data paths
#' @param current_date Current date (default: today)
#' @return List with should_update (logical) and reason (character)
check_baseline_update_needed <- function(config, hls_paths, current_date = Sys.Date()) {

  baseline_file <- file.path(hls_paths$gam_models, "conus_4km_baseline.csv")
  baseline_meta <- file.path(hls_paths$gam_models, "baseline_metadata.rds")

  # Check if baseline exists
  if (!file.exists(baseline_file)) {
    return(list(should_update = TRUE, reason = "No baseline exists"))
  }

  # Load metadata
  if (file.exists(baseline_meta)) {
    meta <- readRDS(baseline_meta)
  } else {
    # No metadata - assume old baseline
    return(list(should_update = TRUE, reason = "No metadata - baseline outdated"))
  }

  # Check recalculation frequency
  freq <- config$baseline$recalculation_frequency

  if (freq == "never") {
    return(list(should_update = FALSE, reason = "Recalculation disabled"))
  }

  last_calc <- as.Date(meta$calculation_date)
  days_since <- as.numeric(current_date - last_calc)

  # Annual update logic
  if (freq == "annual") {
    trigger_month <- match(tolower(config$baseline$update_trigger),
                          c("january", "february", "march", "april", "may", "june",
                            "july", "august", "september", "october", "november", "december"))

    current_month <- month(current_date)
    last_calc_year <- year(last_calc)
    current_year <- year(current_date)

    # Update if we're in trigger month and haven't updated this year
    if (current_month == trigger_month && current_year > last_calc_year) {
      return(list(should_update = TRUE,
                 reason = paste("Annual update in", config$baseline$update_trigger)))
    }
  }

  # Seasonal update logic
  if (freq == "seasonal") {
    if (days_since >= 90) {  # Roughly quarterly
      return(list(should_update = TRUE, reason = "Seasonal update due"))
    }
  }

  # Monthly update logic
  if (freq == "monthly") {
    if (days_since >= 30) {
      return(list(should_update = TRUE, reason = "Monthly update due"))
    }
  }

  # Continuous (always update if new complete year)
  if (freq == "continuous") {
    latest_complete_year <- year(current_date) - 1  # Previous year
    if (latest_complete_year > max(meta$baseline_years)) {
      return(list(should_update = TRUE, reason = "New complete year available"))
    }
  }

  return(list(should_update = FALSE,
             reason = paste("Next update:", last_calc + 365)))
}

#' Calculate baseline years based on strategy
#'
#' @param config Operational configuration
#' @param current_date Current date
#' @return Vector of years to include in baseline
calculate_baseline_years <- function(config, current_date = Sys.Date()) {

  latest_complete_year <- year(current_date) - 1

  if (config$baseline$rolling_window) {
    # Rolling N-year window
    n_years <- config$baseline$rolling_window_years
    baseline_years <- (latest_complete_year - n_years + 1):latest_complete_year

    cat("Using rolling", n_years, "year window\n")
    cat("Baseline years:", paste(range(baseline_years), collapse = "-"), "\n\n")

  } else {
    # Fixed period (default: 2013-present)
    start_year <- min(config$region$baseline_years)
    baseline_years <- start_year:latest_complete_year

    cat("Using fixed baseline period\n")
    cat("Baseline years:", paste(range(baseline_years), collapse = "-"), "\n\n")
  }

  if (length(baseline_years) < config$baseline$min_baseline_years) {
    warning("Baseline period shorter than minimum recommended: ",
            length(baseline_years), " < ", config$baseline$min_baseline_years)
  }

  return(baseline_years)
}

# ==============================================================================
# BASELINE CALCULATION
# ==============================================================================

#' Recalculate baseline using updated year range
#'
#' @param config Operational configuration
#' @param hls_paths Data paths
#' @param baseline_years Years to include
#' @return Baseline dataframe
recalculate_baseline <- function(config, hls_paths, baseline_years) {

  cat("\n=== RECALCULATING BASELINE ===\n\n")
  cat("Using years:", paste(range(baseline_years), collapse = "-"), "\n")
  cat("Total years:", length(baseline_years), "\n\n")

  # Archive old baseline if requested
  if (config$products$archive_baseline) {
    old_baseline <- file.path(hls_paths$gam_models, "conus_4km_baseline.csv")
    if (file.exists(old_baseline)) {
      archive_name <- file.path(hls_paths$gam_models, "baseline_archive",
                               paste0("baseline_", Sys.Date(), ".csv"))
      ensure_directory(dirname(archive_name))
      file.copy(old_baseline, archive_name)
      cat("✓ Archived old baseline to:", archive_name, "\n\n")
    }
  }

  # Load timeseries
  timeseries_file <- file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.csv")
  cat("Loading timeseries...\n")
  timeseries_df <- read.csv(timeseries_file, stringsAsFactors = FALSE)
  timeseries_df$date <- as.Date(timeseries_df$date)
  cat("  Total observations:", nrow(timeseries_df), "\n\n")

  # Source Phase 2 baseline fitting functions
  cat("Sourcing baseline fitting functions from Phase 2...\n")
  source("../../CONUS_HLS_drought_monitoring/02_fit_longterm_baseline.R",
         local = TRUE)

  # Update config for Phase 2
  phase2_config <- config
  phase2_config$baseline_years <- baseline_years
  phase2_config$n_cores <- config$processing$parallel_cores
  phase2_config$min_observations <- config$qc$min_observations_baseline

  # Run baseline calculation
  baseline_df <- fit_all_baselines(timeseries_df, phase2_config)

  # Save metadata
  metadata <- list(
    calculation_date = Sys.time(),
    baseline_years = baseline_years,
    n_years = length(baseline_years),
    n_pixels = length(unique(baseline_df$pixel_id)),
    n_observations = nrow(timeseries_df %>% filter(year %in% baseline_years)),
    config_snapshot = config
  )

  saveRDS(metadata, file.path(hls_paths$gam_models, "baseline_metadata.rds"))
  cat("✓ Baseline metadata saved\n\n")

  return(baseline_df)
}

# ==============================================================================
# DERIVATIVE UPDATE
# ==============================================================================

#' Recalculate baseline derivatives
#'
#' @param config Operational configuration
#' @param hls_paths Data paths
#' @param baseline_years Years to use
#' @return Derivatives dataframe
recalculate_baseline_derivatives <- function(config, hls_paths, baseline_years) {

  cat("\n=== RECALCULATING BASELINE DERIVATIVES ===\n\n")

  # Archive old derivatives if they exist
  if (config$products$archive_baseline) {
    old_derivs <- file.path(hls_paths$gam_models, "conus_4km_baseline_derivatives.csv")
    if (file.exists(old_derivs)) {
      archive_name <- file.path(hls_paths$gam_models, "baseline_archive",
                               paste0("baseline_derivatives_", Sys.Date(), ".csv"))
      ensure_directory(dirname(archive_name))
      file.copy(old_derivs, archive_name)
      cat("✓ Archived old derivatives\n\n")
    }
  }

  # Load timeseries
  timeseries_file <- file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.csv")
  timeseries_df <- read.csv(timeseries_file, stringsAsFactors = FALSE)
  timeseries_df$date <- as.Date(timeseries_df$date)

  # Source Phase 3 derivative functions
  cat("Sourcing derivative functions from Phase 3...\n")
  source("../../CONUS_HLS_drought_monitoring/03_derivatives_baseline.R",
         local = TRUE)

  # Update config
  phase3_config <- config
  phase3_config$baseline_years <- baseline_years
  phase3_config$n_cores <- config$processing$parallel_cores

  # Calculate derivatives
  derivs_df <- calculate_baseline_derivatives(timeseries_df, phase3_config)

  return(derivs_df)
}

# ==============================================================================
# MAIN WORKFLOW
# ==============================================================================

#' Run baseline update check and recalculation if needed
#'
#' @param config_file Configuration file or region name
#' @param force_update Force recalculation regardless of schedule
#' @return Status
run_baseline_update <- function(config_file = "midwest_operational",
                                force_update = FALSE) {

  cat("\n")
  cat("================================================================================\n")
  cat("  OPERATIONAL BASELINE UPDATE\n")
  cat("================================================================================\n")
  cat("Started:", as.character(Sys.time()), "\n\n")

  start_time <- Sys.time()

  # Load configuration
  if (!grepl("\\.yaml$", config_file)) {
    config_file <- file.path("../config", paste0(config_file, ".yaml"))
  }
  config <- load_config(config_file)

  # Get paths
  hls_paths <- get_hls_paths()

  # Check if update needed
  check <- check_baseline_update_needed(config, hls_paths)

  cat("Update check:\n")
  cat("  Should update:", check$should_update, "\n")
  cat("  Reason:", check$reason, "\n\n")

  if (!check$should_update && !force_update) {
    cat("Baseline update not needed at this time.\n\n")
    return("skipped")
  }

  if (force_update) {
    cat("⚠ Force update requested - proceeding\n\n")
  }

  # Calculate baseline years
  baseline_years <- calculate_baseline_years(config)

  # Recalculate baseline
  cat("Starting baseline recalculation...\n")
  baseline_df <- recalculate_baseline(config, hls_paths, baseline_years)

  # Recalculate derivatives
  cat("\nStarting derivative recalculation...\n")
  derivs_df <- recalculate_baseline_derivatives(config, hls_paths, baseline_years)

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "hours"))

  cat("\n=== BASELINE UPDATE COMPLETE ===\n")
  cat("Total time:", round(elapsed, 2), "hours\n")
  cat("Baseline years:", paste(range(baseline_years), collapse = "-"), "\n")
  cat("Pixels:", length(unique(baseline_df$pixel_id)), "\n\n")

  return("success")
}

# ==============================================================================
# EXECUTION
# ==============================================================================

if (!interactive() || exists("run_baseline_update_script")) {

  config_name <- ifelse(exists("region_config"), region_config, "midwest_operational")
  force <- ifelse(exists("force_baseline_update"), force_baseline_update, FALSE)

  status <- run_baseline_update(config_name, force)

  cat("\nBaseline update status:", status, "\n\n")

} else {
  cat("\n=== BASELINE UPDATE FUNCTIONS LOADED ===\n")
  cat("Ready for operational baseline management\n\n")
  cat("Usage:\n")
  cat("  # Check and update if needed\n")
  cat("  run_baseline_update('midwest_operational')\n\n")
  cat("  # Force immediate update\n")
  cat("  run_baseline_update('midwest_operational', force_update = TRUE)\n\n")
}
