# ==============================================================================
# OPERATIONAL: CURRENT CONDITIONS MONITOR
# ==============================================================================
# Purpose: Calculate current drought conditions using latest available data
# Frequency: Weekly or as data updates
# Output: Current anomalies, derivatives, and summary products
# Author: M. Ross Alexander
# Date: 2025-10-21
# ==============================================================================

library(dplyr)
library(lubridate)
library(ggplot2)
library(terra)

# Source utilities
source("../../CONUS_HLS_drought_monitoring/00_setup_paths.R")
source("../../CONUS_HLS_drought_monitoring/00_gam_utility_functions.R")
source("../config/region_configs.R")

cat("=== CURRENT CONDITIONS MONITOR ===\n\n")

# ==============================================================================
# CURRENT YEAR GAM FITTING
# ==============================================================================

#' Fit GAM for current (incomplete) year
#'
#' @param timeseries_df Full timeseries
#' @param current_year Year to fit (default: current year)
#' @param config Operational configuration
#' @return Year-specific GAM predictions
fit_current_year_gam <- function(timeseries_df, current_year = year(Sys.Date()),
                                 config) {

  cat("\n=== FITTING CURRENT YEAR GAM ===\n\n")
  cat("Year:", current_year, "\n")

  # Filter to current year (incomplete)
  year_data <- timeseries_df %>%
    filter(year == current_year)

  cat("Observations available:", nrow(year_data), "\n")
  cat("Date range:", paste(range(year_data$date), collapse = " to "), "\n")
  cat("Latest data:", as.character(max(year_data$date)), "\n\n")

  if (nrow(year_data) < config$qc$min_observations_year) {
    warning("Insufficient data for current year (", nrow(year_data),
            " < ", config$qc$min_observations_year, ")")
    return(NULL)
  }

  # Source Phase 4 year-specific GAM fitting
  cat("Sourcing year-specific GAM functions...\n")
  source("../../CONUS_HLS_drought_monitoring/04_fit_year_gams.R",
         local = TRUE)

  # Configure for current year only
  phase4_config <- config
  phase4_config$target_years <- current_year
  phase4_config$n_cores <- config$processing$parallel_cores

  # Fit year GAMs
  year_splines <- fit_all_year_gams(timeseries_df, phase4_config)

  return(year_splines)
}

# ==============================================================================
# CURRENT ANOMALY CALCULATION
# ==============================================================================

#' Calculate anomalies for current year
#'
#' @param year_splines Current year GAM predictions
#' @param baseline_df Baseline climatology
#' @return Anomaly dataframe
calculate_current_anomalies <- function(year_splines, baseline_df) {

  cat("\n=== CALCULATING CURRENT ANOMALIES ===\n\n")

  # Join with baseline
  anomaly_df <- year_splines %>%
    left_join(baseline_df, by = c("pixel_id", "yday"), suffix = c("_year", "_norm"))

  # Calculate anomalies
  anomaly_df <- anomaly_df %>%
    mutate(
      anomaly = year_mean - norm_mean,
      anomaly_se = sqrt(year_se^2 + norm_se^2),
      z_score = anomaly / anomaly_se,
      p_value = 2 * pnorm(-abs(z_score)),
      is_significant = p_value < 0.05
    )

  cat("Total pixel-day combinations:", nrow(anomaly_df), "\n")
  cat("Significant anomalies:", sum(anomaly_df$is_significant), "\n")
  cat("  Negative (below normal):", sum(anomaly_df$anomaly < 0 & anomaly_df$is_significant), "\n")
  cat("  Positive (above normal):", sum(anomaly_df$anomaly > 0 & anomaly_df$is_significant), "\n\n")

  return(anomaly_df)
}

# ==============================================================================
# CURRENT DERIVATIVES
# ==============================================================================

#' Calculate derivatives for current year
#'
#' @param timeseries_df Full timeseries
#' @param current_year Year to analyze
#' @param config Operational configuration
#' @return Derivatives dataframe
calculate_current_derivatives <- function(timeseries_df, current_year = year(Sys.Date()),
                                         config) {

  cat("\n=== CALCULATING CURRENT YEAR DERIVATIVES ===\n\n")

  # Source Phase 5 derivatives
  source("../../CONUS_HLS_drought_monitoring/05_derivatives_individual_years.R",
         local = TRUE)

  # Configure
  phase5_config <- config
  phase5_config$target_years <- current_year
  phase5_config$n_cores <- config$processing$parallel_cores

  # Calculate derivatives
  year_derivs <- calculate_year_derivatives(timeseries_df, phase5_config)

  return(year_derivs)
}

# ==============================================================================
# SUMMARY PRODUCTS
# ==============================================================================

