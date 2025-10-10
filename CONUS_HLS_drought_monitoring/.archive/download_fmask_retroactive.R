# Download Fmask Bands for Existing Data
# Purpose: Retroactively download Fmask quality layers for 2013-2024 HLS data
# Strategy: Much faster than re-downloading Red/NIR (~2 MB vs 15-25 MB per scene)

library(httr)
library(jsonlite)

# Source required scripts
source("00_setup_paths.R")
source("01_HLS_data_acquisition_FINAL.R")

hls_paths <- get_hls_paths()

cat("=== RETROACTIVE FMASK DOWNLOAD ===\n\n")

######################
# Find Existing NDVI Files
######################

find_existing_ndvi_files <- function() {

  cat("Scanning for existing NDVI files...\n")

  ndvi_files <- list.files(
    file.path(hls_paths$processed_ndvi, "daily"),
    pattern = "_NDVI\\.tif$",
    recursive = TRUE,
    full.names = TRUE
  )

  cat("Found", length(ndvi_files), "NDVI files\n\n")

  # Extract metadata from filenames
  # Format: HLS.L30.T13SEA.2024005T173159.v2.0_NDVI.tif
  file_df <- data.frame(
    filepath = ndvi_files,
    filename = basename(ndvi_files),
    stringsAsFactors = FALSE
  )

  file_df$sensor <- ifelse(grepl("HLS\\.L30\\.", file_df$filename), "L30", "S30")
  file_df$collection <- ifelse(file_df$sensor == "L30", "HLSL30_2.0", "HLSS30_2.0")
  file_df$tile_id <- sub(".*\\.(T[0-9A-Z]+)\\..*", "\\1", file_df$filename)
  file_df$scene_id <- sub("_NDVI\\.tif", "", file_df$filename)

  # Extract date from filename
  date_string <- sub(".*\\.([0-9]{7}T[0-9]{6})\\..*", "\\1", file_df$filename)
  file_df$year <- as.numeric(substr(date_string, 1, 4))
  file_df$yday <- as.numeric(substr(date_string, 5, 7))
  file_df$date <- as.Date(paste0(file_df$year, "-01-01")) + file_df$yday - 1

  return(file_df)
}

######################
# Check for Existing Fmask Files
######################

check_fmask_exists <- function(file_df) {

  cat("Checking which scenes already have Fmask...\n")

  file_df$fmask_path <- NA
  file_df$has_fmask <- FALSE

  # Progress bar for scanning
  pb <- txtProgressBar(min = 0, max = nrow(file_df), style = 3)

  for (i in 1:nrow(file_df)) {
    # Look for Fmask in raw data directory
    fmask_pattern <- paste0(file_df$scene_id[i], "_Fmask\\.tif")
    fmask_files <- list.files(
      file.path(hls_paths$raw_hls_data),
      pattern = fmask_pattern,
      recursive = TRUE,
      full.names = TRUE
    )

    if (length(fmask_files) > 0) {
      file_df$has_fmask[i] <- TRUE
      file_df$fmask_path[i] <- fmask_files[1]
    }

    setTxtProgressBar(pb, i)
  }

  close(pb)

  cat("Scenes with Fmask:", sum(file_df$has_fmask), "/", nrow(file_df), "\n")
  cat("Scenes needing Fmask:", sum(!file_df$has_fmask), "\n\n")

  return(file_df)
}

######################
# Search and Download Fmask
######################

