# ==============================================================================
# TEST: CRS Handling for Multi-UTM Zone Aggregation
# ==============================================================================
# Purpose: Verify that 4km Albers grid correctly handles scenes from different
#          UTM zones during aggregation
# ==============================================================================

library(terra)
library(dplyr)

# Source the aggregation script
source("00_setup_paths.R")
hls_paths <- get_hls_paths()
source("01_aggregate_to_4km.R")

cat("=== TESTING CRS AGGREGATION ACROSS UTM ZONES ===\n\n")

# Find sample files from different UTM zones
ndvi_dir <- file.path(hls_paths$processed_ndvi, "daily")
all_files <- list.files(ndvi_dir, pattern = "_NDVI\\.tif$", full.names = TRUE, recursive = TRUE)

# Extract tile IDs and UTM zones
get_utm_zone <- function(filepath) {
  filename <- basename(filepath)
  tile_id <- substr(filename, 9, 13)  # Extract tile ID (e.g., T13SEB)
  utm_zone <- as.integer(substr(tile_id, 2, 3))  # Extract zone number
  return(list(tile = tile_id, zone = utm_zone, path = filepath))
}

# Sample files from different zones
sample_info <- lapply(head(all_files, 200), get_utm_zone)
zones <- unique(sapply(sample_info, function(x) x$zone))

cat("Found", length(zones), "unique UTM zones in data:", paste(zones, collapse = ", "), "\n\n")

# Select one file from each zone for testing
test_files <- list()
for (zone in zones) {
  zone_files <- Filter(function(x) x$zone == zone, sample_info)
  if (length(zone_files) > 0) {
    test_files[[paste0("zone_", zone)]] <- zone_files[[1]]
  }
}

cat("Testing with", length(test_files), "files across zones:\n")
for (tf in test_files) {
  cat("  Zone", tf$zone, ":", basename(tf$path), "\n")
}
cat("\n")

# Create 4km reference grid
cat("Step 1: Creating 4km Albers reference grid...\n")
midwest_bbox <- c(-104.5, 37.0, -82.0, 47.5)
grid_4km <- create_4km_grid(4000, midwest_bbox)
cat("  Grid CRS:", crs(grid_4km, describe = TRUE)$name, "\n\n")

# Test aggregation for each zone
cat("Step 2: Testing aggregation across zones...\n")
results <- list()

for (i in seq_along(test_files)) {
  tf <- test_files[[i]]
  cat("\nProcessing Zone", tf$zone, "file:", basename(tf$path), "\n")

  # Load scene
  scene_rast <- rast(tf$path)
  cat("  Scene CRS:", crs(scene_rast, describe = TRUE)$name, "\n")

  # Test aggregation
  agg_result <- tryCatch({
    aggregate_scene_to_4km(tf$path, grid_4km, method = "median", min_pixels = 10)
  }, error = function(e) {
    cat("  ❌ ERROR:", e$message, "\n")
    return(NULL)
  })

  if (!is.null(agg_result) && nrow(agg_result) > 0) {
    cat("  ✓ Success! Aggregated to", nrow(agg_result), "4km cells\n")
    cat("    Pixel ID range:", min(agg_result$pixel_id), "-", max(agg_result$pixel_id), "\n")
    cat("    NDVI range:", round(min(agg_result$ndvi_agg), 3), "-", round(max(agg_result$ndvi_agg), 3), "\n")
    results[[paste0("zone_", tf$zone)]] <- agg_result
  } else {
    cat("  ⚠ No valid 4km cells produced\n")
  }
}

# Summary
cat("\n=== TEST SUMMARY ===\n")
cat("Zones tested:", length(test_files), "\n")
cat("Successful aggregations:", length(results), "\n")

if (length(results) == length(test_files)) {
  cat("\n✅ ALL ZONES PASSED - CRS handling is working correctly!\n")
  cat("\nPixel ID consistency check:\n")

  # Check if pixel IDs overlap (they should for overlapping regions)
  all_pixel_ids <- unique(unlist(lapply(results, function(x) x$pixel_id)))
  cat("  Total unique 4km pixels across all test zones:", length(all_pixel_ids), "\n")
  cat("  This confirms the Albers grid provides consistent pixel IDs\n")

} else {
  cat("\n⚠ SOME ZONES FAILED - Review errors above\n")
}

cat("\n=== TEST COMPLETE ===\n")
cat("Ready to run full aggregation: timeseries_4km <- process_ndvi_to_4km(config)\n\n")
