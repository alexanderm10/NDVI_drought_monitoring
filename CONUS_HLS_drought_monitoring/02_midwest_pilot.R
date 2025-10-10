# NIDIS Midwest DEWS Pilot - HLS Drought Monitoring
# Pilot implementation for Midwest Drought Early Warning System domain
# Tests full workflow before CONUS scaling

library(httr)
library(jsonlite)
library(terra)
library(sf)

# Source the main pipeline
source("01_HLS_data_acquisition_FINAL.R")

######################
# NIDIS Midwest DEWS Domain Definition
######################

# NIDIS Midwest DEWS approximate boundaries
# Covers: Iowa, Illinois, Indiana, southern Wisconsin, southern Minnesota, 
# eastern Nebraska, eastern Kansas, western Missouri, northern Missouri
midwest_dews_bbox <- c(
  xmin = -104.5,  # Western edge (eastern Nebraska/Kansas)
  ymin = 37.0,    # Southern edge (northern Kansas/Missouri)
  xmax = -82.0,   # Eastern edge (Indiana/Ohio border)
  ymax = 47.5     # Northern edge (Minnesota/Wisconsin)
)

cat("NIDIS Midwest DEWS Domain:\n")
cat("West:", midwest_dews_bbox[1], "°W\n")
cat("South:", midwest_dews_bbox[2], "°N\n") 
cat("East:", midwest_dews_bbox[3], "°W\n")
cat("North:", midwest_dews_bbox[4], "°N\n")

# Create smaller processing tiles for the Midwest domain
create_midwest_tiles <- function(n_tiles_x = 4, n_tiles_y = 3) {
  
  cat("Creating Midwest DEWS processing grid:", n_tiles_x, "x", n_tiles_y, "tiles\n")
  
  x_breaks <- seq(midwest_dews_bbox[1], midwest_dews_bbox[3], length.out = n_tiles_x + 1)
  y_breaks <- seq(midwest_dews_bbox[2], midwest_dews_bbox[4], length.out = n_tiles_y + 1)
  
  tiles <- list()
  
  for (i in 1:n_tiles_x) {
    for (j in 1:n_tiles_y) {
      tile_bbox <- c(x_breaks[i], y_breaks[j], x_breaks[i+1], y_breaks[j+1])
      
      # Add descriptive names for Midwest regions
      region_name <- paste0("midwest_", sprintf("%02d_%02d", i, j))
      
      tiles[[length(tiles) + 1]] <- list(
        id = region_name,
        bbox = tile_bbox,
        region = "midwest_dews"
      )
    }
  }
  
  return(tiles)
}

######################
# Pilot Data Acquisition Functions
######################

