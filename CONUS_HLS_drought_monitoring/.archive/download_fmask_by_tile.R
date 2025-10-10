# Fmask Download by Tile ID
# Purpose: Search for Fmask files by exact tile ID - much more reliable than bbox

library(httr)
library(jsonlite)
library(dplyr)

source("00_setup_paths.R")
source("01_HLS_data_acquisition_FINAL.R")

hls_paths <- get_hls_paths()

cat("=== FMASK DOWNLOAD BY TILE ID ===\n\n")

######################
# Load Cache
######################

load_scene_cache <- function(cache_file = "scene_list_cache.csv") {

  if (!file.exists(cache_file)) {
    cat("❌ Cache file not found. Run scan first.\n")
    return(NULL)
  }

  scenes_df <- read.csv(cache_file, stringsAsFactors = FALSE)
  scenes_df$date <- as.Date(scenes_df$date)

  cat("Loaded", nrow(scenes_df), "scenes from cache\n")
  cat("Spanning", length(unique(scenes_df$tile_id)), "unique tiles\n\n")

  return(scenes_df)
}

######################
# Search by Tile ID
######################

search_fmask_by_tile_id <- function(tile_id, year, collection) {

  # Date range for the year
  start_date <- paste0(year, "-01-01")
  end_date <- paste0(year, "-12-31")

  # Convert collection format: HLSL30.v2.0 -> HLSL30_2.0
  api_collection <- gsub("\\.v", "_", collection)

  # Midwest bbox to limit search area
  midwest_bbox <- c(-104.5, 37.0, -82.0, 47.5)

  stac_url <- "https://cmr.earthdata.nasa.gov/stac/LPCLOUD/search"

  query_params <- list(
    collections = api_collection,
    bbox = paste(midwest_bbox, collapse = ","),
    datetime = paste0(start_date, "T00:00:00Z/", end_date, "T23:59:59Z"),
    limit = 500
  )

  response <- try({
    GET(
      url = stac_url,
      query = query_params,
      add_headers("Accept" = "application/json"),
      timeout(60)
    )
  }, silent = TRUE)

  if (inherits(response, "try-error")) {
    return(list(error = "request_failed"))
  }

  if (status_code(response) != 200) {
    return(list(error = paste0("status_", status_code(response))))
  }

  content_json <- fromJSON(content(response, "text", encoding = "UTF-8"), simplifyVector = FALSE)

  if (is.null(content_json$features) || length(content_json$features) == 0) {
    return(list(error = "no_features"))
  }

  # Filter to exact tile match and extract Fmask URLs
  fmask_lookup <- list()
  total_features <- length(content_json$features)
  tile_matches <- 0
  fmask_found <- 0

  for (feature in content_json$features) {
    # Check if scene ID contains this tile ID
    if (grepl(tile_id, feature$id, fixed = TRUE)) {
      tile_matches <- tile_matches + 1
      if (!is.null(feature$assets$Fmask)) {
        fmask_found <- fmask_found + 1
        fmask_lookup[[feature$id]] <- feature$assets$Fmask$href
      }
    }
  }

  # Add debug info to result
  attr(fmask_lookup, "debug") <- list(
    total_features = total_features,
    tile_matches = tile_matches,
    fmask_found = fmask_found,
    sample_id = if (total_features > 0) content_json$features[[1]]$id else NULL
  )

  return(fmask_lookup)
}

######################
# Download by Tile
######################