download_fmask_for_scene <- function(scene_id, collection, tile_id, date, output_dir, nasa_session) {

  # Search for this specific scene in CMR-STAC
  stac_url <- "https://cmr.earthdata.nasa.gov/stac/LPCLOUD/search"

  # Use correct collection naming for STAC search
  # Search uses: HLSL30.v2.0, but our data uses: HLSL30_2.0
  # Convert: HLSL30_2.0 -> HLSL30.v2.0
  collection_name <- gsub("_", ".v", collection)

  # Ensure date is formatted as string (YYYY-MM-DD)
  date_str <- as.character(as.Date(date))

  # Midwest bounding box (approximate - covers tiles T13-T16)
  # [west, south, east, north]
  midwest_bbox <- c(-97, 37, -80, 49)

  query_params <- list(
    collections = collection_name,
    bbox = paste(midwest_bbox, collapse = ","),
    datetime = paste0(date_str, "T00:00:00Z/", date_str, "T23:59:59Z"),
    limit = 500  # Increase limit to get more tiles for the date
  )

  response <- try({
    GET(
      url = stac_url,
      query = query_params,
      add_headers(
        "Accept" = "application/json"
      ),
      timeout(30)
    )
  }, silent = TRUE)

  if (inherits(response, "try-error") || status_code(response) != 200) {
    cat("  ⚠ Search failed for", scene_id, "(status:",
        if (inherits(response, "try-error")) "error" else status_code(response), ")\n")
    return(FALSE)
  }

  content_json <- fromJSON(content(response, "text", encoding = "UTF-8"), simplifyVector = FALSE)

  if (is.null(content_json$features) || length(content_json$features) == 0) {
    cat("  ⚠ No features found for", scene_id, "on", date_str, "\n")
    cat("     Collection searched:", collection_name, "\n")
    cat("     Query URL:", stac_url, "\n")
    return(FALSE)
  }

  cat("  → Found", length(content_json$features), "features for", date_str, "\n")

  # Find matching scene (need to check all features since API doesn't filter by tile)
  found_scene <- FALSE
  scene_ids_found <- c()
  tile_matches <- c()

  for (feature in content_json$features) {
    scene_ids_found <- c(scene_ids_found, feature$id)

    # Check if this feature matches our tile
    if (grepl(tile_id, feature$id)) {
      tile_matches <- c(tile_matches, feature$id)
    }

    if (feature$id == scene_id) {
      found_scene <- TRUE
      # Found it! Check for Fmask asset
      if (!is.null(feature$assets$Fmask)) {
        fmask_url <- feature$assets$Fmask$href
        fmask_file <- file.path(output_dir, paste0(scene_id, "_Fmask.tif"))

        # Download
        success <- download_hls_band(fmask_url, fmask_file, nasa_session)

        if (success) {
          cat("  ✓ Downloaded Fmask for", scene_id, "\n")
          return(TRUE)
        } else {
          cat("  ⚠ Download failed for", scene_id, "\n")
          return(FALSE)
        }
      } else {
        cat("  ⚠ No Fmask asset for", scene_id, "(may not exist in archive)\n")
        return(FALSE)
      }
    }
  }

  if (!found_scene) {
    cat("  ⚠ Scene not found in search results:", scene_id, "\n")
    if (length(tile_matches) > 0) {
      cat("     Found", length(tile_matches), "scenes for tile", tile_id, ":\n")
      for (tm in tile_matches) {
        cat("       -", tm, "\n")
      }
    } else {
      cat("     No scenes found for tile", tile_id, "on this date\n")
      cat("     (API returned", length(scene_ids_found), "scenes from other tiles)\n")
    }
  }
  return(FALSE)
}

######################
# Main Execution
######################

run_fmask_download <- function(skip_existence_check = FALSE) {

  cat("=== STARTING FMASK RETROACTIVE DOWNLOAD ===\n\n")

  # Find existing NDVI files
  ndvi_files <- find_existing_ndvi_files()

  # Check which have Fmask (optional - can be slow)
  if (!skip_existence_check) {
    ndvi_files <- check_fmask_exists(ndvi_files)

    # Filter to scenes needing Fmask
    scenes_to_download <- ndvi_files[!ndvi_files$has_fmask, ]

    if (nrow(scenes_to_download) == 0) {
      cat("✅ All scenes already have Fmask!\n")
      return(invisible(NULL))
    }
  } else {
    cat("⚠ Skipping existence check - will attempt to download all Fmask files\n")
    cat("  (Existing files will be skipped by NASA if already downloaded)\n\n")
    scenes_to_download <- ndvi_files
  }

  cat("Downloading Fmask for", nrow(scenes_to_download), "scenes...\n\n")

  # Set up NASA session
  nasa_session <- create_nasa_session()

  # Track progress
  success_count <- 0
  fail_count <- 0

  # Progress bar
  pb <- txtProgressBar(min = 0, max = nrow(scenes_to_download), style = 3)

  for (i in 1:nrow(scenes_to_download)) {
    scene <- scenes_to_download[i, ]

    # Determine output directory (same as Red/NIR bands)
    output_dir <- file.path(
      hls_paths$raw_hls_data,
      paste0("year_", scene$year),
      paste0("midwest_", scene$tile_id)  # Adjust if needed
    )

    # Create directory if needed
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

    # Download Fmask
    success <- download_fmask_for_scene(
      scene$scene_id,
      scene$collection,
      scene$tile_id,
      scene$date,
      output_dir,
      nasa_session
    )

    if (success) {
      success_count <- success_count + 1
    } else {
      fail_count <- fail_count + 1
    }

    setTxtProgressBar(pb, i)
  }

  close(pb)

  cat("\n\n=== FMASK DOWNLOAD COMPLETE ===\n")
  cat("Successful downloads:", success_count, "\n")
  cat("Failed downloads:", fail_count, "\n")
  cat("Total processed:", nrow(scenes_to_download), "\n\n")

  # Estimate data downloaded
  avg_fmask_size_mb <- 1.5
  total_mb <- success_count * avg_fmask_size_mb
  cat("Estimated data downloaded:", round(total_mb / 1024, 1), "GB\n")

  return(list(
    total = nrow(scenes_to_download),
    success = success_count,
    failed = fail_count
  ))
}

######################
# Debug Function
######################

