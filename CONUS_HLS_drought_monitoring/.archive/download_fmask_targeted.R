# Targeted Fmask Download - Match Exact NDVI Tiles and Dates
# Purpose: Download Fmask ONLY for tiles/dates where NDVI exists
# This ensures 100% relevance and high match rate

library(httr)
library(jsonlite)
library(dplyr)

# Source required scripts
source("00_setup_paths.R")
source("01_HLS_data_acquisition_FINAL.R")

hls_paths <- get_hls_paths()

cat("=== TARGETED FMASK DOWNLOAD ===\n\n")

######################
# Build Target List from NDVI
######################

build_target_list <- function() {

  cat("Building target list from existing NDVI files...\n")

  # Scan NDVI files
  ndvi_files <- list.files(
    file.path(hls_paths$processed_ndvi, "daily"),
    pattern = "_NDVI\\.tif$",
    recursive = TRUE,
    full.names = TRUE
  )

  cat("Found", length(ndvi_files), "NDVI files\n")

  # Extract metadata
  file_df <- data.frame(
    ndvi_path = ndvi_files,
    scene_id = sub("_NDVI\\.tif", "", basename(ndvi_files)),
    stringsAsFactors = FALSE
  )

  # Parse scene info
  file_df$sensor <- ifelse(grepl("HLS\\.L30\\.", file_df$scene_id), "L30", "S30")
  file_df$collection <- ifelse(file_df$sensor == "L30", "HLSL30_2.0", "HLSS30_2.0")
  file_df$tile_id <- sub(".*\\.(T[0-9A-Z]+)\\..*", "\\1", file_df$scene_id)

  # Parse date
  date_string <- sub(".*\\.([0-9]{7}T[0-9]{6})\\..*", "\\1", file_df$scene_id)
  file_df$year <- as.numeric(substr(date_string, 1, 4))
  file_df$yday <- as.numeric(substr(date_string, 5, 7))
  file_df$date <- as.Date(paste0(file_df$year, "-01-01")) + file_df$yday - 1

  # Check for existing Fmask
  file_df$has_fmask <- FALSE
  cat("Checking for existing Fmask files...\n")

  for (i in 1:nrow(file_df)) {
    fmask_pattern <- paste0(file_df$scene_id[i], "_Fmask\\.tif")
    fmask_exists <- length(list.files(
      hls_paths$raw_hls_data,
      pattern = fmask_pattern,
      recursive = TRUE
    )) > 0

    file_df$has_fmask[i] <- fmask_exists
  }

  cat("Already have Fmask for:", sum(file_df$has_fmask), "scenes\n")
  cat("Need to download:", sum(!file_df$has_fmask), "scenes\n\n")

  return(file_df)
}

######################
# Search by Tile and Date Range
######################

search_fmask_by_tile <- function(tile_id, start_date, end_date, collection) {

  stac_url <- "https://cmr.earthdata.nasa.gov/stac/LPCLOUD/search"

  # Convert collection name
  collection_name <- gsub("_", ".v", collection)

  query_params <- list(
    collections = collection_name,
    datetime = paste0(start_date, "T00:00:00Z/", end_date, "T23:59:59Z"),
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
    return(NULL)
  }

  content_json <- fromJSON(content(response, "text", encoding = "UTF-8"), simplifyVector = FALSE)

  if (is.null(content_json$features) || length(content_json$features) == 0) {
    return(NULL)
  }

  # Filter to matching tile
  matching_scenes <- list()
  for (feature in content_json$features) {
    if (grepl(tile_id, feature$id) && !is.null(feature$assets$Fmask)) {
      matching_scenes[[length(matching_scenes) + 1]] <- list(
        scene_id = feature$id,
        fmask_url = feature$assets$Fmask$href
      )
    }
  }

  return(matching_scenes)
}

######################
# Download Fmask for Target Scenes
######################

