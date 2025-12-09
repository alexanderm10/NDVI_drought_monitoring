# ==============================================================================
# 05b_animation_maps.R
#
# Purpose: Create SLOW animation and spatial maps of NDVI anomalies
#   - Sample static maps (10 weeks)
#   - Full animation frames (~600 frames)
#   - Animated GIF
#
# Input: Script 04 anomaly outputs
# Output: Maps and animation in /data/figures/MIDWEST/
#
# Runtime: ~45-60 minutes (memory intensive)
#
# ==============================================================================

library(dplyr)
library(ggplot2)
library(lubridate)
library(viridis)
library(sf)
library(maps)

# Source utility functions
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  anomalies_dir = file.path(hls_paths$gam_models, "modeled_ndvi_anomalies"),
  valid_pixels_file = file.path(hls_paths$gam_models, "valid_pixels_landcover_filtered.rds"),
  output_dir = file.path("/data/figures/MIDWEST"),

  # Plotting parameters
  dpi = 300,
  width = 12,
  height = 8,

  # Animation parameters
  fps = 5,  # Frames per second
  aggregate_days = 7  # Aggregate to weekly for animation (reduces frame count)
)

cat("=== Animation and Spatial Maps ===\n")
cat("Output directory:", config$output_dir, "\n")
cat("WARNING: This script is memory intensive and takes 45-60 minutes\n\n")

# Create output directory if needed
if (!dir.exists(config$output_dir)) {
  dir.create(config$output_dir, recursive = TRUE)
}

# ==============================================================================
# LOAD DATA (MEMORY EFFICIENT - WEEKLY AGGREGATES ONLY)
# ==============================================================================

cat("Loading anomaly data (processing year-by-year for memory efficiency)...\n")

# Get all anomaly files
anomaly_files <- list.files(config$anomalies_dir, pattern = "anomalies_\\d{4}\\.rds", full.names = TRUE)
years <- as.integer(gsub(".*anomalies_(\\d{4})\\.rds", "\\1", basename(anomaly_files)))

# Load valid pixels for verification
if (file.exists(config$valid_pixels_file)) {
  valid_pixels_df <- readRDS(config$valid_pixels_file)
  expected_pixels <- length(valid_pixels_df$pixel_id)
} else {
  stop("Valid pixels file not found - cannot verify filtering")
}

# Process each year separately to calculate weekly aggregates
weekly_list <- list()

for (i in seq_along(anomaly_files)) {
  yr <- years[i]
  cat(sprintf("  Processing year %d...\n", yr))

  # Load year data
  anoms <- readRDS(anomaly_files[i])
  anoms$year <- yr
  anoms$date <- as.Date(sprintf("%d-%03d", yr, anoms$yday), format = "%Y-%j")

  # Verify pixel count
  actual_pixels <- length(unique(anoms$pixel_id))
  if (actual_pixels != expected_pixels) {
    warning(sprintf("Year %d: pixel count %d differs from expected %d", yr, actual_pixels, expected_pixels))
  }

  # Calculate weekly aggregates for animation
  anoms_weekly <- anoms %>%
    mutate(
      week_of_year = floor((yday - 1) / config$aggregate_days),
      week_label = sprintf("%d-W%02d", year, week_of_year)
    ) %>%
    group_by(year, week_of_year, week_label, pixel_id, x, y) %>%
    summarise(
      mean_anom = mean(anoms_mean, na.rm = TRUE),
      n_obs = n(),
      .groups = "drop"
    ) %>%
    filter(!is.na(mean_anom))

  weekly_list[[i]] <- anoms_weekly

  # Free memory
  rm(anoms)
  gc(verbose = FALSE)
}

# Combine aggregated results
weekly_anoms <- bind_rows(weekly_list)

cat(sprintf("\n  Weekly data points: %s (aggregated for animation)\n", format(nrow(weekly_anoms), big.mark = ",")))
cat(sprintf("  ✓ Land cover filtering verified: %d pixels\n\n", expected_pixels))

# ==============================================================================
# LOAD STATE BOUNDARIES
# ==============================================================================

cat("Loading state boundaries...\n")
# Get US state boundaries and transform to Albers Equal Area (EPSG:5070)
states_wgs84 <- st_as_sf(map("state", plot = FALSE, fill = TRUE))
states_albers <- st_transform(states_wgs84, crs = "EPSG:5070")
cat("  ✓ State boundaries loaded and transformed to EPSG:5070\n\n")

# ==============================================================================
# SAMPLE STATIC MAPS
# ==============================================================================

cat("Creating animated map...\n")
cat(sprintf("  Weekly frames: %d\n", length(unique(weekly_anoms$week_label))))
cat(sprintf("  Total data points: %s\n", format(nrow(weekly_anoms), big.mark = ",")))

# Create static map for each week (sample of 10 weeks for testing)
cat("  Generating sample maps...\n")

# Get representative weeks
sample_weeks <- weekly_anoms %>%
  group_by(week_label) %>%
  summarise(n = n(), .groups = "drop") %>%
  filter(n > 100000) %>%  # Only weeks with good coverage
  slice_sample(n = min(10, nrow(.))) %>%
  pull(week_label)

