# Reprocess NDVI with Fmask Quality Filtering
# Purpose: Apply quality masks to existing NDVI files using downloaded Fmask layers
# Strategy: Faster than re-downloading - just re-calculate NDVI from existing bands

library(terra)

# Source required scripts
source("00_setup_paths.R")
source("01_HLS_data_acquisition_FINAL.R")

hls_paths <- get_hls_paths()

cat("=== NDVI REPROCESSING WITH FMASK ===\n\n")

######################
# Find Files to Reprocess (OPTIMIZED)
######################

find_reprocessing_candidates <- function() {

  cat("Finding NDVI files with available Fmask...\n")

  # Check if matching report exists (FAST method)
  matching_report <- file.path(hls_paths$processing_logs, "ndvi_fmask_matching_report.csv")

  if (file.exists(matching_report)) {
    cat("Using existing matching report (FAST)...\n")

    file_df <- read.csv(matching_report, stringsAsFactors = FALSE)

    # Filter to only scenes with Fmask
    file_df <- file_df[file_df$has_fmask, ]

    # Add NIR band column
    file_df$nir_band <- ifelse(file_df$sensor == "L30", "B05", "B8A")

    # Build Red and NIR paths from Fmask path (they're in the same directory)
    file_df$red_path <- NA
    file_df$nir_path <- NA

    for (i in 1:nrow(file_df)) {
      fmask_dir <- dirname(file_df$fmask_path[i])
      scene_id <- file_df$scene_id[i]

      file_df$red_path[i] <- file.path(fmask_dir, paste0(scene_id, "_B04.tif"))
      file_df$nir_path[i] <- file.path(fmask_dir, paste0(scene_id, "_", file_df$nir_band[i], ".tif"))
    }

    # Verify files actually exist
    file_df$can_reprocess <- file.exists(file_df$red_path) &
                              file.exists(file_df$nir_path) &
                              file.exists(file_df$fmask_path)

    cat("Total NDVI files:", nrow(file_df), "\n")
    cat("Files with all bands (Red+NIR+Fmask):", sum(file_df$can_reprocess), "\n")
    cat("Files missing bands:", sum(!file_df$can_reprocess), "\n\n")

    return(file_df)

  } else {
    # SLOW fallback method (original code)
    cat("WARNING: Matching report not found. Using slow search method...\n")
    cat("Run match_ndvi_fmask.R first for much faster processing!\n\n")

    # Get all NDVI files
    ndvi_files <- list.files(
      file.path(hls_paths$processed_ndvi, "daily"),
      pattern = "_NDVI\\.tif$",
      recursive = TRUE,
      full.names = TRUE
    )

    file_df <- data.frame(
      ndvi_path = ndvi_files,
      scene_id = sub("_NDVI\\.tif", "", basename(ndvi_files)),
      stringsAsFactors = FALSE
    )

    # Extract metadata
    file_df$sensor <- ifelse(grepl("HLS\\.L30\\.", file_df$scene_id), "L30", "S30")
    file_df$nir_band <- ifelse(file_df$sensor == "L30", "B05", "B8A")

    # Look for corresponding Red, NIR, and Fmask files
    file_df$red_path <- NA
    file_df$nir_path <- NA
    file_df$fmask_path <- NA
    file_df$can_reprocess <- FALSE

    for (i in 1:nrow(file_df)) {
      scene_id <- file_df$scene_id[i]

      # Find Red band
      red_files <- list.files(
        hls_paths$raw_hls_data,
        pattern = paste0(scene_id, "_B04\\.tif"),
        recursive = TRUE,
        full.names = TRUE
      )

      # Find NIR band
      nir_files <- list.files(
        hls_paths$raw_hls_data,
        pattern = paste0(scene_id, "_", file_df$nir_band[i], "\\.tif"),
        recursive = TRUE,
        full.names = TRUE
      )

      # Find Fmask
      fmask_files <- list.files(
        hls_paths$raw_hls_data,
        pattern = paste0(scene_id, "_Fmask\\.tif"),
        recursive = TRUE,
        full.names = TRUE
      )

      if (length(red_files) > 0 && length(nir_files) > 0 && length(fmask_files) > 0) {
        file_df$red_path[i] <- red_files[1]
        file_df$nir_path[i] <- nir_files[1]
        file_df$fmask_path[i] <- fmask_files[1]
        file_df$can_reprocess[i] <- TRUE
      }
    }

    cat("Total NDVI files:", nrow(file_df), "\n")
    cat("Files with all bands (Red+NIR+Fmask):", sum(file_df$can_reprocess), "\n")
    cat("Files missing bands:", sum(!file_df$can_reprocess), "\n\n")

    return(file_df)
  }
}

######################
# Reprocess NDVI
######################

