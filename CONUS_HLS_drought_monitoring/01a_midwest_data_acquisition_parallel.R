# CONUS HLS Drought Monitoring - HLS Data Acquisition (PARALLEL VERSION)
# Full CONUS domain implementation with parallel processing
# Processes 40 tiles (8x5 grid) across continental United States
#
# PARALLELIZATION: Uses future.apply to process tiles in parallel (4 cores max)

library(httr)
library(jsonlite)
library(terra)
library(sf)
library(future)
library(future.apply)

# Source the main pipeline
source("01_HLS_data_acquisition_FINAL.R")

######################
# CONUS Domain Definition
######################

# Full Continental United States boundaries
# Covers all 48 contiguous states
conus_bbox <- c(
  xmin = -125,  # Western edge (Pacific coast)
  ymin = 25,    # Southern edge (southern tip of Texas/Florida)
  xmax = -66,   # Eastern edge (Atlantic coast)
  ymax = 49     # Northern edge (Canadian border)
)

cat("CONUS HLS Drought Monitoring Domain:\n")
cat("West:", conus_bbox[1], "°W\n")
cat("South:", conus_bbox[2], "°N\n")
cat("East:", conus_bbox[3], "°W\n")
cat("North:", conus_bbox[4], "°N\n")

# Create processing tiles for full CONUS domain
create_conus_tiles <- function(n_tiles_x = 8, n_tiles_y = 5) {

  cat("Creating CONUS processing grid:", n_tiles_x, "x", n_tiles_y, "tiles\n")

  x_breaks <- seq(conus_bbox[1], conus_bbox[3], length.out = n_tiles_x + 1)
  y_breaks <- seq(conus_bbox[2], conus_bbox[4], length.out = n_tiles_y + 1)

  tiles <- list()

  for (i in 1:n_tiles_x) {
    for (j in 1:n_tiles_y) {
      tile_bbox <- c(x_breaks[i], y_breaks[j], x_breaks[i+1], y_breaks[j+1])

      # Add descriptive names for CONUS regions
      region_name <- paste0("conus_", sprintf("%02d_%02d", i, j))

      tiles[[length(tiles) + 1]] <- list(
        id = region_name,
        bbox = tile_bbox,
        region = "conus"
      )
    }
  }

  return(tiles)
}

######################
# CONUS Data Acquisition Functions
######################

