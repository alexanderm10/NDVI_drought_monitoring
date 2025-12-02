# ==============================================================================
# 00_reproject_nlcd.R
#
# Purpose: Reproject NLCD land cover raster to match HLS NDVI projection
#
# Background:
#   - Source NLCD from wildfire project is in WGS 84 (EPSG:4326, lat/lon)
#   - HLS NDVI data is in Albers Equal Area (EPSG:5070, meters)
#   - Need to reproject NLCD once to match for efficient extraction
#
# Input: /data/processed_ndvi/land_cover/nlcd_4km.tif (WGS 84)
# Output: /data/processed_ndvi/land_cover/nlcd_4km_albers.tif (EPSG:5070)
#
# Runtime: ~1-2 minutes
# ==============================================================================

library(terra)

# Source utility functions
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()

cat("=== NLCD REPROJECTION TO ALBERS EQUAL AREA ===\n\n")

# Input and output files
nlcd_wgs84 <- file.path(hls_paths$processed_ndvi, "land_cover/nlcd_4km.tif")
nlcd_albers <- file.path(hls_paths$processed_ndvi, "land_cover/nlcd_4km_albers.tif")

# Check if output already exists
if (file.exists(nlcd_albers)) {
  cat("Reprojected NLCD already exists:", nlcd_albers, "\n")
  cat("Delete this file if you want to reproject again.\n")
  quit(save = "no")
}

# Check input exists
if (!file.exists(nlcd_wgs84)) {
  stop("Source NLCD file not found: ", nlcd_wgs84,
       "\nRun land cover setup first (copy from wildfire project)")
}

# Load source raster
cat("Loading source NLCD raster...\n")
nlcd_src <- rast(nlcd_wgs84)

cat("  Source CRS:", as.character(crs(nlcd_src)), "\n")
cat("  Source extent:", as.vector(ext(nlcd_src)), "\n")
cat("  Source dimensions:", dim(nlcd_src), "\n\n")

# Reproject to Albers Equal Area (EPSG:5070)
# This matches the HLS NDVI data projection
cat("Reprojecting to EPSG:5070 (Albers Equal Area)...\n")
cat("  Method: nearest neighbor (preserves integer land cover codes)\n")

nlcd_reproj <- project(
  nlcd_src,
  "EPSG:5070",
  method = "near"  # Nearest neighbor for categorical data
)

cat("  Reprojected CRS:", as.character(crs(nlcd_reproj)), "\n")
cat("  Reprojected extent:", as.vector(ext(nlcd_reproj)), "\n")
cat("  Reprojected dimensions:", dim(nlcd_reproj), "\n\n")

# Save reprojected raster
cat("Saving reprojected raster...\n")
writeRaster(
  nlcd_reproj,
  nlcd_albers,
  overwrite = FALSE,
  datatype = "INT1U",  # Unsigned 8-bit integer (codes 0-9)
  gdal = c("COMPRESS=LZW", "TILED=YES")
)

# Verify output
cat("\nVerifying output...\n")
nlcd_check <- rast(nlcd_albers)
cat("  Output file:", nlcd_albers, "\n")
cat("  File size:", round(file.info(nlcd_albers)$size / 1024, 1), "KB\n")
cat("  CRS matches EPSG:5070:", grepl("5070", as.character(crs(nlcd_check))), "\n")

# Show value distribution
cat("\nLand cover code distribution:\n")
freq_table <- freq(nlcd_check)
print(freq_table)

cat("\n=== REPROJECTION COMPLETE ===\n")
cat("Reprojected NLCD saved to:", nlcd_albers, "\n")
cat("This file can now be used directly with HLS NDVI pixel coordinates.\n")