reprocess_ndvi_with_quality <- function(red_path, nir_path, fmask_path, output_path, overwrite = TRUE) {

  # Check if output exists and whether to skip
  if (file.exists(output_path) && !overwrite) {
    return(list(status = "skipped", message = "Already processed"))
  }

  tryCatch({
    # Load bands
    red <- rast(red_path)
    nir <- rast(nir_path)
    fmask <- rast(fmask_path)

    # Ensure bands align spatially
    if (!compareGeom(red, nir)) {
      nir <- resample(nir, red)
    }

    # Calculate NDVI: (NIR - Red) / (NIR + Red)
    ndvi <- (nir - red) / (nir + red)

    # Quality control: mask invalid NDVI values
    ndvi[ndvi < -1 | ndvi > 1] <- NA

    # Ensure Fmask aligns with NDVI
    if (!compareGeom(ndvi, fmask)) {
      fmask <- resample(fmask, ndvi, method = "near")
    }

    # Build quality mask using bit flags
    # Use direct bit values instead of bitwShiftL to avoid type mismatch
    # Bit 1 (2): cloud, Bit 2 (4): adjacent, Bit 3 (8): shadow, Bit 4 (16): snow/ice, Bit 5 (32): water
    quality_mask <- (
      (fmask %% 4) < 2 &    # Bit 1 not set (cloud)
      (fmask %% 8) < 4 &    # Bit 2 not set (adjacent)
      (fmask %% 16) < 8 &   # Bit 3 not set (shadow)
      (fmask %% 32) < 16 &  # Bit 4 not set (snow/ice)
      (fmask %% 64) < 32    # Bit 5 not set (water)
    )

    # Apply mask (keep only quality_mask = TRUE pixels)
    ndvi_masked <- mask(ndvi, quality_mask, maskvalue = 0, updatevalue = NA)

    # Save with explicit datatype to avoid type mismatch errors
    dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
    writeRaster(ndvi_masked, output_path, overwrite = TRUE, datatype = "FLT4S")

    return(list(status = "success", message = "Reprocessed with quality mask"))

  }, error = function(e) {
    return(list(status = "error", message = e$message))
  })
}

######################
# Main Execution
######################

run_ndvi_reprocessing <- function(overwrite = FALSE) {

  cat("=== STARTING NDVI REPROCESSING ===\n\n")

  # Find files to reprocess
  file_df <- find_reprocessing_candidates()

  # Filter to processable files
  to_process <- file_df[file_df$can_reprocess, ]

  if (nrow(to_process) == 0) {
    cat("❌ No files available for reprocessing\n")
    cat("Run download_fmask_retroactive.R first to get Fmask layers\n")
    return(invisible(NULL))
  }

  cat("Reprocessing", nrow(to_process), "NDVI files with quality masks...\n\n")

  # Track results
  results <- list(
    success = 0,
    skipped = 0,
    failed = 0
  )

  # Progress bar
  pb <- txtProgressBar(min = 0, max = nrow(to_process), style = 3)

  for (i in 1:nrow(to_process)) {
    scene <- to_process[i, ]

    # Create backup of original NDVI (first time only)
    backup_dir <- file.path(hls_paths$processed_ndvi, "daily_unmasked_backup")
    backup_file <- file.path(backup_dir, basename(scene$ndvi_path))

    if (i == 1 && !dir.exists(backup_dir)) {
      cat("\nCreating backup of original NDVI files...\n")
      dir.create(backup_dir, recursive = TRUE)
    }

    if (!file.exists(backup_file)) {
      file.copy(scene$ndvi_path, backup_file)
    }

    # Reprocess
    result <- reprocess_ndvi_with_quality(
      scene$red_path,
      scene$nir_path,
      scene$fmask_path,
      scene$ndvi_path,
      overwrite = overwrite
    )

    if (result$status == "success") {
      results$success <- results$success + 1
    } else if (result$status == "skipped") {
      results$skipped <- results$skipped + 1
    } else {
      results$failed <- results$failed + 1
      cat("\n  ⚠ Failed:", basename(scene$ndvi_path), "-", result$message, "\n")
    }

    setTxtProgressBar(pb, i)
  }

  close(pb)

  cat("\n\n=== NDVI REPROCESSING COMPLETE ===\n")
  cat("Successfully reprocessed:", results$success, "\n")
  cat("Skipped (already done):", results$skipped, "\n")
  cat("Failed:", results$failed, "\n")
  cat("Total processed:", nrow(to_process), "\n\n")

  cat("Original NDVI files backed up to:\n")
  cat("  ", file.path(hls_paths$processed_ndvi, "daily_unmasked_backup"), "\n\n")

  return(results)
}

# Instructions
cat("=== NDVI REPROCESSING WITH FMASK READY ===\n")
cat("This script recalculates NDVI with quality filtering applied\n")
cat("Original NDVI files will be backed up before overwriting\n\n")
cat("To run (overwrite existing):\n")
cat("  results <- run_ndvi_reprocessing(overwrite = TRUE)\n\n")
cat("To run (skip existing):\n")
cat("  results <- run_ndvi_reprocessing(overwrite = FALSE)\n\n")
cat("Estimated time: 30-60 min for ~5000 scenes\n\n")
