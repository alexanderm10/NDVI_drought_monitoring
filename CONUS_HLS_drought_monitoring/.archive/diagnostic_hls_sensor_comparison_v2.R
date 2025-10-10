# HLS Sensor Comparison Diagnostic - REVISED
# Purpose: Properly test if HLS L30 (Landsat) vs HLS S30 (Sentinel) show residual sensor differences
# Strategy: Use PAIRED observations (same location, close in time) to avoid temporal/spatial confounding
#
# NOTE: HLS products are already harmonized by NASA for surface reflectance, BRDF, and spectral bandpass
# This diagnostic verifies that harmonization is sufficient for drought monitoring applications

library(terra)
library(dplyr)
library(tidyr)
library(ggplot2)
library(lubridate)
library(mgcv)

# Setup paths
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

######################
# Configuration
######################

DIAGNOSTIC_CONFIG <- list(
  # Spatial subsampling - use one representative tile
  test_tile = "midwest_02_02",  # Central Iowa/Illinois - agricultural focus

  # Temporal window - focus on recent years with both sensors active
  test_years = c(2022, 2023, 2024),  # Sentinel-2A/B + Landsat 8/9 all active

  # Pixel subsampling strategy
  pixel_sample_rate = 0.01,  # 1% of pixels (~10,000-30,000 pixels depending on tile)
  min_pixels = 5000,         # Minimum pixels to sample
  max_pixels = 30000,        # Maximum pixels to sample

  # Scene subsampling
  scenes_per_sensor_per_month = 5,  # Sample ~5 scenes per sensor per month for balanced comparison

  # Pairing parameters (CRITICAL for valid comparison)
  max_day_difference = 3,    # Maximum days between L30 and S30 observations to consider "paired"
  min_paired_obs = 100,      # Minimum paired observations needed for analysis

  # Quality filters
  ndvi_valid_range = c(-0.2, 1.0),  # Valid NDVI range
  min_obs_per_pixel = 2             # Minimum observations per pixel
)

cat("=== HLS SENSOR DIAGNOSTIC CONFIGURATION (PAIRED COMPARISON) ===\n")
cat("Test years:", paste(DIAGNOSTIC_CONFIG$test_years, collapse = ", "), "\n")
cat("Pairing window: ±", DIAGNOSTIC_CONFIG$max_day_difference, "days\n")
cat("Pixel sample rate:", DIAGNOSTIC_CONFIG$pixel_sample_rate * 100, "%\n\n")

######################
# Step 1: Get File List with Temporal Stratification
######################

get_diagnostic_files <- function(config = DIAGNOSTIC_CONFIG) {

  cat("=== STEP 1: Building Temporally Balanced File List ===\n")

  all_files <- list()

  for (year in config$test_years) {
    year_dir <- file.path(hls_paths$processed_ndvi, "daily", year)

    if (!dir.exists(year_dir)) {
      cat("⚠ Year directory not found:", year_dir, "\n")
      next
    }

    # Get all NDVI files for this year
    ndvi_files <- list.files(year_dir, pattern = "_NDVI\\.tif$", full.names = TRUE)

    if (length(ndvi_files) == 0) {
      cat("⚠ No NDVI files found for year", year, "\n")
      next
    }

    # Extract metadata from filenames
    file_df <- data.frame(
      filepath = ndvi_files,
      filename = basename(ndvi_files),
      stringsAsFactors = FALSE
    )

    file_df$sensor <- ifelse(grepl("HLS\\.L30\\.", file_df$filename), "L30", "S30")
    file_df$tile <- sub(".*\\.(T[0-9A-Z]+)\\..*", "\\1", file_df$filename)

    # Extract date from filename (format: YYYYDDDTHHMMSS)
    date_string <- sub(".*\\.([0-9]{7}T[0-9]{6})\\..*", "\\1", file_df$filename)
    file_df$year <- as.numeric(substr(date_string, 1, 4))
    file_df$yday <- as.numeric(substr(date_string, 5, 7))
    file_df$date <- as.Date(paste0(file_df$year, "-01-01")) + file_df$yday - 1
    file_df$month <- month(file_df$date)

    cat("Year", year, "- Found", nrow(file_df), "NDVI scenes\n")
    cat("  L30 (Landsat):", sum(file_df$sensor == "L30"), "\n")
    cat("  S30 (Sentinel):", sum(file_df$sensor == "S30"), "\n")

    # Sample scenes per sensor per month to ensure temporal balance
    file_df_sampled <- file_df %>%
      group_by(sensor, month) %>%
      {
        # Get count for each group and take minimum
        group_data <- group_keys(.)
        group_indices <- group_rows(.)

        sampled_rows <- lapply(group_indices, function(idx) {
          n_available <- length(idx)
          n_sample <- min(config$scenes_per_sensor_per_month, n_available)
          if (n_sample > 0) {
            sample(idx, n_sample)
          } else {
            integer(0)
          }
        })

        slice(., unlist(sampled_rows))
      } %>%
      ungroup() %>%
      arrange(date)

    cat("  After temporal stratification:", nrow(file_df_sampled), "scenes\n")
    cat("    L30:", sum(file_df_sampled$sensor == "L30"), "\n")
    cat("    S30:", sum(file_df_sampled$sensor == "S30"), "\n\n")

    all_files[[as.character(year)]] <- file_df_sampled
  }

  combined_files <- bind_rows(all_files)

  cat("✓ Total scenes selected for analysis:", nrow(combined_files), "\n")
  cat("  L30 (Landsat):", sum(combined_files$sensor == "L30"), "\n")
  cat("  S30 (Sentinel):", sum(combined_files$sensor == "S30"), "\n")
  cat("  Date range:", as.character(min(combined_files$date)), "to",
      as.character(max(combined_files$date)), "\n\n")

  return(combined_files)
}

