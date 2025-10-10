# Bulk Fmask Archive Download for Midwest Region
# Purpose: Download complete Fmask archive for 2013-2024 to match against existing NDVI
# Strategy: Systematic download by date ranges, then match against existing data

library(httr)
library(jsonlite)

# Source required scripts
source("00_setup_paths.R")
source("01_HLS_data_acquisition_FINAL.R")

hls_paths <- get_hls_paths()

cat("=== BULK FMASK ARCHIVE DOWNLOAD ===\n\n")

######################
# Search for Fmask Data
######################

search_fmask_data <- function(bbox, start_date, end_date, max_items = 2000) {

  cat("Searching for Fmask data:\n")
  cat("  Bbox:", paste(bbox, collapse = ", "), "\n")
  cat("  Date range:", start_date, "to", end_date, "\n")

  stac_url <- "https://cmr.earthdata.nasa.gov/stac/LPCLOUD/search"

  query_params <- list(
    collections = "HLSL30.v2.0,HLSS30.v2.0",  # Both Landsat and Sentinel
    bbox = paste(bbox, collapse = ","),
    datetime = paste0(start_date, "T00:00:00Z/", end_date, "T23:59:59Z"),
    limit = max_items
  )

  cat("Making API request...\n")

  response <- try({
    GET(
      url = stac_url,
      query = query_params,
      add_headers(
        "Accept" = "application/json",
        "User-Agent" = "R/httr HLS-CONUS-Drought-Monitor"
      ),
      timeout(60)
    )
  }, silent = TRUE)

  if (inherits(response, "try-error") || status_code(response) != 200) {
    cat("❌ Search failed\n")
    return(NULL)
  }

  content_json <- fromJSON(content(response, "text", encoding = "UTF-8"), simplifyVector = FALSE)

  if (is.null(content_json$features) || length(content_json$features) == 0) {
    cat("No features found\n")
    return(NULL)
  }

  cat("Found", length(content_json$features), "scenes\n")

  # Process features
  scenes <- list()
  for (feature in content_json$features) {

    # Check if Fmask asset exists
    if (is.null(feature$assets$Fmask)) {
      next
    }

    scene_id <- feature$id
    collection_id <- feature$collection

    # Get Fmask URL
    fmask_url <- feature$assets$Fmask$href

    # Extract tile and date info
    tile_id <- sub(".*\\.(T[0-9A-Z]+)\\..*", "\\1", scene_id)
    date_string <- sub(".*\\.([0-9]{7}T[0-9]{6})\\..*", "\\1", scene_id)
    year <- as.numeric(substr(date_string, 1, 4))

    scenes[[length(scenes) + 1]] <- list(
      scene_id = scene_id,
      tile_id = tile_id,
      collection = collection_id,
      year = year,
      fmask_url = fmask_url,
      sensor = if (collection_id == "HLSL30_2.0") "L30" else "S30"
    )
  }

  cat("Scenes with Fmask:", length(scenes), "\n\n")

  return(scenes)
}

######################
# Download Fmask Files
######################

download_fmask_archive <- function(scenes, nasa_session) {

  if (length(scenes) == 0) {
    cat("No scenes to download\n")
    return(list(success = 0, skipped = 0, failed = 0))
  }

  success_count <- 0
  skip_count <- 0
  fail_count <- 0

  pb <- txtProgressBar(min = 0, max = length(scenes), style = 3)

  for (i in 1:length(scenes)) {
    scene <- scenes[[i]]

    # Determine output directory by year and tile
    output_dir <- file.path(
      hls_paths$raw_hls_data,
      paste0("year_", scene$year),
      paste0("midwest_", scene$tile_id)
    )

    dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

    # Output filename
    fmask_file <- file.path(output_dir, paste0(scene$scene_id, "_Fmask.tif"))

    # Skip if already exists
    if (file.exists(fmask_file)) {
      skip_count <- skip_count + 1
      setTxtProgressBar(pb, i)
      next
    }

    # Download
    success <- download_hls_band(scene$fmask_url, fmask_file, nasa_session)

    if (success) {
      success_count <- success_count + 1
    } else {
      fail_count <- fail_count + 1
    }

    setTxtProgressBar(pb, i)
  }

  close(pb)

  return(list(
    success = success_count,
    skipped = skip_count,
    failed = fail_count
  ))
}

######################
# Main Execution
######################

download_fmask_archive_by_year <- function(start_year = 2013, end_year = 2024,
                                           months_per_batch = 3) {

  cat("=== DOWNLOADING FMASK ARCHIVE ===\n")
  cat("Years:", start_year, "to", end_year, "\n")
  cat("Batch size:", months_per_batch, "months\n\n")

  # Midwest bounding box
  midwest_bbox <- c(-97, 37, -80, 49)

  # Set up NASA session
  nasa_session <- create_nasa_session()

  # Track overall results
  total_success <- 0
  total_skipped <- 0
  total_failed <- 0

  # Process by year and batch
  for (year in start_year:end_year) {

    cat("\n=== YEAR", year, "===\n")

    # Process year in batches to avoid hitting API limits
    for (start_month in seq(1, 12, by = months_per_batch)) {

      end_month <- min(start_month + months_per_batch - 1, 12)

      # Create date range
      start_date <- sprintf("%04d-%02d-01", year, start_month)

      # Last day of end_month
      if (end_month == 12) {
        end_date <- sprintf("%04d-12-31", year)
      } else {
        end_date <- sprintf("%04d-%02d-01", year, end_month + 1)
        end_date <- as.character(as.Date(end_date) - 1)
      }

      cat(sprintf("\nBatch: %s to %s\n", start_date, end_date))

      # Search for scenes
      scenes <- search_fmask_data(
        bbox = midwest_bbox,
        start_date = start_date,
        end_date = end_date,
        max_items = 2000
      )

      if (is.null(scenes) || length(scenes) == 0) {
        cat("No scenes found for this batch\n")
        next
      }

      # Download
      results <- download_fmask_archive(scenes, nasa_session)

      total_success <- total_success + results$success
      total_skipped <- total_skipped + results$skipped
      total_failed <- total_failed + results$failed

      cat(sprintf("Batch results: %d downloaded, %d skipped, %d failed\n",
                  results$success, results$skipped, results$failed))

      # Brief pause to be nice to the API
      Sys.sleep(2)
    }
  }

  cat("\n\n=== FMASK ARCHIVE DOWNLOAD COMPLETE ===\n")
  cat("Total downloaded:", total_success, "\n")
  cat("Total skipped (already exist):", total_skipped, "\n")
  cat("Total failed:", total_failed, "\n")
  cat("Total processed:", total_success + total_skipped + total_failed, "\n\n")

  # Estimate data downloaded
  avg_fmask_size_mb <- 1.5
  total_mb <- total_success * avg_fmask_size_mb
  cat("Estimated data downloaded:", round(total_mb / 1024, 2), "GB\n\n")

  return(list(
    success = total_success,
    skipped = total_skipped,
    failed = total_failed
  ))
}

# Instructions
cat("=== BULK FMASK ARCHIVE DOWNLOAD READY ===\n")
cat("This script downloads ALL Fmask data for the Midwest region 2013-2024\n")
cat("Download happens in 3-month batches to manage API limits\n\n")
cat("To download the complete archive:\n")
cat("  results <- download_fmask_archive_by_year()\n\n")
cat("To download specific years:\n")
cat("  results <- download_fmask_archive_by_year(start_year = 2020, end_year = 2024)\n\n")
cat("Estimated time: 2-4 hours for full 2013-2024 archive\n")
cat("Estimated download: 5-10 GB total\n\n")
