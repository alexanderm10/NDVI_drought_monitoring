# ==============================================================================
# 07_visualize_derivatives.R
#
# Purpose: Visualize change rate derivatives to identify drought stress timing
#
# Creates:
#   - Spatial maps of change rate anomalies for each time window
#   - Time series of change rates through the season
#   - Comparison panels across time windows
#   - Maps highlighting significant rapid browning/greening events
#
# Input:
#   - Change derivatives from script 06: derivatives_YYYY.rds
#   - Valid pixels with coordinates: valid_pixels_landcover_filtered.rds
#
# Output:
#   - Sample maps for different time windows
#   - Time series plots
#   - Comparison figures
#
# ==============================================================================

library(dplyr)
library(ggplot2)
library(sf)
library(maps)

# Source utility functions
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Input directories
  derivatives_dir = file.path(hls_paths$gam_models, "change_derivatives"),
  valid_pixels_file = file.path(hls_paths$gam_models, "valid_pixels_landcover_filtered.rds"),

  # Output directory
  output_dir = "/data/figures/DERIVATIVES",

  # Years to visualize (matching Script 05 data range: 2013-2024)
  years = c(2013, 2016, 2020, 2024),  # Mix of drought and normal years

  # Time windows
  windows = c(3, 7, 14, 30),

  # Sample weeks for detailed maps
  n_sample_maps = 8
)

# Create output directory
if (!dir.exists(config$output_dir)) {
  dir.create(config$output_dir, recursive = TRUE)
}

cat("=== Visualize Change Derivatives ===\n")
cat("Output:", config$output_dir, "\n\n")

# ==============================================================================
# LOAD DATA
# ==============================================================================

# Load valid pixels with coordinates
cat("Loading pixel coordinates...\n")
valid_pixels_df <- readRDS(config$valid_pixels_file)
cat(sprintf("  Pixels: %s\n", format(nrow(valid_pixels_df), big.mark = ",")))