######################
# Step 2: Load Data with Spatial Subsampling
######################

load_diagnostic_data <- function(file_list, config = DIAGNOSTIC_CONFIG) {

  cat("=== STEP 2: Loading NDVI Data with Spatial Subsampling ===\n")

  # Read first file to establish pixel sampling grid
  first_rast <- rast(file_list$filepath[1])
  cat("First raster dimensions:", dim(first_rast)[1], "rows ×", dim(first_rast)[2], "cols\n")
  cat("Total pixels:", ncell(first_rast), "\n")

  # Calculate target sample size
  total_pixels <- ncell(first_rast)
  target_sample <- min(
    max(round(total_pixels * config$pixel_sample_rate), config$min_pixels),
    config$max_pixels
  )

  cat("Target pixel sample:", target_sample, "(", round(100 * target_sample/total_pixels, 2), "%)\n")

  # Create random pixel sample indices (consistent across all rasters)
  set.seed(12345)  # Reproducible sampling
  sample_indices <- sort(sample.int(total_pixels, size = target_sample))

  # Extract coordinates for sampled pixels
  xy <- xyFromCell(first_rast, sample_indices)
  pixel_df <- data.frame(
    pixel_id = 1:nrow(xy),
    x = xy[, 1],
    y = xy[, 2]
  )

  cat("Sampling", length(sample_indices), "pixel locations\n\n")

  # Initialize data storage
  ndvi_data <- list()

  # Load each scene
  pb <- txtProgressBar(min = 0, max = nrow(file_list), style = 3)

  for (i in 1:nrow(file_list)) {

    scene <- file_list[i, ]

    tryCatch({
      if (!file.exists(scene$filepath)) {
        next
      }

      rast_ndvi <- rast(scene$filepath)

      if (nlyr(rast_ndvi) == 0 || ncell(rast_ndvi) == 0) {
        next
      }

      # Extract values at sampled cell indices
      all_vals <- values(rast_ndvi)
      ndvi_vals <- all_vals[sample_indices]

      # Filter valid NDVI range
      valid_idx <- !is.na(ndvi_vals) &
        ndvi_vals >= config$ndvi_valid_range[1] &
        ndvi_vals <= config$ndvi_valid_range[2]

      if (sum(valid_idx) > 0) {
        ndvi_data[[i]] <- data.frame(
          pixel_id = pixel_df$pixel_id[valid_idx],
          x = pixel_df$x[valid_idx],
          y = pixel_df$y[valid_idx],
          ndvi = ndvi_vals[valid_idx],
          sensor = scene$sensor,
          date = scene$date,
          year = scene$year,
          yday = scene$yday,
          month = scene$month,
          scene_id = scene$filename,
          stringsAsFactors = FALSE
        )
      }

    }, error = function(e) {
      # Silent error handling
    })

    setTxtProgressBar(pb, i)
  }

  close(pb)

  # Combine all data
  combined_data <- bind_rows(ndvi_data)

  if (nrow(combined_data) == 0) {
    stop("No valid NDVI data extracted. Check file paths and NDVI value ranges.")
  }

  cat("\n✓ Data loaded successfully\n")
  cat("Total observations:", nrow(combined_data), "\n")
  cat("Unique pixels:", length(unique(combined_data$pixel_id)), "\n")
  cat("L30 observations:", sum(combined_data$sensor == "L30"), "\n")
  cat("S30 observations:", sum(combined_data$sensor == "S30"), "\n")
  cat("Date range:", as.character(min(combined_data$date)), "to",
      as.character(max(combined_data$date)), "\n\n")

  return(combined_data)
}

