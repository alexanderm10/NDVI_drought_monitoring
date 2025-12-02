# ==============================================================================
# 02_doy_looped_norms.R
#
# Purpose: Calculate DOY-looped spatial norms (baseline) for NDVI
# Based on: Juliana's spatial_analysis/05_norms_looped_by_yday.R
#
# Approach:
#   For each day of year (1-365):
#     - Pull observations from +/- 7 day window around that DOY
#     - Pool ALL years together
#     - Fit spatial GAM: gam(NDVI ~ s(x, y))
#     - Use post.distns() to get uncertainty (mean, lwr, upr)
#
# Input: Phase 1 aggregated timeseries (01_aggregate_to_4km output)
# Output:
#   1. doy_looped_norms.rds - Summary stats (mean, lwr, upr) per pixel-DOY
#   2. doy_looped_norms_posteriors.rds - Raw posterior simulations for derivatives
#
# Modifications (2024):
#   - Added return.sims=TRUE to post.distns() to save raw posteriors
#   - Posteriors saved separately for derivative calculations (script 06)
#   - Uses xz compression for posteriors to minimize storage (~10-30 GB)
#   - Maintains backward compatibility: summary file unchanged
#
# ==============================================================================

# Limit BLAS/LAPACK threads to be a good neighbor on shared systems
Sys.setenv(OMP_NUM_THREADS = 2)
Sys.setenv(OPENBLAS_NUM_THREADS = 2)

library(mgcv)
library(dplyr)
library(MASS)
library(parallel)

# Source utility functions
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()
source("00_posterior_functions.R")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Window parameters
  window_size = 7,  # +/- days around target DOY

  # GAM parameters (may need tuning for CONUS scale)
  gam_knots = -1,  # -1 lets mgcv choose automatically

  # Output
  output_file = file.path(hls_paths$gam_models, "doy_looped_norms.rds"),
  checkpoint_file = file.path(hls_paths$gam_models, "doy_looped_norms_checkpoint.rds"),
  checkpoint_interval = 50,  # Save every N DOYs

  # Posterior simulation
  n_posterior_sims = 100,  # Number of simulations for uncertainty

  # Parallelization (conservative for shared systems)
  n_cores = 2  # Reduced further for resume run
)