# Worker function to process a single tile for a single month
# MUST be at top level so workers can access it when they source this file
# Each worker creates its own NASA session to avoid connection conflicts
process_tile_month_worker <- function(tile, year, month_start, month_end,
                                      cloud_cover_max, worker_hls_paths) {

  # Each worker needs its own NASA session
  worker_nasa_session <- create_nasa_session()

  tile_stats <- list(
    tile_id = tile$id,
    scenes_found = 0,
    scenes_downloaded = 0,
    ndvi_processed = 0,
    landsat_count = 0,
    sentinel_count = 0
  )

  # Search for HLS data
  # Use max_items=1000 to avoid truncation; cloud_cover=100 to get all scenes
  # (pixel-level Fmask handles cloud masking during NDVI calculation)
  scenes <- search_hls_data(
    bbox = tile$bbox,
    start_date = month_start,
    end_date = month_end,
    cloud_cover = cloud_cover_max,
    max_items = 1000
  )

  if (length(scenes) == 0) {
    return(tile_stats)
  }

  tile_stats$scenes_found <- length(scenes)

  # Count by sensor type
  for (scene in scenes) {
    if (scene$sensor == "Landsat") {
      tile_stats$landsat_count <- tile_stats$landsat_count + 1
    } else {
      tile_stats$sentinel_count <- tile_stats$sentinel_count + 1
    }
  }

  # Create year/tile directory (using worker's path object)
  tile_dir <- file.path(worker_hls_paths$raw_hls_data, paste0("year_", year), tile$id)

  # Process each scene
  for (scene_idx in seq_along(scenes)) {
    scene <- scenes[[scene_idx]]

    # Set up file paths
    red_file <- file.path(tile_dir, paste0(scene$scene_id, "_B04.tif"))
    nir_file <- file.path(tile_dir, paste0(scene$scene_id, "_", scene$nir_band, ".tif"))
    fmask_file <- file.path(tile_dir, paste0(scene$scene_id, "_Fmask.tif"))
    ndvi_file <- file.path(worker_hls_paths$processed_ndvi, "daily", year, paste0(scene$scene_id, "_NDVI.tif"))

    # Skip if NDVI already exists
    if (file.exists(ndvi_file)) {
      tile_stats$ndvi_processed <- tile_stats$ndvi_processed + 1
      next
    }

    # Download bands (Red, NIR, and Fmask)
    red_success <- download_hls_band(scene$red_url, red_file, worker_nasa_session)
    if (red_success) {
      nir_success <- download_hls_band(scene$nir_url, nir_file, worker_nasa_session)
      if (nir_success) {
        # Download Fmask (quality layer) - IMPORTANT for quality control
        fmask_success <- download_hls_band(scene$fmask_url, fmask_file, worker_nasa_session)

        if (!fmask_success) {
          cat("    ⚠ WARNING: Fmask download failed for", scene$scene_id, "\n")
        }

        tile_stats$scenes_downloaded <- tile_stats$scenes_downloaded + 1

        # Calculate NDVI with quality filtering
        ndvi_result <- try({
          calculate_ndvi_from_hls(red_file, nir_file, ndvi_file,
                                 fmask_file = if(fmask_success) fmask_file else NULL)
        }, silent = TRUE)

        if (!inherits(ndvi_result, "try-error")) {
          tile_stats$ndvi_processed <- tile_stats$ndvi_processed + 1
        }
      }
    }
  }

  return(tile_stats)
}