######################
# Step 3: Create Paired Observations
######################

create_paired_observations <- function(ndvi_data, config = DIAGNOSTIC_CONFIG) {

  cat("=== STEP 3: Creating Paired Observations (L30 vs S30) ===\n\n")

  # Separate by sensor
  l30_data <- ndvi_data %>% filter(sensor == "L30")
  s30_data <- ndvi_data %>% filter(sensor == "S30")

  cat("L30 observations:", nrow(l30_data), "\n")
  cat("S30 observations:", nrow(s30_data), "\n\n")

  # For each L30 observation, find nearest S30 observation at same pixel
  paired_obs <- list()

  cat("Finding paired observations (within ±", config$max_day_difference, "days)...\n")
  pb <- txtProgressBar(min = 0, max = nrow(l30_data), style = 3)

  for (i in 1:nrow(l30_data)) {
    l30_row <- l30_data[i, ]

    # Find S30 observations at same pixel within time window
    s30_matches <- s30_data %>%
      filter(pixel_id == l30_row$pixel_id,
             abs(as.numeric(date - l30_row$date)) <= config$max_day_difference)

    if (nrow(s30_matches) > 0) {
      # If multiple matches, take closest in time
      s30_matches$time_diff <- abs(as.numeric(s30_matches$date - l30_row$date))
      s30_match <- s30_matches %>% slice_min(time_diff, n = 1)

      paired_obs[[length(paired_obs) + 1]] <- data.frame(
        pixel_id = l30_row$pixel_id,
        x = l30_row$x,
        y = l30_row$y,
        l30_date = l30_row$date,
        s30_date = s30_match$date[1],
        day_diff = s30_match$time_diff[1],
        l30_ndvi = l30_row$ndvi,
        s30_ndvi = s30_match$ndvi[1],
        year = l30_row$year,
        month = l30_row$month,
        yday_avg = round((l30_row$yday + s30_match$yday[1]) / 2),
        stringsAsFactors = FALSE
      )
    }

    if (i %% 1000 == 0) setTxtProgressBar(pb, i)
  }

  close(pb)

  paired_df <- bind_rows(paired_obs)

  cat("\n\n✓ Paired observations created\n")
  cat("Total paired observations:", nrow(paired_df), "\n")
  cat("Unique pixels with pairs:", length(unique(paired_df$pixel_id)), "\n")
  cat("Mean time difference:", round(mean(paired_df$day_diff), 2), "days\n")
  cat("Max time difference:", max(paired_df$day_diff), "days\n\n")

  if (nrow(paired_df) < config$min_paired_obs) {
    warning("Insufficient paired observations (", nrow(paired_df), " < ",
            config$min_paired_obs, "). Results may not be reliable.")
  }

  return(paired_df)
}

######################
# Step 4: Analyze Paired Sensor Differences
######################