download_fmask_by_tile <- function(cache_file = "scene_list_cache.csv", nasa_session) {

  scenes_df <- load_scene_cache(cache_file)
  if (is.null(scenes_df)) return(NULL)

  cat("=== STARTING TILE-BASED FMASK DOWNLOAD ===\n\n")

  # Group by tile, year, collection
  grouped <- scenes_df %>%
    group_by(tile_id, year, collection) %>%
    summarise(
      n_scenes = n(),
      scene_data = list(data.frame(scene_id, scene_dir)),
      .groups = "drop"
    ) %>%
    arrange(year, tile_id)

  cat("Processing", nrow(grouped), "tile-year-collection groups\n")
  cat("This will make", nrow(grouped), "API requests\n\n")

  success_count <- 0
  fail_count <- 0
  skip_count <- 0

  # Show sample of what we're searching for
  cat("Sample searches:\n")
  for (i in 1:min(3, nrow(grouped))) {
    cat("  ", grouped$tile_id[i], grouped$year[i], grouped$collection[i],
        "(", grouped$n_scenes[i], "scenes )\n")
  }
  cat("\n")

  pb <- txtProgressBar(min = 0, max = nrow(grouped), style = 3)

  for (i in 1:nrow(grouped)) {
    group <- grouped[i, ]

    # Search for this specific tile-year-collection
    fmask_lookup <- search_fmask_by_tile_id(
      tile_id = group$tile_id,
      year = group$year,
      collection = group$collection
    )

    # Debug first few iterations
    if (i <= 3) {
      cat("\n[Debug] Tile:", group$tile_id, "Year:", group$year, "Collection:", group$collection, "\n")
      if (!is.null(fmask_lookup$error)) {
        cat("[Debug] API Error:", fmask_lookup$error, "\n")
      } else {
        debug_info <- attr(fmask_lookup, "debug")
        if (!is.null(debug_info)) {
          cat("[Debug] Total features from API:", debug_info$total_features, "\n")
          cat("[Debug] Matching tile ID:", debug_info$tile_matches, "\n")
          cat("[Debug] With Fmask asset:", debug_info$fmask_found, "\n")
          if (!is.null(debug_info$sample_id)) {
            cat("[Debug] Sample feature ID:", debug_info$sample_id, "\n")
          }
        }
        cat("[Debug] Final Fmask URLs:", length(fmask_lookup), "\n")
      }
    }

    # Download Fmask for each scene in this group
    scene_data <- group$scene_data[[1]]

    for (j in 1:nrow(scene_data)) {
      scene_id <- scene_data$scene_id[j]
      scene_dir <- scene_data$scene_dir[j]

      fmask_file <- file.path(scene_dir, paste0(scene_id, "_Fmask.tif"))

      # Skip if exists
      if (file.exists(fmask_file)) {
        skip_count <- skip_count + 1
        next
      }

      # Get Fmask URL
      fmask_url <- fmask_lookup[[scene_id]]

      if (is.null(fmask_url)) {
        fail_count <- fail_count + 1
        next
      }

      # Download
      success <- download_hls_band(fmask_url, fmask_file, nasa_session)

      if (success) {
        success_count <- success_count + 1
      } else {
        fail_count <- fail_count + 1
      }

      Sys.sleep(0.05)
    }

    setTxtProgressBar(pb, i)

    # Brief pause every 50 requests
    if (i %% 50 == 0) {
      Sys.sleep(2)
    }
  }

  close(pb)

  return(list(
    success = success_count,
    failed = fail_count,
    skipped = skip_count
  ))
}

######################
# Main Function
######################

run_tile_based_download <- function(cache_file = "scene_list_cache.csv") {

  cat("=== TILE-BASED FMASK DOWNLOAD ===\n\n")

  # Set up NASA session
  cat("Setting up NASA Earthdata session...\n")
  nasa_session <- create_nasa_session()

  # Download
  results <- download_fmask_by_tile(cache_file, nasa_session)

  if (is.null(results)) {
    return(invisible(NULL))
  }

  cat("\n\n=== DOWNLOAD COMPLETE ===\n")
  cat("Successfully downloaded:", results$success, "Fmask files\n")
  cat("Skipped (already exist):", results$skipped, "Fmask files\n")
  cat("Failed:", results$failed, "Fmask files\n")

  scenes_df <- read.csv(cache_file, stringsAsFactors = FALSE)
  cat("Total scenes:", nrow(scenes_df), "\n")

  final_coverage <- round(100 * (results$success + results$skipped) / nrow(scenes_df), 1)
  cat("\nFinal Fmask coverage:", final_coverage, "%\n\n")

  return(results)
}

# Instructions
cat("=== TILE-BASED FMASK DOWNLOAD READY ===\n")
cat("This searches by individual tile ID for maximum reliability\n\n")
cat("To run:\n")
cat("  results <- run_tile_based_download()\n\n")
cat("Searches each tile-year-collection combo separately\n")
cat("More API requests but much higher success rate\n\n")