# Acquire full time series for CONUS domain
acquire_conus_data <- function(start_year = 2013,  # First HLS data available
                               end_year = 2025,    # Current year
                               cloud_cover_max = 40) {  # Slightly higher for completeness

  cat("=== CONUS HLS DROUGHT MONITORING DATA ACQUISITION (PARALLEL) ===\n")
  cat("Building", end_year - start_year + 1, "year climatology (", start_year, "-", end_year, ")\n")
  cat("Domain: Full Continental United States (CONUS)\n")
  cat("Storage:", hls_paths$base, "\n")
  cat("Parallel processing: 4 workers\n\n")

  # Set up parallel processing (4 cores max to avoid overwhelming the system)
  options(future.globals.maxSize = 2 * 1024^3)  # 2 GB
  plan(multisession, workers = 4)
  cat("✓ Parallel backend configured (4 workers)\n")

  # Create CONUS processing tiles (8x5 = 40 tiles)
  conus_tiles <- create_conus_tiles(n_tiles_x = 8, n_tiles_y = 5)
  
  # Initialize tracking
  total_stats <- list(
    years_processed = 0,
    total_scenes_found = 0,
    total_scenes_downloaded = 0,
    total_ndvi_processed = 0,
    landsat_scenes = 0,
    sentinel_scenes = 0
  )

  # Process each year
  for (year in start_year:end_year) {

    cat("=== PROCESSING YEAR", year, "===\n")

    year_stats <- list(
      scenes_found = 0,
      scenes_downloaded = 0,
      ndvi_processed = 0,
      landsat_count = 0,
      sentinel_count = 0
    )

    # Process each MONTH to avoid API 100-item limit
    for (month in 1:12) {

      # Define month date range
      month_start <- sprintf("%04d-%02d-01", year, month)
      # Get last day of month
      if (month == 12) {
        month_end <- sprintf("%04d-12-31", year)
      } else {
        next_month <- as.Date(sprintf("%04d-%02d-01", year, month + 1))
        month_end <- as.character(next_month - 1)
      }

      cat("\n--- Processing", format(as.Date(month_start), "%B %Y"), "---\n")
      cat("Processing", length(conus_tiles), "tiles in parallel (4 workers)...\n")

      # Process all tiles for this month in PARALLEL with error recovery
      # Each tile gets its own worker with independent NASA session
      # Fresh worker pool each month to prevent memory buildup
      plan(multisession, workers = 4)

      tile_results <- tryCatch({
        future_lapply(conus_tiles, function(tile) {
          # Load required packages in each worker
          library(httr)
          library(terra)

          # Source required functions in each worker
          # NOTE: Must source in this order to resolve dependencies
          source("00_setup_paths.R")
          source("01_HLS_data_acquisition_FINAL.R")
          source("01a_midwest_data_acquisition_parallel.R")  # For process_tile_month_worker

          # Get paths in worker environment
          worker_hls_paths <- get_hls_paths()

          # Call the processing function (now available in worker)
          result <- process_tile_month_worker(tile, year, month_start, month_end,
                                    cloud_cover_max, worker_hls_paths)
          gc(verbose = FALSE)
          result
        }, future.seed = TRUE)
      }, error = function(e) {
        cat("WARNING: Parallel processing failed for", format(as.Date(month_start), "%B %Y"),
            ":", conditionMessage(e), "\n")
        cat("Falling back to sequential processing for this month...\n")

        # Sequential fallback - process tiles one at a time
        lapply(conus_tiles, function(tile) {
          tryCatch({
            library(httr)
            library(terra)
            source("00_setup_paths.R")
            source("01_HLS_data_acquisition_FINAL.R")
            source("01a_midwest_data_acquisition_parallel.R")
            worker_hls_paths <- get_hls_paths()
            result <- process_tile_month_worker(tile, year, month_start, month_end,
                                      cloud_cover_max, worker_hls_paths)
            gc(verbose = FALSE)
            result
          }, error = function(e2) {
            cat("  ERROR processing tile", tile$id, ":", conditionMessage(e2), "\n")
            list(tile_id = tile$id, scenes_found = 0, scenes_downloaded = 0,
                 ndvi_processed = 0, landsat_count = 0, sentinel_count = 0)
          })
        })
      })

      # Clean up workers between months
      plan(sequential)
      gc(verbose = FALSE)

      # Aggregate results from all tiles
      for (tile_result in tile_results) {
        year_stats$scenes_found <- year_stats$scenes_found + tile_result$scenes_found
        year_stats$scenes_downloaded <- year_stats$scenes_downloaded + tile_result$scenes_downloaded
        year_stats$ndvi_processed <- year_stats$ndvi_processed + tile_result$ndvi_processed
        year_stats$landsat_count <- year_stats$landsat_count + tile_result$landsat_count
        year_stats$sentinel_count <- year_stats$sentinel_count + tile_result$sentinel_count
      }

      cat("Month complete - Total downloaded so far:", year_stats$scenes_downloaded, "\n")
    }
    
    # Year summary
    cat("\n--- YEAR", year, "SUMMARY ---\n")
    cat("Scenes found:", year_stats$scenes_found, "\n")
    cat("  Landsat:", year_stats$landsat_count, "\n")
    cat("  Sentinel:", year_stats$sentinel_count, "\n")
    cat("Scenes downloaded:", year_stats$scenes_downloaded, "\n")
    cat("NDVI processed:", year_stats$ndvi_processed, "\n")
    cat("Success rate:", round(100 * year_stats$scenes_downloaded / max(year_stats$scenes_found, 1), 1), "%\n\n")
    
    # Update totals
    total_stats$years_processed <- total_stats$years_processed + 1
    total_stats$total_scenes_found <- total_stats$total_scenes_found + year_stats$scenes_found
    total_stats$total_scenes_downloaded <- total_stats$total_scenes_downloaded + year_stats$scenes_downloaded
    total_stats$total_ndvi_processed <- total_stats$total_ndvi_processed + year_stats$ndvi_processed
    total_stats$landsat_scenes <- total_stats$landsat_scenes + year_stats$landsat_count
    total_stats$sentinel_scenes <- total_stats$sentinel_scenes + year_stats$sentinel_count
  }
  
  # Final summary
  cat("=== CONUS HLS ACQUISITION COMPLETE ===\n")
  cat("Years processed:", total_stats$years_processed, "(", start_year, "-", end_year, ")\n")
  cat("Total scenes found:", total_stats$total_scenes_found, "\n")
  cat("  Landsat scenes:", total_stats$landsat_scenes, "\n")
  cat("  Sentinel scenes:", total_stats$sentinel_scenes, "\n")
  cat("Total downloaded:", total_stats$total_scenes_downloaded, "\n")
  cat("Total NDVI products:", total_stats$total_ndvi_processed, "\n")
  cat("Overall success rate:", round(100 * total_stats$total_scenes_downloaded / max(total_stats$total_scenes_found, 1), 1), "%\n")
  cat("Data stored in:", hls_paths$base, "\n")
  cat("CONUS Coverage: 40 tiles (8x5 grid) across continental US\n")
  
  # Estimate data volume
  avg_file_size_mb <- 15  # Rough estimate based on test
  total_gb <- (total_stats$total_scenes_downloaded * 2 * avg_file_size_mb + total_stats$total_ndvi_processed * avg_file_size_mb) / 1024
  cat("Estimated data volume:", round(total_gb, 1), "GB\n")
  
  return(total_stats)
}