#' Generate current conditions summary
#'
#' @param anomaly_df Current anomalies
#' @param year_derivs Current year derivatives (optional)
#' @param baseline_derivs Baseline derivatives (optional)
#' @param config Operational configuration
#' @return Summary dataframe
generate_conditions_summary <- function(anomaly_df, year_derivs = NULL,
                                       baseline_derivs = NULL, config) {

  cat("\n=== GENERATING CONDITIONS SUMMARY ===\n\n")

  current_year <- unique(anomaly_df$year)
  current_date <- Sys.Date()
  current_yday <- yday(current_date)

  # Most recent conditions (last 7 days)
  recent_anomalies <- anomaly_df %>%
    filter(yday >= (current_yday - 7) & yday <= current_yday) %>%
    group_by(pixel_id) %>%
    summarise(
      recent_anomaly = mean(anomaly),
      recent_z = mean(z_score),
      pct_sig = mean(is_significant),
      .groups = "drop"
    )

  # Overall summary statistics
  summary_stats <- list(
    date = current_date,
    year = current_year,
    yday = current_yday,

    # Magnitude anomalies
    n_pixels_total = length(unique(anomaly_df$pixel_id)),
    mean_anomaly = mean(anomaly_df$anomaly),
    median_anomaly = median(anomaly_df$anomaly),
    pct_below_normal = 100 * mean(anomaly_df$anomaly < 0),
    pct_sig_below = 100 * mean(anomaly_df$anomaly < 0 & anomaly_df$is_significant),
    pct_sig_above = 100 * mean(anomaly_df$anomaly > 0 & anomaly_df$is_significant),

    # Severity categories (simple percentile-based)
    pct_extreme_low = 100 * mean(anomaly_df$z_score < -2),
    pct_moderate_low = 100 * mean(anomaly_df$z_score < -1 & anomaly_df$z_score >= -2),
    pct_normal = 100 * mean(abs(anomaly_df$z_score) < 1),
    pct_moderate_high = 100 * mean(anomaly_df$z_score > 1 & anomaly_df$z_score <= 2),
    pct_extreme_high = 100 * mean(anomaly_df$z_score > 2)
  )

  # Add timing information if derivatives available
  if (!is.null(year_derivs) && !is.null(baseline_derivs)) {
    cat("Analyzing phenological timing...\n")

    # Find peak green-up day (max positive derivative)
    baseline_greenup <- baseline_derivs %>%
      filter(yday <= 180) %>%  # Spring only
      group_by(pixel_id) %>%
      filter(deriv_mean == max(deriv_mean)) %>%
      select(pixel_id, baseline_greenup_day = yday)

    year_greenup <- year_derivs %>%
      filter(yday <= 180) %>%
      group_by(pixel_id) %>%
      filter(deriv_mean == max(deriv_mean)) %>%
      select(pixel_id, year_greenup_day = yday)

    greenup_comparison <- baseline_greenup %>%
      left_join(year_greenup, by = "pixel_id") %>%
      mutate(greenup_shift = year_greenup_day - baseline_greenup_day)

    summary_stats$mean_greenup_shift <- mean(greenup_comparison$greenup_shift, na.rm = TRUE)
    summary_stats$pct_delayed_greenup <- 100 * mean(greenup_comparison$greenup_shift > 7, na.rm = TRUE)

    cat("  Mean green-up shift:", round(summary_stats$mean_greenup_shift, 1), "days\n")
  }

  cat("\n=== CURRENT CONDITIONS ===\n")
  cat("Date:", as.character(summary_stats$date), "(day", summary_stats$yday, ")\n")
  cat("Region:", config$region$name, "\n\n")
  cat("Magnitude Anomalies:\n")
  cat("  Mean anomaly:", round(summary_stats$mean_anomaly, 3), "\n")
  cat("  Below normal:", round(summary_stats$pct_below_normal, 1), "%\n")
  cat("  Significantly below:", round(summary_stats$pct_sig_below, 1), "%\n")
  cat("  Significantly above:", round(summary_stats$pct_sig_above, 1), "%\n\n")

  cat("Severity Distribution:\n")
  cat("  Extreme low (z < -2):", round(summary_stats$pct_extreme_low, 1), "%\n")
  cat("  Moderate low (-2 < z < -1):", round(summary_stats$pct_moderate_low, 1), "%\n")
  cat("  Normal (|z| < 1):", round(summary_stats$pct_normal, 1), "%\n")
  cat("  Moderate high (1 < z < 2):", round(summary_stats$pct_moderate_high, 1), "%\n")
  cat("  Extreme high (z > 2):", round(summary_stats$pct_extreme_high, 1), "%\n\n")

  return(summary_stats)
}

