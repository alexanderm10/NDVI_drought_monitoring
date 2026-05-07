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
library(future)
library(future.apply)

# Required for future.apply globals — chunk_data slices can hit ~250-400 MB
# and the default 500 MB cap silently kills the run. See MEMORY.md
# "R Parallel Processing Stability".
options(future.globals.maxSize = 2 * 1024^3)

# Source utility functions
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()
source("00_posterior_functions.R")

# Optional CLI arg:
#   --doy=N         : single-DOY backfill / smoke test
#   --doys=A,B,C    : explicit list of DOYs (parallel smoke test)
# Resume logic still runs first; either flag overrides days_to_process.
test_doys <- NULL
for (.a in commandArgs(trailingOnly = TRUE)) {
  if (grepl("^--doy=", .a)) {
    test_doys <- as.integer(sub("^--doy=", "", .a))
  } else if (grepl("^--doys=", .a)) {
    test_doys <- as.integer(strsplit(sub("^--doys=", "", .a), ",")[[1]])
  }
}
if (!is.null(test_doys) &&
    (any(is.na(test_doys)) || any(test_doys < 1) || any(test_doys > 365))) {
  stop("--doy/--doys must be integers in 1..365; got: ",
       paste(test_doys, collapse = ","))
}

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Window parameters
  window_size = 7,  # +/- days around target DOY

  # Output
  output_file = file.path(hls_paths$gam_models, "doy_looped_norms.rds"),
  checkpoint_file = file.path(hls_paths$gam_models, "doy_looped_norms_checkpoint.rds"),
  checkpoint_interval = 50,  # Save every N DOYs

  # Posteriors directory (individual files per DOY to avoid memory issues)
  posteriors_dir = file.path(hls_paths$gam_models, "baseline_posteriors"),

  # Posterior simulation
  n_posterior_sims = 100,  # Number of simulations for uncertainty

  # Parallelization. 4 workers via future_lapply (multisession), with
  # plan/sequential/gc recycling per chunk — the stable pattern documented in
  # MEMORY.md and used by 01_aggregate_to_4km_parallel.R / 03. The 2026-05-06
  # serial smoke test took 9.8 min/DOY against the 148M-row filtered
  # timeseries; full 365 DOYs serial = ~60 hr. At 4 workers with ~30 DOYs per
  # recycle round, expected wall-clock is ~14-16 hr.
  #
  # Memory budget (empirical, from 2026-05-07 smoke + first OOM):
  #   - Parent steady-state ≈ 30 GB (timeseries 8.7 GB + norms_df 47M-row
  #     prediction grid + intermediate copies from expand.grid/merge)
  #   - Per active worker peak ≈ 11 GB (GAM fit + posterior sims + xz write)
  #   - 4 workers × 11 GB + 30 GB parent = 74 GB peak in 96 GB container
  #     (22 GB headroom)
  # 8 workers OOM-killed the run on 2026-05-07 (peak >96 GB); do NOT raise
  # n_cores above 4 without first verifying per-worker memory peak.
  n_cores = 4,

  # DOYs per worker-recycle round. Each round: parent pre-filters chunk_data
  # for the ±7-day window union of the chunk, plan(multisession) workers,
  # future_lapply, plan(sequential) + gc(). Smaller chunks = more recycling
  # overhead; larger = more memory creep risk. 30 DOYs ≈ 12 chunks total.
  chunk_size = 30
)

cat("=== DOY-Looped Spatial Norms ===\n")
cat("Window size: +/-", config$window_size, "days\n")
cat("Output:", config$output_file, "\n")
cat("Posteriors:", config$posteriors_dir, "\n")
cat("Cores:", config$n_cores, "(future multisession,",
    config$chunk_size, "DOYs per recycle round)\n\n")

