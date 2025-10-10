# Re-download Failed Scenes from NDVI Reprocessing
# Purpose: Attempt to recover the 19 scenes that failed during reprocessing

library(httr)
library(jsonlite)
library(terra)

# Source required scripts
source("00_setup_paths.R")
source("01_HLS_data_acquisition_FINAL.R")

hls_paths <- get_hls_paths()

cat("=== RE-DOWNLOADING FAILED SCENES ===\n\n")

######################
# Failed Scene List
######################

failed_scenes <- c(
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
  "HLS.S30.T15TXL.2023008T165699.v2.0",
  "HLS.S30.T15TXM.2018007T170659.v2.0",
  "HLS.S30.T15TXM.2020007T170659.v2.0",
  "HLS.S30.T15TXM.2020010T171659.v2.0",
  "HLS.S30.T15TXM.2023008T165659.v2.0",
  "HLS.S30.T15TXN.2018009T165651.v2.0",
  "HLS.S30.T15TXN.2019004T165701.v2.0"
)

cat("Attempting to re-download", length(failed_scenes), "scenes\n\n")

######################
# Download Scene by ID
######################

download_scene_by_id <- function(scene_id, nasa_session) {

  cat("--- Scene:", scene_id, "---\n")

  # Parse scene ID
  sensor <- ifelse(grepl("L30", scene_id), "Landsat", "Sentinel")
  collection <- ifelse(sensor == "Landsat", "HLSL30_2.0", "HLSS30_2.0")
  nir_band <- ifelse(sensor == "Landsat", "B05", "B8A")

  # Extract year from scene ID (format: HLS.XXX.TXXXXX.YYYYDDDTHHMMSS.v2.0)
  year <- as.numeric(substr(scene_id, 15, 18))

  cat("  Sensor:", sensor, "\n")
  cat("  Year:", year, "\n")

  # Query NASA STAC API for this specific scene
  stac_url <- paste0("https://cmr.earthdata.nasa.gov/stac/LPCLOUD/collections/",
                     collection, "/items/", scene_id)

  cat("  Querying NASA API...\n")

  response <- try({
    GET(
      url = stac_url,
      add_headers(
        "Accept" = "application/json",
        "User-Agent" = "R/httr HLS-CONUS-Drought-Monitor"
      ),
      timeout(60)
    )
  }, silent = TRUE)

  if (inherits(response, "try-error") || status_code(response) != 200) {
    cat("  ❌ Failed to query API (status:",
        ifelse(inherits(response, "try-error"), "error", status_code(response)), ")\n\n")
    return(list(success = FALSE, reason = "API query failed"))
  }

  # Parse response
  content_json <- fromJSON(content(response, "text", encoding = "UTF-8"), simplifyVector = FALSE)

  # Extract download URLs
  assets <- content_json$assets

  if (is.null(assets$B04) || is.null(assets[[nir_band]]) || is.null(assets$Fmask)) {
    cat("  ❌ Missing required bands in API response\n\n")
    return(list(success = FALSE, reason = "Missing bands"))
  }

  red_url <- assets$B04$href
  nir_url <- assets[[nir_band]]$href
  fmask_url <- assets$Fmask$href

  # Determine output directory (use midwest_02_03 or midwest_03_03 based on tile)
  tile_id <- sub(".*\\.(T[0-9A-Z]+)\\..*", "\\1", scene_id)

  # Guess appropriate midwest tile based on HLS tile ID
  if (grepl("T15TU", tile_id)) {
    midwest_tile <- "midwest_02_03"
  } else if (grepl("T15TX", tile_id)) {
    midwest_tile <- "midwest_03_03"
  } else {
    midwest_tile <- "midwest_02_03"  # default
  }

  output_dir <- file.path(hls_paths$raw_hls_data, paste0("year_", year), midwest_tile)
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

  # Set up file paths
  red_file <- file.path(output_dir, paste0(scene_id, "_B04.tif"))
  nir_file <- file.path(output_dir, paste0(scene_id, "_", nir_band, ".tif"))
  fmask_file <- file.path(output_dir, paste0(scene_id, "_Fmask.tif"))

  # Download bands
  cat("  Downloading Red band...\n")
  red_success <- download_hls_band(red_url, red_file, nasa_session)

  if (!red_success) {
    cat("  ❌ Red band download failed\n\n")
    return(list(success = FALSE, reason = "Red band download failed"))
  }

  cat("  Downloading NIR band...\n")
  nir_success <- download_hls_band(nir_url, nir_file, nasa_session)

  if (!nir_success) {
    cat("  ❌ NIR band download failed\n\n")
    return(list(success = FALSE, reason = "NIR band download failed"))
  }

  cat("  Downloading Fmask...\n")
  fmask_success <- download_hls_band(fmask_url, fmask_file, nasa_session)

  if (!fmask_success) {
    cat("  ⚠ Fmask download failed (continuing anyway)\n")
  }

  cat("  ✅ Scene downloaded successfully\n\n")

  return(list(
    success = TRUE,
    red_file = red_file,
    nir_file = nir_file,
    fmask_file = if(fmask_success) fmask_file else NULL
  ))
}

######################
# Main Execution
######################

run_failed_scene_recovery <- function() {

  cat("=== STARTING FAILED SCENE RECOVERY ===\n\n")

  # Set up NASA session
  nasa_session <- create_nasa_session()
  cat("✓ NASA Earthdata session established\n\n")

  # Track results
  results <- list(
    downloaded = 0,
    reprocessed = 0,
    still_failed = 0
  )

  for (scene_id in failed_scenes) {

    # Download scene
    download_result <- download_scene_by_id(scene_id, nasa_session)

    if (!download_result$success) {
      results$still_failed <- results$still_failed + 1
      next
    }

    results$downloaded <- results$downloaded + 1

    # Reprocess NDVI
    if (!is.null(download_result$fmask_file)) {

      # Determine year for output directory
      year <- as.numeric(substr(scene_id, 15, 18))
      ndvi_file <- file.path(hls_paths$processed_ndvi, "daily", year,
                             paste0(scene_id, "_NDVI.tif"))

      cat("  Reprocessing NDVI with quality mask...\n")

      ndvi_result <- try({
        calculate_ndvi_from_hls(
          download_result$red_file,
          download_result$nir_file,
          ndvi_file,
          download_result$fmask_file
        )
      }, silent = TRUE)

      if (!inherits(ndvi_result, "try-error")) {
        results$reprocessed <- results$reprocessed + 1
        cat("  ✅ NDVI reprocessed successfully\n\n")
      } else {
        cat("  ⚠ NDVI reprocessing failed:", ndvi_result[1], "\n\n")
      }
    }
  }

  # Summary
  cat("\n=== RECOVERY COMPLETE ===\n")
  cat("Scenes successfully re-downloaded:", results$downloaded, "/", length(failed_scenes), "\n")
  cat("NDVI successfully reprocessed:", results$reprocessed, "/", length(failed_scenes), "\n")
  cat("Still failed:", results$still_failed, "/", length(failed_scenes), "\n")

  recovery_rate <- round(100 * results$reprocessed / length(failed_scenes), 1)
  cat("Recovery rate:", recovery_rate, "%\n\n")

  return(results)
}

# Instructions
cat("=== FAILED SCENE RECOVERY READY ===\n")
cat("This script will attempt to re-download and reprocess the 19 failed scenes\n\n")
cat("To run:\n")
cat("  results <- run_failed_scene_recovery()\n\n")
