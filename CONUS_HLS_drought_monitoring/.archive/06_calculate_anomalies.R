# ==============================================================================
# PHASE 6: ANOMALY CALCULATION WITH UNCERTAINTY PROPAGATION
# ==============================================================================
# Purpose: Calculate vegetation anomalies as deviations from climatological norms
# Input: Baseline (Phase 2) and year-specific splines (Phase 4)
# Output: Anomalies with uncertainty (pixel_id, year, yday, anomaly, anomaly_se, z_score, p_value)
# Note: Uses GAM predictions with standard errors (not full posterior distributions)
#       For posterior-based uncertainty, use post.distns() from 00_gam_utility_functions.R
# ==============================================================================

library(dplyr)

# Source path configuration
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

cat("=== PHASE 6: ANOMALY CALCULATION ===\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Input files
  baseline_file = file.path(hls_paths$gam_models, "conus_4km_baseline.csv"),
  year_splines_file = file.path(hls_paths$gam_models, "conus_4km_year_splines.csv"),

  # Output
  output_file = file.path(hls_paths$gam_models, "conus_4km_anomalies.csv"),
  anomaly_archive = file.path(hls_paths$anomaly_products),

  # Statistical thresholds
  alpha_level = 0.05  # For significance testing
)

# Ensure output directories exist
ensure_directory(hls_paths$gam_models)
ensure_directory(config$anomaly_archive)