analyze_paired_differences <- function(paired_data) {

  cat("=== STEP 4: Paired Sensor Difference Analysis ===\n\n")

  # Calculate difference for each pair
  paired_data$ndvi_diff <- paired_data$l30_ndvi - paired_data$s30_ndvi
  paired_data$ndvi_mean <- (paired_data$l30_ndvi + paired_data$s30_ndvi) / 2

  # Overall statistics
  cat("--- Overall Paired Comparison ---\n")
  cat("Mean L30 NDVI:", round(mean(paired_data$l30_ndvi), 4), "\n")
  cat("Mean S30 NDVI:", round(mean(paired_data$s30_ndvi), 4), "\n")
  cat("Mean difference (L30 - S30):", round(mean(paired_data$ndvi_diff), 4), "\n")
  cat("SD of differences:", round(sd(paired_data$ndvi_diff), 4), "\n")
  cat("95% CI of difference: [",
      round(mean(paired_data$ndvi_diff) - 1.96 * sd(paired_data$ndvi_diff) / sqrt(nrow(paired_data)), 4),
      ",",
      round(mean(paired_data$ndvi_diff) + 1.96 * sd(paired_data$ndvi_diff) / sqrt(nrow(paired_data)), 4),
      "]\n")

  # Paired t-test
  t_test <- t.test(paired_data$l30_ndvi, paired_data$s30_ndvi, paired = TRUE)
  cat("\nPaired t-test:\n")
  cat("  t-statistic:", round(t_test$statistic, 3), "\n")
  cat("  p-value:", format.pval(t_test$p.value, digits = 3), "\n")
  cat("  Significant at α=0.05:", t_test$p.value < 0.05, "\n\n")

  # Correlation
  cor_test <- cor.test(paired_data$l30_ndvi, paired_data$s30_ndvi)
  cat("Correlation:\n")
  cat("  Pearson's r:", round(cor_test$estimate, 4), "\n")
  cat("  R²:", round(cor_test$estimate^2, 4), "\n\n")

  # By month (to check for seasonal patterns)
  monthly_diff <- paired_data %>%
    group_by(month) %>%
    summarise(
      n_pairs = n(),
      mean_l30 = mean(l30_ndvi),
      mean_s30 = mean(s30_ndvi),
      mean_diff = mean(ndvi_diff),
      sd_diff = sd(ndvi_diff),
      .groups = "drop"
    )

  cat("--- Differences by Month ---\n")
  print(as.data.frame(monthly_diff))
  cat("\n")

  # GAM to test for systematic patterns in difference
  cat("--- GAM Analysis of Differences ---\n")

  if (nrow(paired_data) >= 100) {
    # Determine appropriate k based on unique values
    n_unique_yday <- length(unique(paired_data$yday_avg))
    k_yday <- min(10, max(3, floor(n_unique_yday / 2)))

    n_unique_ndvi <- length(unique(round(paired_data$ndvi_mean, 3)))
    k_ndvi <- min(10, max(3, floor(n_unique_ndvi / 2)))

    cat("Unique yday values:", n_unique_yday, "| Using k =", k_yday, "\n")
    cat("Unique NDVI values:", n_unique_ndvi, "| Using k =", k_ndvi, "\n\n")

    # Model: Does the difference vary systematically with day of year?
    gam_diff <- try(gam(ndvi_diff ~ s(yday_avg, k = k_yday), data = paired_data), silent = TRUE)

    if (!inherits(gam_diff, "try-error")) {
      cat("GAM Summary (Difference ~ s(yday)):\n")
      cat("  Deviance explained:", round(summary(gam_diff)$dev.expl * 100, 2), "%\n")
      cat("  p-value for smooth term:", format.pval(summary(gam_diff)$s.pv, digits = 3), "\n\n")
    } else {
      cat("⚠ GAM fitting failed for yday model\n\n")
      gam_diff <- NULL
    }

    # Test if difference varies with NDVI magnitude (Bland-Altman style)
    gam_magnitude <- try(gam(ndvi_diff ~ s(ndvi_mean, k = k_ndvi), data = paired_data), silent = TRUE)

    if (!inherits(gam_magnitude, "try-error")) {
      cat("GAM Summary (Difference ~ s(mean_NDVI)):\n")
      cat("  Deviance explained:", round(summary(gam_magnitude)$dev.expl * 100, 2), "%\n")
      cat("  p-value for smooth term:", format.pval(summary(gam_magnitude)$s.pv, digits = 3), "\n\n")
    } else {
      cat("⚠ GAM fitting failed for magnitude model\n\n")
      gam_magnitude <- NULL
    }

  } else {
    cat("⚠ Insufficient data for GAM analysis\n\n")
    gam_diff <- NULL
    gam_magnitude <- NULL
  }

  return(list(
    paired_data_enriched = paired_data,  # Return the modified paired_data with ndvi_diff and ndvi_mean
    overall_stats = data.frame(
      mean_l30 = mean(paired_data$l30_ndvi),
      mean_s30 = mean(paired_data$s30_ndvi),
      mean_diff = mean(paired_data$ndvi_diff),
      sd_diff = sd(paired_data$ndvi_diff),
      correlation = cor_test$estimate,
      t_statistic = t_test$statistic,
      p_value = t_test$p.value
    ),
    monthly = monthly_diff,
    t_test = t_test,
    cor_test = cor_test,
    gam_diff = gam_diff,
    gam_magnitude = gam_magnitude
  ))
}

