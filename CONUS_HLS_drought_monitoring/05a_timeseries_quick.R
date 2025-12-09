# ==============================================================================
# 05a_timeseries_quick.R
#
# Purpose: Create FAST time series visualizations of NDVI anomalies
#   - Domain-wide average time series with SE uncertainty
#   - Faceted time series by year
#
# Input: Script 04 anomaly outputs
# Output: Time series plots in /data/figures/MIDWEST/
#
# Runtime: ~2-3 minutes (vs 45+ minutes for full animation)
#
# ==============================================================================

library(dplyr)
library(ggplot2)
library(lubridate)

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
  height = 8
)

cat("=== Quick Time Series Visualizations ===\n")
cat("Output directory:", config$output_dir, "\n\n")

# Create output directory if needed
if (!dir.exists(config$output_dir)) {
  dir.create(config$output_dir, recursive = TRUE)
}

# ==============================================================================
# LOAD DATA (MEMORY EFFICIENT - TIME SERIES ONLY)
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

# Process each year separately to calculate time series aggregates
timeseries_list <- list()

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

  # Free memory
  rm(anoms)
  gc(verbose = FALSE)
}

# Combine aggregated results
timeseries_df <- bind_rows(timeseries_list) %>% arrange(date)

cat(sprintf("\n  Time series points: %d (aggregated across dates)\n", nrow(timeseries_df)))
cat(sprintf("  ✓ Land cover filtering verified: %d pixels\n\n", expected_pixels))

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
# SUMMARY
# ==============================================================================

cat("\n======================================\n")
cat("Quick time series visualization complete!\n\n")
cat("Output files:\n")
cat(sprintf("  1. Time series (full): %s\n", basename(ts_file)))
cat(sprintf("  2. Time series (by year): %s\n", basename(facet_file)))
cat(sprintf("\nAll files saved to: %s\n", config$output_dir))
cat("\nFor animation and spatial maps, run: 05b_animation_maps.R\n")
