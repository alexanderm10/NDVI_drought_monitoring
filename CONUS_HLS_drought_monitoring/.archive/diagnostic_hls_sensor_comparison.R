# HLS Sensor Comparison Diagnostic
# Purpose: Test if HLS.L30 (Landsat) vs HLS.S30 (Sentinel) show residual sensor differences
# Strategy: Subsample pixels and scenes to make analysis tractable at 30m resolution

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

  # Temporal subsampling - focus on recent years with both sensors
  test_years = c(2022, 2023, 2024),  # Sentinel-2A/B + Landsat 8/9 all active

  # Pixel subsampling strategy
  pixel_sample_rate = 0.01,  # 1% of pixels (~10,000-30,000 pixels depending on tile)
  min_pixels = 5000,         # Minimum pixels to sample
  max_pixels = 30000,        # Maximum pixels to sample

  # Scene subsampling
  scenes_per_sensor_per_year = 20,  # Subsample to ~20 scenes per sensor per year

  # Quality filters
  ndvi_valid_range = c(-0.2, 1.0),  # Valid NDVI range
  min_obs_per_pixel = 3             # Minimum observations per pixel for analysis (lowered due to sparse temporal sampling)
)

cat("=== HLS SENSOR DIAGNOSTIC CONFIGURATION ===\n")
cat("Test tile:", DIAGNOSTIC_CONFIG$test_tile, "\n")
cat("Test years:", paste(DIAGNOSTIC_CONFIG$test_years, collapse = ", "), "\n")
cat("Pixel sample rate:", DIAGNOSTIC_CONFIG$pixel_sample_rate * 100, "%\n")
cat("Target pixel range:", DIAGNOSTIC_CONFIG$min_pixels, "-", DIAGNOSTIC_CONFIG$max_pixels, "\n\n")

######################
# Step 1: Get File List and Subsample Scenes
######################

get_diagnostic_files <- function(config = DIAGNOSTIC_CONFIG) {

  cat("=== STEP 1: Building File List ===\n")

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
    # Format: HLS.L30.T13SEA.2024005T173159.v2.0_NDVI.tif
    # or:     HLS.S30.T13SEA.2024005T173159.v2.0_NDVI.tif

    file_df <- data.frame(
      filepath = ndvi_files,
      filename = basename(ndvi_files),
      stringsAsFactors = FALSE
    )

    file_df$sensor <- ifelse(grepl("HLS\\.L30\\.", file_df$filename), "L30_Landsat", "S30_Sentinel")
    file_df$tile <- sub(".*\\.(T[0-9A-Z]+)\\..*", "\\1", file_df$filename)

    # Extract date from filename (format: YYYYDDDTHHMMSS)
    date_string <- sub(".*\\.([0-9]{7}T[0-9]{6})\\..*", "\\1", file_df$filename)
    file_df$year <- as.numeric(substr(date_string, 1, 4))
    file_df$yday <- as.numeric(substr(date_string, 5, 7))
    file_df$date <- as.Date(paste0(file_df$year, "-01-01")) + file_df$yday - 1

    # Filter to test tile (note: HLS tiles are different from our processing tiles)
    # We'll use spatial subsetting instead during read

    cat("Year", year, "- Found", nrow(file_df), "NDVI scenes\n")
    cat("  L30 (Landsat):", sum(file_df$sensor == "L30_Landsat"), "\n")
    cat("  S30 (Sentinel):", sum(file_df$sensor == "S30_Sentinel"), "\n")

    # Subsample scenes per sensor to keep analysis tractable
    file_df_sampled <- file_df %>%
      group_by(sensor) %>%
      slice_sample(n = config$scenes_per_sensor_per_year) %>%
      ungroup()

    cat("  After subsampling:", nrow(file_df_sampled), "scenes\n\n")

    all_files[[as.character(year)]] <- file_df_sampled
  }

  combined_files <- bind_rows(all_files)

  cat("✓ Total scenes selected for analysis:", nrow(combined_files), "\n")
  cat("  L30 (Landsat):", sum(combined_files$sensor == "L30_Landsat"), "\n")
  cat("  S30 (Sentinel):", sum(combined_files$sensor == "S30_Sentinel"), "\n\n")

  return(combined_files)
}

######################
# Step 2: Load Data with Spatial Subsampling
######################