# Create posteriors directory if it doesn't exist
if (!dir.exists(config$posteriors_dir)) {
  dir.create(config$posteriors_dir, recursive = TRUE)
  cat("Created posteriors directory\n")
}

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
#' @param day Target DOY (1-365). Used to derive a unique posterior seed so
#'   that the 100 sims for one DOY are independent of those for adjacent DOYs.
#'   Critical for script 06's change derivatives.
#' @return Data frame with mean, lwr, upr for each pixel
fit_doy_spatial_gam <- function(df_doy, pred_grid, n_sims = 100, day = NA_integer_) {

  # Check minimum data requirements
  if (nrow(df_doy) < 50) {
    warning("Insufficient data for spatial GAM")
    return(NULL)
  }

  # Fit spatial GAM
  #
  # Sensor term intentionally omitted from this formula. HLS L30 and S30 are
  # NASA-harmonized at processing (Claverie et al. 2018), and an internal
  # comparison during early CONUS pipeline development confirmed negligible
  # NDVI offset between sensors. With a +/- 7 day window pooled over 13 years,
  # any residual sensor-mix imbalance is approximately constant across years
  # and is absorbed into the baseline; the year - baseline anomaly cancels it.
  # The `sensor` column is preserved upstream (script 01) for diagnostic /
  # re-analysis use only.
  gam_model <- tryCatch({
    gam(NDVI ~ s(x, y), data = df_doy)
  }, error = function(e) {
    warning("GAM fitting failed: ", e$message)
    return(NULL)
  })

  if (is.null(gam_model)) return(NULL)

  # Get predictions with uncertainty using post.distns
  # IMPORTANT: return.sims=TRUE saves raw posteriors for derivative calculations
  # seed = 1034 + day gives each DOY a unique-but-reproducible RNG state, so
  # the 100 sims across DOYs are independent (matters for script 06).
  result <- tryCatch({
    post.distns(
      model.gam = gam_model,
      newdata = pred_grid,
      vars = c("x", "y"),
      n = n_sims,
      return.sims = TRUE,  # Save raw posteriors for derivatives
      seed = 1034L + as.integer(day)
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
cat("  Year range:", min(timeseries_df$year), "-", max(timeseries_df$year), "\n")

# Report leap-year DOY 366 observations that will be silently dropped.
# The baseline structure is fixed at 1:365 (norms_df, doy_window, etc.), so
# leap-year Dec 31 observations cannot contribute. Reporting the count makes
# the data loss visible rather than invisible. Expected magnitude: ~0.08% of
# rows (one DOY out of ~365 per leap year, in 2016/2020/2024).
n_doy366 <- sum(timeseries_df$yday == 366, na.rm = TRUE)
if (n_doy366 > 0) {
  cat(sprintf("  Note: dropping %s DOY-366 observations (%.3f%% of total) —\n",
              format(n_doy366, big.mark = ","),
              100 * n_doy366 / nrow(timeseries_df)))
  cat("        baseline structure is fixed at DOY 1:365, leap-year Dec 31 excluded.\n")
}
cat("\n")

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
  valid_pixels %>% dplyr::select(pixel_id, x, y, nlcd_code),
  file.path(hls_paths$gam_models, "valid_pixels_landcover_filtered.rds")
)

cat("=== LAND COVER FILTERING COMPLETE ===\n\n")

# ==============================================================================
# CREATE PREDICTION GRID
# ==============================================================================

cat("Creating prediction grid...\n")

# Get unique pixel locations.
# Sorted by pixel_id so the row order of `result$sims` (which inherits this
# order from post.distns's `newdata`) is canonical across all DOYs and across
# scripts 02 and 03. Downstream scripts (04, 06) can then align posteriors
# from different files purely by checking pixel_id equality (cheap) instead
# of doing a full merge per DOY.
pixel_coords <- timeseries_df %>%
  group_by(pixel_id) %>%
  summarise(
    x = first(x),
    y = first(y),
    .groups = "drop"
  ) %>%
  arrange(pixel_id) %>%
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

if (file.exists(config$output_file)) {
  cat("Found existing results, checking for missing DOYs...\n")
  existing_norms <- readRDS(config$output_file)

  # A DOY needs reprocessing if EITHER:
  #   (a) its summary stats in `output_file` are all-NA (the GAM never fit), OR
  #   (b) its posterior file in `posteriors_dir` is missing or zero-byte.
  # Catching (b) is critical: script 06 (change derivatives) reads the
  # posterior files directly. If a posterior was deleted or written
  # incompletely after a crash, the prior resume logic would silently skip
  # it here and then script 06 would hard-fail hours into its 1.5-2 day run.
  doy_status <- tapply(existing_norms$mean, existing_norms$yday,
                       function(x) sum(!is.na(x)))
  doys_missing_stats <- as.integer(names(doy_status[doy_status == 0]))

  posterior_paths <- file.path(config$posteriors_dir,
                               sprintf("doy_%03d.rds", 1:365))
  posterior_size  <- file.info(posterior_paths)$size
  doys_missing_posteriors <- which(is.na(posterior_size) | posterior_size == 0)

  missing_doys <- sort(unique(c(doys_missing_stats,
                                doys_missing_posteriors)))

  if (length(missing_doys) > 0) {
    cat("  Missing summary stats for ", length(doys_missing_stats), " DOYs\n",
        sep = "")
    cat("  Missing posterior files for ", length(doys_missing_posteriors),
        " DOYs\n", sep = "")
    cat("  Total DOYs to process: ", length(missing_doys),
        " (union of both)\n\n", sep = "")
    norms_df <- existing_norms
    days_to_process <- missing_doys
  } else {
    cat("  All DOYs complete (summary stats and posteriors present).\n")
    days_to_process <- integer(0)
  }
}

# --doy=N / --doys=A,B,C override: process only the listed DOYs (smoke test
# / explicit backfill). Resume merging into existing norms_df is preserved.
if (!is.null(test_doys)) {
  cat(sprintf("\n*** TEST MODE: --doy(s)=%s, processing only these DOYs ***\n",
              paste(test_doys, collapse = ",")))
  days_to_process <- test_doys
}

# Note: Posteriors are saved incrementally to individual files during processing
cat("Posteriors will be saved to:", config$posteriors_dir, "\n")

# ==============================================================================
# MAIN PROCESSING - PARALLEL (chunked future_lapply with worker recycling)
# ==============================================================================

if (length(days_to_process) > 0) {
  cat("Processing DOY-looped spatial norms...\n")
  cat("======================================\n\n")

  start_time <- Sys.time()

  # Per-DOY worker. Receives `chunk_data` via futures' globals; per-DOY filter
  # to the ±7-day window happens inside the worker. The function references
  # `pixel_coords` and `config` from globals as well.
  process_single_doy <- function(day, chunk_data) {
    doy_window <- get_doy_window(day, config$window_size)

    df_doy <- chunk_data %>%
      filter(yday %in% doy_window) %>%
      filter(!is.na(NDVI))

    if (nrow(df_doy) < 50) {
      return(list(day = day, ci = NULL, n_obs = nrow(df_doy)))
    }

    result <- fit_doy_spatial_gam(df_doy, pixel_coords,
                                  config$n_posterior_sims, day = day)

    if (is.null(result)) {
      return(list(day = day, ci = NULL, n_obs = nrow(df_doy)))
    }

    # Save posteriors IMMEDIATELY (avoid worker memory buildup). Format:
    # list(pixel_id = <int vector>, sims = <numeric matrix>) with sims
    # 129,310 rows × 100 columns. post.distns() prepends X/x/y to the sim
    # columns; we strip them so downstream scripts see a clean numeric matrix.
    # pixel_id is sourced from pixel_coords (same canonical order as 03).
    if (!is.null(result$sims)) {
      posterior_file <- file.path(config$posteriors_dir,
                                  sprintf("doy_%03d.rds", day))
      sims_matrix <- as.matrix(result$sims[, -(1:3)])
      saveRDS(
        list(pixel_id = pixel_coords$pixel_id, sims = sims_matrix),
        posterior_file, compress = "xz"
      )
    }

    return(list(day = day, ci = result$ci, n_obs = nrow(df_doy)))
  }

  # Split DOYs into chunks for worker recycling
  day_chunks <- split(
    days_to_process,
    ceiling(seq_along(days_to_process) / config$chunk_size)
  )
  cat("Processing", length(days_to_process), "DOYs in",
      length(day_chunks), "chunk(s) of up to", config$chunk_size,
      "DOYs each, with", config$n_cores, "workers per chunk.\n")
  cat("Posteriors saved incrementally to:", config$posteriors_dir, "\n\n")

  n_fitted <- 0
  n_failed <- 0
  doys_done <- 0

  for (chunk_i in seq_along(day_chunks)) {
    chunk_doys <- day_chunks[[chunk_i]]
    chunk_start <- Sys.time()

    # Pre-filter timeseries to the union of all ±window_size windows in this
    # chunk, with column projection. This is the per-chunk analogue of script
    # 03's per-year pre-filter — keeps each worker's serialized global down to
    # ~150-300 MB rather than the full 7.7 GB filtered timeseries.
    chunk_window_ydays <- unique(unlist(lapply(chunk_doys, get_doy_window,
                                               config$window_size)))
    chunk_data <- timeseries_df %>%
      filter(yday %in% chunk_window_ydays, !is.na(NDVI)) %>%
      dplyr::select(yday, x, y, NDVI)

    cat(sprintf("Chunk %d/%d: DOYs %d-%d (%d days), chunk_data %s rows / %.0f MB\n",
                chunk_i, length(day_chunks),
                min(chunk_doys), max(chunk_doys), length(chunk_doys),
                format(nrow(chunk_data), big.mark = ","),
                as.numeric(object.size(chunk_data)) / 1024^2))

    # Future recycling pattern from MEMORY.md "R Parallel Processing
    # Stability": plan(multisession) before, plan(sequential) + gc() after,
    # tryCatch fallback to sequential lapply if a worker dies.
    plan(multisession, workers = config$n_cores)

    chunk_results <- tryCatch({
      future_lapply(chunk_doys, function(day) {
        # Workers are fresh R processes — load packages explicitly. Globals
        # (chunk_data, pixel_coords, config, get_doy_window,
        # fit_doy_spatial_gam, post.distns) are auto-detected by future.apply.
        library(mgcv)
        library(dplyr)
        library(MASS)
        process_single_doy(day, chunk_data)
      }, future.seed = NULL)
      # future.seed = NULL : we deterministically seed inside post.distns()
      # via `1034L + day` (per-DOY, matches serial). future.seed = TRUE would
      # switch the worker's RNGkind to L'Ecuyer-CMRG before our set.seed()
      # ran, producing posteriors that correlate at ~0.9999998 with the serial
      # output but are not bit-identical (smoke test 2026-05-07 showed
      # max-abs-diff 0.0045). NULL preserves the worker's default
      # Mersenne-Twister and yields bit-identical sims to the serial path.
    }, error = function(e) {
      cat("WARNING: future_lapply failed for chunk ", chunk_i, ": ",
          conditionMessage(e), "\n", sep = "")
      cat("Falling back to sequential lapply for this chunk...\n")
      lapply(chunk_doys, function(day) process_single_doy(day, chunk_data))
    })

    plan(sequential)
    rm(chunk_data)
    gc(verbose = FALSE)

    # Merge chunk results into norms_df
    for (res in chunk_results) {
      if (!is.null(res$ci)) {
        idx <- which(norms_df$yday == res$day)
        norms_df$mean[idx] <- res$ci$mean
        norms_df$lwr[idx]  <- res$ci$lwr
        norms_df$upr[idx]  <- res$ci$upr
        n_fitted <- n_fitted + 1
      } else {
        n_failed <- n_failed + 1
      }
    }

    doys_done <- doys_done + length(chunk_doys)
    chunk_elapsed <- as.numeric(difftime(Sys.time(), chunk_start, units = "mins"))
    overall_elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
    cat(sprintf("  Chunk %d done in %.1f min (%d/%d DOYs done, %.1f min total elapsed)\n\n",
                chunk_i, chunk_elapsed, doys_done, length(days_to_process),
                overall_elapsed))

    # Checkpoint after each chunk so a mid-run crash doesn't lose chunk-level work
    saveRDS(norms_df, config$checkpoint_file, compress = "gzip")
  }

  cat(sprintf("\nProcessed %d DOYs: %d fitted, %d failed\n",
              length(days_to_process), n_fitted, n_failed))

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

# Report on posteriors (saved incrementally during processing)
posterior_files <- list.files(config$posteriors_dir, pattern = "^doy_.*\\.rds$", full.names = TRUE)
if (length(posterior_files) > 0) {
  cat(sprintf("  Posteriors saved: %d individual DOY files in %s\n",
              length(posterior_files), config$posteriors_dir))

  # Report total size
  total_size_mb <- sum(file.info(posterior_files)$size) / (1024^2)
  cat(sprintf("    Total size: %.1f MB\n", total_size_mb))
} else {
  cat("  Warning: No posterior files found\n")
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
