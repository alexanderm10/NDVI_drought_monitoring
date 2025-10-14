# Recover Failed Scenes - Simple Approach
# Use the working reprocessing function after re-downloading band files

library(httr)
library(jsonlite)
library(terra)

# Source required scripts
source("00_setup_paths.R")
source("01_HLS_data_acquisition_FINAL.R")
source("reprocess_ndvi_with_fmask.R")

hls_paths <- get_hls_paths()

cat("=== RECOVERING FAILED SCENES ===\n\n")

######################
# Get Failed Scenes from Matching Report
######################

# Read the matching report
matching_report <- read.csv(file.path(hls_paths$processing_logs, "ndvi_fmask_matching_report.csv"),
                            stringsAsFactors = FALSE)

# These are the scene IDs that failed (from your error log)
failed_scene_ids <- c(
  "HLS.L30.T15TUL.2017014T165847.v2.0",
  "HLS.L30.T15TUL.2018001T165846.v2.0",
  "HLS.L30.T15TUL.2019004T165829.v2.0",
  "HLS.L30.T15TUL.2023005T171126.v2.0",
  "HLS.L30.T15TUL.2023006T170512.v2.0",
  "HLS.L30.T15TUL.2023007T165904.v2.0",
  "HLS.L30.T15TUM.2013113T171221.v2.0",
  "HLS.L30.T15TUM.2014004T171156.v2.0",
  "HLS.L30.T15TUM.2014006T165956.v2.0",
  "HLS.L30.T15TUM.2016010T171039.v2.0",
  "HLS.S30.T15TXL.2022001T170721.v2.0",
  "HLS.S30.T15TXL.2023008T165659.v2.0",
  "HLS.S30.T15TXM.2018007T170659.v2.0",
  "HLS.S30.T15TXM.2020007T170659.v2.0",
  "HLS.S30.T15TXM.2020010T171659.v2.0",
  "HLS.S30.T15TXM.2023008T165659.v2.0",
  "HLS.S30.T15TXN.2018009T165651.v2.0",
  "HLS.S30.T15TXN.2019004T165701.v2.0"
)

# Get metadata from matching report for these scenes
failed_scenes <- matching_report[matching_report$scene_id %in% failed_scene_ids, ]

cat("Found", nrow(failed_scenes), "failed scenes in matching report\n\n")

######################
# Download Scene Bands from NASA API
######################

