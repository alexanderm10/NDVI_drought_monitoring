# ==============================================================================
# 03_doy_looped_year_predictions.R
#
# Purpose: Calculate DOY-looped year-specific predictions
# Based on: Juliana's spatial_analysis/06_year_splines_yday_looped_.R
#
# Approach:
#   For each year-DOY combination:
#     - Pull 16-day trailing window of observations
#     - Merge with norms from script 02
#     - Fit spatial GAM: gam(NDVI ~ norm + s(x, y) - 1)
#     - Use post.distns() to get uncertainty (mean, lwr, upr)
#
# Input:
#   - Phase 1 aggregated timeseries
#   - Script 02 norms output
# Output: Year predictions for each pixel-year-DOY with uncertainty
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
library(lubridate)

# Required for future.apply globals — the per-year filtered timeseries is
# ~134 MB, but norms_df dominates at ~2.3 GB (47M pixel-DOY rows), and
# pixel_coords adds ~3 MB. Total auto-detected globals ~2.4 GB per worker.
# Cap at 4 GB for headroom; with 3 workers that's ~7 GB worker globals overhead
# vs the 96 GB Docker cap, well within budget.
# Updated 2026-05-08 from 2 GB after a 2.42 GB future.globals.maxSize hit on
# year 2013 silently dropped the script into sequential lapply (caught by the
# flush.console patch in the same commit). See MEMORY.md "R Parallel
# Processing Stability" for the full pattern.
options(future.globals.maxSize = 4 * 1024^3)

# Source utility functions
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()
source("00_posterior_functions.R")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Window parameters
  window_size = 16,  # Trailing window (days before target)

  # Minimum data requirement
  min_pixel_coverage = 0.33,  # Require 33% of pixels to have data

  # SPATIAL RESOLUTION PARAMETER
  # k=50 selected based on testing (Jan 2026):
  #   - k=30: stable but limited spatial resolution
  #   - k=50: stable (0.11% negative predictions), good balance
  #   - k=80: overfitting (207K negative predictions)
  #   - k=150: severe overfitting
  # k=50 test results: R²=0.698, RMSE=0.089, NormCoef=0.995
  spatial_k = 50,

  # Output (year-by-year files)
  output_dir = file.path(hls_paths$gam_models, "modeled_ndvi"),
  stats_file = file.path(hls_paths$gam_models, "modeled_ndvi_stats.rds"),

  # Posteriors directory (organized by year, incremental saving to avoid memory issues)
  posteriors_dir = file.path(hls_paths$gam_models, "year_predictions_posteriors"),

  # Posterior simulation
  n_posterior_sims = 100,

  # Parallelization. 3 workers via future_lapply (multisession), with
  # plan/sequential/gc recycling per year — the stable pattern documented in
  # MEMORY.md and used by 01_aggregate_to_4km_parallel.R. Each multisession
  # worker holds its own copy of the per-year-filtered timeseries (~250-400 MB),
  # plus norms_df (~700 MB), plus pixel_coords. Budget: ~3 × 1.5 GB ≈ 5 GB
  # workers + parent overhead, well within the 96 GB Docker container.
  n_cores = 3
)

# Create output directories
if (!dir.exists(config$output_dir)) {
  dir.create(config$output_dir, recursive = TRUE)
}
if (!dir.exists(config$posteriors_dir)) {
  dir.create(config$posteriors_dir, recursive = TRUE)
}