load_diagnostic_data <- function(file_list, config = DIAGNOSTIC_CONFIG) {

  cat("=== STEP 2: Loading NDVI Data with Spatial Subsampling ===\n")

  # Read first file to get extent and establish pixel sampling grid
  first_rast <- rast(file_list$filepath[1])
  cat("First raster dimensions:", dim(first_rast)[1], "rows ×", dim(first_rast)[2], "cols\n")
  cat("Total pixels:", ncell(first_rast), "\n")
  cat("CRS:", crs(first_rast, proj=TRUE), "\n")

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

  cat("Sampling", length(sample_indices), "pixel locations\n\n")

  # Extract coordinates for sampled pixels (will be in raster's native CRS)
  xy <- xyFromCell(first_rast, sample_indices)
  pixel_df <- data.frame(
    pixel_id = 1:nrow(xy),
    x = xy[, 1],
    y = xy[, 2]
  )

  cat("Coordinate range:\n")
  cat("  X:", range(xy[,1]), "\n")
  cat("  Y:", range(xy[,2]), "\n\n")

  # Initialize data storage
  ndvi_data <- list()

  # Load each scene
  pb <- txtProgressBar(min = 0, max = nrow(file_list), style = 3)

  for (i in 1:nrow(file_list)) {

    scene <- file_list[i, ]

    tryCatch({
      # Read raster with error checking
      if (!file.exists(scene$filepath)) {
        cat("⚠ File not found:", scene$filepath, "\n")
        return(NULL)
      }

      rast_ndvi <- rast(scene$filepath)

      # Validate raster
      if (nlyr(rast_ndvi) == 0 || ncell(rast_ndvi) == 0) {
        cat("⚠ Invalid raster:", scene$filename, "\n")
        return(NULL)
      }

      # Extract values at sampled cell indices directly (more robust)
      # Use the same cell indices we sampled earlier
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
          scene_id = scene$filename,
          stringsAsFactors = FALSE
        )
      }

    }, error = function(e) {
      cat("⚠ Error reading", basename(scene$filepath), ":", e$message, "\n")
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
  cat("Date range:", as.character(min(combined_data$date)), "to", as.character(max(combined_data$date)), "\n\n")

  # Filter pixels with minimum observations
  pixel_counts <- combined_data %>%
    group_by(pixel_id) %>%
    summarise(n_obs = n(), .groups = "drop") %>%
    filter(n_obs >= config$min_obs_per_pixel)

  filtered_data <- combined_data %>%
    filter(pixel_id %in% pixel_counts$pixel_id)

  cat("After filtering (≥", config$min_obs_per_pixel, "obs per pixel):\n")
  cat("Retained pixels:", length(unique(filtered_data$pixel_id)), "\n")
  cat("Retained observations:", nrow(filtered_data), "\n\n")

  return(filtered_data)
}

######################
# Step 3: Sensor Comparison Analysis
######################

analyze_sensor_differences <- function(ndvi_data) {

  cat("=== STEP 3: Sensor Comparison Analysis ===\n\n")

  # Summary statistics by sensor
  sensor_summary <- ndvi_data %>%
    group_by(sensor) %>%
    summarise(
      n_obs = n(),
      n_pixels = n_distinct(pixel_id),
      mean_ndvi = mean(ndvi, na.rm = TRUE),
      sd_ndvi = sd(ndvi, na.rm = TRUE),
      median_ndvi = median(ndvi, na.rm = TRUE),
      .groups = "drop"
    )

  cat("--- Sensor Summary Statistics ---\n")
  print(sensor_summary)
  cat("\n")

  # Calculate difference in means
  l30_mean <- sensor_summary$mean_ndvi[sensor_summary$sensor == "L30_Landsat"]
  s30_mean <- sensor_summary$mean_ndvi[sensor_summary$sensor == "S30_Sentinel"]
  mean_diff <- l30_mean - s30_mean

  cat("Mean NDVI difference (L30 - S30):", round(mean_diff, 4), "\n")
  cat("Percent difference:", round(100 * mean_diff / s30_mean, 2), "%\n\n")

  # Seasonal patterns by sensor
  seasonal_pattern <- ndvi_data %>%
    mutate(month = month(date)) %>%
    group_by(sensor, month) %>%
    summarise(
      mean_ndvi = mean(ndvi, na.rm = TRUE),
      sd_ndvi = sd(ndvi, na.rm = TRUE),
      n = n(),
      .groups = "drop"
    )

  cat("--- Seasonal Patterns (by month) ---\n")
  print(seasonal_pattern %>% arrange(month, sensor))
  cat("\n")

  # Test for sensor effect using GAM
  cat("--- GAM Test for Sensor Effects ---\n")

  # Check data availability for GAM
  cat("Data availability for GAM:\n")
  cat("  Total observations:", nrow(ndvi_data), "\n")
  cat("  L30 observations:", sum(ndvi_data$sensor == "L30_Landsat"), "\n")
  cat("  S30 observations:", sum(ndvi_data$sensor == "S30_Sentinel"), "\n")
  cat("  Unique yday values:", length(unique(ndvi_data$yday)), "\n\n")

  # Check if we have enough data for GAM
  if (nrow(ndvi_data) < 100) {
    cat("⚠ Insufficient data for GAM fitting (< 100 observations)\n")
    cat("Skipping GAM analysis. Try adjusting NDVI valid range or increasing sample size.\n\n")

    return(list(
      summary = sensor_summary,
      seasonal = seasonal_pattern,
      gam_model = NULL,
      mean_difference = mean_diff,
      sensor_coefficient = NA
    ))
  }

  # Check both sensors are present
  if (sum(ndvi_data$sensor == "L30_Landsat") < 20 || sum(ndvi_data$sensor == "S30_Sentinel") < 20) {
    cat("⚠ Insufficient data for one or both sensors (< 20 obs each)\n")
    cat("Skipping GAM analysis.\n\n")

    return(list(
      summary = sensor_summary,
      seasonal = seasonal_pattern,
      gam_model = NULL,
      mean_difference = mean_diff,
      sensor_coefficient = NA
    ))
  }

  cat("Fitting model: NDVI ~ s(yday, by=sensor) + sensor\n")

  # Subsample further for GAM if needed (GAMs can be slow with large data)
  if (nrow(ndvi_data) > 50000) {
    cat("Subsampling to 50,000 observations for GAM fitting...\n")
    gam_data <- ndvi_data %>% slice_sample(n = 50000)
  } else {
    gam_data <- ndvi_data
  }

  # Make sure sensor is a factor for GAM
  gam_data$sensor <- as.factor(gam_data$sensor)

  gam_sensor <- try(gam(ndvi ~ s(yday, k = 12, by = sensor) + sensor, data = gam_data), silent = FALSE)

  if (inherits(gam_sensor, "try-error")) {
    cat("⚠ GAM fitting failed. Using simpler analysis.\n\n")

    return(list(
      summary = sensor_summary,
      seasonal = seasonal_pattern,
      gam_model = NULL,
      mean_difference = mean_diff,
      sensor_coefficient = NA
    ))
  }

  cat("\nGAM Summary:\n")
  print(summary(gam_sensor))

  # Extract sensor effect size
  sensor_coef <- coef(gam_sensor)["sensorS30_Sentinel"]
  cat("\nSensor coefficient (S30 vs L30):", round(sensor_coef, 4), "\n")
  cat("(Positive = S30 higher, Negative = S30 lower)\n\n")

  return(list(
    summary = sensor_summary,
    seasonal = seasonal_pattern,
    gam_model = gam_sensor,
    mean_difference = mean_diff,
    sensor_coefficient = sensor_coef
  ))
}

######################
# Step 4: Visualization
######################

create_diagnostic_plots <- function(ndvi_data, analysis_results) {

  cat("=== STEP 4: Creating Diagnostic Plots ===\n")

  output_dir <- file.path(hls_paths$figures, "sensor_diagnostics")
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  # Plot 1: NDVI distribution by sensor
  p1 <- ggplot(ndvi_data, aes(x = ndvi, fill = sensor)) +
    geom_density(alpha = 0.5) +
    scale_fill_manual(values = c("L30_Landsat" = "#1f77b4", "S30_Sentinel" = "#ff7f0e")) +
    labs(title = "HLS NDVI Distribution by Sensor",
         subtitle = paste("Midwest DEWS |", paste(unique(ndvi_data$year), collapse = ", ")),
         x = "NDVI", y = "Density") +
    theme_minimal() +
    theme(panel.background = element_rect(fill = "white", color = NA),
          plot.background = element_rect(fill = "white", color = NA))

  ggsave(file.path(output_dir, "01_ndvi_distribution_by_sensor.png"),
         p1, width = 8, height = 5, dpi = 300, bg = "white")
  cat("✓ Saved: 01_ndvi_distribution_by_sensor.png\n")

  # Plot 2: Seasonal patterns
  p2 <- ggplot(analysis_results$seasonal, aes(x = month, y = mean_ndvi, color = sensor, group = sensor)) +
    geom_line(size = 1) +
    geom_point(size = 2) +
    geom_errorbar(aes(ymin = mean_ndvi - sd_ndvi, ymax = mean_ndvi + sd_ndvi),
                  width = 0.2, alpha = 0.5) +
    scale_color_manual(values = c("L30_Landsat" = "#1f77b4", "S30_Sentinel" = "#ff7f0e")) +
    scale_x_continuous(breaks = 1:12) +
    labs(title = "Seasonal NDVI Patterns by Sensor",
         x = "Month", y = "Mean NDVI (±SD)") +
    theme_minimal() +
    theme(panel.background = element_rect(fill = "white", color = NA),
          plot.background = element_rect(fill = "white", color = NA))

  ggsave(file.path(output_dir, "02_seasonal_patterns_by_sensor.png"),
         p2, width = 10, height = 5, dpi = 300, bg = "white")
  cat("✓ Saved: 02_seasonal_patterns_by_sensor.png\n")

  # Plot 3: Scatter plot L30 vs S30 (matched pixels/dates if possible)
  paired_data <- ndvi_data %>%
    select(pixel_id, date, sensor, ndvi) %>%
    pivot_wider(names_from = sensor, values_from = ndvi, values_fn = mean) %>%
    filter(!is.na(L30_Landsat) & !is.na(S30_Sentinel))

  if (nrow(paired_data) > 100) {
    p3 <- ggplot(paired_data, aes(x = L30_Landsat, y = S30_Sentinel)) +
      geom_hex(bins = 50) +
      geom_abline(slope = 1, intercept = 0, color = "red", linetype = "dashed") +
      scale_fill_viridis_c() +
      labs(title = "HLS L30 vs S30 NDVI Comparison",
           subtitle = paste(nrow(paired_data), "paired observations"),
           x = "L30 (Landsat) NDVI", y = "S30 (Sentinel) NDVI") +
      theme_minimal() +
      theme(panel.background = element_rect(fill = "white", color = NA),
            plot.background = element_rect(fill = "white", color = NA))

    ggsave(file.path(output_dir, "03_l30_vs_s30_scatter.png"),
           p3, width = 7, height = 7, dpi = 300, bg = "white")
    cat("✓ Saved: 03_l30_vs_s30_scatter.png\n")
  }

  # Plot 4: GAM predictions (only if GAM succeeded)
  if (!is.null(analysis_results$gam_model)) {
    newdata <- expand.grid(
      yday = 1:365,
      sensor = c("L30_Landsat", "S30_Sentinel")
    )
    newdata$pred <- predict(analysis_results$gam_model, newdata = newdata)

    p4 <- ggplot(newdata, aes(x = yday, y = pred, color = sensor)) +
      geom_line(linewidth = 1) +
      scale_color_manual(values = c("L30_Landsat" = "#1f77b4", "S30_Sentinel" = "#ff7f0e")) +
      labs(title = "GAM Seasonal Patterns by Sensor",
           subtitle = "Smoothed day-of-year curves",
           x = "Day of Year", y = "Predicted NDVI") +
      theme_minimal() +
      theme(panel.background = element_rect(fill = "white", color = NA),
            plot.background = element_rect(fill = "white", color = NA))

    ggsave(file.path(output_dir, "04_gam_seasonal_curves.png"),
           p4, width = 10, height = 5, dpi = 300, bg = "white")
    cat("✓ Saved: 04_gam_seasonal_curves.png\n")
  } else {
    cat("⚠ Skipping GAM plot (model fitting failed)\n")
  }

  cat("\n✓ All plots saved to:", output_dir, "\n\n")
}

######################
# Step 5: Recommendations
######################

make_recommendations <- function(analysis_results) {

  cat("=== STEP 5: RECOMMENDATIONS ===\n\n")

  abs_mean_diff <- abs(analysis_results$mean_difference)
  abs_sensor_coef <- abs(analysis_results$sensor_coefficient)

  cat("Analysis Results:\n")
  cat("  Mean NDVI difference (L30-S30):", round(analysis_results$mean_difference, 4), "\n")
  cat("  GAM sensor coefficient:", round(analysis_results$sensor_coefficient, 4), "\n\n")

  # Decision criteria
  if (abs_mean_diff < 0.02 & abs_sensor_coef < 0.02) {
    cat("✅ RECOMMENDATION: No sensor correction needed\n")
    cat("   HLS harmonization is sufficient for drought monitoring.\n")
    cat("   Combine L30 and S30 data directly.\n\n")
    cat("   Justification:\n")
    cat("   - Mean difference < 0.02 NDVI units (acceptable for drought analysis)\n")
    cat("   - GAM sensor effect < 0.02 (minimal residual bias)\n")
    cat("   - Proceed directly to climatology/anomaly calculation\n\n")

  } else if (abs_mean_diff < 0.05 & abs_sensor_coef < 0.05) {
    cat("⚠ RECOMMENDATION: Optional minor sensor correction\n")
    cat("   Consider simple offset correction or proceed without.\n\n")
    cat("   Option 1: Apply constant offset adjustment\n")
    cat("   Option 2: Use L30 and S30 separately, combine after anomaly calculation\n")
    cat("   Option 3: Proceed without correction (conservative approach)\n\n")

  } else {
    cat("❌ RECOMMENDATION: Sensor correction required\n")
    cat("   Significant residual sensor differences detected.\n\n")
    cat("   Suggested approach:\n")
    cat("   1. Fit pixel-by-pixel GAMs: NDVI ~ s(yday, k=12, by=sensor) + sensor\n")
    cat("   2. Reproject S30 to L30 reference (similar to Juliana's approach)\n")
    cat("   3. Use reprojected NDVI for downstream analysis\n\n")
  }

  cat("Next Steps:\n")
  cat("1. Review diagnostic plots in:", file.path(hls_paths$figures, "sensor_diagnostics"), "\n")
  cat("2. Decide on sensor handling approach based on analysis domain requirements\n")
  cat("3. Proceed to spatial analysis workflow\n\n")
}

######################
# Main Execution
######################

run_hls_sensor_diagnostic <- function() {

  cat("\n")
  cat("╔══════════════════════════════════════════════════════════╗\n")
  cat("║   HLS SENSOR COMPARISON DIAGNOSTIC                       ║\n")
  cat("║   L30 (Landsat) vs S30 (Sentinel-2)                      ║\n")
  cat("╚══════════════════════════════════════════════════════════╝\n")
  cat("\n")

  # Execute pipeline
  file_list <- get_diagnostic_files()

  if (nrow(file_list) == 0) {
    stop("No files found for analysis. Check configuration and data availability.")
  }

  ndvi_data <- load_diagnostic_data(file_list)

  analysis_results <- analyze_sensor_differences(ndvi_data)

  create_diagnostic_plots(ndvi_data, analysis_results)

  make_recommendations(analysis_results)

  # Save results
  results_file <- file.path(hls_paths$processing_logs, "sensor_diagnostic_results.rds")
  saveRDS(list(
    config = DIAGNOSTIC_CONFIG,
    file_list = file_list,
    data_summary = summary(ndvi_data),
    analysis = analysis_results
  ), results_file)

  cat("✓ Results saved to:", results_file, "\n\n")

  cat("=== DIAGNOSTIC COMPLETE ===\n\n")

  return(list(
    data = ndvi_data,
    analysis = analysis_results
  ))
}

# Instructions
cat("\n=== HLS SENSOR DIAGNOSTIC READY ===\n")
cat("This script compares HLS L30 (Landsat) vs S30 (Sentinel) to determine\n")
cat("if additional sensor correction is needed beyond NASA's harmonization.\n\n")
cat("To run diagnostic:\n")
cat("  results <- run_hls_sensor_diagnostic()\n\n")
cat("Configuration:\n")
cat("  - Test tile:", DIAGNOSTIC_CONFIG$test_tile, "\n")
cat("  - Years:", paste(DIAGNOSTIC_CONFIG$test_years, collapse = ", "), "\n")
cat("  - Pixel sampling:", DIAGNOSTIC_CONFIG$pixel_sample_rate * 100, "%\n\n")