######################
# Step 5: Visualization
######################

create_diagnostic_plots <- function(paired_data, analysis_results) {

  cat("=== STEP 5: Creating Diagnostic Plots ===\n")

  output_dir <- file.path(hls_paths$figures, "sensor_diagnostics_paired")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  # Plot 1: Scatter plot L30 vs S30 (paired observations)
  p1 <- ggplot(paired_data, aes(x = l30_ndvi, y = s30_ndvi)) +
    geom_hex(bins = 50) +
    geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
    scale_fill_viridis_c() +
    labs(title = "HLS Paired Comparison: L30 vs S30 NDVI",
         subtitle = paste(nrow(paired_data), "paired observations within ±",
                          DIAGNOSTIC_CONFIG$max_day_difference, "days"),
         x = "L30 (Landsat) NDVI",
         y = "S30 (Sentinel) NDVI") +
    coord_fixed() +
    theme_minimal() +
    theme(panel.background = element_rect(fill = "white", color = NA),
          plot.background = element_rect(fill = "white", color = NA))

  ggsave(file.path(output_dir, "01_paired_l30_vs_s30_scatter.png"),
         p1, width = 7, height = 7, dpi = 300, bg = "white")
  cat("✓ Saved: 01_paired_l30_vs_s30_scatter.png\n")

  # Plot 2: Bland-Altman plot (difference vs mean)
  p2 <- ggplot(paired_data, aes(x = (l30_ndvi + s30_ndvi)/2, y = l30_ndvi - s30_ndvi)) +
    geom_hex(bins = 50) +
    geom_hline(yintercept = 0, color = "red", linetype = "solid", linewidth = 1) +
    geom_hline(yintercept = mean(paired_data$ndvi_diff), color = "blue", linetype = "dashed", linewidth = 0.8) +
    geom_hline(yintercept = mean(paired_data$ndvi_diff) + 1.96 * sd(paired_data$ndvi_diff),
               color = "blue", linetype = "dotted", linewidth = 0.8) +
    geom_hline(yintercept = mean(paired_data$ndvi_diff) - 1.96 * sd(paired_data$ndvi_diff),
               color = "blue", linetype = "dotted", linewidth = 0.8) +
    scale_fill_viridis_c() +
    labs(title = "Bland-Altman Plot: Sensor Agreement",
         subtitle = "Blue dashed = mean difference, dotted = ±1.96 SD",
         x = "Mean NDVI [(L30 + S30) / 2]",
         y = "Difference (L30 - S30)") +
    theme_minimal() +
    theme(panel.background = element_rect(fill = "white", color = NA),
          plot.background = element_rect(fill = "white", color = NA))

  ggsave(file.path(output_dir, "02_bland_altman_plot.png"),
         p2, width = 8, height = 6, dpi = 300, bg = "white")
  cat("✓ Saved: 02_bland_altman_plot.png\n")

  # Plot 3: Difference by month
  p3 <- ggplot(analysis_results$monthly, aes(x = month, y = mean_diff)) +
    geom_line(linewidth = 1, color = "#1f77b4") +
    geom_point(size = 3, color = "#1f77b4") +
    geom_errorbar(aes(ymin = mean_diff - sd_diff, ymax = mean_diff + sd_diff),
                  width = 0.3, color = "#1f77b4", alpha = 0.6) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
    scale_x_continuous(breaks = 1:12, labels = month.abb) +
    labs(title = "Sensor Difference by Month",
         subtitle = "Mean ± SD of L30 - S30 difference",
         x = "Month",
         y = "NDVI Difference (L30 - S30)") +
    theme_minimal() +
    theme(panel.background = element_rect(fill = "white", color = NA),
          plot.background = element_rect(fill = "white", color = NA))

  ggsave(file.path(output_dir, "03_difference_by_month.png"),
         p3, width = 10, height = 5, dpi = 300, bg = "white")
  cat("✓ Saved: 03_difference_by_month.png\n")

  # Plot 4: Distribution of differences
  p4 <- ggplot(paired_data, aes(x = ndvi_diff)) +
    geom_histogram(bins = 50, fill = "#1f77b4", alpha = 0.7, color = "black") +
    geom_vline(xintercept = 0, color = "red", linetype = "dashed", linewidth = 1) +
    geom_vline(xintercept = mean(paired_data$ndvi_diff), color = "blue", linetype = "solid", linewidth = 1) +
    labs(title = "Distribution of Paired Differences",
         subtitle = paste("Mean =", round(mean(paired_data$ndvi_diff), 4),
                          "| SD =", round(sd(paired_data$ndvi_diff), 4)),
         x = "NDVI Difference (L30 - S30)",
         y = "Count") +
    theme_minimal() +
    theme(panel.background = element_rect(fill = "white", color = NA),
          plot.background = element_rect(fill = "white", color = NA))

  ggsave(file.path(output_dir, "04_difference_distribution.png"),
         p4, width = 8, height = 5, dpi = 300, bg = "white")
  cat("✓ Saved: 04_difference_distribution.png\n")

  # Plot 5: GAM of difference vs day of year (if available)
  if (!is.null(analysis_results$gam_diff)) {
    newdata <- data.frame(yday_avg = 1:365)
    newdata$pred <- predict(analysis_results$gam_diff, newdata = newdata)

    p5 <- ggplot(newdata, aes(x = yday_avg, y = pred)) +
      geom_line(linewidth = 1, color = "#1f77b4") +
      geom_hline(yintercept = 0, linetype = "dashed", color = "red") +
      labs(title = "Sensor Difference Throughout the Year",
           subtitle = "GAM smooth of L30 - S30 difference",
           x = "Day of Year",
           y = "Predicted Difference (L30 - S30)") +
      theme_minimal() +
      theme(panel.background = element_rect(fill = "white", color = NA),
            plot.background = element_rect(fill = "white", color = NA))

    ggsave(file.path(output_dir, "05_gam_difference_by_yday.png"),
           p5, width = 10, height = 5, dpi = 300, bg = "white")
    cat("✓ Saved: 05_gam_difference_by_yday.png\n")
  }

  cat("\n✓ All plots saved to:", output_dir, "\n\n")
}