download_scene_bands <- function(scene_id, year, sensor, nasa_session) {

  cat("--- Scene:", scene_id, "---\n")
  cat("  Year:", year, "Sensor:", sensor, "\n")

  # Determine collection and NIR band
  collection <- ifelse(sensor == "L30", "HLSL30_2.0", "HLSS30_2.0")
  nir_band <- ifelse(sensor == "L30", "B05", "B8A")

  # Query NASA STAC API
  stac_url <- paste0("https://cmr.earthdata.nasa.gov/stac/LPCLOUD/collections/",
                     collection, "/items/", scene_id)

  cat("  Querying NASA API...\n")

  response <- try({
    GET(url = stac_url,
        add_headers("Accept" = "application/json"),
        timeout(60))
  }, silent = TRUE)

  if (inherits(response, "try-error") || status_code(response) != 200) {
    cat("  ❌ API query failed\n\n")
    return(NULL)
  }

  # Parse response
  content_json <- fromJSON(content(response, "text", encoding = "UTF-8"), simplifyVector = FALSE)
  assets <- content_json$assets

  if (is.null(assets$B04) || is.null(assets[[nir_band]]) || is.null(assets$Fmask)) {
    cat("  ❌ Missing required bands\n\n")
    return(NULL)
  }

  # Extract URLs
  red_url <- assets$B04$href
  nir_url <- assets[[nir_band]]$href
  fmask_url <- assets$Fmask$href

  # Determine output directory based on existing Fmask path structure
  # Use the year and tile pattern from the matching report
  tile_id <- sub(".*\\.(T[0-9A-Z]+)\\..*", "\\1", scene_id)

  # Find existing directory structure
  existing_dirs <- list.dirs(file.path(hls_paths$raw_hls_data, paste0("year_", year)),
                              recursive = FALSE)

  # Pick first midwest tile directory (they should all work)
  if (length(existing_dirs) > 0) {
    output_dir <- existing_dirs[1]
  } else {
    output_dir <- file.path(hls_paths$raw_hls_data, paste0("year_", year), "midwest_recovery")
    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  }

  # Set up file paths
  red_file <- file.path(output_dir, paste0(scene_id, "_B04.tif"))
  nir_file <- file.path(output_dir, paste0(scene_id, "_", nir_band, ".tif"))
  fmask_file <- file.path(output_dir, paste0(scene_id, "_Fmask.tif"))

  # Download bands
  cat("  Downloading Red band...\n")
  red_success <- download_hls_band(red_url, red_file, nasa_session)

  if (!red_success) {
    cat("  ❌ Red band download failed\n\n")
    return(NULL)
  }

  cat("  Downloading NIR band...\n")
  nir_success <- download_hls_band(nir_url, nir_file, nasa_session)

  if (!nir_success) {
    cat("  ❌ NIR band download failed\n\n")
    return(NULL)
  }

  cat("  Downloading Fmask...\n")
  fmask_success <- download_hls_band(fmask_url, fmask_file, nasa_session)

  if (!fmask_success) {
    cat("  ⚠ Fmask download failed\n\n")
    return(NULL)
  }

  cat("  ✅ All bands downloaded\n\n")

  return(list(
    red_file = red_file,
    nir_file = nir_file,
    fmask_file = fmask_file
  ))
}

######################
# Main Recovery Function
######################

run_scene_recovery <- function() {

  cat("=== STARTING SCENE RECOVERY ===\n\n")

  # Set up NASA session
  nasa_session <- create_nasa_session()
  cat("✓ NASA Earthdata session established\n\n")

  # Track results
  results <- list(
    downloaded = 0,
    reprocessed = 0,
    failed = 0
  )

  for (i in 1:nrow(failed_scenes)) {
    scene <- failed_scenes[i, ]

    # Download bands
    band_files <- download_scene_bands(scene$scene_id, scene$year, scene$sensor, nasa_session)

    if (is.null(band_files)) {
      results$failed <- results$failed + 1
      next
    }

    results$downloaded <- results$downloaded + 1

    # Reprocess using the WORKING function from reprocess_ndvi_with_fmask.R
    cat("  Reprocessing NDVI...\n")

    reprocess_result <- reprocess_ndvi_with_quality(
      red_path = band_files$red_file,
      nir_path = band_files$nir_file,
      fmask_path = band_files$fmask_file,
      output_path = scene$ndvi_path,
      overwrite = TRUE
    )

    if (reprocess_result$status == "success") {
      results$reprocessed <- results$reprocessed + 1
      cat("  ✅ NDVI reprocessed successfully\n\n")
    } else {
      results$failed <- results$failed + 1
      cat("  ⚠ NDVI reprocessing failed:", reprocess_result$message, "\n\n")
    }
  }

  # Summary
  cat("\n=== RECOVERY COMPLETE ===\n")
  cat("Bands re-downloaded:", results$downloaded, "/", nrow(failed_scenes), "\n")
  cat("NDVI reprocessed:", results$reprocessed, "/", nrow(failed_scenes), "\n")
  cat("Still failed:", results$failed, "/", nrow(failed_scenes), "\n")
  cat("Recovery rate:", round(100 * results$reprocessed / nrow(failed_scenes), 1), "%\n\n")

  return(results)
}

# Instructions
cat("=== SCENE RECOVERY READY ===\n")
cat("This script will re-download and reprocess failed scenes\n")
cat("Uses the matching report for metadata and the working reprocessing function\n\n")
cat("To run:\n")
cat("  results <- run_scene_recovery()\n\n")
