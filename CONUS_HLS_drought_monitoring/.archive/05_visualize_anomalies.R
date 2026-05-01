# ==============================================================================
# 05_visualize_anomalies.R
#
# Purpose: Create visualizations of NDVI anomalies
#   1. Time series: Domain-wide average anomaly with error ribbon
#   2. Animated map: Spatial anomalies rolling through dates
#
# Input: Script 04 anomaly outputs
# Output: Figures in /data/figures/MIDWEST/
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

cat("=== Visualize NDVI Anomalies ===\n")
cat("Output directory:", config$output_dir, "\n\n")

# ==============================================================================
# LOAD DATA (MEMORY EFFICIENT)
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

# Process each year separately to calculate aggregates without loading all data
timeseries_list <- list()
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

  # Calculate domain-wide average for time series (aggregate to dates)
  # Use SE of the mean for uncertainty (precision of the aggregate statistic)
  ts_yr <- anoms %>%
    group_by(date, year, yday) %>%
    summarise(
      mean_anom = mean(anoms_mean, na.rm = TRUE),
      sd_anom = sd(anoms_mean, na.rm = TRUE),
      n_pixels = sum(!is.na(anoms_mean)),
      .groups = "drop"
    ) %>%
    mutate(
      se_anom = sd_anom / sqrt(n_pixels),
      lwr_anom = mean_anom - 1.96 * se_anom,  # 95% CI
      upr_anom = mean_anom + 1.96 * se_anom
    )
  timeseries_list[[i]] <- ts_yr

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
  rm(anoms, anoms_weekly)
  gc(verbose = FALSE)
}

# Combine aggregated results (much smaller than raw data)
timeseries_df <- bind_rows(timeseries_list) %>% arrange(date)
weekly_anoms <- bind_rows(weekly_list)

cat(sprintf("\n  Time series points: %d (aggregated across dates)\n", nrow(timeseries_df)))
cat(sprintf("  Weekly data points: %s (aggregated for animation)\n", format(nrow(weekly_anoms), big.mark = ",")))
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
# TIME SERIES PLOT
# ==============================================================================

cat("Creating time series plot...\n")

# Create plot
p_timeseries <- ggplot(timeseries_df, aes(x = date)) +
  # Error ribbon
  geom_ribbon(aes(ymin = lwr_anom, ymax = upr_anom),
              fill = "skyblue", alpha = 0.3) +
  # Zero line
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
  # Mean anomaly line
  geom_line(aes(y = mean_anom), color = "darkblue", size = 0.8) +
  # Add points to show where data exists (makes gaps visually apparent)
  geom_point(aes(y = mean_anom), color = "darkblue", size = 1.2, alpha = 0.6) +
  # Styling
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(
    title = "Domain-Wide NDVI Anomalies (2013-2024)",
    subtitle = "Spatial average across all pixels with uncertainty bounds",
    x = "Date",
    y = "NDVI Anomaly (deviation from long-term normal)",
    caption = sprintf("Data coverage varies by year (gaps indicate insufficient raw data for predictions)\\nShaded region: 95%% CI of domain-wide mean")
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "gray30"),
    panel.grid.minor = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1),
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA)
  )

# Save time series
ts_file <- file.path(config$output_dir, "timeseries_domain_anomalies.png")
ggsave(ts_file, p_timeseries, width = config$width, height = config$height * 0.7, dpi = config$dpi, bg = "white")
cat(sprintf("  Saved: %s\n\n", ts_file))

# ==============================================================================
# TIME SERIES BY YEAR (FACETED)
# ==============================================================================

cat("Creating faceted time series by year...\n")

# Add line grouping to break at gaps (identify continuous segments)
timeseries_df <- timeseries_df %>%
  arrange(year, yday) %>%
  group_by(year) %>%
  mutate(
    gap = c(0, diff(yday)) > 2,  # Gap if more than 2 days between observations
    line_group = cumsum(gap)      # Increment group at each gap
  ) %>%
  ungroup()

# Month breaks for x-axis (approximate day of year for month starts)
month_breaks <- c(1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335)
month_labels <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

p_faceted <- ggplot(timeseries_df, aes(x = yday)) +
  geom_ribbon(aes(ymin = lwr_anom, ymax = upr_anom, group = line_group),
              fill = "skyblue", alpha = 0.3) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
  geom_line(aes(y = mean_anom, group = line_group), color = "darkblue", size = 0.6) +
  geom_point(aes(y = mean_anom), color = "darkblue", size = 0.8, alpha = 0.6) +
  facet_wrap(~ year, ncol = 3) +
  scale_x_continuous(breaks = month_breaks, labels = month_labels) +
  labs(
    title = "NDVI Anomalies by Year (2013-2024)",
    subtitle = "Seasonal progression for each year",
    x = NULL,
    y = "NDVI Anomaly",
    caption = "Note: Gaps indicate insufficient raw data for predictions"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold"),
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

facet_file <- file.path(config$output_dir, "timeseries_by_year_faceted.png")
ggsave(facet_file, p_faceted, width = config$width, height = config$height * 1.2, dpi = config$dpi, bg = "white")
cat(sprintf("  Saved: %s\n\n", facet_file))

# ==============================================================================
# ANIMATED MAP
# ==============================================================================

cat("Creating animated map...\n")
cat(sprintf("  Weekly frames: %d\n", length(unique(weekly_anoms$week_label))))
cat(sprintf("  Total data points: %s\n", format(nrow(weekly_anoms), big.mark = ",")))

# Create static map for each week (sample from specific years)
cat("  Generating sample maps...\n")

# Target years for sample maps (consistent with derivative visualizations)
sample_years <- c(2013, 2016, 2020, 2021, 2023, 2024)

# Get representative weeks from target years
sample_weeks <- weekly_anoms %>%
  filter(year %in% sample_years) %>%
  group_by(week_label, year) %>%
  summarise(n_pixels = n(), .groups = "drop") %>%
  filter(n_pixels > 100000) %>%  # Only weeks with good coverage
  group_by(year) %>%
  slice_head(n = 2) %>%  # 2 samples per year
  ungroup() %>%
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

# Automatically create GIF using ImageMagick (if available)
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
cat("Visualization complete!\n\n")
cat("Output files:\n")
cat(sprintf("  1. Time series (full): %s\n", basename(ts_file)))
cat(sprintf("  2. Time series (by year): %s\n", basename(facet_file)))
cat(sprintf("  3. Sample maps: map_sample_*.png (%d files)\n", length(sample_weeks)))
cat(sprintf("  4. Animation frames: animation_frames/*.png\n"))
cat(sprintf("\nAll files saved to: %s\n", config$output_dir))