cat("=== DOY-Looped Spatial Norms ===\n")
cat("Window size: +/-", config$window_size, "days\n")
cat("Output:", config$output_file, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Get DOY window handling year wrap-around
#'
#' @param target_day Target day of year (1-365)
#' @param window_size Days before and after target
#' @return Vector of DOYs in the window
get_doy_window <- function(target_day, window_size = 7) {
  start <- target_day - window_size
  end <- target_day + window_size

  # Handle wrap-around at year boundaries
  if (start < 1) {
    start_section <- c((start + 365):365, 1:target_day)
  } else {
    start_section <- start:target_day
  }

  if (end > 365) {
    end_section <- c(target_day:365, 1:(end - 365))
  } else {
    end_section <- target_day:end
  }

  return(unique(c(start_section, end_section)))
}

#' Fit spatial GAM for a single DOY
#'
#' @param df_doy Data frame with NDVI, x, y for this DOY window
#' @param pred_grid Prediction grid (unique pixels)
#' @param n_sims Number of posterior simulations
#' @return Data frame with mean, lwr, upr for each pixel
fit_doy_spatial_gam <- function(df_doy, pred_grid, n_sims = 100) {

  # Check minimum data requirements
  if (nrow(df_doy) < 50) {
    warning("Insufficient data for spatial GAM")
    return(NULL)
  }

  # Fit spatial GAM
  gam_model <- tryCatch({
    gam(NDVI ~ s(x, y), data = df_doy)
  }, error = function(e) {
    warning("GAM fitting failed: ", e$message)
    return(NULL)
  })

  if (is.null(gam_model)) return(NULL)

  # Get predictions with uncertainty using post.distns
  # IMPORTANT: return.sims=TRUE saves raw posteriors for derivative calculations
  result <- tryCatch({
    post.distns(
      model.gam = gam_model,
      newdata = pred_grid,
      vars = c("x", "y"),
      n = n_sims,
      return.sims = TRUE  # Save raw posteriors for derivatives
    )
  }, error = function(e) {
    warning("Posterior calculation failed: ", e$message)
    # Fall back to simple prediction without uncertainty
    pred <- predict(gam_model, newdata = pred_grid, se.fit = TRUE)
    list(
      ci = data.frame(
        mean = pred$fit,
        lwr = pred$fit - 1.96 * pred$se.fit,
        upr = pred$fit + 1.96 * pred$se.fit
      ),
      sims = NULL
    )
  })

  return(result)
}

# ==============================================================================
# LOAD DATA
# ==============================================================================

cat("Loading Phase 1 timeseries data...\n")

# Check for RDS first (faster)
rds_file <- file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.rds")
csv_file <- file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.csv")

if (file.exists(rds_file)) {
  cat("  Using RDS format...\n")
  timeseries_df <- readRDS(rds_file)
} else if (file.exists(csv_file)) {
  cat("  Using CSV format...\n")
  timeseries_df <- read.csv(csv_file, stringsAsFactors = FALSE)
  timeseries_df$date <- as.Date(timeseries_df$date)
} else {
  stop("No timeseries data found. Run script 01 first.")
}

# Fix year column from date (handles any parsing issues)
timeseries_df$year <- as.integer(format(timeseries_df$date, "%Y"))

cat("  Total observations:", nrow(timeseries_df), "\n")
cat("  Unique pixels:", length(unique(timeseries_df$pixel_id)), "\n")
cat("  Year range:", min(timeseries_df$year), "-", max(timeseries_df$year), "\n\n")

# ==============================================================================
# LAND COVER FILTERING
# ==============================================================================

cat("=== APPLYING LAND COVER FILTER ===\n")

# Load land cover raster (Albers projection to match HLS data)
library(terra)
nlcd_file <- file.path(hls_paths$processed_ndvi, "land_cover/nlcd_4km_albers.tif")

if (!file.exists(nlcd_file)) {
  stop("NLCD land cover file not found: ", nlcd_file,
       "\nRun 00_reproject_nlcd.R first to create the reprojected land cover file")
}

nlcd_raster <- rast(nlcd_file)
cat("  NLCD raster loaded:", nlcd_file, "\n")

# Extract NLCD codes for all pixel coordinates
pixel_coords_prelim <- timeseries_df %>%
  group_by(pixel_id) %>%
  summarise(x = first(x), y = first(y), .groups = "drop")

# Create spatial points from pixel coordinates
# HLS coordinates are in Albers Equal Area (EPSG:5070), matching NLCD
pixel_points <- vect(
  pixel_coords_prelim[, c("x", "y")],
  geom = c("x", "y"),
  crs = "EPSG:5070"  # Albers Equal Area
)

# Extract NLCD values (no reprojection needed - both in Albers)
pixel_coords_prelim$nlcd_code <- extract(nlcd_raster, pixel_points)[, 2]

# Filter: Keep only pixels where NLCD code != 1 (exclude water/NoData)
valid_pixels <- pixel_coords_prelim %>%
  filter(!is.na(nlcd_code), nlcd_code != 1)

cat("  Pixels before filtering:", nrow(pixel_coords_prelim), "\n")
cat("  Pixels after filtering:", nrow(valid_pixels), "\n")
cat("  Pixels removed (water/NoData):", nrow(pixel_coords_prelim) - nrow(valid_pixels), "\n")

# Filter timeseries data to valid pixels only
timeseries_df <- timeseries_df %>%
  filter(pixel_id %in% valid_pixels$pixel_id)

cat("  Timeseries rows after filtering:", format(nrow(timeseries_df), big.mark=","), "\n")

# Save filtered pixel list for consistency across scripts
saveRDS(
  valid_pixels %>% select(pixel_id, x, y, nlcd_code),
  file.path(hls_paths$gam_models, "valid_pixels_landcover_filtered.rds")
)

cat("=== LAND COVER FILTERING COMPLETE ===\n\n")

# ==============================================================================
# CREATE PREDICTION GRID
# ==============================================================================

cat("Creating prediction grid...\n")

# Get unique pixel locations
pixel_coords <- timeseries_df %>%
  group_by(pixel_id) %>%
  summarise(
    x = first(x),
    y = first(y),
    .groups = "drop"
  ) %>%
  as.data.frame()

cat("  Unique pixel locations:", nrow(pixel_coords), "\n\n")

# Create output structure: one row per pixel-DOY
norms_df <- expand.grid(
  pixel_id = unique(pixel_coords$pixel_id),
  yday = 1:365
)

# Add coordinates
norms_df <- merge(norms_df, pixel_coords, by = "pixel_id")

# Add columns for results
norms_df$mean <- NA_real_
norms_df$lwr <- NA_real_
norms_df$upr <- NA_real_

cat("Output structure:", nrow(norms_df), "rows (",
    length(unique(norms_df$pixel_id)), "pixels x 365 days)\n\n")

# ==============================================================================
# CHECK FOR EXISTING RESULTS (RESUME MODE)
# ==============================================================================

days_to_process <- 1:365

# Initialize posteriors storage (will be populated during processing or resume)
norms_posteriors <- list()

if (file.exists(config$output_file)) {
  cat("Found existing results, checking for missing DOYs...\n")
  existing_norms <- readRDS(config$output_file)

  # Load existing posteriors if available
  posteriors_file <- file.path(hls_paths$gam_models, "doy_looped_norms_posteriors.rds")
  if (file.exists(posteriors_file)) {
    cat("  Loading existing posteriors...\n")
    norms_posteriors <- readRDS(posteriors_file)
    cat(sprintf("    Loaded posteriors for %d DOYs\n", length(norms_posteriors)))
  }

  # Find DOYs with all NAs (failed cores)
  doy_status <- tapply(existing_norms$mean, existing_norms$yday, function(x) sum(!is.na(x)))
  missing_doys <- as.integer(names(doy_status[doy_status == 0]))

  if (length(missing_doys) > 0) {
    cat("  Found", length(missing_doys), "missing DOYs\n")
    cat("  Will resume with existing data and process missing DOYs only\n\n")
    norms_df <- existing_norms
    days_to_process <- missing_doys
  } else {
    cat("  All DOYs complete! Nothing to process.\n")
    days_to_process <- integer(0)
  }
}

# ==============================================================================
# MAIN PROCESSING - PARALLEL
# ==============================================================================

if (length(days_to_process) > 0) {
  cat("Processing DOY-looped spatial norms...\n")
  cat("Using", config$n_cores, "cores\n")
  cat("======================================\n\n")

  start_time <- Sys.time()

  # Define function to process a single DOY
  process_single_doy <- function(day) {
    # Get DOY window
    doy_window <- get_doy_window(day, config$window_size)

    # Filter data for this window (all years pooled)
    df_doy <- timeseries_df %>%
      filter(yday %in% doy_window) %>%
      filter(!is.na(NDVI))

    # Skip if insufficient data
    if (nrow(df_doy) < 50) {
      return(list(day = day, result = NULL, n_obs = nrow(df_doy)))
    }

    # Fit spatial GAM and get predictions
    result <- fit_doy_spatial_gam(df_doy, pixel_coords, config$n_posterior_sims)

    return(list(day = day, result = result, n_obs = nrow(df_doy)))
  }

  # Run parallel processing
  cat("Processing", length(days_to_process), "DOYs...\n\n")

  results_list <- mclapply(
    days_to_process,
    process_single_doy,
    mc.cores = config$n_cores
  )

  # Combine results into norms_df
  cat("Combining results...\n")

  # Initialize posteriors storage for NEW results from this run
  # Structure: list by DOY, each containing matrix (pixels x simulations)
  # - Key: DOY as string ("1" to "365")
  # - Value: matrix with nrow=pixels, ncol=100 (posterior simulations)
  # This will be merged with existing posteriors (if in resume mode)
  norms_posteriors_new <- list()

  for (res in results_list) {
    if (!is.null(res$result)) {
      idx <- which(norms_df$yday == res$day)

      # Extract summary stats (backward compatibility)
      if (is.list(res$result) && "ci" %in% names(res$result)) {
        norms_df$mean[idx] <- res$result$ci$mean
        norms_df$lwr[idx] <- res$result$ci$lwr
        norms_df$upr[idx] <- res$result$ci$upr

        # Store posteriors if available
        if (!is.null(res$result$sims)) {
          # Extract just the simulation columns (exclude metadata columns)
          sim_cols <- grep("^X", names(res$result$sims), value = TRUE)
          if (length(sim_cols) == 0) {
            # If no X prefix, take all numeric columns after metadata
            sim_cols <- setdiff(names(res$result$sims), c("X", "x", "y"))
          }
          norms_posteriors_new[[as.character(res$day)]] <-
            as.matrix(res$result$sims[, sim_cols])
        }
      } else {
        # Old format (no list structure) - for backward compatibility
        norms_df$mean[idx] <- res$result$mean
        norms_df$lwr[idx] <- res$result$lwr
        norms_df$upr[idx] <- res$result$upr
      }
    }
  }

  # Merge new posteriors with existing posteriors
  if (length(norms_posteriors_new) > 0) {
    cat(sprintf("  Merging %d new posterior DOYs with existing data...\n",
                length(norms_posteriors_new)))
    # Update existing posteriors with new ones
    for (doy_key in names(norms_posteriors_new)) {
      norms_posteriors[[doy_key]] <- norms_posteriors_new[[doy_key]]
    }
  }

  elapsed_total <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
} else {
  elapsed_total <- 0
}

# ==============================================================================
# FINAL SAVE
# ==============================================================================

cat("\n======================================\n")
cat("Processing complete!\n\n")

# Save final output
cat("Saving final output...\n")

# Save summary stats (backward compatible, fast loading)
cat("  Saving summary statistics (mean, lwr, upr)...\n")
saveRDS(norms_df, config$output_file, compress = "gzip")

# Save posteriors separately (for derivative calculations)
posteriors_file <- file.path(hls_paths$gam_models, "doy_looped_norms_posteriors.rds")
if (exists("norms_posteriors") && length(norms_posteriors) > 0) {
  cat("  Saving posterior distributions...\n")
  cat("    (this may take a few minutes due to compression)\n")
  saveRDS(norms_posteriors, posteriors_file, compress = "xz")  # Maximum compression
  cat(sprintf("  Posteriors saved: %s\n", posteriors_file))

  # Report file size
  post_size_mb <- file.info(posteriors_file)$size / (1024^2)
  cat(sprintf("    File size: %.1f MB\n", post_size_mb))
} else {
  cat("  No posteriors to save (may be resume mode with no new data)\n")
}

# Summary statistics
n_complete <- sum(!is.na(norms_df$mean))
n_total <- nrow(norms_df)
pct_complete <- 100 * n_complete / n_total

cat("\nSummary:\n")
cat("  Total pixel-DOY combinations:", n_total, "\n")
cat("  Successfully fitted:", n_complete, sprintf("(%.1f%%)\n", pct_complete))
cat("  Output saved to:", config$output_file, "\n")

# Clean up checkpoint
if (file.exists(config$checkpoint_file)) {
  file.remove(config$checkpoint_file)
  cat("  Checkpoint file removed\n")
}

cat(sprintf("\nTotal time: %.1f minutes\n", elapsed_total))
