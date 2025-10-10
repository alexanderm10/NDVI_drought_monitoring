# Check HLS Band Scaling
# Quick diagnostic to verify if Red/NIR bands are properly scaled

library(terra)

# Test files - one L30 and one S30
l30_file <- "U:/datasets/ndvi_monitor/processed_ndvi/daily/2024/HLS.L30.T13SEA.2024005T173159.v2.0_NDVI.tif"
s30_file <- list.files("U:/datasets/ndvi_monitor/processed_ndvi/daily/2024",
                       pattern = "HLS\\.S30.*_NDVI\\.tif", full.names = TRUE)[1]

cat("=== CHECKING HLS BAND SCALING ===\n\n")

# Check L30 NDVI
cat("--- L30 NDVI File ---\n")
cat("File:", basename(l30_file), "\n")
l30_ndvi <- rast(l30_file)
l30_vals <- values(l30_ndvi, mat=FALSE)
l30_vals <- l30_vals[!is.na(l30_vals)]

cat("NDVI Range:", range(l30_vals), "\n")
cat("NDVI Mean:", mean(l30_vals), "\n")
cat("NDVI Median:", median(l30_vals), "\n")
cat("Sample values:", head(l30_vals[l30_vals > -0.5], 20), "\n\n")

# Check S30 NDVI if available
if (!is.na(s30_file)) {
  cat("--- S30 NDVI File ---\n")
  cat("File:", basename(s30_file), "\n")
  s30_ndvi <- rast(s30_file)
  s30_vals <- values(s30_ndvi, mat=FALSE)
  s30_vals <- s30_vals[!is.na(s30_vals)]

  cat("NDVI Range:", range(s30_vals), "\n")
  cat("NDVI Mean:", mean(s30_vals), "\n")
  cat("NDVI Median:", median(s30_vals), "\n")
  cat("Sample values:", head(s30_vals[s30_vals > -0.5], 20), "\n\n")
}

# Now check the SOURCE bands (Red/NIR) to see if they're scaled
cat("=== CHECKING SOURCE BAND SCALING ===\n\n")

# Find corresponding Red and NIR bands for L30
l30_base <- sub("_NDVI\\.tif", "", basename(l30_file))
l30_red_file <- list.files("U:/datasets/ndvi_monitor/raw_hls_data",
                           pattern = paste0(l30_base, "_B04\\.tif"),
                           recursive = TRUE, full.names = TRUE)[1]
l30_nir_file <- list.files("U:/datasets/ndvi_monitor/raw_hls_data",
                           pattern = paste0(l30_base, "_B05\\.tif"),
                           recursive = TRUE, full.names = TRUE)[1]

if (!is.na(l30_red_file)) {
  cat("--- L30 Red Band (B04) ---\n")
  l30_red <- rast(l30_red_file)
  red_vals <- values(l30_red, mat=FALSE)
  red_vals <- red_vals[!is.na(red_vals)]

  cat("Range:", range(red_vals), "\n")
  cat("Mean:", mean(red_vals), "\n")
  cat("Sample values:", head(red_vals[red_vals > 0], 10), "\n")

  if (max(red_vals) > 2) {
    cat("⚠ WARNING: Values > 2 suggest unscaled reflectance (should be 0-1)\n")
    cat("Expected: 0-1 (scaled), Actual: 0-", max(red_vals), "\n")
  } else {
    cat("✓ Values appear properly scaled (0-1 range)\n")
  }
  cat("\n")
}

if (!is.na(l30_nir_file)) {
  cat("--- L30 NIR Band (B05) ---\n")
  l30_nir <- rast(l30_nir_file)
  nir_vals <- values(l30_nir, mat=FALSE)
  nir_vals <- nir_vals[!is.na(nir_vals)]

  cat("Range:", range(nir_vals), "\n")
  cat("Mean:", mean(nir_vals), "\n")
  cat("Sample values:", head(nir_vals[nir_vals > 0], 10), "\n")

  if (max(nir_vals) > 2) {
    cat("⚠ WARNING: Values > 2 suggest unscaled reflectance (should be 0-1)\n")
    cat("Expected: 0-1 (scaled), Actual: 0-", max(nir_vals), "\n")
  } else {
    cat("✓ Values appear properly scaled (0-1 range)\n")
  }
  cat("\n")
}

# Check S30 bands if available
if (!is.na(s30_file)) {
  s30_base <- sub("_NDVI\\.tif", "", basename(s30_file))
  s30_red_file <- list.files("U:/datasets/ndvi_monitor/raw_hls_data",
                             pattern = paste0(s30_base, "_B04\\.tif"),
                             recursive = TRUE, full.names = TRUE)[1]
  s30_nir_file <- list.files("U:/datasets/ndvi_monitor/raw_hls_data",
                             pattern = paste0(s30_base, "_B8A\\.tif"),
                             recursive = TRUE, full.names = TRUE)[1]

  if (!is.na(s30_red_file)) {
    cat("--- S30 Red Band (B04) ---\n")
    s30_red <- rast(s30_red_file)
    red_vals <- values(s30_red, mat=FALSE)
    red_vals <- red_vals[!is.na(red_vals)]

    cat("Range:", range(red_vals), "\n")
    cat("Mean:", mean(red_vals), "\n")
    cat("Sample values:", head(red_vals[red_vals > 0], 10), "\n")

    if (max(red_vals) > 2) {
      cat("⚠ WARNING: Values > 2 suggest unscaled reflectance (should be 0-1)\n")
      cat("Expected: 0-1 (scaled), Actual: 0-", max(red_vals), "\n")
    } else {
      cat("✓ Values appear properly scaled (0-1 range)\n")
    }
    cat("\n")
  }

  if (!is.na(s30_nir_file)) {
    cat("--- S30 NIR Band (B8A) ---\n")
    s30_nir <- rast(s30_nir_file)
    nir_vals <- values(s30_nir, mat=FALSE)
    nir_vals <- nir_vals[!is.na(nir_vals)]

    cat("Range:", range(nir_vals), "\n")
    cat("Mean:", mean(nir_vals), "\n")
    cat("Sample values:", head(nir_vals[nir_vals > 0], 10), "\n")

    if (max(nir_vals) > 2) {
      cat("⚠ WARNING: Values > 2 suggest unscaled reflectance (should be 0-1)\n")
      cat("Expected: 0-1 (scaled), Actual: 0-", max(nir_vals), "\n")
    } else {
      cat("✓ Values appear properly scaled (0-1 range)\n")
    }
    cat("\n")
  }
}

cat("=== DIAGNOSTIC COMPLETE ===\n")
cat("\nIf bands show values > 2, they need to be multiplied by 0.0001 scale factor\n")
cat("NDVI should be in range -1 to 1, with typical values 0-0.8\n")
