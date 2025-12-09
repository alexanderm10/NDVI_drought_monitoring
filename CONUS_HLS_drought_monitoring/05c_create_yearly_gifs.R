# ==============================================================================
# 05c_create_yearly_gifs.R
#
# Purpose: Create yearly GIF animations from existing frames
#   - Splits the 446 frames into 12 yearly GIFs
#   - Much more manageable for ImageMagick (30-40 frames each)
#
# Prerequisites: Run 05_visualize_anomalies.R or 05b_animation_maps.R first
#
# ==============================================================================

library(dplyr)

# ==============================================================================
# CONFIGURATION
# ==============================================================================

frames_dir <- "/data/figures/MIDWEST/animation_frames"
output_dir <- "/data/figures/MIDWEST"

cat("=== Create Yearly GIF Animations ===\n")
cat("Frames directory:", frames_dir, "\n")
cat("Output directory:", output_dir, "\n\n")

# Check if frames exist
if (!dir.exists(frames_dir)) {
  stop("Animation frames directory not found. Run script 05 first.")
}

# Get all frame files
frame_files <- list.files(frames_dir, pattern = "frame_\\d{4}\\.png", full.names = FALSE)
n_frames <- length(frame_files)

if (n_frames == 0) {
  stop("No animation frames found. Run script 05 first.")
}

cat(sprintf("Found %d total frames\n", n_frames))

# Load the weekly data to get year-frame mapping
# We need to reconstruct which frames belong to which year
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()

anomalies_dir <- file.path(hls_paths$gam_models, "modeled_ndvi_anomalies")
anomaly_files <- list.files(anomalies_dir, pattern = "anomalies_\\d{4}\\.rds", full.names = TRUE)
years <- as.integer(gsub(".*anomalies_(\\d{4})\\.rds", "\\1", basename(anomaly_files)))
years <- sort(years)

# Build frame-to-year mapping by processing same logic as 05
cat("\nBuilding frame-to-year mapping...\n")

aggregate_days <- 7
weekly_list <- list()

for (i in seq_along(anomaly_files)) {
  yr <- years[i]

  anoms <- readRDS(anomaly_files[i])
  anoms$year <- yr

  # Calculate weekly aggregates (same as script 05)
  anoms_weekly <- anoms %>%
    mutate(
      week_of_year = floor((yday - 1) / aggregate_days),
      week_label = sprintf("%d-W%02d", year, week_of_year)
    ) %>%
    group_by(year, week_of_year, week_label) %>%
    summarise(n = n(), .groups = "drop")

  weekly_list[[i]] <- anoms_weekly
  rm(anoms)
}

# Combine and sort (same order as script 05)
all_weeks <- bind_rows(weekly_list) %>%
  arrange(year, week_of_year) %>%
  mutate(frame_num = row_number())

cat(sprintf("  Total weeks/frames: %d\n", nrow(all_weeks)))

# ==============================================================================
# CREATE YEARLY GIFS
# ==============================================================================

cat("\nCreating yearly GIF animations...\n")

# Check if ImageMagick is available
convert_available <- system("which convert", ignore.stdout = TRUE, ignore.stderr = TRUE) == 0

if (!convert_available) {
  stop("ImageMagick 'convert' not found. Please install ImageMagick.")
}

for (yr in years) {
  cat(sprintf("  Processing year %d...\n", yr))

  # Get frame numbers for this year
  year_frames <- all_weeks %>% filter(year == yr)
  n_year_frames <- nrow(year_frames)

  if (n_year_frames == 0) {
    cat(sprintf("    No frames for year %d, skipping\n", yr))
    next
  }

  # Create temporary file list for this year
  frame_list_file <- tempfile(fileext = ".txt")
  frame_paths <- file.path(frames_dir, sprintf("frame_%04d.png", year_frames$frame_num))
  writeLines(frame_paths, frame_list_file)

  # Create GIF for this year
  gif_output <- file.path(output_dir, sprintf("anomalies_%d.gif", yr))

  # Use convert with file list (avoids command line length issues)
  convert_cmd <- sprintf(
    "convert -delay 20 -loop 0 @%s %s",
    frame_list_file, gif_output
  )

  result <- system(convert_cmd, ignore.stdout = TRUE, ignore.stderr = FALSE)

  if (result == 0 && file.exists(gif_output)) {
    gif_size_mb <- file.size(gif_output) / 1024^2
    cat(sprintf("    ✓ Created: %s (%.1f MB, %d frames)\n",
                basename(gif_output), gif_size_mb, n_year_frames))
  } else {
    warning(sprintf("    ✗ Failed to create GIF for year %d", yr))
  }

  # Clean up temp file
  unlink(frame_list_file)
}

# ==============================================================================
# SUMMARY
# ==============================================================================

cat("\n======================================\n")
cat("Yearly GIF creation complete!\n\n")

# List created GIFs
gif_files <- list.files(output_dir, pattern = "anomalies_\\d{4}\\.gif", full.names = FALSE)
cat(sprintf("Created %d yearly GIF files:\n", length(gif_files)))
for (gif in sort(gif_files)) {
  cat(sprintf("  - %s\n", gif))
}

cat(sprintf("\nAll files saved to: %s\n", output_dir))