######################
# Step 6: Recommendations
######################

make_recommendations <- function(analysis_results) {

  cat("=== STEP 6: RECOMMENDATIONS ===\n\n")

  mean_diff <- analysis_results$overall_stats$mean_diff
  abs_mean_diff <- abs(mean_diff)
  p_value <- analysis_results$overall_stats$p_value
  correlation <- analysis_results$overall_stats$correlation

  cat("Key Results:\n")
  cat("  Mean difference (L30 - S30):", round(mean_diff, 4), "NDVI units\n")
  cat("  SD of differences:", round(analysis_results$overall_stats$sd_diff, 4), "\n")
  cat("  Correlation (r):", round(correlation, 4), "\n")
  cat("  Statistical significance: p", ifelse(p_value < 0.001, "< 0.001",
                                               paste("=", round(p_value, 4))), "\n\n")

  # Interpretation
  cat("Interpretation:\n")

  if (abs_mean_diff < 0.02) {
    cat("✅ EXCELLENT AGREEMENT: Sensors show negligible difference (<0.02 NDVI)\n")
    cat("   NASA's HLS harmonization is working well.\n")
    cat("   L30 and S30 can be combined directly for drought monitoring.\n\n")

  } else if (abs_mean_diff < 0.05) {
    cat("⚠ MINOR DIFFERENCE: Small but detectable sensor offset (0.02-0.05 NDVI)\n")
    cat("   This may be within measurement uncertainty.\n")
    cat("   Consider whether this magnitude matters for your drought thresholds.\n\n")
    cat("   Options:\n")
    cat("   1. Proceed without correction (conservative approach)\n")
    cat("   2. Apply simple offset correction (subtract mean difference)\n")
    cat("   3. Use sensors separately, combine after anomaly calculation\n\n")

  } else {
    cat("❌ SIGNIFICANT DIFFERENCE: Sensor offset >0.05 NDVI detected\n")
    cat("   This is larger than expected for harmonized HLS data.\n")
    cat("   Possible causes:\n")
    cat("   - Remaining cloud contamination despite Fmask\n")
    cat("   - Temporal sampling bias (check monthly patterns)\n")
    cat("   - Regional BRDF effects not fully corrected\n\n")
    cat("   Recommended actions:\n")
    cat("   1. Review Bland-Altman and monthly difference plots\n")
    cat("   2. Check if difference varies with NDVI magnitude or season\n")
    cat("   3. Consider sensor-specific analysis or correction\n\n")
  }

  # Contextual guidance
  cat("Context for Drought Monitoring:\n")
  cat("  - Typical drought NDVI anomalies: 0.05-0.15 units\n")
  cat("  - Sensor difference as % of drought signal:",
      round(100 * abs_mean_diff / 0.10, 1), "%\n")
  cat("  - If difference is <20% of expected drought signal, may be acceptable\n\n")

  cat("NASA HLS Documentation:\n")
  cat("  HLS products are radiometrically harmonized for BRDF, spectral bandpass,\n")
  cat("  and surface reflectance. Small residual differences (<0.02) are expected.\n")
  cat("  Larger differences may indicate data quality issues or sampling artifacts.\n\n")

  cat("Next Steps:\n")
  cat("1. Review diagnostic plots in:", file.path(hls_paths$figures, "sensor_diagnostics_paired"), "\n")
  cat("2. Based on results, decide on sensor handling strategy\n")
  cat("3. Proceed to climatology and anomaly calculation\n\n")
}