######################
# Test CONUS Domain Search
######################

test_conus_search <- function(year = 2024, month = 10) {

  cat("=== TESTING CONUS DOMAIN SEARCH ===\n")
  cat("Test period:", month, "/", year, "\n")

  # Test search over entire CONUS domain for one month
  start_date <- sprintf("%04d-%02d-01", year, month)
  end_date <- sprintf("%04d-%02d-30", year, month)

  scenes <- search_hls_data(
    bbox = conus_bbox,
    start_date = start_date,
    end_date = end_date,
    cloud_cover = 50
  )

  if (length(scenes) > 0) {
    cat("✅ Found", length(scenes), "scenes across CONUS domain\n")
    
    # Analyze by sensor
    landsat_count <- sum(sapply(scenes, function(x) x$sensor == "Landsat"))
    sentinel_count <- sum(sapply(scenes, function(x) x$sensor == "Sentinel"))
    
    cat("Sensor breakdown:\n")
    cat("  Landsat:", landsat_count, "\n")
    cat("  Sentinel:", sentinel_count, "\n")
    
    # Show date range
    dates <- sapply(scenes, function(x) as.character(x$date))
    cat("Date range:", min(dates), "to", max(dates), "\n")
    
    # Sample scene info
    cat("Sample scene:", scenes[[1]]$scene_id, "\n")
    cat("  Sensor:", scenes[[1]]$sensor, "\n")
    cat("  Date:", as.character(scenes[[1]]$date), "\n")
    cat("  Cloud cover:", round(scenes[[1]]$cloud_cover, 1), "%\n")
    
    return(TRUE)
  } else {
    cat("❌ No scenes found\n")
    return(FALSE)
  }
}

# Instructions
cat("=== CONUS HLS DROUGHT MONITORING (PARALLEL) READY ===\n")
cat("Domain: Full Continental United States (48 contiguous states)\n")
cat("Domain bounds:", paste(conus_bbox, collapse = ", "), "\n")
cat("Processing: 40 tiles (8x5 grid) with 4 parallel workers\n")
cat("\nAvailable functions:\n")
cat("1. test_conus_search() - Test search over full CONUS domain\n")
cat("2. acquire_conus_data() - Full historical data acquisition (2013-2025)\n")
cat("\nRecommended: Start with test_conus_search() before full acquisition\n")