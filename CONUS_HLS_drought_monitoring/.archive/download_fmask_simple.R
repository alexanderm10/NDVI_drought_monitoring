# Simplified Fmask Download - Download for Existing Band Files
# Purpose: Scan existing B04/B05/B8A files and download matching Fmask files
# No checking - just download what we need

library(httr)
library(jsonlite)
library(dplyr)

# Source required scripts
source("00_setup_paths.R")
source("01_HLS_data_acquisition_FINAL.R")

hls_paths <- get_hls_paths()

cat("=== SIMPLIFIED FMASK DOWNLOAD ===\n\n")

######################
# Scan for Band Files
######################

scan_existing_scenes <- function() {

  cat("Scanning for existing HLS band files...\n")
  cat("This may take a few minutes...\n\n")

  # Get all band files
  band_files <- c(
    list.files(hls_paths$raw_hls_data, pattern = "_B04\\.tif$", recursive = TRUE, full.names = TRUE),
    list.files(hls_paths$raw_hls_data, pattern = "_B05\\.tif$", recursive = TRUE, full.names = TRUE),
    list.files(hls_paths$raw_hls_data, pattern = "_B8A\\.tif$", recursive = TRUE, full.names = TRUE)
  )

  cat("Found", length(band_files), "band files\n")

  if (length(band_files) == 0) {
    cat("❌ No band files found - nothing to download Fmask for\n")
    return(NULL)
  }

  # Extract unique scene IDs
  scene_ids <- unique(sub("_(B04|B05|B8A)\\.tif$", "", basename(band_files)))

  cat("Found", length(scene_ids), "unique scenes\n")

  # Parse scene metadata
  scenes_df <- data.frame(
    scene_id = scene_ids,
    stringsAsFactors = FALSE
  )

  # Extract sensor and collection
  scenes_df$sensor <- ifelse(grepl("HLS\\.L30\\.", scenes_df$scene_id), "L30", "S30")
  scenes_df$collection <- ifelse(scenes_df$sensor == "L30", "HLSL30.v2.0", "HLSS30.v2.0")

  # Extract tile ID
  scenes_df$tile_id <- sub(".*\\.(T[0-9A-Z]+)\\..*", "\\1", scenes_df$scene_id)

  # Extract date
  date_string <- sub(".*\\.([0-9]{7}T[0-9]{6})\\..*", "\\1", scenes_df$scene_id)
  scenes_df$year <- as.numeric(substr(date_string, 1, 4))
  scenes_df$yday <- as.numeric(substr(date_string, 5, 7))
  scenes_df$date <- as.Date(paste0(scenes_df$year, "-01-01")) + scenes_df$yday - 1

  cat("\n=== BREAKDOWN BY YEAR ===\n")
  year_counts <- table(scenes_df$year)
  print(year_counts)

  cat("\n=== BREAKDOWN BY SENSOR ===\n")
  sensor_counts <- table(scenes_df$sensor)
  print(sensor_counts)

  return(scenes_df)
}

######################
# Search and Download Fmask
######################

