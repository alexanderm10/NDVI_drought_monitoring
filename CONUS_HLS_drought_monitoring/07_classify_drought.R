# ==============================================================================
# PHASE 5: DROUGHT CLASSIFICATION (PLACEHOLDER)
# ==============================================================================
# Purpose: Classify vegetation stress using anomaly thresholds
# Input: Anomalies with uncertainty (Phase 4)
# Output: Drought classifications and validation comparisons
# Status: PLACEHOLDER - Methodology to be determined
# ==============================================================================

library(dplyr)
library(ggplot2)

# Source path configuration
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

cat("=== PHASE 5: DROUGHT CLASSIFICATION (PLACEHOLDER) ===\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Input
  anomaly_file = file.path(hls_paths$gam_models, "conus_4km_anomalies.csv"),

  # Output
  output_file = file.path(hls_paths$anomaly_products, "conus_4km_drought_classification.csv"),
  validation_dir = file.path(hls_paths$validation_data),
  figures_dir = file.path(hls_paths$figures, "drought_classification"),

  # Classification method (to be determined)
  method = "percentile_based"  # Options: "percentile_based", "significance_based", "hybrid"
)

# Ensure output directories exist
ensure_directory(config$output_file %>% dirname())
ensure_directory(config$validation_dir)
ensure_directory(config$figures_dir)

cat("Configuration:\n")
cat("  Input:", config$anomaly_file, "\n")
cat("  Output:", config$output_file, "\n")
cat("  Method:", config$method, "(PLACEHOLDER)\n\n")

# ==============================================================================
# PLACEHOLDER CLASSIFICATION FUNCTIONS
# ==============================================================================

#' Classify drought using percentile-based thresholds
#'
#' @param anomaly_df Anomaly dataframe
#' @return Anomaly dataframe with drought_category column
classify_percentile_based <- function(anomaly_df) {

  cat("=== PERCENTILE-BASED CLASSIFICATION ===\n\n")
  cat("⚠ PLACEHOLDER METHOD - To be validated\n\n")

  # Calculate empirical percentiles
  percentiles <- quantile(anomaly_df$anomaly, probs = c(0.02, 0.05, 0.10, 0.25, 0.75, 0.90, 0.95, 0.98))

  cat("Anomaly percentiles:\n")
  print(round(percentiles, 4))
  cat("\n")

  # Classify based on percentiles
  anomaly_df <- anomaly_df %>%
    mutate(
      drought_category = case_when(
        anomaly < percentiles[1] ~ "D4 - Exceptional Drought",
        anomaly < percentiles[2] ~ "D3 - Extreme Drought",
        anomaly < percentiles[3] ~ "D2 - Severe Drought",
        anomaly < percentiles[4] ~ "D1 - Moderate Drought",
        anomaly > percentiles[8] ~ "W4 - Exceptional Wetness",
        anomaly > percentiles[7] ~ "W3 - Extreme Wetness",
        anomaly > percentiles[6] ~ "W2 - Abundant Vegetation",
        anomaly > percentiles[5] ~ "W1 - Above Normal",
        TRUE ~ "D0 - Normal"
      )
    )

  # Summary
  cat("Classification distribution:\n")
  print(table(anomaly_df$drought_category))
  cat("\n")

  return(anomaly_df)
}

#' Classify drought using significance-based thresholds
#'
#' @param anomaly_df Anomaly dataframe
#' @return Anomaly dataframe with drought_category column
classify_significance_based <- function(anomaly_df) {

  cat("=== SIGNIFICANCE-BASED CLASSIFICATION ===\n\n")
  cat("⚠ PLACEHOLDER METHOD - To be validated\n\n")

  # Classify based on z-score magnitude and significance
  anomaly_df <- anomaly_df %>%
    mutate(
      drought_category = case_when(
        z_score < -3 & is_significant ~ "D4 - Exceptional Drought",
        z_score < -2 & is_significant ~ "D3 - Extreme Drought",
        z_score < -1.5 & is_significant ~ "D2 - Severe Drought",
        z_score < -1 & is_significant ~ "D1 - Moderate Drought",
        z_score > 3 & is_significant ~ "W4 - Exceptional Wetness",
        z_score > 2 & is_significant ~ "W3 - Extreme Wetness",
        z_score > 1.5 & is_significant ~ "W2 - Abundant Vegetation",
        z_score > 1 & is_significant ~ "W1 - Above Normal",
        TRUE ~ "D0 - Normal"
      )
    )

  # Summary
  cat("Classification distribution:\n")
  print(table(anomaly_df$drought_category))
  cat("\n")

  return(anomaly_df)
}

