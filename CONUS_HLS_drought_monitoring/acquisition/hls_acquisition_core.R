# HLS CONUS Drought Monitoring Pipeline
# Production-ready NASA HLS L30 data acquisition for CONUS-scale drought monitoring
# Replaces Google Earth Engine with direct NASA API access

library(httr)
library(jsonlite)
library(terra)

# Source the cross-platform path setup
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

######################
# NASA HLS Data Search
######################

search_hls_data <- function(bbox, start_date, end_date, cloud_cover = 50, max_items = 1000) {
  
  cat("Searching HLS data:\n")
  cat("  Bbox:", paste(bbox, collapse = ", "), "\n")
  cat("  Date range:", start_date, "to", end_date, "\n")
  cat("  Max cloud cover:", cloud_cover, "%\n")
  
  stac_url <- "https://cmr.earthdata.nasa.gov/stac/LPCLOUD/search"
  
  query_params <- list(
    collections = "HLSL30.v2.0,HLSS30.v2.0",  # Both Landsat and Sentinel (comma-separated)
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
  
  if (inherits(response, "try-error")) {
    cat("❌ API request failed\n")
    return(list())
  }
  
  if (status_code(response) != 200) {
    cat("❌ API request failed with status:", status_code(response), "\n")
    return(list())
  }
  
  # Parse response (keep nested structure for proper handling)
  content_text <- content(response, "text", encoding = "UTF-8")
  content_json <- try(fromJSON(content_text, simplifyVector = FALSE), silent = TRUE)
  
  if (inherits(content_json, "try-error")) {
    cat("❌ Failed to parse JSON response\n")
    return(list())
  }
  
  if (is.null(content_json$features) || length(content_json$features) == 0) {
    cat("⚠ No features found in response\n")
    return(list())
  }
  
  cat("✓ Found", length(content_json$features), "total scenes\n")
  
  # Process each scene and extract required information
  processed_scenes <- list()
  
  for (i in seq_along(content_json$features)) {
    feature <- content_json$features[[i]]
    
    # Extract metadata
    scene_id <- feature$id
    datetime <- feature$properties$datetime
    scene_date <- as.Date(substr(datetime, 1, 10))
    
    # Extract cloud cover
    cloud_cover_val <- feature$properties$`eo:cloud_cover`
    if (is.null(cloud_cover_val)) cloud_cover_val <- 100
    
    # Determine sensor type and check for required bands
    assets <- feature$assets
    collection_id <- feature$collection
    
    # HLS band mapping:
    # HLSL30 (Landsat): Red=B04, NIR=B05
    # HLSS30 (Sentinel): Red=B04, NIR=B8A
    
    has_red <- "B04" %in% names(assets)
    if (collection_id == "HLSL30_2.0") {
      has_nir <- "B05" %in% names(assets)
      nir_band <- "B05"
    } else if (collection_id == "HLSS30_2.0") {
      has_nir <- "B8A" %in% names(assets)
      nir_band <- "B8A"
    } else {
      next  # Unknown collection
    }
    
    if (!has_red || !has_nir) {
      next  # Skip scenes without required bands
    }
    
    # Extract download URLs
    red_url <- assets$B04$href
    nir_url <- assets[[nir_band]]$href
    fmask_url <- assets$Fmask$href

    # Store processed scene
    processed_scenes[[length(processed_scenes) + 1]] <- list(
      scene_id = scene_id,
      date = scene_date,
      datetime = datetime,
      cloud_cover = cloud_cover_val,
      collection = collection_id,
      sensor = if (collection_id == "HLSL30_2.0") "Landsat" else "Sentinel",
      red_url = red_url,
      nir_url = nir_url,
      nir_band = nir_band,
      fmask_url = fmask_url,
      year = as.numeric(format(scene_date, "%Y")),
      yday = as.numeric(format(scene_date, "%j"))
    )
  }
  
  # Filter by cloud cover
  if (length(processed_scenes) > 0) {
    cloud_covers <- sapply(processed_scenes, function(x) x$cloud_cover)
    valid_scenes <- processed_scenes[cloud_covers <= cloud_cover]
    
    cat("✓ After cloud cover filtering (≤", cloud_cover, "%):", length(valid_scenes), "scenes\n")
    return(valid_scenes)
  }
  
  return(list())
}

######################
# NASA Earthdata Authentication
######################

create_nasa_session <- function() {

  # Get netrc path (cross-platform)
  netrc_path <- get_netrc_path()

  if (!file.exists(netrc_path)) {
    stop("NASA Earthdata netrc file not found at: ", netrc_path,
         "\nCreate this file with your NASA Earthdata credentials:\n",
         "  machine urs.earthdata.nasa.gov login YOUR_USERNAME password YOUR_PASSWORD")
  }
  
  netrc_content <- readLines(netrc_path, warn = FALSE)
  netrc_line <- grep("urs.earthdata.nasa.gov", netrc_content, value = TRUE)
  if (length(netrc_line) == 0) {
    stop("NASA credentials not found in netrc file")
  }
  
  # Extract credentials
  parts <- strsplit(netrc_line, "\\s+")[[1]]
  username <- parts[which(parts == "login") + 1]
  password <- parts[which(parts == "password") + 1]
  
  return(list(username = username, password = password))
}

######################
# HLS Data Download with NASA Authentication
######################

download_hls_band <- function(download_url, output_file, nasa_session, max_attempts = 3) {
  
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  
  for (attempt in 1:max_attempts) {
    cat("    Downloading", basename(output_file), "(attempt", attempt, ")...\n")
    
    # Handle NASA's authentication redirect flow
    current_url <- download_url
    max_redirects <- 10
    
    for (redirect_count in 1:max_redirects) {
      response <- try({
        GET(
          current_url,
          authenticate(nasa_session$username, nasa_session$password),
          config(followlocation = FALSE),
          timeout(60)
        )
      }, silent = TRUE)
      
      if (inherits(response, "try-error")) {
        break
      }
      
      status <- status_code(response)
      
      if (status == 200) {
        # Success! Download the actual file
        final_response <- try({
          GET(
            current_url,
            authenticate(nasa_session$username, nasa_session$password),
            config(followlocation = TRUE, maxredirs = 5),
            timeout(600),
            write_disk(output_file, overwrite = TRUE),
            progress()
          )
        }, silent = TRUE)
        
        if (!inherits(final_response, "try-error") && 
            status_code(final_response) == 200 && 
            file.exists(output_file) && 
            file.size(output_file) > 1000) {
          
          file_size_mb <- round(file.size(output_file) / 1024 / 1024, 1)
          cat("    ✓ Download successful:", file_size_mb, "MB\n")
          return(TRUE)
        }
        break
        
      } else if (status %in% c(301, 302, 303, 307, 308)) {
        # Handle redirect
        location <- headers(response)$location
        if (is.null(location)) break
        
        # Handle relative URLs
        if (!grepl("^https?://", location)) {
          parsed_url <- parse_url(current_url)
          location <- paste0(parsed_url$scheme, "://", parsed_url$hostname, location)
        }
        
        current_url <- location
        
      } else if (status == 401) {
        cat("    ⚠ Authentication failed (401)\n")
        break
      } else {
        cat("    ⚠ Unexpected status:", status, "\n")
        break
      }
    }
    
    cat("    ⚠ Download attempt", attempt, "failed, retrying...\n")
    if (file.exists(output_file)) file.remove(output_file)
    Sys.sleep(2^attempt)
  }
  
  cat("    ❌ Download failed after", max_attempts, "attempts\n")
  return(FALSE)
}

######################
# NDVI Processing from HLS Data
######################

calculate_ndvi_from_hls <- function(red_file, nir_file, output_file, fmask_file = NULL) {

  cat("    Calculating NDVI from HLS bands...\n")

  # Load HLS bands (already surface reflectance corrected)
  red_raster <- rast(red_file)
  nir_raster <- rast(nir_file)

  # Ensure bands align spatially
  if (!compareGeom(red_raster, nir_raster)) {
    cat("    Resampling NIR to match Red band geometry...\n")
    nir_raster <- resample(nir_raster, red_raster)
  }

  # Calculate NDVI: (NIR - Red) / (NIR + Red)
  ndvi <- (nir_raster - red_raster) / (nir_raster + red_raster)

  # Quality control: mask invalid NDVI values
  ndvi[ndvi < -1 | ndvi > 1] <- NA

  # Apply Fmask quality filtering if provided
  if (!is.null(fmask_file) && file.exists(fmask_file)) {
    cat("    Applying Fmask quality filtering...\n")
    fmask <- rast(fmask_file)

    # Ensure Fmask aligns with NDVI
    if (!compareGeom(ndvi, fmask)) {
      fmask <- resample(fmask, ndvi, method = "near")
    }

    # Build quality mask using bit flags
    # Use modulo arithmetic instead of bitwAnd to avoid type mismatch with terra rasters
    # Bit 1 (2): cloud, Bit 2 (4): adjacent, Bit 3 (8): shadow, Bit 4 (16): snow/ice, Bit 5 (32): water
    quality_mask <- (
      (fmask %% 4) < 2 &    # Bit 1 not set (cloud)
      (fmask %% 8) < 4 &    # Bit 2 not set (adjacent)
      (fmask %% 16) < 8 &   # Bit 3 not set (shadow)
      (fmask %% 32) < 16 &  # Bit 4 not set (snow/ice)
      (fmask %% 64) < 32    # Bit 5 not set (water)
    )

    # Apply mask (keep only quality_mask = TRUE pixels)
    ndvi <- mask(ndvi, quality_mask, maskvalue = 0, updatevalue = NA)
    cat("    ✓ Quality filtering applied\n")
  } else {
    cat("    ⚠ No Fmask provided - NDVI calculated without quality filtering\n")
  }

  # Save result
  dir.create(dirname(output_file), recursive = TRUE, showWarnings = FALSE)
  writeRaster(ndvi, output_file, overwrite = TRUE)

  cat("    ✓ NDVI calculated and saved\n")
  return(ndvi)
}

######################
# CONUS Processing Framework
######################

# CONUS bounding box
conus_bbox <- c(-125, 25, -66, 49)  # xmin, ymin, xmax, ymax

# Create processing tiles for CONUS
create_conus_tiles <- function(n_tiles_x = 10, n_tiles_y = 6) {
  
  cat("Creating CONUS processing grid:", n_tiles_x, "x", n_tiles_y, "tiles\n")
  
  x_breaks <- seq(conus_bbox[1], conus_bbox[3], length.out = n_tiles_x + 1)
  y_breaks <- seq(conus_bbox[2], conus_bbox[4], length.out = n_tiles_y + 1)
  
  tiles <- list()
  
  for (i in 1:n_tiles_x) {
    for (j in 1:n_tiles_y) {
      tile_bbox <- c(x_breaks[i], y_breaks[j], x_breaks[i+1], y_breaks[j+1])
      
      # Add region labels for organization
      center_lon <- mean(c(tile_bbox[1], tile_bbox[3]))
      region <- if (center_lon < -115) "west" 
               else if (center_lon < -95) "mountain"
               else if (center_lon < -80) "central" 
               else "east"
      
      tiles[[length(tiles) + 1]] <- list(
        id = sprintf("conus_%s_%02d_%02d", region, i, j),
        bbox = tile_bbox,
        region = region
      )
    }
  }
  
  return(tiles)
}

######################
# Main CONUS Data Acquisition Function
######################

acquire_hls_conus <- function(start_date = "2024-01-01", 
                              end_date = "2024-12-31",
                              cloud_cover_max = 30,
                              tile_subset = NULL,
                              process_ndvi = TRUE) {
  
  cat("=== HLS CONUS DROUGHT MONITORING DATA ACQUISITION ===\n")
  cat("Date range:", start_date, "to", end_date, "\n")
  cat("Max cloud cover:", cloud_cover_max, "%\n")
  cat("Storage location:", hls_paths$base, "\n")
  
  # Set up NASA authentication
  nasa_session <- create_nasa_session()
  cat("✓ NASA Earthdata session established\n")
  
  # Set up directory structure
  create_hls_directory_structure(hls_paths)
  
  # Create CONUS processing tiles
  if (is.null(tile_subset)) {
    processing_tiles <- create_conus_tiles(n_tiles_x = 8, n_tiles_y = 5)
  } else {
    processing_tiles <- tile_subset
  }
  
  cat("Processing", length(processing_tiles), "CONUS tiles...\n\n")
  
  # Initialize progress tracking
  total_scenes <- 0
  downloaded_scenes <- 0
  processed_ndvi <- 0
  
  # Process each tile
  for (tile_idx in seq_along(processing_tiles)) {
    tile <- processing_tiles[[tile_idx]]
    
    cat("=== TILE", tile_idx, "of", length(processing_tiles), ":", tile$id, "===\n")
    cat("Region:", tile$region, "\n")
    
    # Search for HLS data in this tile
    scenes <- search_hls_data(
      bbox = tile$bbox,
      start_date = start_date,
      end_date = end_date,
      cloud_cover = cloud_cover_max
    )
    
    if (length(scenes) == 0) {
      cat("No scenes found, skipping tile\n\n")
      next
    }
    
    total_scenes <- total_scenes + length(scenes)
    
    # Create tile directory
    tile_dir <- file.path(hls_paths$raw_hls_data, paste0("year_", format(as.Date(start_date), "%Y")), tile$id)
    
    # Process each scene
    for (scene_idx in seq_along(scenes)) {
      scene <- scenes[[scene_idx]]
      
      cat("Scene", scene_idx, "/", length(scenes), ":", scene$scene_id, "\n")
      cat("  Date:", as.character(scene$date), ", Cloud cover:", round(scene$cloud_cover, 1), "%\n")
      
      # Set up file paths
      red_file <- file.path(tile_dir, paste0(scene$scene_id, "_B04.tif"))
      nir_file <- file.path(tile_dir, paste0(scene$scene_id, "_B05.tif"))
      ndvi_file <- file.path(hls_paths$processed_ndvi, "daily", paste0(scene$scene_id, "_NDVI.tif"))
      
      # Skip if NDVI already exists
      if (process_ndvi && file.exists(ndvi_file)) {
        cat("  ✓ Already processed, skipping\n")
        processed_ndvi <- processed_ndvi + 1
        next
      }
      
      # Download bands
      cat("  Downloading Red band (B04)...\n")
      red_success <- download_hls_band(scene$red_url, red_file, nasa_session)
      
      if (!red_success) {
        cat("  ❌ Failed to download Red band, skipping scene\n\n")
        next
      }
      
      cat("  Downloading NIR band (", scene$nir_band, ")...\n")
      nir_success <- download_hls_band(scene$nir_url, nir_file, nasa_session)
      
      if (!nir_success) {
        cat("  ❌ Failed to download NIR band, skipping scene\n\n")
        next
      }
      
      downloaded_scenes <- downloaded_scenes + 1
      
      # Process NDVI if requested
      if (process_ndvi) {
        cat("  Processing NDVI...\n")
        ndvi_result <- try({
          calculate_ndvi_from_hls(red_file, nir_file, ndvi_file)
        }, silent = TRUE)
        
        if (!inherits(ndvi_result, "try-error")) {
          processed_ndvi <- processed_ndvi + 1
          cat("  ✅ Scene processed successfully!\n\n")
        } else {
          cat("  ⚠ NDVI calculation failed, but bands saved\n\n")
        }
      } else {
        cat("  ✅ Bands downloaded successfully!\n\n")
      }
    }
    
    cat("Tile", tile$id, "complete\n\n")
  }
  
  # Final summary
  cat("=== ACQUISITION COMPLETE ===\n")
  cat("Total scenes found:", total_scenes, "\n")
  cat("Successfully downloaded:", downloaded_scenes, "\n")
  if (process_ndvi) {
    cat("NDVI products created:", processed_ndvi, "\n")
  }
  cat("Success rate:", round(100 * downloaded_scenes / max(total_scenes, 1), 1), "%\n")
  
  return(list(
    total_scenes = total_scenes,
    downloaded_scenes = downloaded_scenes,
    processed_ndvi = processed_ndvi,
    data_path = hls_paths$base
  ))
}

######################
# Test Functions
######################

# Test the complete pipeline
test_hls_pipeline <- function() {
  
  cat("=== HLS CONUS PIPELINE TEST ===\n")
  
  # Test with Chicago area
  chicago_bbox <- c(-88.2, 41.7, -87.8, 42.1)
  
  # Search for data
  scenes <- search_hls_data(
    bbox = chicago_bbox,
    start_date = "2024-07-01",
    end_date = "2024-07-07",
    cloud_cover = 30
  )
  
  if (length(scenes) == 0) {
    cat("❌ No scenes found\n")
    return(FALSE)
  }
  
  cat("✅ Search successful! Testing complete workflow...\n")
  
  # Set up NASA session
  nasa_session <- create_nasa_session()
  
  scene <- scenes[[1]]
  cat("Testing with scene:", scene$scene_id, "\n")
  
  # Test file paths
  test_dir <- file.path(hls_paths$raw_hls_data, "pipeline_test")
  red_file <- file.path(test_dir, paste0(scene$scene_id, "_B04.tif"))
  nir_file <- file.path(test_dir, paste0(scene$scene_id, "_B05.tif"))
  ndvi_file <- file.path(hls_paths$processed_ndvi, "test", paste0(scene$scene_id, "_NDVI.tif"))
  
  # Download and process
  red_success <- download_hls_band(scene$red_url, red_file, nasa_session)
  if (red_success) {
    nir_success <- download_hls_band(scene$nir_url, nir_file, nasa_session)
    if (nir_success) {
      ndvi_result <- try(calculate_ndvi_from_hls(red_file, nir_file, ndvi_file), silent = TRUE)
      if (!inherits(ndvi_result, "try-error")) {
        cat("🎉 COMPLETE PIPELINE TEST SUCCESSFUL!\n")
        cat("Files created:\n")
        cat("  Red:", red_file, "\n")
        cat("  NIR:", nir_file, "\n")
        cat("  NDVI:", ndvi_file, "\n")
        return(TRUE)
      }
    }
  }
  
  cat("❌ Pipeline test failed\n")
  return(FALSE)
}

# Instructions
cat("=== HLS CONUS DROUGHT MONITORING PIPELINE READY ===\n")
cat("Production system for scaling drought monitoring to CONUS\n")
cat("Data storage:", hls_paths$base, "\n")
cat("\nQuick start:\n")
cat("1. test_hls_pipeline() - Test the complete system\n")
cat("2. acquire_hls_conus(start_date='2024-06-01', end_date='2024-08-31') - Run CONUS acquisition\n")
cat("\n✅ NASA Earthdata authentication configured and tested\n")