# Acquire full time series for Midwest pilot
acquire_midwest_pilot_data <- function(start_year = 2014,  # First full year of HLS
                                      end_year = 2023,    # Complete climatology
                                      cloud_cover_max = 40) {  # Slightly higher for completeness
  
  cat("=== NIDIS MIDWEST DEWS PILOT DATA ACQUISITION ===\n")
  cat("Building", end_year - start_year + 1, "year climatology (", start_year, "-", end_year, ")\n")
  cat("Domain: Midwest Drought Early Warning System\n")
  cat("Storage:", hls_paths$base, "\n\n")
  
  # Set up NASA session
  nasa_session <- create_nasa_session()
  
  # Create Midwest processing tiles
  midwest_tiles <- create_midwest_tiles(n_tiles_x = 4, n_tiles_y = 3)
  
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
    year_start <- paste0(year, "-01-01")
    year_end <- paste0(year, "-12-31")
    
    year_stats <- list(
      scenes_found = 0,
      scenes_downloaded = 0,
      ndvi_processed = 0,
      landsat_count = 0,
      sentinel_count = 0
    )
    
    # Process each tile for this year
    for (tile_idx in seq_along(midwest_tiles)) {
      tile <- midwest_tiles[[tile_idx]]
      
      cat("--- Tile", tile_idx, "of", length(midwest_tiles), ":", tile$id, "---\n")
      
      # Search for HLS data
      scenes <- search_hls_data(
        bbox = tile$bbox,
        start_date = year_start,
        end_date = year_end,
        cloud_cover = cloud_cover_max,
        max_items = 500  # Allow more scenes per tile/year
      )
      
      if (length(scenes) == 0) {
        cat("No scenes found for this tile/year\n")
        next
      }
      
      year_stats$scenes_found <- year_stats$scenes_found + length(scenes)
      
      # Count by sensor type
      for (scene in scenes) {
        if (scene$sensor == "Landsat") {
          year_stats$landsat_count <- year_stats$landsat_count + 1
        } else {
          year_stats$sentinel_count <- year_stats$sentinel_count + 1
        }
      }
      
      # Create year/tile directory
      tile_dir <- file.path(hls_paths$raw_hls_data, paste0("year_", year), tile$id)
      
      # Process each scene
      for (scene_idx in seq_along(scenes)) {
        scene <- scenes[[scene_idx]]
        
        if (scene_idx %% 10 == 1) {  # Progress indicator
          cat("  Processing scene", scene_idx, "/", length(scenes), "\n")
        }
        
        # Set up file paths
        red_file <- file.path(tile_dir, paste0(scene$scene_id, "_B04.tif"))
        nir_file <- file.path(tile_dir, paste0(scene$scene_id, "_", scene$nir_band, ".tif"))
        fmask_file <- file.path(tile_dir, paste0(scene$scene_id, "_Fmask.tif"))
        ndvi_file <- file.path(hls_paths$processed_ndvi, "daily", year, paste0(scene$scene_id, "_NDVI.tif"))

        # Skip if NDVI already exists
        if (file.exists(ndvi_file)) {
          year_stats$ndvi_processed <- year_stats$ndvi_processed + 1
          next
        }

        # Download bands (Red, NIR, and Fmask)
        red_success <- download_hls_band(scene$red_url, red_file, nasa_session)
        if (red_success) {
          nir_success <- download_hls_band(scene$nir_url, nir_file, nasa_session)
          if (nir_success) {
            # Download Fmask (quality layer) - IMPORTANT for quality control
            fmask_success <- download_hls_band(scene$fmask_url, fmask_file, nasa_session)

            if (!fmask_success) {
              cat("    ⚠ WARNING: Fmask download failed for", scene$scene_id, "\n")
            }

            year_stats$scenes_downloaded <- year_stats$scenes_downloaded + 1

            # Calculate NDVI with quality filtering
            ndvi_result <- try({
              calculate_ndvi_from_hls(red_file, nir_file, ndvi_file, fmask_file = if(fmask_success) fmask_file else NULL)
            }, silent = TRUE)

            if (!inherits(ndvi_result, "try-error")) {
              year_stats$ndvi_processed <- year_stats$ndvi_processed + 1
            }
          }
        }
      }
      
      cat("Tile", tile$id, "complete:", year_stats$scenes_downloaded, "downloaded\n")
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
  cat("=== MIDWEST PILOT ACQUISITION COMPLETE ===\n")
  cat("Years processed:", total_stats$years_processed, "(", start_year, "-", end_year, ")\n")
  cat("Total scenes found:", total_stats$total_scenes_found, "\n")
  cat("  Landsat scenes:", total_stats$landsat_scenes, "\n")
  cat("  Sentinel scenes:", total_stats$sentinel_scenes, "\n")
  cat("Total downloaded:", total_stats$total_scenes_downloaded, "\n")
  cat("Total NDVI products:", total_stats$total_ndvi_processed, "\n")
  cat("Overall success rate:", round(100 * total_stats$total_scenes_downloaded / max(total_stats$total_scenes_found, 1), 1), "%\n")
  cat("Data stored in:", hls_paths$base, "\n")
  
  # Estimate data volume
  avg_file_size_mb <- 15  # Rough estimate based on test
  total_gb <- (total_stats$total_scenes_downloaded * 2 * avg_file_size_mb + total_stats$total_ndvi_processed * avg_file_size_mb) / 1024
  cat("Estimated data volume:", round(total_gb, 1), "GB\n")
  
  return(total_stats)
}

######################
# Test Midwest Domain Search
######################

test_midwest_search <- function(year = 2024, month = 7) {
  
  cat("=== TESTING MIDWEST DEWS DOMAIN SEARCH ===\n")
  cat("Test period:", month, "/", year, "\n")
  
  # Test search over entire Midwest domain for one month
  start_date <- sprintf("%04d-%02d-01", year, month)
  end_date <- sprintf("%04d-%02d-30", year, month)
  
  scenes <- search_hls_data(
    bbox = midwest_dews_bbox,
    start_date = start_date,
    end_date = end_date,
    cloud_cover = 50
  )
  
  if (length(scenes) > 0) {
    cat("✅ Found", length(scenes), "scenes across Midwest domain\n")
    
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
cat("=== NIDIS MIDWEST DEWS PILOT READY ===\n")
cat("Pilot domain covers the core agricultural Midwest drought region\n")
cat("Domain bounds:", paste(midwest_dews_bbox, collapse = ", "), "\n")
cat("\nAvailable functions:\n")
cat("1. test_midwest_search() - Test search over full domain\n") 
cat("2. acquire_midwest_pilot_data() - Full historical data acquisition\n")
cat("\nStart with: test_midwest_search()\n")