#' Classify drought using hybrid approach
#'
#' @param anomaly_df Anomaly dataframe
#' @return Anomaly dataframe with drought_category column
classify_hybrid <- function(anomaly_df) {

  cat("=== HYBRID CLASSIFICATION ===\n\n")
  cat("⚠ PLACEHOLDER METHOD - Combines percentiles and significance\n\n")

  # Calculate percentiles
  percentiles <- quantile(anomaly_df$anomaly, probs = c(0.05, 0.10, 0.25, 0.75, 0.90, 0.95))

  # Hybrid: Require both percentile threshold AND significance
  anomaly_df <- anomaly_df %>%
    mutate(
      drought_category = case_when(
        anomaly < percentiles[1] & is_significant ~ "D3 - Extreme Drought",
        anomaly < percentiles[2] & is_significant ~ "D2 - Severe Drought",
        anomaly < percentiles[3] & is_significant ~ "D1 - Moderate Drought",
        anomaly > percentiles[6] & is_significant ~ "W3 - Extreme Wetness",
        anomaly > percentiles[5] & is_significant ~ "W2 - Abundant Vegetation",
        anomaly > percentiles[4] & is_significant ~ "W1 - Above Normal",
        anomaly < 0 ~ "D0 - Abnormally Dry (not significant)",
        TRUE ~ "Normal"
      )
    )

  # Summary
  cat("Classification distribution:\n")
  print(table(anomaly_df$drought_category))
  cat("\n")

  return(anomaly_df)
}

# ==============================================================================
# VALIDATION FUNCTIONS (PLACEHOLDER)
# ==============================================================================

#' Compare drought classifications to USDM (placeholder)
#'
#' @param classified_df Classified anomaly dataframe
#' @return Validation statistics
validate_against_usdm <- function(classified_df) {

  cat("=== USDM VALIDATION (PLACEHOLDER) ===\n\n")
  cat("⚠ Requires USDM data integration\n")
  cat("   TODO: Download and align USDM drought categories by date/location\n")
  cat("   TODO: Calculate agreement metrics (kappa, confusion matrix)\n")
  cat("   TODO: Identify systematic biases\n\n")

  # Placeholder return
  return(NULL)
}

#' Plot classification distributions
#'
#' @param classified_df Classified anomaly dataframe
#' @param output_dir Directory to save figures
plot_classification_diagnostics <- function(classified_df, output_dir) {

  cat("=== GENERATING DIAGNOSTIC PLOTS ===\n\n")

  # 1. Anomaly distribution by drought category
  p1 <- ggplot(classified_df, aes(x = drought_category, y = anomaly)) +
    geom_boxplot(fill = "steelblue", alpha = 0.7) +
    theme_minimal() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      panel.background = element_rect(fill = "white", color = NA),
      plot.background = element_rect(fill = "white", color = NA)
    ) +
    labs(
      title = "Anomaly Distribution by Drought Category",
      x = "Category",
      y = "NDVI Anomaly"
    )

  ggsave(file.path(output_dir, "anomaly_by_category.png"), p1,
         width = 10, height = 6, dpi = 300, bg = "white")

  cat("  Saved: anomaly_by_category.png\n")

  # 2. Classification counts by year
  year_counts <- classified_df %>%
    group_by(year, drought_category) %>%
    summarise(n = n(), .groups = "drop")

  p2 <- ggplot(year_counts, aes(x = year, y = n, fill = drought_category)) +
    geom_col(position = "fill") +
    scale_y_continuous(labels = scales::percent) +
    theme_minimal() +
    theme(
      panel.background = element_rect(fill = "white", color = NA),
      plot.background = element_rect(fill = "white", color = NA),
      legend.position = "bottom"
    ) +
    labs(
      title = "Drought Category Distribution by Year",
      x = "Year",
      y = "Proportion",
      fill = "Category"
    )

  ggsave(file.path(output_dir, "category_by_year.png"), p2,
         width = 12, height = 6, dpi = 300, bg = "white")

  cat("  Saved: category_by_year.png\n\n")
}