debug_stac_search <- function() {
  cat("=== DEBUGGING STAC SEARCH ===\n\n")

  # Test with a known 2024 scene
  test_date <- "2024-01-10"
  collection <- "HLSL30.v2.0"

  stac_url <- "https://cmr.earthdata.nasa.gov/stac/LPCLOUD/search"

  query_params <- list(
    collections = collection,
    datetime = paste0(test_date, "T00:00:00Z/", test_date, "T23:59:59Z"),
    limit = 10
  )

  cat("Testing STAC search:\n")
  cat("  URL:", stac_url, "\n")
  cat("  Collection:", collection, "\n")
  cat("  Date:", test_date, "\n\n")

  response <- try({
    GET(
      url = stac_url,
      query = query_params,
      add_headers("Accept" = "application/json"),
      timeout(30)
    )
  }, silent = FALSE)

  if (inherits(response, "try-error")) {
    cat("❌ Request failed\n")
    return(invisible(NULL))
  }

  cat("Response status:", status_code(response), "\n")

  if (status_code(response) == 200) {
    content_json <- fromJSON(content(response, "text", encoding = "UTF-8"), simplifyVector = FALSE)

    cat("Number of features returned:", length(content_json$features), "\n\n")

    if (length(content_json$features) > 0) {
      cat("First 3 scene IDs found:\n")
      for (i in 1:min(3, length(content_json$features))) {
        feature <- content_json$features[[i]]
        cat("  ", i, ":", feature$id, "\n")
        cat("      Collection:", feature$collection, "\n")
        cat("      Has Fmask:", !is.null(feature$assets$Fmask), "\n")
        if (!is.null(feature$assets$Fmask)) {
          cat("      Fmask URL:", substr(feature$assets$Fmask$href, 1, 80), "...\n")
        }
      }
    } else {
      cat("No features found. Response:\n")
      print(str(content_json))
    }
  } else {
    cat("❌ Bad status code\n")
    cat("Response:", content(response, "text"), "\n")
  }

  return(invisible(NULL))
}

######################
# Test Function
######################

test_fmask_download <- function(n_scenes = 5, year_filter = NULL) {
  cat("=== TESTING FMASK DOWNLOAD ===\n\n")

  # Find a few NDVI files to test
  ndvi_files <- find_existing_ndvi_files()

  if (nrow(ndvi_files) == 0) {
    cat("❌ No NDVI files found\n")
    return(invisible(NULL))
  }

  # Filter by year if specified
  if (!is.null(year_filter)) {
    ndvi_files <- ndvi_files[ndvi_files$year == year_filter, ]
    cat("Filtering to year", year_filter, "- found", nrow(ndvi_files), "files\n")
  }

  if (nrow(ndvi_files) == 0) {
    cat("❌ No NDVI files found for year", year_filter, "\n")
    return(invisible(NULL))
  }

  # Sample from available files
  test_scenes <- ndvi_files[sample(1:min(100, nrow(ndvi_files)), min(n_scenes, nrow(ndvi_files))), ]

  cat("Testing", nrow(test_scenes), "scenes:\n")
  for (i in 1:nrow(test_scenes)) {
    cat(" ", i, ":", test_scenes$scene_id[i], "(", test_scenes$year[i], ")\n")
  }
  cat("\n")

  # Set up NASA session
  nasa_session <- create_nasa_session()

  # Try downloading
  results <- data.frame(
    scene_id = test_scenes$scene_id,
    year = test_scenes$year,
    success = FALSE,
    message = "",
    stringsAsFactors = FALSE
  )

  for (i in 1:nrow(test_scenes)) {
    scene <- test_scenes[i, ]
    cat("\nTesting scene", i, "of", nrow(test_scenes), "...\n")

    output_dir <- file.path(
      hls_paths$raw_hls_data,
      paste0("year_", scene$year),
      "fmask_test"
    )
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

    success <- download_fmask_for_scene(
      scene$scene_id,
      scene$collection,
      scene$tile_id,
      scene$date,
      output_dir,
      nasa_session
    )

    results$success[i] <- success
    results$message[i] <- ifelse(success, "Downloaded", "Failed")
  }

  cat("\n\n=== TEST RESULTS ===\n")
  print(results)
  cat("\nSuccess rate:", sum(results$success), "/", nrow(results), "\n")

  return(results)
}

# Instructions
cat("=== FMASK RETROACTIVE DOWNLOAD READY ===\n")
cat("This script downloads Fmask quality layers for existing NDVI data\n")
cat("Fmask files are ~1-2 MB each vs 15-25 MB for Red/NIR bands\n\n")
cat("To test with 5 random scenes first:\n")
cat("  test_results <- test_fmask_download()\n")
cat("To test with scenes from a specific year:\n")
cat("  test_results <- test_fmask_download(year_filter = 2024)\n\n")
cat("To run with existence check (slower, more accurate):\n")
cat("  results <- run_fmask_download()\n\n")
cat("To run without existence check (faster, may attempt duplicate downloads):\n")
cat("  results <- run_fmask_download(skip_existence_check = TRUE)\n\n")
cat("Estimated time: 30-60 min for ~5000 scenes\n")
cat("Estimated download: ~2-5 GB total\n\n")
