# Fmask Download with Cached Scene List
# Purpose: Scan once, cache locally, then download to avoid repeated server hits

library(httr)
library(jsonlite)
library(dplyr)

# Source required scripts
source("00_setup_paths.R")
source("01_HLS_data_acquisition_FINAL.R")

hls_paths <- get_hls_paths()

cat("=== FMASK DOWNLOAD WITH CACHED SCENE LIST ===\n\n")

######################
# Step 1: Scan and Cache
######################

scan_and_cache_scenes <- function(cache_file = "scene_list_cache.csv") {

  cat("=== SCANNING FOR EXISTING HLS SCENES ===\n")
  cat("This will scan the U: drive ONCE and save results locally\n")
  cat("Scanning... (this may take 2-5 minutes)\n\n")

  # Get all band files in one go
  cat("Finding B04 files...\n")
  b04_files <- list.files(hls_paths$raw_hls_data, pattern = "_B04\\.tif$", recursive = TRUE, full.names = TRUE)

  cat("Finding B05 files...\n")
  b05_files <- list.files(hls_paths$raw_hls_data, pattern = "_B05\\.tif$", recursive = TRUE, full.names = TRUE)

  cat("Finding B8A files...\n")
  b8a_files <- list.files(hls_paths$raw_hls_data, pattern = "_B8A\\.tif$", recursive = TRUE, full.names = TRUE)

  all_band_files <- c(b04_files, b05_files, b8a_files)

  cat("\nFound", length(all_band_files), "total band files\n")

  # Extract unique scene IDs
  scene_ids <- unique(sub("_(B04|B05|B8A)\\.tif$", "", basename(all_band_files)))

  cat("Found", length(scene_ids), "unique scenes\n")

  # Parse metadata
  scenes_df <- data.frame(
    scene_id = scene_ids,
    stringsAsFactors = FALSE
  )

  scenes_df$sensor <- ifelse(grepl("HLS\\.L30\\.", scenes_df$scene_id), "L30", "S30")
  scenes_df$collection <- ifelse(scenes_df$sensor == "L30", "HLSL30.v2.0", "HLSS30.v2.0")
  scenes_df$tile_id <- sub(".*\\.(T[0-9A-Z]+)\\..*", "\\1", scenes_df$scene_id)

  date_string <- sub(".*\\.([0-9]{7}T[0-9]{6})\\..*", "\\1", scenes_df$scene_id)
  scenes_df$year <- as.numeric(substr(date_string, 1, 4))
  scenes_df$yday <- as.numeric(substr(date_string, 5, 7))
  scenes_df$date <- as.Date(paste0(scenes_df$year, "-01-01")) + scenes_df$yday - 1

  # Find directory for each scene (need this for download)
  cat("Mapping scene directories...\n")
  scenes_df$scene_dir <- NA

  for (i in 1:nrow(scenes_df)) {
    # Find first matching band file
    pattern <- paste0(scenes_df$scene_id[i], "_(B04|B05|B8A)\\.tif$")
    matching_file <- grep(pattern, all_band_files, value = TRUE)[1]
    if (!is.na(matching_file)) {
      scenes_df$scene_dir[i] <- dirname(matching_file)
    }
  }

  # Save to local cache
  write.csv(scenes_df, cache_file, row.names = FALSE)
  cat("\n✓ Scene list cached to:", cache_file, "\n")

  cat("\n=== SCENE SUMMARY ===\n")
  cat("Total unique scenes:", nrow(scenes_df), "\n\n")

  cat("By year:\n")
  print(table(scenes_df$year))

  cat("\nBy sensor:\n")
  print(table(scenes_df$sensor))

  return(scenes_df)
}

######################
# Step 2: Load Cache and Download
######################