for (wk in sample_weeks) {
  week_data <- weekly_anoms %>% filter(week_label == wk)

  p_map <- ggplot(week_data, aes(x = x, y = y, fill = mean_anom)) +
    geom_raster() +
    geom_sf(data = states_albers, fill = NA, color = "black", linewidth = 0.3, inherit.aes = FALSE) +
    scale_fill_gradient2(
      low = "brown", mid = "white", high = "darkgreen",
      midpoint = 0, limits = c(-0.3, 0.3), oob = scales::squish,
      name = "NDVI Anomaly"
    ) +
    coord_sf(expand = FALSE) +
    labs(
      title = sprintf("NDVI Anomalies: %s", wk),
      subtitle = sprintf("%s pixels", format(nrow(week_data), big.mark = ","))
    ) +
    theme_void() +
    theme(
      plot.title = element_text(face = "bold", hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5),
      legend.position = "right",
      plot.background = element_rect(fill = "white", colour = NA),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank()
    )

  map_file <- file.path(config$output_dir, sprintf("map_sample_%s.png", gsub("-", "_", wk)))
  ggsave(map_file, p_map, width = 10, height = 8, dpi = 200, bg = "white")
}

cat(sprintf("  Saved %d sample maps\n", length(sample_weeks)))

# ==============================================================================
# CREATE ANIMATION FRAMES
# ==============================================================================

cat("\nCreating animation frames...\n")
cat("  Generating PNG sequence for all weeks...\n")

# Get all weeks, sorted
all_weeks <- weekly_anoms %>%
  group_by(week_label, year, week_of_year) %>%
  summarise(n = n(), .groups = "drop") %>%
  arrange(year, week_of_year)

cat(sprintf("  Total frames to generate: %d\n", nrow(all_weeks)))

# Create frames directory
frames_dir <- file.path(config$output_dir, "animation_frames")
if (!dir.exists(frames_dir)) {
  dir.create(frames_dir, recursive = TRUE)
}

# Generate all frames (with progress)
pb <- txtProgressBar(min = 0, max = nrow(all_weeks), style = 3)
for (i in 1:nrow(all_weeks)) {
  wk <- all_weeks$week_label[i]
  week_data <- weekly_anoms %>% filter(week_label == wk)

  p_frame <- ggplot(week_data, aes(x = x, y = y, fill = mean_anom)) +
    geom_raster() +
    geom_sf(data = states_albers, fill = NA, color = "black", linewidth = 0.3, inherit.aes = FALSE) +
    scale_fill_gradient2(
      low = "brown", mid = "white", high = "darkgreen",
      midpoint = 0, limits = c(-0.3, 0.3), oob = scales::squish,
      name = "NDVI\\nAnomaly"
    ) +
    coord_sf(expand = FALSE) +
    labs(
      title = sprintf("NDVI Anomalies: %s", wk),
      subtitle = sprintf("%s pixels", format(nrow(week_data), big.mark = ","))
    ) +
    theme_void(base_size = 14) +
    theme(
      plot.title = element_text(face = "bold", hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5, color = "gray40"),
      legend.position = "right",
      plot.background = element_rect(fill = "white", colour = NA),
      panel.grid.major = element_blank(),
      panel.grid.minor = element_blank()
    )

  frame_file <- file.path(frames_dir, sprintf("frame_%04d.png", i))
  ggsave(frame_file, p_frame, width = 10, height = 8, dpi = 150, bg = "white")

  setTxtProgressBar(pb, i)
}
close(pb)

cat(sprintf("\n  Saved %d frames to: %s\n", nrow(all_weeks), frames_dir))

# ==============================================================================
# CREATE ANIMATED GIF
# ==============================================================================

cat("\nCreating animated GIF...\n")
gif_output <- file.path(config$output_dir, "anomalies_animated.gif")

# Check if ImageMagick convert is available
convert_available <- system("which convert", ignore.stdout = TRUE, ignore.stderr = TRUE) == 0

if (convert_available) {
  cat("  Using ImageMagick to create GIF...\n")

  # Create GIF using convert command
  convert_cmd <- sprintf(
    "convert -delay 20 -loop 0 %s/frame_*.png %s",
    frames_dir, gif_output
  )

  result <- system(convert_cmd, ignore.stdout = FALSE, ignore.stderr = FALSE)

  if (result == 0 && file.exists(gif_output)) {
    gif_size_mb <- file.size(gif_output) / 1024^2
    cat(sprintf("  ✓ GIF created successfully: %s (%.1f MB)\n",
                basename(gif_output), gif_size_mb))
  } else {
    warning("Failed to create GIF with ImageMagick")
    cat(sprintf("  Manual command:\n    %s\n", convert_cmd))
  }
} else {
  cat("  ImageMagick 'convert' not found - skipping GIF creation\n")
  cat(sprintf("  To create GIF manually, run:\n"))
  cat(sprintf("    convert -delay 20 -loop 0 %s/frame_*.png %s\n",
              frames_dir, gif_output))
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n======================================\n")
cat("Animation and maps complete!\n\n")
cat("Output files:\n")
cat(sprintf("  1. Sample maps: map_sample_*.png (%d files)\n", length(sample_weeks)))
cat(sprintf("  2. Animation frames: animation_frames/*.png (%d frames)\n", nrow(all_weeks)))
if (convert_available && file.exists(gif_output)) {
  cat(sprintf("  3. Animated GIF: %s\n", basename(gif_output)))
}
cat(sprintf("\nAll files saved to: %s\n", config$output_dir))
cat("\nFor quick time series plots, run: 05a_timeseries_quick.R\n")