download_targeted_fmask <- function(target_df, nasa_session) {

  # Filter to scenes needing download
  to_download <- target_df[!target_df$has_fmask, ]

  if (nrow(to_download) == 0) {
    cat("All scenes already have Fmask!\n")
    return(list(success = 0, failed = 0, skipped = nrow(target_df)))
  }

  cat("Downloading Fmask for", nrow(to_download), "scenes\n")
  cat("Processing by tile to optimize API queries...\n\n")

  # Group by tile, year, and collection for efficient searching
  grouped <- to_download %>%
    group_by(tile_id, year, collection) %>%
    summarise(
      n_scenes = n(),
      min_date = min(date),
      max_date = max(date),
      scene_ids = list(scene_id),
      .groups = "drop"
    )

  cat("Grouped into", nrow(grouped), "tile-year-collection combinations\n\n")

  success_count <- 0
  fail_count <- 0

  pb <- txtProgressBar(min = 0, max = nrow(grouped), style = 3)

  for (i in 1:nrow(grouped)) {
    group <- grouped[i, ]

    # Search for all scenes in this tile/year/collection
    scenes <- search_fmask_by_tile(
      tile_id = group$tile_id,
      start_date = as.character(group$min_date),
      end_date = as.character(group$max_date),
      collection = group$collection
    )

    if (is.null(scenes) || length(scenes) == 0) {
      fail_count <- fail_count + group$n_scenes
      setTxtProgressBar(pb, i)
      next
    }

    # Download each needed scene
    for (target_scene_id in group$scene_ids[[1]]) {

      # Find matching scene in search results
      matching_scene <- NULL
      for (scene in scenes) {
        if (scene$scene_id == target_scene_id) {
          matching_scene <- scene
          break
        }
      }

      if (is.null(matching_scene)) {
        fail_count <- fail_count + 1
        next
      }

      # Determine output directory
      scene_year <- as.numeric(substr(sub(".*\\.([0-9]{7}T[0-9]{6})\\..*", "\\1", target_scene_id), 1, 4))
      output_dir <- file.path(
        hls_paths$raw_hls_data,
        paste0("year_", scene_year),
        paste0("midwest_", group$tile_id)
      )

      dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

      fmask_file <- file.path(output_dir, paste0(target_scene_id, "_Fmask.tif"))

      # Download
      success <- download_hls_band(matching_scene$fmask_url, fmask_file, nasa_session)

      if (success) {
        success_count <- success_count + 1
      } else {
        fail_count <- fail_count + 1
      }
    }

    setTxtProgressBar(pb, i)
  }

  close(pb)

  return(list(
    success = success_count,
    failed = fail_count,
    skipped = sum(target_df$has_fmask)
  ))
}

######################
# Main Execution
######################

run_targeted_fmask_download <- function() {

  cat("=== STARTING TARGETED FMASK DOWNLOAD ===\n\n")

  # Build target list from NDVI
  target_df <- build_target_list()

  # Set up NASA session
  nasa_session <- create_nasa_session()

  # Download
  results <- download_targeted_fmask(target_df, nasa_session)

  cat("\n\n=== TARGETED DOWNLOAD COMPLETE ===\n")
  cat("Successfully downloaded:", results$success, "\n")
  cat("Failed:", results$failed, "\n")
  cat("Already had:", results$skipped, "\n")
  cat("Total NDVI files:", nrow(target_df), "\n")

  final_match_rate <- round(100 * (results$success + results$skipped) / nrow(target_df), 1)
  cat("\nFinal match rate:", final_match_rate, "%\n\n")

  return(results)
}

# Instructions
cat("=== TARGETED FMASK DOWNLOAD READY ===\n")
cat("This script downloads Fmask ONLY for tiles/dates where you have NDVI\n")
cat("Ensures maximum relevance and match rate\n\n")
cat("To run:\n")
cat("  results <- run_targeted_fmask_download()\n\n")
cat("After completion, re-run match_ndvi_fmask.R to verify\n\n")
cat("Estimated time: 1-3 hours for ~4000 scenes\n")
cat("Estimated download: ~6-8 GB\n\n")