download_from_cache <- function(cache_file = "scene_list_cache.csv", nasa_session) {

  if (!file.exists(cache_file)) {
    cat("❌ Cache file not found:", cache_file, "\n")
    cat("Run scan_and_cache_scenes() first\n")
    return(NULL)
  }

  cat("=== LOADING SCENE LIST FROM CACHE ===\n")
  scenes_df <- read.csv(cache_file, stringsAsFactors = FALSE)
  scenes_df$date <- as.Date(scenes_df$date)

  cat("Loaded", nrow(scenes_df), "scenes from cache\n\n")

  cat("=== STARTING FMASK DOWNLOAD ===\n")
  cat("Grouping scenes for batch API queries...\n\n")

  # Group by year and collection ONLY (not tile) to minimize API requests
  grouped <- scenes_df %>%
    group_by(year, collection) %>%
    summarise(
      n_scenes = n(),
      min_date = min(date),
      max_date = max(date),
      tiles = paste(unique(tile_id), collapse = ","),
      .groups = "drop"
    )

  cat("Making", nrow(grouped), "batch API requests (year × collection)\n")
  cat("This covers", nrow(scenes_df), "scenes across", length(unique(scenes_df$tile_id)), "tiles\n\n")

  success_count <- 0
  fail_count <- 0
  skip_count <- 0

  # Create lookup for scenes needing download
  scenes_lookup <- scenes_df[, c("scene_id", "scene_dir")]

  pb <- txtProgressBar(min = 0, max = nrow(grouped), style = 3)

  # Midwest DEWS bbox - matches 02_midwest_pilot.R
  midwest_bbox <- c(-104.5, 37.0, -82.0, 47.5)  # xmin, ymin, xmax, ymax

  for (i in 1:nrow(grouped)) {
    group <- grouped[i, ]

    cat("\n\nProcessing", group$year, group$collection, ":", group$n_scenes, "scenes\n")

    # Search STAC API with bbox and pagination
    stac_url <- "https://cmr.earthdata.nasa.gov/stac/LPCLOUD/search"

    all_features <- list()
    page <- 1
    max_pages <- 20  # Safety limit

    repeat {

      query_params <- list(
        collections = group$collection,
        datetime = paste0(group$min_date, "T00:00:00Z/", group$max_date, "T23:59:59Z"),
        bbox = paste(midwest_bbox, collapse = ","),
        limit = 100,
        page = page
      )

      response <- try({
        GET(
          url = stac_url,
          query = query_params,
          add_headers("Accept" = "application/json"),
          timeout(120)
        )
      }, silent = TRUE)

      if (inherits(response, "try-error")) {
        cat("❌ API request failed on page", page, ":", as.character(response), "\n")
        break
      }

      if (status_code(response) != 200) {
        cat("❌ API returned status code:", status_code(response), "on page", page, "\n")
        break
      }

      content_json <- fromJSON(content(response, "text", encoding = "UTF-8"), simplifyVector = FALSE)

      if (is.null(content_json$features) || length(content_json$features) == 0) {
        break  # No more results
      }

      all_features <- c(all_features, content_json$features)
      cat("  Page", page, ":", length(content_json$features), "scenes\n")

      # Check if there are more pages
      if (length(content_json$features) < 100 || page >= max_pages) {
        break
      }

      page <- page + 1
      Sys.sleep(0.5)  # Brief delay between pages
    }

    cat("✓ Found", length(all_features), "total scenes from API\n")

    # Build Fmask lookup from ALL returned features
    fmask_lookup <- list()
    for (feature in all_features) {
      if (!is.null(feature$assets$Fmask)) {
        fmask_lookup[[feature$id]] <- feature$assets$Fmask$href
      }
    }

    cat("✓ Found", length(fmask_lookup), "Fmask files available\n")

    # Get scenes for this year-collection
    year_scenes <- scenes_df[scenes_df$year == group$year & scenes_df$collection == group$collection, ]

    # Download Fmask for each scene we need
    for (j in 1:nrow(year_scenes)) {
      scene_id <- year_scenes$scene_id[j]
      scene_dir <- year_scenes$scene_dir[j]

      fmask_file <- file.path(scene_dir, paste0(scene_id, "_Fmask.tif"))

      # Skip if already exists
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

    # Show which scenes failed for this batch
    failed_scenes <- year_scenes$scene_id[!year_scenes$scene_id %in% names(fmask_lookup)]
    if (length(failed_scenes) > 0 && length(failed_scenes) <= 10) {
      cat("Failed scenes (not in API):", paste(head(failed_scenes, 5), collapse = ", "), "\n")
    } else if (length(failed_scenes) > 10) {
      cat("Failed scenes count:", length(failed_scenes), "- Sample:", paste(head(failed_scenes, 3), collapse = ", "), "\n")
    }

    cat("Batch progress: Success =", success_count, "Skip =", skip_count, "Fail =", fail_count, "\n")

    setTxtProgressBar(pb, i)
    Sys.sleep(1)  # Brief pause between API requests
  }

  close(pb)

  return(list(
    success = success_count,
    failed = fail_count,
    skipped = skip_count
  ))
}

######################
# Main Workflow
######################

run_cached_fmask_download <- function(force_rescan = FALSE, cache_file = "scene_list_cache.csv") {

  cat("=== FMASK DOWNLOAD WITH CACHED SCENE LIST ===\n\n")

  # Step 1: Load or create cache
  if (file.exists(cache_file) && !force_rescan) {
    cat("Found existing scene cache:", cache_file, "\n")
    cat("Using cached scene list (set force_rescan=TRUE to rescan)\n\n")
    scenes_df <- read.csv(cache_file, stringsAsFactors = FALSE)
  } else {
    cat("Creating new scene cache...\n")
    scenes_df <- scan_and_cache_scenes(cache_file)
  }

  # Step 2: Set up NASA session
  cat("\nSetting up NASA Earthdata session...\n")
  nasa_session <- create_nasa_session()

  # Step 3: Download
  results <- download_from_cache(cache_file, nasa_session)

  cat("\n\n=== DOWNLOAD COMPLETE ===\n")
  cat("Successfully downloaded:", results$success, "Fmask files\n")
  cat("Skipped (already exist):", results$skipped, "Fmask files\n")
  cat("Failed:", results$failed, "Fmask files\n")
  cat("Total scenes:", nrow(scenes_df), "\n")

  final_coverage <- round(100 * (results$success + results$skipped) / nrow(scenes_df), 1)
  cat("\nFinal Fmask coverage:", final_coverage, "%\n\n")

  return(results)
}

# Instructions
cat("=== CACHED FMASK DOWNLOAD READY ===\n")
cat("This approach scans the U: drive ONCE and caches results locally\n\n")
cat("To run:\n")
cat("  results <- run_cached_fmask_download()\n\n")
cat("To force a rescan:\n")
cat("  results <- run_cached_fmask_download(force_rescan = TRUE)\n\n")
cat("The workflow:\n")
cat("  1. Scan U: drive for band files (2-5 min, done once)\n")
cat("  2. Cache scene list locally as CSV\n")
cat("  3. Download Fmask files using cached list (no repeated U: drive hits)\n\n")