cat("Configuration:\n")
cat("  Baseline input:", config$baseline_file, "\n")
cat("  Year splines input:", config$year_splines_file, "\n")
cat("  Output:", config$output_file, "\n")
cat("  Significance level:", config$alpha_level, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Calculate anomalies with uncertainty propagation
#'
#' @param baseline_df Baseline norms (pixel_id, yday, norm_mean, norm_se)
#' @param year_splines_df Year-specific splines (pixel_id, year, yday, year_mean, year_se)
#' @return Anomaly dataframe
calculate_anomalies <- function(baseline_df, year_splines_df) {

  cat("=== CALCULATING ANOMALIES ===\n\n")

  cat("Joining year splines with baseline...\n")

  # Join on pixel_id and yday
  anomaly_df <- year_splines_df %>%
    left_join(baseline_df, by = c("pixel_id", "yday"), suffix = c("_year", "_norm"))

  cat("  Records before join:", nrow(year_splines_df), "\n")
  cat("  Records after join:", nrow(anomaly_df), "\n\n")

  # Check for missing baseline
  n_missing_baseline <- sum(is.na(anomaly_df$norm_mean))
  if (n_missing_baseline > 0) {
    cat("  ⚠ Warning:", n_missing_baseline,
        "records missing baseline (will be excluded)\n")
    anomaly_df <- anomaly_df %>% filter(!is.na(norm_mean))
  }

  cat("\nCalculating anomaly statistics...\n")

  # Calculate anomaly and propagate uncertainty
  anomaly_df <- anomaly_df %>%
    mutate(
      # Anomaly = year - norm
      anomaly = year_mean - norm_mean,

      # Error propagation (assuming independent errors)
      anomaly_se = sqrt(year_se^2 + norm_se^2),

      # Z-score (standardized anomaly)
      z_score = anomaly / anomaly_se,

      # Two-tailed p-value
      p_value = 2 * pnorm(-abs(z_score)),

      # Significance flag
      is_significant = p_value < 0.05
    )

  # Select output columns
  anomaly_df <- anomaly_df %>%
    select(pixel_id, year, yday, anomaly, anomaly_se, z_score, p_value, is_significant,
           year_mean, year_se, norm_mean, norm_se)

  cat("  Total anomaly records:", nrow(anomaly_df), "\n")
  cat("  Significant anomalies (p < 0.05):", sum(anomaly_df$is_significant), "\n")
  cat("  Significant rate:", round(100 * mean(anomaly_df$is_significant), 1), "%\n\n")

  return(anomaly_df)
}

#' Summarize anomalies
#'
#' @param anomaly_df Anomaly dataframe
#' @return Summary statistics
summarize_anomalies <- function(anomaly_df) {

  cat("=== ANOMALY SUMMARY ===\n\n")

  # Overall statistics
  cat("Total records:", nrow(anomaly_df), "\n")
  cat("Unique pixels:", length(unique(anomaly_df$pixel_id)), "\n")
  cat("Years:", paste(range(anomaly_df$year), collapse = "-"), "\n\n")

  # Anomaly distribution
  cat("Anomaly distribution:\n")
  cat("  Mean:", round(mean(anomaly_df$anomaly), 4), "\n")
  cat("  Median:", round(median(anomaly_df$anomaly), 4), "\n")
  cat("  SD:", round(sd(anomaly_df$anomaly), 4), "\n")
  cat("  Min:", round(min(anomaly_df$anomaly), 4), "\n")
  cat("  Max:", round(max(anomaly_df$anomaly), 4), "\n")
  cat("  Q05:", round(quantile(anomaly_df$anomaly, 0.05), 4), "\n")
  cat("  Q95:", round(quantile(anomaly_df$anomaly, 0.95), 4), "\n\n")

  # Negative vs positive anomalies
  n_negative <- sum(anomaly_df$anomaly < 0)
  n_positive <- sum(anomaly_df$anomaly > 0)

  cat("Anomaly direction:\n")
  cat("  Negative (below normal):", n_negative, "(", round(100 * n_negative / nrow(anomaly_df), 1), "%)\n")
  cat("  Positive (above normal):", n_positive, "(", round(100 * n_positive / nrow(anomaly_df), 1), "%)\n\n")

  # Significance
  cat("Statistical significance:\n")
  cat("  Significant (p < 0.05):", sum(anomaly_df$is_significant), "\n")
  cat("  Significant negative:", sum(anomaly_df$anomaly < 0 & anomaly_df$is_significant), "\n")
  cat("  Significant positive:", sum(anomaly_df$anomaly > 0 & anomaly_df$is_significant), "\n\n")

  # By year summary
  year_summary <- anomaly_df %>%
    group_by(year) %>%
    summarise(
      n_pixels = length(unique(pixel_id)),
      mean_anomaly = mean(anomaly),
      median_anomaly = median(anomaly),
      pct_negative = 100 * mean(anomaly < 0),
      pct_sig_negative = 100 * mean(anomaly < 0 & is_significant),
      .groups = "drop"
    )

  cat("By-year summary:\n")
  print(year_summary, n = Inf)
  cat("\n")

  return(year_summary)
}

#' Classify anomaly severity (placeholder for Phase 5)
#'
#' @param anomaly_df Anomaly dataframe
#' @return Anomaly dataframe with severity classification
classify_anomaly_severity <- function(anomaly_df) {

  cat("=== CLASSIFYING ANOMALY SEVERITY (Placeholder) ===\n\n")

  # Simple percentile-based classification (to be refined in Phase 5)
  percentiles <- quantile(anomaly_df$anomaly, probs = c(0.05, 0.10, 0.25, 0.75, 0.90, 0.95))

  cat("Anomaly percentiles:\n")
  print(round(percentiles, 4))
  cat("\n")

  anomaly_df <- anomaly_df %>%
    mutate(
      severity = case_when(
        anomaly < percentiles[1] & is_significant ~ "Severe Stress",
        anomaly < percentiles[2] & is_significant ~ "Moderate Stress",
        anomaly < percentiles[3] & is_significant ~ "Mild Stress",
        anomaly > percentiles[6] & is_significant ~ "Exceptional Greenness",
        anomaly > percentiles[5] & is_significant ~ "Above Normal",
        TRUE ~ "Normal"
      )
    )

  # Summary of classifications
  severity_counts <- table(anomaly_df$severity)
  cat("Severity classification counts:\n")
  print(severity_counts)
  cat("\n")

  cat("⚠ Note: This is a placeholder classification.\n")
  cat("   Phase 5 will implement validated drought thresholds.\n\n")

  return(anomaly_df)
}

#' Export anomalies by year for spatial visualization
#'
#' @param anomaly_df Anomaly dataframe
#' @param output_dir Directory to save year-specific CSVs
export_anomalies_by_year <- function(anomaly_df, output_dir) {

  cat("=== EXPORTING YEAR-SPECIFIC ANOMALIES ===\n\n")

  years <- unique(anomaly_df$year)

  for (yr in years) {

    year_data <- anomaly_df %>%
      filter(year == yr)

    output_file <- file.path(output_dir, paste0("anomalies_", yr, ".csv"))

    write.csv(year_data, output_file, row.names = FALSE)

    cat("  ", yr, ":", nrow(year_data), "records ->", output_file, "\n")
  }

  cat("\n✓ Year-specific exports complete\n\n")
}

# ==============================================================================
# MAIN PROCESSING WORKFLOW
# ==============================================================================

#' Process all anomaly calculations
#'
#' @param config Configuration list
#' @return Anomaly dataframe
process_anomalies <- function(config) {

  cat("=== STARTING ANOMALY PROCESSING ===\n\n")

  # Load baseline
  cat("Loading baseline from Phase 2...\n")
  if (!file.exists(config$baseline_file)) {
    stop("Baseline file not found. Run Phase 2 first.")
  }

  baseline_df <- read.csv(config$baseline_file, stringsAsFactors = FALSE)
  cat("  Records:", nrow(baseline_df), "\n")
  cat("  Pixels:", length(unique(baseline_df$pixel_id)), "\n\n")

  # Load year splines
  cat("Loading year-specific splines from Phase 4...\n")
  if (!file.exists(config$year_splines_file)) {
    stop("Year splines file not found. Run Phase 4 first.")
  }

  year_splines_df <- read.csv(config$year_splines_file, stringsAsFactors = FALSE)
  cat("  Records:", nrow(year_splines_df), "\n")
  cat("  Pixel-years:",
      length(unique(paste(year_splines_df$pixel_id, year_splines_df$year))), "\n\n")

  # Calculate anomalies
  anomaly_df <- calculate_anomalies(baseline_df, year_splines_df)

  # Summarize
  year_summary <- summarize_anomalies(anomaly_df)

  # Placeholder classification
  anomaly_df <- classify_anomaly_severity(anomaly_df)

  # Save main output
  cat("Saving anomalies to:", config$output_file, "\n")
  write.csv(anomaly_df, config$output_file, row.names = FALSE)

  # Export by year
  export_anomalies_by_year(anomaly_df, config$anomaly_archive)

  cat("\n=== PHASE 6 COMPLETE ===\n\n")

  return(anomaly_df)
}

# ==============================================================================
# EXECUTION
# ==============================================================================

cat("=== READY TO CALCULATE ANOMALIES ===\n")

# Check if running as main script (not being sourced)
if (!interactive() || exists("run_phase6")) {

  cat("\n=== EXECUTING PHASE 6: CALCULATE ANOMALIES ===\n")
  cat("Started at:", as.character(Sys.time()), "\n\n")

  # Run anomaly calculation
  start_time <- Sys.time()
  anomaly_df <- process_anomalies(config)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  # Final summary
  cat("\n=== PHASE 6 COMPLETE ===\n")
  cat("Total time:", round(elapsed, 1), "minutes\n")
  cat("Output saved to:", config$output_file, "\n")

} else {
  cat("\n=== PHASE 6 FUNCTIONS LOADED ===\n")
  cat("Ready to calculate anomalies by joining baseline and year splines\n")
  cat("Estimated time: ~5 minutes\n")
  cat("Output will be saved to:", config$output_file, "\n\n")
  cat("To run manually:\n")
  cat("  anomaly_df <- process_anomalies(config)\n\n")
}