# Load state boundaries for maps
cat("Loading state boundaries...\n")
states_wgs84 <- st_as_sf(map("state", plot = FALSE, fill = TRUE))
states_albers <- st_transform(states_wgs84, crs = "EPSG:5070")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Create spatial map of change rate anomalies
plot_derivative_map <- function(data, title, subtitle = NULL) {
  ggplot(data, aes(x = x, y = y, fill = anomaly_change_mean)) +
    geom_raster() +
    geom_sf(data = states_albers, fill = NA, color = "black",
            linewidth = 0.3, inherit.aes = FALSE) +
    scale_fill_gradient2(
      low = "brown", mid = "white", high = "darkgreen",
      midpoint = 0,
      limits = c(-0.05, 0.05),
      oob = scales::squish,
      name = "Change Rate\nAnomaly"
    ) +
    coord_sf(expand = FALSE) +
    labs(
      title = title,
      subtitle = subtitle
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
}

#' Create spatial map of significant changes only
plot_significant_changes <- function(data, title, subtitle = NULL) {
  # Filter to significant changes only
  sig_data <- data %>% filter(significant == TRUE)

  ggplot(sig_data, aes(x = x, y = y, fill = anomaly_change_mean)) +
    geom_raster() +
    geom_sf(data = states_albers, fill = NA, color = "black",
            linewidth = 0.3, inherit.aes = FALSE) +
    scale_fill_gradient2(
      low = "brown", mid = "gray90", high = "darkgreen",
      midpoint = 0,
      limits = c(-0.05, 0.05),
      oob = scales::squish,
      name = "Change Rate\nAnomaly"
    ) +
    coord_sf(expand = FALSE) +
    labs(
      title = title,
      subtitle = subtitle
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
}

# ==============================================================================
# CREATE VISUALIZATIONS FOR EACH YEAR
# ==============================================================================

for (yr in config$years) {
  cat(sprintf("\n=== Processing Year %d ===\n", yr))

  # Load derivative data
  deriv_file <- file.path(config$derivatives_dir, sprintf("derivatives_%d.rds", yr))
  if (!file.exists(deriv_file)) {
    cat(sprintf("  Skipping %d - no derivative file\n", yr))
    next
  }

  cat("  Loading derivative data...\n")
  deriv_df <- readRDS(deriv_file)
  cat(sprintf("    Rows: %s\n", format(nrow(deriv_df), big.mark = ",")))

  # Join with pixel coordinates
  deriv_spatial <- deriv_df %>%
    left_join(valid_pixels_df, by = "pixel_id")

  # Calculate summary statistics
  n_total <- nrow(deriv_spatial)
  n_significant <- sum(deriv_spatial$significant, na.rm = TRUE)
  pct_significant <- 100 * n_significant / n_total

  cat(sprintf("    Significant changes: %s of %s (%.1f%%)\n",
              format(n_significant, big.mark = ","),
              format(n_total, big.mark = ","),
              pct_significant))

  # ============================================================================
  # 1. SAMPLE MAPS FOR EACH TIME WINDOW
  # ============================================================================

  cat("  Creating sample maps for each time window...\n")

  for (win in config$windows) {
    # Get data for this window
    win_data <- deriv_spatial %>% filter(window == win)

    # Select sample weeks
    sample_weeks <- win_data %>%
      group_by(yday) %>%
      summarise(
        n = n(),
        mean_anom = mean(abs(anomaly_change_mean), na.rm = TRUE),
        .groups = "drop"
      ) %>%
      filter(n > 50000) %>%  # Ensure good coverage
      arrange(desc(mean_anom)) %>%  # Prioritize high anomaly days
      slice_head(n = config$n_sample_maps) %>%
      pull(yday)

    for (doy in sample_weeks) {
      doy_data <- win_data %>% filter(yday == doy)

      if (nrow(doy_data) == 0) next

      # Map of all change rate anomalies
      p_all <- plot_derivative_map(
        doy_data,
        title = sprintf("%d DOY %03d - %d-day Window", yr, doy, win),
        subtitle = sprintf("%s pixels", format(nrow(doy_data), big.mark = ","))
      )

      map_file <- file.path(config$output_dir,
                           sprintf("map_%d_doy%03d_win%02d.png", yr, doy, win))
      ggsave(map_file, p_all, width = 10, height = 8, dpi = 200, bg = "white")

      # Map of significant changes only
      n_sig <- sum(doy_data$significant, na.rm = TRUE)
      if (n_sig > 0) {
        p_sig <- plot_significant_changes(
          doy_data,
          title = sprintf("%d DOY %03d - Significant Changes (%d-day)", yr, doy, win),
          subtitle = sprintf("%s significant pixels (%.1f%%)",
                           format(n_sig, big.mark = ","),
                           100 * n_sig / nrow(doy_data))
        )

        sig_file <- file.path(config$output_dir,
                             sprintf("significant_%d_doy%03d_win%02d.png", yr, doy, win))
        ggsave(sig_file, p_sig, width = 10, height = 8, dpi = 200, bg = "white")
      }
    }

    cat(sprintf("    Window %d days: %d sample maps created\n",
                win, length(sample_weeks)))
  }

  # ============================================================================
  # 2. TIME SERIES OF CHANGE RATES (DOMAIN AVERAGE)
  # ============================================================================

  cat("  Creating time series...\n")

  # Calculate domain-average change rates
  timeseries_df <- deriv_spatial %>%
    group_by(yday, window) %>%
    summarise(
      mean_baseline = mean(baseline_change_mean, na.rm = TRUE),
      mean_year = mean(year_change_mean, na.rm = TRUE),
      mean_anomaly = mean(anomaly_change_mean, na.rm = TRUE),
      se_anomaly = sd(anomaly_change_mean, na.rm = TRUE) / sqrt(n()),
      lwr_anomaly = mean_anomaly - 1.96 * se_anomaly,
      upr_anomaly = mean_anomaly + 1.96 * se_anomaly,
      pct_significant = 100 * sum(significant, na.rm = TRUE) / n(),
      .groups = "drop"
    ) %>%
    mutate(window_label = sprintf("%d-day", window))

  # Month breaks for x-axis
  month_breaks <- c(1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335)
  month_labels <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun",
                    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

  # Plot change rate anomalies for all windows
  p_ts <- ggplot(timeseries_df, aes(x = yday, color = window_label, fill = window_label)) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "gray40") +
    geom_ribbon(aes(ymin = lwr_anomaly, ymax = upr_anomaly),
                alpha = 0.2, color = NA) +
    geom_line(aes(y = mean_anomaly), linewidth = 0.8) +
    scale_color_brewer(palette = "Set1", name = "Time Window") +
    scale_fill_brewer(palette = "Set1", name = "Time Window") +
    scale_x_continuous(breaks = month_breaks, labels = month_labels) +
    labs(
      title = sprintf("Change Rate Anomalies: %d", yr),
      subtitle = "Domain average with 95% confidence intervals",
      x = "Day of Year",
      y = "Change Rate Anomaly (NDVI/day)"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold"),
      panel.grid.minor = element_blank(),
      plot.background = element_rect(fill = "white", colour = NA),
      panel.background = element_rect(fill = "white", colour = NA),
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "bottom"
    )

  ts_file <- file.path(config$output_dir, sprintf("timeseries_%d.png", yr))
  ggsave(ts_file, p_ts, width = 12, height = 6, dpi = 200, bg = "white")

  # Plot percent significant
  p_sig_pct <- ggplot(timeseries_df, aes(x = yday, y = pct_significant,
                                          color = window_label)) +
    geom_line(linewidth = 0.8) +
    scale_color_brewer(palette = "Set1", name = "Time Window") +
    scale_x_continuous(breaks = month_breaks, labels = month_labels) +
    labs(
      title = sprintf("Percent Significant Changes: %d", yr),
      subtitle = "Percentage of pixels with significant change rate anomalies",
      x = "Day of Year",
      y = "% Significant"
    ) +
    theme_minimal(base_size = 12) +
    theme(
      plot.title = element_text(face = "bold"),
      panel.grid.minor = element_blank(),
      plot.background = element_rect(fill = "white", colour = NA),
      panel.background = element_rect(fill = "white", colour = NA),
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "bottom"
    )

  sig_pct_file <- file.path(config$output_dir, sprintf("significant_pct_%d.png", yr))
  ggsave(sig_pct_file, p_sig_pct, width = 12, height = 6, dpi = 200, bg = "white")

  cat(sprintf("  Year %d complete\n", yr))
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n=== Visualization Complete ===\n")
cat(sprintf("Output directory: %s\n", config$output_dir))
cat("\nCreated:\n")
cat("  - Sample maps for each time window\n")
cat("  - Maps of significant changes only\n")
cat("  - Time series of change rate anomalies\n")
cat("  - Percent significant change over time\n")
