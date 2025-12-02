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

# Source utility functions
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  anomalies_dir = file.path(hls_paths$gam_models, "modeled_ndvi_anomalies"),
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
# LOAD DATA
# ==============================================================================

cat("Loading anomaly data...\n")

# Get all anomaly files
anomaly_files <- list.files(config$anomalies_dir, pattern = "anomalies_\\d{4}\\.rds", full.names = TRUE)
years <- as.integer(gsub(".*anomalies_(\\d{4})\\.rds", "\\1", basename(anomaly_files)))

# Load and combine all anomalies
all_anomalies <- list()
for (i in seq_along(anomaly_files)) {
  yr <- years[i]
  cat(sprintf("  Loading year %d...\n", yr))

  anoms <- readRDS(anomaly_files[i])
  anoms$year <- yr

  # Create date column (using year + yday)
  anoms$date <- as.Date(sprintf("%d-%03d", yr, anoms$yday), format = "%Y-%j")

  all_anomalies[[i]] <- anoms
}

anomalies_df <- bind_rows(all_anomalies)
cat(sprintf("  Total rows: %s\n\n", format(nrow(anomalies_df), big.mark = ",")))

# ==============================================================================
# TIME SERIES PLOT
# ==============================================================================

cat("Creating time series plot...\n")

# Calculate domain-wide average anomalies by date
timeseries_df <- anomalies_df %>%
  group_by(date, year, yday) %>%
  summarise(
    mean_anom = mean(anoms_mean, na.rm = TRUE),
    lwr_anom = mean(anoms_lwr, na.rm = TRUE),
    upr_anom = mean(anoms_upr, na.rm = TRUE),
    n_pixels = sum(!is.na(anoms_mean)),
    .groups = "drop"
  ) %>%
  arrange(date)

cat(sprintf("  Time series points: %d\n", nrow(timeseries_df)))

# Create plot
p_timeseries <- ggplot(timeseries_df, aes(x = date)) +
  # Error ribbon
  geom_ribbon(aes(ymin = lwr_anom, ymax = upr_anom),
              fill = "skyblue", alpha = 0.3) +
  # Zero line
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
  # Mean anomaly line
  geom_line(aes(y = mean_anom), color = "darkblue", size = 0.8) +
  # Styling
  scale_x_date(date_breaks = "1 year", date_labels = "%Y") +
  labs(
    title = "Domain-Wide NDVI Anomalies (2013-2024)",
    subtitle = "Spatial average across all pixels with uncertainty bounds",
    x = "Date",
    y = "NDVI Anomaly (deviation from long-term normal)",
    caption = sprintf("Data coverage varies by year (2014 limited to 42 days)\\nShaded region: mean ± posterior uncertainty")
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(face = "bold", size = 14),
    plot.subtitle = element_text(color = "gray30"),
    panel.grid.minor = element_blank(),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

# Save time series
ts_file <- file.path(config$output_dir, "timeseries_domain_anomalies.png")
ggsave(ts_file, p_timeseries, width = config$width, height = config$height * 0.7, dpi = config$dpi)
cat(sprintf("  Saved: %s\n\n", ts_file))

# ==============================================================================
# TIME SERIES BY YEAR (FACETED)
# ==============================================================================

cat("Creating faceted time series by year...\n")

p_faceted <- ggplot(timeseries_df, aes(x = yday)) +
  geom_ribbon(aes(ymin = lwr_anom, ymax = upr_anom),
              fill = "skyblue", alpha = 0.3) +
  geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
  geom_line(aes(y = mean_anom), color = "darkblue", size = 0.6) +
  facet_wrap(~ year, ncol = 3) +
  labs(
    title = "NDVI Anomalies by Year (2013-2024)",
    subtitle = "Day-of-year progression for each year",
    x = "Day of Year",
    y = "NDVI Anomaly",
    caption = "Note: 2014 has limited coverage (42 days)"
  ) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold"),
    panel.grid.minor = element_blank(),
    strip.text = element_text(face = "bold")
  )

facet_file <- file.path(config$output_dir, "timeseries_by_year_faceted.png")
ggsave(facet_file, p_faceted, width = config$width, height = config$height * 1.2, dpi = config$dpi)
cat(sprintf("  Saved: %s\n\n", facet_file))

# ==============================================================================
# ANIMATED MAP
# ==============================================================================

cat("Creating animated map...\n")

# Aggregate to weekly to reduce frame count
cat(sprintf("  Aggregating to %d-day intervals...\n", config$aggregate_days))

# Create week bins
anomalies_df <- anomalies_df %>%
  mutate(
    week_of_year = floor((yday - 1) / config$aggregate_days),
    week_label = sprintf("%d-W%02d", year, week_of_year)
  )

# Aggregate by week and pixel
weekly_anoms <- anomalies_df %>%
  group_by(year, week_of_year, week_label, pixel_id, x, y) %>%
  summarise(
    mean_anom = mean(anoms_mean, na.rm = TRUE),
    n_obs = n(),
    .groups = "drop"
  ) %>%
  filter(!is.na(mean_anom))

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
    scale_fill_gradient2(
      low = "brown", mid = "white", high = "darkgreen",
      midpoint = 0, limits = c(-0.3, 0.3), oob = scales::squish,
      name = "NDVI Anomaly"
    ) +
    coord_equal() +
    labs(
      title = sprintf("NDVI Anomalies: %s", wk),
      subtitle = sprintf("%s pixels", format(nrow(week_data), big.mark = ","))
    ) +
    theme_void() +
    theme(
      plot.title = element_text(face = "bold", hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5),
      legend.position = "right"
    )

  map_file <- file.path(config$output_dir, sprintf("map_sample_%s.png", gsub("-", "_", wk)))
  ggsave(map_file, p_map, width = 10, height = 8, dpi = 200)
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
    scale_fill_gradient2(
      low = "brown", mid = "white", high = "darkgreen",
      midpoint = 0, limits = c(-0.3, 0.3), oob = scales::squish,
      name = "NDVI\\nAnomaly"
    ) +
    coord_equal() +
    labs(
      title = sprintf("NDVI Anomalies: %s", wk),
      subtitle = sprintf("%s pixels", format(nrow(week_data), big.mark = ","))
    ) +
    theme_void(base_size = 14) +
    theme(
      plot.title = element_text(face = "bold", hjust = 0.5),
      plot.subtitle = element_text(hjust = 0.5, color = "gray40"),
      legend.position = "right"
    )

  frame_file <- file.path(frames_dir, sprintf("frame_%04d.png", i))
  ggsave(frame_file, p_frame, width = 10, height = 8, dpi = 150)

  setTxtProgressBar(pb, i)
}
close(pb)

cat(sprintf("\n  Saved %d frames to: %s\n", nrow(all_weeks), frames_dir))
cat(sprintf("\n  To create GIF, run from command line:\\n"))
cat(sprintf("    convert -delay 20 -loop 0 %s/frame_*.png %s/anomalies_animated.gif\\n",
            frames_dir, config$output_dir))

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