######################
# Main Execution
######################

run_hls_sensor_diagnostic <- function() {

  cat("\n")
  cat("╔══════════════════════════════════════════════════════════╗\n")
  cat("║   HLS SENSOR DIAGNOSTIC - PAIRED COMPARISON              ║\n")
  cat("║   L30 (Landsat) vs S30 (Sentinel-2)                      ║\n")
  cat("║   Uses temporally matched observations                   ║\n")
  cat("╚══════════════════════════════════════════════════════════╝\n")
  cat("\n")

  # Execute pipeline
  file_list <- get_diagnostic_files()

  if (nrow(file_list) == 0) {
    stop("No files found for analysis. Check configuration and data availability.")
  }

  ndvi_data <- load_diagnostic_data(file_list)

  paired_data <- create_paired_observations(ndvi_data)

  analysis_results <- analyze_paired_differences(paired_data)

  # Use the enriched paired_data with ndvi_diff and ndvi_mean columns
  create_diagnostic_plots(analysis_results$paired_data_enriched, analysis_results)

  make_recommendations(analysis_results)

  # Save results
  results_file <- file.path(hls_paths$processing_logs, "sensor_diagnostic_paired_results.rds")
  saveRDS(list(
    config = DIAGNOSTIC_CONFIG,
    file_list = file_list,
    paired_data = paired_data,
    analysis = analysis_results
  ), results_file)

  cat("✓ Results saved to:", results_file, "\n\n")

  cat("=== DIAGNOSTIC COMPLETE ===\n\n")

  return(list(
    paired_data = paired_data,
    analysis = analysis_results
  ))
}

# Instructions
cat("\n=== HLS SENSOR DIAGNOSTIC READY (PAIRED COMPARISON) ===\n")
cat("This script uses PAIRED observations (same location, close in time)\n")
cat("to properly compare HLS L30 (Landsat) vs S30 (Sentinel) sensors.\n\n")
cat("To run diagnostic:\n")
cat("  results <- run_hls_sensor_diagnostic()\n\n")
cat("Configuration:\n")
cat("  - Years:", paste(DIAGNOSTIC_CONFIG$test_years, collapse = ", "), "\n")
cat("  - Pairing window: ±", DIAGNOSTIC_CONFIG$max_day_difference, "days\n")
cat("  - Pixel sampling:", DIAGNOSTIC_CONFIG$pixel_sample_rate * 100, "%\n\n")