#' Export current conditions products
#'
#' @param anomaly_df Current anomalies
#' @param summary_stats Summary statistics
#' @param config Operational configuration
#' @param hls_paths Data paths
export_conditions_products <- function(anomaly_df, summary_stats, config, hls_paths) {

  cat("\n=== EXPORTING PRODUCTS ===\n\n")

  output_dir <- file.path(hls_paths$web_products, "current_conditions")
  ensure_directory(output_dir)

  current_date <- summary_stats$date

  # 1. Current anomalies CSV
  anomaly_file <- file.path(output_dir,
                            paste0("current_anomalies_", current_date, ".csv"))
  write.csv(anomaly_df, anomaly_file, row.names = FALSE)
  cat("✓ Anomalies:", anomaly_file, "\n")

  # 2. Summary statistics JSON
  summary_file <- file.path(output_dir,
                           paste0("current_summary_", current_date, ".json"))
  jsonlite::write_json(summary_stats, summary_file, auto_unbox = TRUE, pretty = TRUE)
  cat("✓ Summary:", summary_file, "\n")

  # 3. Latest symlink (for web access)
  if (config$products$generate_maps && Sys.info()["sysname"] != "Windows") {
    latest_anomaly <- file.path(output_dir, "latest_anomalies.csv")
    latest_summary <- file.path(output_dir, "latest_summary.json")

    if (file.exists(latest_anomaly)) file.remove(latest_anomaly)
    if (file.exists(latest_summary)) file.remove(latest_summary)

    file.symlink(anomaly_file, latest_anomaly)
    file.symlink(summary_file, latest_summary)

    cat("✓ Latest symlinks created\n")
  }

  cat("\n")
}

# ==============================================================================
# MAIN WORKFLOW
# ==============================================================================

#' Run current conditions assessment
#'
#' @param config_file Configuration file or region name
#' @param include_derivatives Include derivative analysis (slower)
#' @return Conditions summary
run_current_conditions <- function(config_file = "midwest_operational",
                                  include_derivatives = TRUE) {

  cat("\n")
  cat("================================================================================\n")
  cat("  CURRENT CONDITIONS MONITOR\n")
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

  # Load baseline
  cat("Loading baseline...\n")
  baseline_file <- file.path(hls_paths$gam_models, "conus_4km_baseline.csv")
  baseline_df <- read.csv(baseline_file, stringsAsFactors = FALSE)
  cat("  Baseline pixels:", length(unique(baseline_df$pixel_id)), "\n\n")

  # Load timeseries
  cat("Loading timeseries...\n")
  timeseries_file <- file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.csv")
  timeseries_df <- read.csv(timeseries_file, stringsAsFactors = FALSE)
  timeseries_df$date <- as.Date(timeseries_df$date)
  cat("  Latest data:", as.character(max(timeseries_df$date)), "\n\n")

  # Fit current year GAM
  year_splines <- fit_current_year_gam(timeseries_df, year(Sys.Date()), config)

  if (is.null(year_splines)) {
    cat("❌ Insufficient data for current year analysis\n\n")
    return(NULL)
  }

  # Calculate anomalies
  anomaly_df <- calculate_current_anomalies(year_splines, baseline_df)

  # Calculate derivatives if requested
  year_derivs <- NULL
  baseline_derivs <- NULL

  if (include_derivatives) {
    year_derivs <- calculate_current_derivatives(timeseries_df, year(Sys.Date()), config)

    baseline_deriv_file <- file.path(hls_paths$gam_models,
                                     "conus_4km_baseline_derivatives.csv")
    if (file.exists(baseline_deriv_file)) {
      baseline_derivs <- read.csv(baseline_deriv_file, stringsAsFactors = FALSE)
    }
  }

  # Generate summary
  summary_stats <- generate_conditions_summary(anomaly_df, year_derivs,
                                               baseline_derivs, config)

  # Export products
  export_conditions_products(anomaly_df, summary_stats, config, hls_paths)

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  cat("\n=== CURRENT CONDITIONS COMPLETE ===\n")
  cat("Time elapsed:", round(elapsed, 1), "minutes\n\n")

  return(summary_stats)
}

# ==============================================================================
# EXECUTION
# ==============================================================================

if (!interactive() || exists("run_current_conditions_script")) {

  config_name <- ifelse(exists("region_config"), region_config, "midwest_operational")
  include_derivs <- ifelse(exists("include_derivatives"), include_derivatives, TRUE)

  summary <- run_current_conditions(config_name, include_derivs)

  if (!is.null(summary)) {
    cat("\nCurrent conditions summary generated\n")
    cat("Region coverage:", round(summary$pct_sig_below, 1), "% below normal\n\n")
  }

} else {
  cat("\n=== CURRENT CONDITIONS FUNCTIONS LOADED ===\n")
  cat("Ready for operational monitoring\n\n")
  cat("Usage:\n")
  cat("  # Full analysis with derivatives\n")
  cat("  run_current_conditions('midwest_operational')\n\n")
  cat("  # Quick analysis (magnitude only)\n")
  cat("  run_current_conditions('midwest_operational', include_derivatives = FALSE)\n\n")
}