cat("=== DOY-Looped Year Predictions ===\n")
cat("Trailing window:", config$window_size, "days\n")
cat("Using", config$n_cores, "cores\n")
cat("Predictions:", config$output_dir, "\n")
cat("Posteriors:", config$posteriors_dir, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Get trailing window dates for a specific year-DOY
#'
#' @param year Target year
#' @param target_day Target day of year (1-365)
#' @param window_size Days before target (inclusive)
#' @return Vector of dates in the window
get_trailing_window <- function(year, target_day, window_size = 16) {
  target_date <- as.Date(paste(year, target_day, sep = "-"), format = "%Y-%j")
  start_date <- target_date - (window_size - 1)
  seq.Date(start_date, target_date, by = "day")
}

#' Fit year-specific spatial GAM
#'
#' @param df_subset Data frame with NDVI, norm, x, y for this window
#' @param pred_grid Prediction grid (with norm values)
#' @param n_sims Number of posterior simulations
#' @param spatial_k Basis dimension for spatial smooth (default 50)
#' @param year Target year (used to derive a unique posterior seed so sims
#'   across (year, DOY) combinations are statistically independent —
#'   matters for script 06's change derivatives and script 04's anomaly
#'   uncertainty propagation).
#' @param day Target DOY (1-365), same purpose as `year`.
#' @return List with predictions and model stats
fit_year_spatial_gam <- function(df_subset, pred_grid, n_sims = 100, spatial_k = 50,
                                 year = NA_integer_, day = NA_integer_) {

  # Fit spatial GAM with norm as covariate
  # spatial_k controls resolution: higher k = finer spatial detail
  gam_model <- tryCatch({
    gam(NDVI ~ norm + s(x, y, k = spatial_k) - 1, data = df_subset)
  }, error = function(e) {
    return(NULL)
  })

  if (is.null(gam_model)) {
    return(list(result = NULL, stats = NULL))
  }

  # Extract model statistics
  gam_summary <- summary(gam_model)
  stats <- list(
    R2 = gam_summary$r.sq,
    NormCoef = gam_summary$p.table["norm", "Estimate"],
    SplineP = gam_summary$s.table[1, "p-value"],
    RMSE = sqrt(mean(residuals(gam_model)^2))
  )

  # Get predictions with uncertainty AND posteriors
  # IMPORTANT: return.sims=TRUE saves raw posteriors for uncertainty propagation
  # seed = year * 1000 + day gives each (year, DOY) a unique-but-reproducible
  # RNG state so the 100 sims are independent across all 13 × 365 fits.
  # This matters for script 06 (which differences posteriors across DOYs)
  # and script 04 (which differences year posteriors against baseline norms).
  result <- tryCatch({
    post.distns(
      model.gam = gam_model,
      newdata = pred_grid,
      vars = c("x", "y"),
      n = n_sims,
      return.sims = TRUE,  # Save posteriors for anomaly uncertainty
      seed = as.integer(year) * 1000L + as.integer(day)
    )
  }, error = function(e) {
    # Fall back to simple prediction without posteriors
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

  return(list(result = result, stats = stats))
}

# ==============================================================================
# LOAD DATA
# ==============================================================================

cat("Loading data...\n")

# Load timeseries
rds_file <- file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.rds")
if (file.exists(rds_file)) {
  timeseries_df <- readRDS(rds_file)
} else {
  stop("Timeseries data not found. Run script 01 first.")
}

# Fix year column from date (handles any parsing issues)
timeseries_df$year <- as.integer(format(timeseries_df$date, "%Y"))

cat("  Timeseries observations (before filtering):", nrow(timeseries_df), "\n")

# ==============================================================================
# APPLY LAND COVER FILTER (consistent with script 02)
# ==============================================================================

cat("\nApplying land cover filter...\n")
valid_pixels_file <- file.path(hls_paths$gam_models, "valid_pixels_landcover_filtered.rds")
if (!file.exists(valid_pixels_file)) {
  stop("Filtered pixel list not found: ", valid_pixels_file,
       "\nRun script 02 first to generate the filtered pixel list")
}

valid_pixels <- readRDS(valid_pixels_file)
cat("  Valid pixels from script 02:", nrow(valid_pixels), "\n")

# Sanity check: the NLCD-filtered pixel count is invariant across the pipeline
# (set in script 02). If this differs from the expected value, it usually means
# script 02 was re-run against a different NLCD reproject — anomalies (script
# 04) and derivatives (script 06) will fail their pixel-count assertions
# downstream. We warn rather than stop so a deliberate filter change can proceed.
# Constant updated 2026-05-08 from 125798 -> 129310 after the May 7-8 v2 backfill
# of script 02 (current NLCD filter: !is.na(nlcd_code) & nlcd_code != 1).
# See WORKFLOW.md "Land Cover Filtering > Maintenance" for the update procedure.
EXPECTED_VALID_PIXELS <- 129310L
if (nrow(valid_pixels) != EXPECTED_VALID_PIXELS) {
  cat(sprintf(
    "  WARNING: valid pixel count %s differs from expected %s.\n",
    format(nrow(valid_pixels), big.mark = ","),
    format(EXPECTED_VALID_PIXELS, big.mark = ",")
  ))
  cat("  This is OK if you intentionally changed the NLCD land-cover filter,\n")
  cat("  but downstream scripts 04/06 expect the same count. Verify before proceeding.\n")
}

# Filter timeseries to only valid (non-water) pixels
timeseries_df <- timeseries_df %>%
  filter(pixel_id %in% valid_pixels$pixel_id)

cat("  Timeseries observations (after filtering):", nrow(timeseries_df), "\n")

# Load norms from script 02
norms_file <- file.path(hls_paths$gam_models, "doy_looped_norms.rds")
if (!file.exists(norms_file)) {
  stop("Norms not found. Run script 02 first.")
}
norms_df <- readRDS(norms_file)
cat("  Norms loaded:", nrow(norms_df), "pixel-DOY combinations\n")

# Get unique years and pixels
years <- sort(unique(timeseries_df$year))

# PRODUCTION MODE: Process all years
# (Test mode removed - k=50 validated on 2017, 2020, 2022, 2024)

n_pixels <- length(unique(timeseries_df$pixel_id))

cat("  Years:", min(years), "-", max(years), "(", length(years), "years)\n")
cat("  Pixels:", n_pixels, "\n\n")

# Get pixel coordinates (used for all years) - from filtered data
pixel_coords <- timeseries_df %>%
  group_by(pixel_id) %>%
  summarise(x = first(x), y = first(y), .groups = "drop") %>%
  as.data.frame()

# Check for existing year files (resume capability).
# A year is "complete" only if BOTH (a) the summary file exists AND (b) every
# DOY whose summary mean is non-NA has a corresponding non-empty posterior
# file in posteriors_dir/YYYY/. Catching (b) protects script 06 from missing
# posteriors hours into its 1.5-2 day run — the same class of bug as the
# resume fix in script 02.
existing_years <- character(0)
incomplete_years <- list()  # year -> count of missing posterior files

for (yr in years) {
  year_file     <- file.path(config$output_dir, sprintf("modeled_ndvi_%d.rds", yr))
  year_post_dir <- file.path(config$posteriors_dir, as.character(yr))

  if (!file.exists(year_file)) next

  # Identify DOYs the summary file claims were successfully fitted
  year_summary <- readRDS(year_file)
  fitted_doys <- sort(unique(year_summary$yday[!is.na(year_summary$mean)]))

  # Tally posterior files actually present
  if (dir.exists(year_post_dir)) {
    post_files <- list.files(year_post_dir, pattern = "^doy_\\d{3}\\.rds$",
                             full.names = TRUE)
    post_sizes <- file.info(post_files)$size
    valid_post_files <- post_files[!is.na(post_sizes) & post_sizes > 0]
    valid_post_doys  <- as.integer(sub("^doy_(\\d{3})\\.rds$", "\\1",
                                       basename(valid_post_files)))
  } else {
    valid_post_doys <- integer(0)
  }

  missing_post_doys <- setdiff(fitted_doys, valid_post_doys)

  if (length(missing_post_doys) == 0) {
    existing_years <- c(existing_years, as.character(yr))
  } else {
    incomplete_years[[as.character(yr)]] <- length(missing_post_doys)
  }
}

if (length(existing_years) > 0) {
  cat("Found complete results for ", length(existing_years), " years: ",
      paste(existing_years, collapse = ", "), "\n", sep = "")
}

if (length(incomplete_years) > 0) {
  cat("Years with summary stats but missing posteriors (will reprocess):\n")
  for (yr_str in names(incomplete_years)) {
    cat(sprintf("  %s: %d posterior file(s) missing\n",
                yr_str, incomplete_years[[yr_str]]))
  }
}

years_to_process <- setdiff(as.character(years), existing_years)

if (length(years_to_process) == 0) {
  cat("All years already processed (with complete posteriors)!\n")
  quit(save = "no")
}

# Convert back to integer for downstream loop indexing
years_to_process <- as.integer(years_to_process)

cat("Will process", length(years_to_process), "years:", paste(years_to_process, collapse=", "), "\n\n")

# ==============================================================================
# MAIN PROCESSING - YEAR-BY-YEAR
# ==============================================================================

cat("Processing year predictions...\n")
cat("======================================\n\n")

overall_start <- Sys.time()

# Merge timeseries with norms once
timeseries_with_norms <- merge(
  timeseries_df,
  norms_df[, c("pixel_id", "yday", "mean")],
  by = c("pixel_id", "yday"),
  all.x = TRUE
)
names(timeseries_with_norms)[names(timeseries_with_norms) == "mean"] <- "norm"

# Initialize overall stats tracking
all_model_stats <- list()

# Process each year sequentially (DOYs within each year run in parallel)
for (yr in years_to_process) {

  cat("\n=== Processing Year", yr, "===\n")
  year_start <- Sys.time()

  # Pre-filter timeseries to just the rows needed for this year. Each
  # multisession worker holds its own copy of the closure environment, so
  # shipping the full 47M-row timeseries_with_norms to 3 workers would cost
  # ~15 GB of duplicated state. Filtering to the year + trailing-window
  # range (~3-4M rows) cuts each worker's footprint to ~250-400 MB.
  year_min_date <- as.Date(paste0(yr, "-01-01")) - config$window_size
  year_max_date <- as.Date(paste0(yr, "-12-31"))
  year_data <- timeseries_with_norms %>%
    filter(date >= year_min_date & date <= year_max_date)
  cat(sprintf("  Year-window slice: %s rows (%s to %s)\n",
              format(nrow(year_data), big.mark = ","),
              as.character(year_min_date), as.character(year_max_date)))

  # Define function to process a single DOY for this year
  process_doy <- function(day) {
    tryCatch({
      # Get trailing window dates
      window_dates <- get_trailing_window(yr, day, config$window_size)

      # Filter data (year_data is the per-year slice; smaller than the full timeseries)
      df_subset <- year_data %>%
        filter(date %in% window_dates) %>%
        filter(!is.na(NDVI) & !is.na(norm))

      # Check data requirement
      n_pixels_with_data <- length(unique(df_subset$pixel_id))
      if (n_pixels_with_data < n_pixels * config$min_pixel_coverage) {
        return(list(yday = day, result = NULL, stats = NULL, n_obs = nrow(df_subset)))
      }

      # Build prediction grid on-the-fly for just this DOY (141K rows)
      # Get norms for this DOY
      norms_for_doy <- norms_df[norms_df$yday == day, c("pixel_id", "mean")]
      names(norms_for_doy)[names(norms_for_doy) == "mean"] <- "norm"

      # Merge with pixel coords. Note: base R merge() sorts by the join column
      # by default, so pred_grid$pixel_id may differ in row order from
      # pixel_coords$pixel_id. The result data frame below MUST take pixel_id
      # from pred_grid (the actual prediction order) — never from pixel_coords.
      pred_grid <- merge(pixel_coords, norms_for_doy, by = "pixel_id", all.x = TRUE)
      pred_grid <- pred_grid[, c("pixel_id", "x", "y", "norm")]

      # Fit model — pass yr and day to give post.distns a unique-per-(year, DOY)
      # seed so the 100 sims are statistically independent across all 13 × 365 fits.
      fit_result <- fit_year_spatial_gam(df_subset, pred_grid,
                                         config$n_posterior_sims, config$spatial_k,
                                         year = yr, day = day)

      # Save posteriors IMMEDIATELY to avoid memory buildup (like script 02).
      # File format: list(pixel_id = <integer vector>, sims = <numeric matrix>)
      # post.distns() returns df.sim with X / x / y prepended to the simulation
      # columns; we strip those here so downstream consumers (scripts 04, 06)
      # see a clean numeric matrix and rowMeans/quantile sweep ONLY across
      # the simulation values. Storing pixel_id alongside protects against
      # any future ordering drift between the per-DOY posterior files.
      if (!is.null(fit_result$result) && !is.null(fit_result$result$sims)) {
        year_post_dir <- file.path(config$posteriors_dir, as.character(yr))
        if (!dir.exists(year_post_dir)) {
          dir.create(year_post_dir, recursive = TRUE)
        }

        posterior_file <- file.path(year_post_dir, sprintf("doy_%03d.rds", day))
        sims_matrix <- as.matrix(fit_result$result$sims[, -(1:3)])  # drop X, x, y
        saveRDS(
          list(pixel_id = pred_grid$pixel_id, sims = sims_matrix),
          posterior_file, compress = "xz"
        )
      }

      # Return summary stats with pixel_id sourced from pred_grid (the actual
      # prediction-order vector). Pre-binding the pixel_id here closes the
      # ordering risk: downstream code can rbind these data frames directly
      # without separate index alignment.
      ci_with_id <- if (!is.null(fit_result$result)) {
        data.frame(
          pixel_id = pred_grid$pixel_id,
          mean     = fit_result$result$ci$mean,
          lwr      = fit_result$result$ci$lwr,
          upr      = fit_result$result$ci$upr
        )
      } else NULL

      return(list(
        yday   = day,
        result = ci_with_id,
        stats  = fit_result$stats,
        n_obs  = nrow(df_subset)
      ))
    }, error = function(e) {
      return(list(yday = day, result = NULL, stats = NULL, n_obs = 0, error = as.character(e)))
    })
  }

  # Per-DOY resume: scan posterior dir for already-completed DOYs. If a
  # posterior file exists and is non-empty, we skip the GAM fit and instead
  # reload the sims to reconstruct (mean, lwr, upr) from rowMeans/quantile.
  # This is bit-equivalent to the original ci because post.distns() with
  # terms=F (the default in this script) defines:
  #   df.out$mean = apply(sim1, 1, mean,     na.rm=T)
  #   df.out$lwr  = apply(sim1, 1, quantile, 0.025, na.rm=T)
  #   df.out$upr  = apply(sim1, 1, quantile, 0.975, na.rm=T)
  # See 00_posterior_functions.R lines 95-97. Trade-off: per-DOY model stats
  # (R2, NormCoef, SplineP, RMSE) are not reconstructable from the posteriors
  # file (those come from gam_summary), so reloaded DOYs get NA stats. This
  # only affects the modeled_ndvi_stats.rds diagnostics file, not any
  # downstream analysis. Added 2026-05-11 after the May 9-10 OOM truncated
  # year 2019's summary RDS while all 365 posteriors remained valid on disk.
  year_post_dir <- file.path(config$posteriors_dir, as.character(yr))
  existing_doy_files <- if (dir.exists(year_post_dir)) {
    files <- list.files(year_post_dir, pattern = "^doy_\\d{3}\\.rds$",
                        full.names = TRUE)
    sizes <- file.info(files)$size
    doys  <- as.integer(sub("^doy_(\\d{3})\\.rds$", "\\1", basename(files)))
    doys[!is.na(sizes) & sizes > 0]
  } else integer(0)

  doys_to_process <- setdiff(1:365, existing_doy_files)
  doys_to_reload  <- intersect(1:365, existing_doy_files)

  cat(sprintf("  DOY plan: %d to fit, %d to reload from posteriors\n",
              length(doys_to_process), length(doys_to_reload)))
  flush.console()

  # Process DOYs that need fitting in parallel using the future-recycling
  # pattern from MEMORY.md: plan(multisession) before, plan(sequential) +
  # gc() after, with a tryCatch fallback to sequential lapply if a worker
  # dies. This is the same pattern proven by 01_aggregate_to_4km_parallel.R
  # over multi-day runs and replaces mclapply (which the project's prior
  # incident showed could exhaust worker memory on long jobs).
  if (length(doys_to_process) > 0) {
    cat("  Fitting", length(doys_to_process), "DOYs with",
        config$n_cores, "future workers...\n")
    flush.console()

    plan(multisession, workers = config$n_cores)

    processed_results <- tryCatch({
      future_lapply(doys_to_process, function(day) {
        # Workers are fresh R processes — load packages explicitly. Globals
        # (year_data, pixel_coords, norms_df, config, n_pixels, fit_year_spatial_gam,
        # post.distns, get_trailing_window, yr) are auto-detected by future.apply.
        library(mgcv)
        library(dplyr)
        library(MASS)
        library(lubridate)
        process_doy(day)
      }, future.seed = NULL)
      # future.seed = NULL: post.distns() seeds itself deterministically with
      # year * 1000L + day. TRUE would override the worker RNGkind to L'Ecuyer-CMRG
      # before that set.seed() runs, breaking bit-equivalence with the serial path.
      # See script 02's matching rationale at lines 508-514.
    }, error = function(e) {
      cat("WARNING: future_lapply failed for year ", yr, ": ",
          conditionMessage(e), "\n", sep = "")
      cat("Falling back to sequential lapply for this year (slower but safer)...\n")
      flush.console()  # Without this, the warning is invisible until the (multi-hour) fallback completes.
      lapply(doys_to_process, process_doy)
    })

    plan(sequential)
    gc(verbose = FALSE)
    flush.console()
  } else {
    processed_results <- list()
  }

  # Reload existing posteriors (if any) and reconstruct ci. Use multisession
  # workers because the apply(quantile) step is CPU-bound (~3-5 sec/DOY for
  # 141K x 100 sims) and dominates over disk read time. With 3 workers, 365
  # reloads take ~10-15 min vs ~30-60 min sequential.
  if (length(doys_to_reload) > 0) {
    cat("  Reloading", length(doys_to_reload),
        "existing posteriors with", config$n_cores, "workers...\n")
    flush.console()

    plan(multisession, workers = config$n_cores)

    reloaded_results <- tryCatch({
      future_lapply(doys_to_reload, function(day) {
        pf <- readRDS(file.path(year_post_dir, sprintf("doy_%03d.rds", day)))
        sims <- pf$sims
        list(
          yday   = day,
          result = data.frame(
            pixel_id = pf$pixel_id,
            # apply(..., mean, na.rm=TRUE) — NOT rowMeans() — to match
            # post.distns() line 95 exactly. rowMeans defaults to na.rm=FALSE
            # which would produce NA for any pixel with even one NA sim,
            # diverging from the original ci values. Bit-equivalence matters
            # because the reloaded ci goes into modeled_ndvi_YYYY.rds and
            # downstream scripts 04/06 compare against the year-2018 ci that
            # came from the unpatched code path.
            mean = apply(sims, 1, mean,     na.rm = TRUE),
            lwr  = apply(sims, 1, quantile, 0.025, na.rm = TRUE),
            upr  = apply(sims, 1, quantile, 0.975, na.rm = TRUE)
          ),
          stats  = NULL,         # not reconstructable without re-fitting
          n_obs  = NA_integer_   # not stored in posterior file
        )
      }, future.seed = NULL)
    }, error = function(e) {
      cat("WARNING: reload future_lapply failed for year ", yr, ": ",
          conditionMessage(e), "\n", sep = "")
      cat("Falling back to sequential reload...\n")
      flush.console()
      lapply(doys_to_reload, function(day) {
        pf <- readRDS(file.path(year_post_dir, sprintf("doy_%03d.rds", day)))
        sims <- pf$sims
        list(yday = day,
             result = data.frame(pixel_id = pf$pixel_id,
                                 mean = apply(sims, 1, mean,     na.rm = TRUE),
                                 lwr  = apply(sims, 1, quantile, 0.025, na.rm = TRUE),
                                 upr  = apply(sims, 1, quantile, 0.975, na.rm = TRUE)),
             stats = NULL, n_obs = NA_integer_)
      })
    })

    plan(sequential)
    gc(verbose = FALSE)
    flush.console()
  } else {
    reloaded_results <- list()
  }

  results_list <- c(processed_results, reloaded_results)
  rm(processed_results, reloaded_results)
  gc(verbose = FALSE)

  # Combine results for this year
  cat("  Combining results...\n")

  year_stats <- data.frame(
    year = yr,
    yday = 1:365,
    R2 = NA_real_,
    NormCoef = NA_real_,
    SplineP = NA_real_,
    RMSE = NA_real_,
    n_obs = NA_integer_
  )

  # Build year_grid from results.
  # IMPORTANT: index year_stats / year_results_list by res$yday (NOT by
  # list position i), because results_list may now be in arbitrary order
  # after the per-DOY skip patch concatenates processed + reloaded results.
  year_results_list <- vector("list", 365)

  for (res in results_list) {
    d <- res$yday

    # Guard: a corrupt reload returning yday = NA / 0 / >365 would silently
    # mis-index year_stats (R allows NA / 0 / out-of-range positional
    # subscripts) and produce a year file with hidden bad rows. Halt loudly
    # instead. (Per r-reviewer flag, 2026-05-11.)
    if (!is.numeric(d) || is.na(d) || d < 1 || d > 365) {
      stop(sprintf("Invalid yday in results_list: %s (year %d)",
                   format(d), yr))
    }

    # Update stats (NA for reloaded DOYs since gam_summary isn't in posteriors)
    year_stats$n_obs[d] <- res$n_obs
    if (!is.null(res$stats)) {
      year_stats$R2[d]       <- res$stats$R2
      year_stats$NormCoef[d] <- res$stats$NormCoef
      year_stats$SplineP[d]  <- res$stats$SplineP
      year_stats$RMSE[d]     <- res$stats$RMSE
    }

    # Store results if present. res$result already has (pixel_id, mean, lwr, upr)
    # with pixel_id sourced from pred_grid — no separate index alignment needed.
    if (!is.null(res$result)) {
      res$result$yday <- res$yday
      year_results_list[[d]] <- res$result
    }
  }

  # Free results_list before building year_grid — it's the largest in-parent
  # object (365 ci data frames + sims metadata) and would otherwise stay
  # resident through the saveRDS step. Same OOM-prevention hygiene as the
  # rm/gc between years (see end of loop).
  rm(results_list)
  gc(verbose = FALSE)

  # Combine all DOYs into year_grid (bind_rows is faster than do.call(rbind)
  # for hundreds of frames; same final result)
  year_grid <- dplyr::bind_rows(year_results_list)
  year_grid <- merge(year_grid, pixel_coords, by = "pixel_id", all.x = TRUE)

  # Free year_results_list now that it's been bound — another ~1 GB recovered
  # before the saveRDS gzip allocation that triggered the May 9-10 OOM.
  rm(year_results_list)
  gc(verbose = FALSE)

  # Save this year's results
  year_file <- file.path(config$output_dir, sprintf("modeled_ndvi_%d.rds", yr))
  cat("  Saving to:", year_file, "\n")
  flush.console()
  saveRDS(year_grid, year_file)

  # Verify write succeeded — guards against NFS/CIFS hiccups producing a
  # truncated file that the resume-mode check would later treat as complete.
  # Per WORKFLOW.md, year files run ~50-300 MB; anything < 1 MB is broken.
  written_size_mb <- file.info(year_file)$size / 1024^2
  if (is.na(written_size_mb) || written_size_mb < 1) {
    stop(sprintf("Year file write failed or suspiciously small (%.2f MB): %s",
                 written_size_mb, year_file))
  }
  cat(sprintf("  Wrote %.1f MB\n", written_size_mb))

  # Track stats
  all_model_stats[[as.character(yr)]] <- year_stats

  # Summary for this year
  n_complete <- sum(!is.na(year_grid$mean))
  n_total <- nrow(year_grid)
  pct_complete <- 100 * n_complete / n_total

  year_elapsed <- as.numeric(difftime(Sys.time(), year_start, units = "mins"))
  cat(sprintf("  Year %d: %.1f%% complete in %.1f minutes\n", yr, pct_complete, year_elapsed))
  flush.console()

  # End-of-year cleanup: drop year-local objects to keep parent footprint
  # flat across years. Without this, year_data + year_grid + closure
  # references accumulated across 13 years (2013-2025), and the OOM at the
  # year-2019 saveRDS proved we had no headroom on the 96 GiB cap. With the
  # 128 GiB cap and these explicit drops, parent stays in the 30-50 GiB band
  # year-over-year. See RUNNING_ANALYSES.md May 11 session for the OOM
  # forensics.
  rm(year_data, year_grid, year_stats)
  gc(verbose = FALSE)
}

# ==============================================================================
# FINAL SAVE
# ==============================================================================

cat("\n======================================\n")
cat("All years complete!\n\n")

# Save combined stats
cat("Saving model statistics...\n")
combined_stats <- do.call(rbind, all_model_stats)
saveRDS(combined_stats, config$stats_file)

# Overall summary
cat("\nSummary:\n")
cat("  Years processed:", paste(years_to_process, collapse=", "), "\n")
cat("  Output directory:", config$output_dir, "\n")
cat("  Model stats saved to:", config$stats_file, "\n")

cat("\nModel Statistics Summary:\n")
cat("  Mean R²:", round(mean(combined_stats$R2, na.rm = TRUE), 3), "\n")
cat("  Mean Norm Coef:", round(mean(combined_stats$NormCoef, na.rm = TRUE), 3), "\n")
cat("  Mean RMSE:", round(mean(combined_stats$RMSE, na.rm = TRUE), 4), "\n")

elapsed_total <- as.numeric(difftime(Sys.time(), overall_start, units = "mins"))
cat(sprintf("\nTotal time: %.1f minutes\n", elapsed_total))