# ==============================================================================
# MAIN PROCESSING WORKFLOW
# ==============================================================================

#' Process drought classification
#'
#' @param config Configuration list
#' @return Classified dataframe
process_drought_classification <- function(config) {

  cat("=== STARTING DROUGHT CLASSIFICATION ===\n\n")
  cat("⚠⚠⚠ WARNING: THIS IS A PLACEHOLDER IMPLEMENTATION ⚠⚠⚠\n")
  cat("    Classification thresholds need validation before operational use\n")
  cat("    Recommended: Compare against USDM, validate with field data\n\n")

  # Load anomalies
  cat("Loading anomalies from Phase 4...\n")
  if (!file.exists(config$anomaly_file)) {
    stop("Anomaly file not found. Run Phase 4 first.")
  }

  anomaly_df <- read.csv(config$anomaly_file, stringsAsFactors = FALSE)
  cat("  Records:", nrow(anomaly_df), "\n\n")

  # Apply classification method
  classified_df <- switch(config$method,
    "percentile_based" = classify_percentile_based(anomaly_df),
    "significance_based" = classify_significance_based(anomaly_df),
    "hybrid" = classify_hybrid(anomaly_df),
    stop("Unknown classification method: ", config$method)
  )

  # Generate diagnostic plots
  plot_classification_diagnostics(classified_df, config$figures_dir)

  # Validation (placeholder)
  validate_against_usdm(classified_df)

  # Save output
  cat("Saving classified data to:", config$output_file, "\n")
  write.csv(classified_df, config$output_file, row.names = FALSE)

  cat("\n=== PHASE 5 COMPLETE (PLACEHOLDER) ===\n\n")
  cat("⚠ Next Steps:\n")
  cat("  1. Review classification distributions in figures/\n")
  cat("  2. Integrate USDM data for validation\n")
  cat("  3. Refine thresholds based on validation results\n")
  cat("  4. Document finalized methodology in GAM_METHODOLOGY.md\n\n")

  return(classified_df)
}

# ==============================================================================
# EXECUTION
# ==============================================================================

cat("=== READY TO CLASSIFY DROUGHT (PLACEHOLDER) ===\n")
cat("This will apply placeholder thresholds to anomalies\n")

# Check if running as main script (not being sourced)
if (!interactive() || exists("run_phase5")) {

  cat("\n=== EXECUTING PHASE 5: CLASSIFY DROUGHT (PLACEHOLDER) ===\n")
  cat("⚠ This uses placeholder thresholds for exploratory analysis\n")
  cat("Started at:", as.character(Sys.time()), "\n\n")

  # Run drought classification
  start_time <- Sys.time()
  classified_df <- process_drought_classification(config)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  # Final summary
  cat("\n=== PHASE 5 COMPLETE ===\n")
  cat("Total time:", round(elapsed, 1), "minutes\n")
  cat("Output saved to:", config$output_file, "\n")

} else {
  cat("\n=== PHASE 5 FUNCTIONS LOADED ===\n")
  cat("Ready to classify drought (placeholder thresholds)\n")
  cat("⚠ Results are for exploratory analysis only - not operational\n")
  cat("Estimated time: ~5 minutes\n")
  cat("Output will be saved to:", config$output_file, "\n\n")
  cat("To run manually:\n")
  cat("  classified_df <- process_drought_classification(config)\n\n")
}
