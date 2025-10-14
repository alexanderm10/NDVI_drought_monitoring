# Match NDVI Files with Fmask Archive
# Purpose: Create report showing which NDVI files have corresponding Fmask data
# Run this AFTER download_fmask_archive.R completes

library(dplyr)

# Source required scripts
source("00_setup_paths.R")

hls_paths <- get_hls_paths()

cat("=== NDVI-FMASK MATCHING REPORT ===\n\n")

######################
# Scan Files
######################

scan_ndvi_files <- function() {

  cat("Scanning for NDVI files...\n")

  ndvi_files <- list.files(
    file.path(hls_paths$processed_ndvi, "daily"),
    pattern = "_NDVI\\.tif$",
    recursive = TRUE,
    full.names = TRUE
  )

  if (length(ndvi_files) == 0) {
    cat("❌ No NDVI files found\n")
    return(NULL)
  }

  cat("Found", length(ndvi_files), "NDVI files\n")

  # Extract metadata
  file_df <- data.frame(
    ndvi_path = ndvi_files,
    scene_id = sub("_NDVI\\.tif", "", basename(ndvi_files)),
    stringsAsFactors = FALSE
  )

  # Extract year
  date_string <- sub(".*\\.([0-9]{7}T[0-9]{6})\\..*", "\\1", file_df$scene_id)
  file_df$year <- as.numeric(substr(date_string, 1, 4))
  file_df$yday <- as.numeric(substr(date_string, 5, 7))

  # Extract sensor
  file_df$sensor <- ifelse(grepl("HLS\\.L30\\.", file_df$scene_id), "L30", "S30")

  # Extract tile
  file_df$tile_id <- sub(".*\\.(T[0-9A-Z]+)\\..*", "\\1", file_df$scene_id)

  return(file_df)
}

scan_fmask_files <- function() {

  cat("Scanning for Fmask files...\n")

  fmask_files <- list.files(
    hls_paths$raw_hls_data,
    pattern = "_Fmask\\.tif$",
    recursive = TRUE,
    full.names = TRUE
  )

  if (length(fmask_files) == 0) {
    cat("❌ No Fmask files found\n")
    return(NULL)
  }

  cat("Found", length(fmask_files), "Fmask files\n\n")

  # Extract scene IDs
  fmask_df <- data.frame(
    fmask_path = fmask_files,
    scene_id = sub("_Fmask\\.tif", "", basename(fmask_files)),
    stringsAsFactors = FALSE
  )

  return(fmask_df)
}

######################
# Match Files
######################

match_ndvi_fmask <- function() {

  # Scan both directories
  ndvi_df <- scan_ndvi_files()
  fmask_df <- scan_fmask_files()

  if (is.null(ndvi_df) || is.null(fmask_df)) {
    cat("❌ Cannot proceed - missing NDVI or Fmask files\n")
    return(invisible(NULL))
  }

  # Merge to find matches
  matched <- merge(ndvi_df, fmask_df, by = "scene_id", all.x = TRUE)

  matched$has_fmask <- !is.na(matched$fmask_path)

  cat("\n=== MATCHING RESULTS ===\n\n")
  cat("Total NDVI files:", nrow(matched), "\n")
  cat("NDVI files WITH Fmask:", sum(matched$has_fmask), "\n")
  cat("NDVI files WITHOUT Fmask:", sum(!matched$has_fmask), "\n")
  cat("Match rate:", round(100 * sum(matched$has_fmask) / nrow(matched), 1), "%\n\n")

  # Breakdown by year
  cat("=== BREAKDOWN BY YEAR ===\n\n")
  year_summary <- matched %>%
    group_by(year) %>%
    summarise(
      total = n(),
      with_fmask = sum(has_fmask),
      without_fmask = sum(!has_fmask),
      match_rate = round(100 * with_fmask / total, 1)
    ) %>%
    arrange(year)

  print(as.data.frame(year_summary))

  # Breakdown by sensor
  cat("\n=== BREAKDOWN BY SENSOR ===\n\n")
  sensor_summary <- matched %>%
    group_by(sensor) %>%
    summarise(
      total = n(),
      with_fmask = sum(has_fmask),
      without_fmask = sum(!has_fmask),
      match_rate = round(100 * with_fmask / total, 1)
    )

  print(as.data.frame(sensor_summary))

  # Show some examples of mismatches
  if (sum(!matched$has_fmask) > 0) {
    cat("\n=== SAMPLE OF UNMATCHED NDVI FILES (first 10) ===\n\n")
    unmatched <- matched[!matched$has_fmask, ]
    print(head(unmatched[, c("scene_id", "year", "sensor", "tile_id")], 10))
  }

  # Save full report
  report_file <- file.path(hls_paths$processing_logs, "ndvi_fmask_matching_report.csv")
  dir.create(dirname(report_file), recursive = TRUE, showWarnings = FALSE)
  write.csv(matched, report_file, row.names = FALSE)
  cat("\n✓ Full report saved to:", report_file, "\n\n")

  return(matched)
}

######################
# Generate Reprocessing List
######################

create_reprocessing_list <- function(matched_df) {

  cat("=== CREATING REPROCESSING LIST ===\n\n")

  # Filter to scenes with Fmask
  can_reprocess <- matched_df[matched_df$has_fmask, ]

  if (nrow(can_reprocess) == 0) {
    cat("❌ No scenes available for reprocessing\n")
    return(invisible(NULL))
  }

  cat("Scenes ready for reprocessing:", nrow(can_reprocess), "\n")

  # Add band paths
  can_reprocess$red_band <- ifelse(can_reprocess$sensor == "L30", "B04", "B04")
  can_reprocess$nir_band <- ifelse(can_reprocess$sensor == "L30", "B05", "B8A")

  # Save reprocessing list
  reprocess_file <- file.path(hls_paths$processing_logs, "reprocessing_list.csv")
  write.csv(can_reprocess, reprocess_file, row.names = FALSE)
  cat("✓ Reprocessing list saved to:", reprocess_file, "\n\n")

  return(can_reprocess)
}

######################
# Main Execution
######################

run_matching_report <- function(create_list = TRUE) {

  cat("=== STARTING NDVI-FMASK MATCHING ===\n\n")

  # Match files
  matched <- match_ndvi_fmask()

  if (is.null(matched)) {
    return(invisible(NULL))
  }

  # Create reprocessing list
  if (create_list) {
    reprocess_list <- create_reprocessing_list(matched)
  }

  cat("\n=== MATCHING COMPLETE ===\n")
  cat("Review the reports in:", hls_paths$processing_logs, "\n\n")

  return(matched)
}

# Instructions
cat("=== NDVI-FMASK MATCHING READY ===\n")
cat("Run this after downloading the Fmask archive\n\n")
cat("To generate matching report:\n")
cat("  matched <- run_matching_report()\n\n")
cat("This will create:\n")
cat("  1. Summary statistics by year and sensor\n")
cat("  2. Full matching report CSV\n")
cat("  3. Reprocessing list for scenes with Fmask\n\n")