search_and_download_fmask <- function(scenes_df, nasa_session) {

  cat("\n=== STARTING FMASK DOWNLOAD ===\n")
  cat("Processing", nrow(scenes_df), "scenes\n")
  cat("Grouping by tile and date range for efficiency...\n\n")

  # Group scenes by tile, year, and collection for batch searching
  grouped <- scenes_df %>%
    group_by(tile_id, year, collection) %>%
    summarise(
      n_scenes = n(),
      min_date = min(date),
      max_date = max(date),
      scene_ids = list(scene_id),
      .groups = "drop"
    )

  cat("Grouped into", nrow(grouped), "tile-year-collection combinations\n\n")

  # Track results
  success_count <- 0
  fail_count <- 0
  skip_count <- 0

  pb <- txtProgressBar(min = 0, max = nrow(grouped), style = 3)

  for (i in 1:nrow(grouped)) {
    group <- grouped[i, ]

    # Search STAC API for this tile/date range
    stac_url <- "https://cmr.earthdata.nasa.gov/stac/LPCLOUD/search"

    query_params <- list(
      collections = group$collection,
      datetime = paste0(group$min_date, "T00:00:00Z/", group$max_date, "T23:59:59Z"),
      limit = 2000
    )

    response <- try({
      GET(
        url = stac_url,
        query = query_params,
        add_headers("Accept" = "application/json"),
        timeout(60)
      )
    }, silent = TRUE)

    if (inherits(response, "try-error") || status_code(response) != 200) {
      fail_count <- fail_count + group$n_scenes
      setTxtProgressBar(pb, i)
      next
    }

    content_json <- fromJSON(content(response, "text", encoding = "UTF-8"), simplifyVector = FALSE)

    if (is.null(content_json$features) || length(content_json$features) == 0) {
      fail_count <- fail_count + group$n_scenes
      setTxtProgressBar(pb, i)
      next
    }

    # Build lookup of available Fmask URLs
    fmask_lookup <- list()
    for (feature in content_json$features) {
      if (grepl(group$tile_id, feature$id) && !is.null(feature$assets$Fmask)) {
        fmask_lookup[[feature$id]] <- feature$assets$Fmask$href
      }
    }

    # Download Fmask for each scene in this group
    for (target_scene_id in group$scene_ids[[1]]) {

      # Check if Fmask already exists
      fmask_pattern <- paste0(target_scene_id, "_Fmask\\.tif$")
      existing_fmask <- list.files(
        hls_paths$raw_hls_data,
        pattern = fmask_pattern,
        recursive = TRUE,
        full.names = TRUE
      )

      if (length(existing_fmask) > 0) {
        skip_count <- skip_count + 1
        next
      }

      # Get Fmask URL
      fmask_url <- fmask_lookup[[target_scene_id]]

      if (is.null(fmask_url)) {
        fail_count <- fail_count + 1
        next
      }

      # Determine output directory (same as band files)
      scene_year <- as.numeric(substr(sub(".*\\.([0-9]{7}T[0-9]{6})\\..*", "\\1", target_scene_id), 1, 4))

      # Find the directory where this scene's band files are stored
      band_file <- list.files(
        file.path(hls_paths$raw_hls_data, paste0("year_", scene_year)),
        pattern = paste0(target_scene_id, "_(B04|B05|B8A)\\.tif$"),
        recursive = TRUE,
        full.names = TRUE
      )[1]

      if (is.na(band_file)) {
        fail_count <- fail_count + 1
        next
      }

      output_dir <- dirname(band_file)
      fmask_file <- file.path(output_dir, paste0(target_scene_id, "_Fmask.tif"))

      # Download
      success <- download_hls_band(fmask_url, fmask_file, nasa_session)

      if (success) {
        success_count <- success_count + 1
      } else {
        fail_count <- fail_count + 1
      }

      # Small delay to avoid overwhelming the server
      Sys.sleep(0.1)
    }

    setTxtProgressBar(pb, i)
  }

  close(pb)

  return(list(
    success = success_count,
    failed = fail_count,
    skipped = skip_count
  ))
}

######################
# Main Execution
######################

run_simple_fmask_download <- function() {

  cat("=== STARTING SIMPLIFIED FMASK DOWNLOAD ===\n\n")

  # Scan for existing scenes
  scenes_df <- scan_existing_scenes()

  if (is.null(scenes_df)) {
    return(invisible(NULL))
  }

  # Set up NASA session
  cat("\nSetting up NASA Earthdata session...\n")
  nasa_session <- create_nasa_session()

  # Download Fmask files
  results <- search_and_download_fmask(scenes_df, nasa_session)

  cat("\n\n=== DOWNLOAD COMPLETE ===\n")
  cat("Successfully downloaded:", results$success, "Fmask files\n")
  cat("Skipped (already exist):", results$skipped, "Fmask files\n")
  cat("Failed:", results$failed, "Fmask files\n")
  cat("Total scenes processed:", nrow(scenes_df), "\n")

  final_coverage <- round(100 * (results$success + results$skipped) / nrow(scenes_df), 1)
  cat("\nFinal Fmask coverage:", final_coverage, "%\n\n")

  return(results)
}

# Instructions
cat("=== SIMPLIFIED FMASK DOWNLOAD READY ===\n")
cat("This script scans your existing HLS band files (B04/B05/B8A)\n")
cat("and downloads the corresponding Fmask files\n\n")
cat("To run:\n")
cat("  results <- run_simple_fmask_download()\n\n")
cat("The script will:\n")
cat("  1. Find all scenes with band files\n")
cat("  2. Check if Fmask already exists (skip if yes)\n")
cat("  3. Download missing Fmask files to same directory as bands\n\n")
