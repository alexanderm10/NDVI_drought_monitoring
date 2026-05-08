# ==============================================================================
# 06_calculate_change_derivatives.R
#
# Purpose: Calculate change derivatives (rate of change anomalies) using
#          posteriors from baseline norms and year predictions
#
# Approach:
#   - For multiple time windows (3, 7, 14, 30 days):
#     - Calculate baseline change: baseline[day] - baseline[day-k]
#     - Calculate year change: year[day] - year[day-k]
#     - Calculate change anomaly: year_change - baseline_change
#   - Use full posterior distributions for uncertainty propagation
#   - Test significance: 95% CI excludes zero
#
# Input:
#   - Baseline posteriors from script 02: baseline_posteriors/doy_*.rds
#   - Year posteriors from script 03: year_predictions_posteriors/YYYY/doy_*.rds
#   - Valid pixels: valid_pixels_landcover_filtered.rds
#
# Output:
#   - Summary stats for each year: change_derivatives/derivatives_YYYY.rds
#   - Posteriors: change_derivatives_posteriors/YYYY/doy_XXX_window_YY.rds
#
# ==============================================================================

# Limit BLAS/LAPACK threads
Sys.setenv(OMP_NUM_THREADS = 2)
Sys.setenv(OPENBLAS_NUM_THREADS = 2)

library(dplyr)
library(future)
library(future.apply)
library(data.table)

# Each parallel task loads up to 4 posteriors of ~100 MB each plus produces
# anomaly_sims of similar size — the default 500 MB future globals cap is
# too small. See MEMORY.md "R Parallel Processing Stability" for the pattern.
options(future.globals.maxSize = 2 * 1024^3)

# Source utility functions
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Input directories
  baseline_posteriors_dir = file.path(hls_paths$gam_models, "baseline_posteriors"),
  year_posteriors_dir = file.path(hls_paths$gam_models, "year_predictions_posteriors"),
  valid_pixels_file = file.path(hls_paths$gam_models, "valid_pixels_landcover_filtered.rds"),

  # Time windows for change calculation (days)
  window_sizes = c(3, 7, 14, 30),

  # Output directories
  output_dir = file.path(hls_paths$gam_models, "change_derivatives"),
  posteriors_dir = file.path(hls_paths$gam_models, "change_derivatives_posteriors"),
  stats_file = file.path(hls_paths$gam_models, "change_derivatives_stats.rds"),

  # Posterior simulation count (must match scripts 02/03)
  n_posterior_sims = 100,

  # Parallelization. 3 workers via future_lapply (multisession), with
  # plan/sequential/gc recycling per year — the stable pattern from MEMORY.md
  # used by 01_aggregate_to_4km_parallel.R and 03_doy_looped_year_predictions.R.
  # Each worker holds at most ~800 MB at peak (4 posteriors + anomaly_sims)
  # plus shipped globals. Budget: ~3 × 1 GB worker memory, well under 96 GB.
  n_cores = 3
)

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Wrap DOY to valid range [1, 365]
wrap_doy <- function(doy) {
  ((doy - 1) %% 365) + 1
}

#' Check if posterior file exists
posterior_exists <- function(year, doy, posteriors_dir, is_baseline = FALSE) {
  if (is_baseline) {
    file_path <- file.path(posteriors_dir, sprintf("doy_%03d.rds", doy))
  } else {
    file_path <- file.path(posteriors_dir, as.character(year), sprintf("doy_%03d.rds", doy))
  }
  return(file.exists(file_path))
}

#' Load posterior simulations for a specific DOY.
#'
#' New posterior file format (set by scripts 02 and 03):
#'   list(pixel_id = <integer vector>, sims = <numeric matrix>)
#' where sims has 125,798 rows × 100 columns.
#'
#' This replaces the prior data-frame format that stored X / x / y as
#' simulation-adjacent columns. Returning a clean numeric matrix here is the
#' root-cause fix for the calculate_stats bias bug: rowMeans/quantile sweeping
#' across an N × 100 matrix correctly averages exactly the 100 simulations,
#' not the X/x/y junk that previously inflated column count to 103.
#'
#' @return list(pixel_id, sims) or NULL if the file does not exist.
load_posteriors <- function(year, doy, posteriors_dir, is_baseline = FALSE) {
  file_path <- if (is_baseline) {
    file.path(posteriors_dir, sprintf("doy_%03d.rds", doy))
  } else {
    file.path(posteriors_dir, as.character(year), sprintf("doy_%03d.rds", doy))
  }

  if (!file.exists(file_path)) return(NULL)

  obj <- readRDS(file_path)

  # Defensive: confirm the new format. Anything else means an old-format file
  # (df.sim with X/x/y) slipped through, which would silently bias the stats.
  if (!is.list(obj) || !all(c("pixel_id", "sims") %in% names(obj))) {
    stop("Posterior file ", file_path,
         " is not in the expected list(pixel_id, sims) format. ",
         "Was it written by scripts 02 / 03 after the format change? ",
         "Old df.sim format files must be regenerated.")
  }

  obj
}

#' Calculate summary statistics from posterior simulations
#' @param sims Matrix with pixels as rows, simulations as columns
calculate_stats <- function(sims) {
  data.frame(
    mean = rowMeans(sims, na.rm = TRUE),
    lwr = apply(sims, 1, quantile, 0.025, na.rm = TRUE),
    upr = apply(sims, 1, quantile, 0.975, na.rm = TRUE)
  )
}

#' Calculate change anomalies for a specific year-DOY-window combination
#' Returns list with summary stats and posteriors
calculate_change_anomaly <- function(year, yday, window, valid_pixel_ids,
                                      baseline_post_dir, year_post_dir) {

  # Calculate lagged DOY
  yday_lagged <- wrap_doy(yday - window)

  # Check if we need previous year's data (for early DOYs with long windows)
  year_current <- year
  year_lagged <- if (yday_lagged > yday) year - 1 else year

  # Check if all required files exist
  baseline_t_exists <- posterior_exists(NULL, yday, baseline_post_dir, is_baseline = TRUE)
  baseline_t_lag_exists <- posterior_exists(NULL, yday_lagged, baseline_post_dir, is_baseline = TRUE)
  year_t_exists <- posterior_exists(year_current, yday, year_post_dir)
  year_t_lag_exists <- posterior_exists(year_lagged, yday_lagged, year_post_dir)

  if (!all(c(baseline_t_exists, baseline_t_lag_exists, year_t_exists, year_t_lag_exists))) {
    # Missing data - return NULL
    return(NULL)
  }

  # Load all 4 posterior objects (each is list(pixel_id, sims))
  baseline_t     <- load_posteriors(NULL, yday,        baseline_post_dir, is_baseline = TRUE)
  baseline_t_lag <- load_posteriors(NULL, yday_lagged, baseline_post_dir, is_baseline = TRUE)
  year_t         <- load_posteriors(year_current, yday,        year_post_dir)
  year_t_lag     <- load_posteriors(year_lagged,  yday_lagged, year_post_dir)

  if (is.null(baseline_t) || is.null(baseline_t_lag) ||
      is.null(year_t) || is.null(year_t_lag)) {
    return(NULL)
  }

  # Align all four on the same pixel ordering. Scripts 02 and 03 both sort
  # pixel_coords by pixel_id before fitting, so under normal operation the
  # vectors are already identical — this stays cheap. The reorder happens
  # only if some future change drifts the ordering.
  ref_pixels <- baseline_t$pixel_id
  align <- function(post) {
    if (identical(post$pixel_id, ref_pixels)) return(post$sims)
    idx <- match(ref_pixels, post$pixel_id)
    if (anyNA(idx)) {
      stop("Pixel mismatch in posterior file: ",
           sum(is.na(idx)), " reference pixels missing.")
    }
    post$sims[idx, , drop = FALSE]
  }
  baseline_t_sims     <- align(baseline_t)
  baseline_t_lag_sims <- align(baseline_t_lag)
  year_t_sims         <- align(year_t)
  year_t_lag_sims     <- align(year_t_lag)

  # Calculate changes (for each simulation column)
  # Change = current − lagged (positive = increasing, negative = decreasing)
  baseline_change_sims <- baseline_t_sims - baseline_t_lag_sims
  year_change_sims     <- year_t_sims - year_t_lag_sims

  # Calculate anomaly (difference of differences)
  # Positive anomaly = year increasing faster than baseline (or decreasing slower)
  # Negative anomaly = year decreasing faster than baseline (drought stress signal)
  anomaly_sims <- year_change_sims - baseline_change_sims

  # Calculate summary statistics
  baseline_change_stats <- calculate_stats(baseline_change_sims)
  year_change_stats <- calculate_stats(year_change_sims)
  anomaly_stats <- calculate_stats(anomaly_sims)

  # Test significance (95% CI excludes zero)
  significant <- (anomaly_stats$lwr > 0) | (anomaly_stats$upr < 0)

  # Calculate posterior probabilities
  prob_slower <- rowMeans(anomaly_sims < 0, na.rm = TRUE)  # Year changing slower
  prob_faster <- rowMeans(anomaly_sims > 0, na.rm = TRUE)  # Year changing faster

  # Combine summary statistics
  summary_df <- data.frame(
    pixel_id = valid_pixel_ids,

    # Baseline change
    baseline_change_mean = baseline_change_stats$mean,
    baseline_change_lwr = baseline_change_stats$lwr,
    baseline_change_upr = baseline_change_stats$upr,

    # Year change
    year_change_mean = year_change_stats$mean,
    year_change_lwr = year_change_stats$lwr,
    year_change_upr = year_change_stats$upr,

    # Anomaly
    anomaly_change_mean = anomaly_stats$mean,
    anomaly_change_lwr = anomaly_stats$lwr,
    anomaly_change_upr = anomaly_stats$upr,

    # Significance
    significant = significant,
    prob_slower = prob_slower,
    prob_faster = prob_faster
  )

  return(list(
    summary = summary_df,
    posteriors = anomaly_sims
  ))
}

#' Process all windows for a specific year-DOY combination
process_year_doy <- function(year, yday, window_sizes, valid_pixel_ids,
                               baseline_post_dir, year_post_dir, posteriors_output_dir) {

  results_list <- list()

  for (window in window_sizes) {
    # Calculate change anomaly
    result <- tryCatch({
      calculate_change_anomaly(year, yday, window, valid_pixel_ids,
                                baseline_post_dir, year_post_dir)
    }, error = function(e) {
      warning(sprintf("Error in year %d, DOY %d, window %d: %s",
                      year, yday, window, e$message))
      return(NULL)
    })

    if (is.null(result)) {
      next  # Skip if data missing or error
    }

    # Save posteriors immediately to avoid memory buildup
    year_post_dir_out <- file.path(posteriors_output_dir, as.character(year))
    if (!dir.exists(year_post_dir_out)) {
      dir.create(year_post_dir_out, recursive = TRUE)
    }

    posterior_file <- file.path(year_post_dir_out,
                                 sprintf("doy_%03d_window_%02d.rds", yday, window))
    # Match the list(pixel_id, sims) format used by scripts 02 and 03 so any
    # future consumer of these posteriors uses a single, consistent loader.
    saveRDS(
      list(pixel_id = valid_pixel_ids, sims = result$posteriors),
      posterior_file, compress = "xz"
    )

    # Add metadata and store summary
    result$summary$yday <- yday
    result$summary$window <- window
    results_list[[as.character(window)]] <- result$summary
  }

  # Combine all windows for this DOY
  if (length(results_list) > 0) {
    return(do.call(rbind, results_list))
  } else {
    return(NULL)
  }
}

# ==============================================================================
# MAIN
# ==============================================================================

cat("=== Calculate Change Derivatives ===\n")
cat("Windows:", paste(config$window_sizes, "days"), "\n")
cat("Output:", config$output_dir, "\n")
cat("Posteriors:", config$posteriors_dir, "\n\n")

# Create output directories
if (!dir.exists(config$output_dir)) {
  dir.create(config$output_dir, recursive = TRUE)
}
if (!dir.exists(config$posteriors_dir)) {
  dir.create(config$posteriors_dir, recursive = TRUE)
}

# Load valid pixels
cat("Loading valid pixels...\n")
if (!file.exists(config$valid_pixels_file)) {
  stop("Valid pixels file not found. Run script 02 first.")
}
valid_pixels_df <- readRDS(config$valid_pixels_file)
# Sort to match the canonical pixel ordering used by scripts 02 and 03
# (those scripts arrange(pixel_id) before fitting; aligning here means the
# valid_pixel_ids vector is in the same order as the posterior matrices).
valid_pixels_df <- valid_pixels_df[order(valid_pixels_df$pixel_id), ]
valid_pixel_ids <- valid_pixels_df$pixel_id
cat("  Valid pixels:", format(length(valid_pixel_ids), big.mark = ","), "\n")

# Sanity check: NLCD-filtered pixel count is invariant across the pipeline.
# Hard stop rather than warning: a mismatch silently misaligns matrix rows in
# calculate_change_anomaly and produces wrong derivatives.
EXPECTED_VALID_PIXELS <- 125798L
if (length(valid_pixel_ids) != EXPECTED_VALID_PIXELS) {
  stop(sprintf(
    "Valid pixel count %s does not match expected %s. ",
    format(length(valid_pixel_ids), big.mark = ","),
    format(EXPECTED_VALID_PIXELS, big.mark = ",")
  ),
  "If the NLCD land-cover filter was intentionally changed, update ",
  "EXPECTED_VALID_PIXELS in scripts 04 and 06 to match.")
}
cat("\n")

# Get list of years from year posteriors directory
year_dirs <- list.dirs(config$year_posteriors_dir, full.names = FALSE, recursive = FALSE)
years <- as.integer(year_dirs)
years <- sort(years[!is.na(years)])

if (length(years) == 0) {
  stop("No year posterior directories found. Run script 03 first.")
}

cat("Found", length(years), "years:", paste(years, collapse = ", "), "\n\n")

# ==============================================================================
# PRE-FLIGHT POSTERIOR INVENTORY
# ==============================================================================
# Without this, missing posteriors are discovered one-task-at-a-time deep
# inside the parallel loop, wasting hours of compute. Inventory now, abort
# loudly if too much is missing.

cat("--- Pre-flight posterior inventory ---\n")

baseline_files <- list.files(config$baseline_posteriors_dir,
                             pattern = "^doy_\\d{3}\\.rds$",
                             full.names = FALSE)
baseline_doys <- as.integer(sub("^doy_(\\d{3})\\.rds$", "\\1", baseline_files))
baseline_doys <- sort(baseline_doys)
missing_baseline_doys <- setdiff(1:365, baseline_doys)
cat(sprintf("  Baseline posteriors: %d / 365 DOYs present\n",
            length(baseline_doys)))
if (length(missing_baseline_doys) > 0) {
  cat(sprintf("    Missing baseline DOYs: %s\n",
              paste(missing_baseline_doys, collapse = ", ")))
}

# Per-year DOY count
year_doy_counts <- integer(length(years)); names(year_doy_counts) <- years
for (yr in years) {
  yd_files <- list.files(file.path(config$year_posteriors_dir, as.character(yr)),
                         pattern = "^doy_\\d{3}\\.rds$",
                         full.names = FALSE)
  year_doy_counts[as.character(yr)] <- length(yd_files)
}
cat("  Year posteriors per year:\n")
for (yr_str in names(year_doy_counts)) {
  cat(sprintf("    %s: %d DOYs\n", yr_str, year_doy_counts[yr_str]))
}

# Heuristic abort: if baseline is more than 5% incomplete, the change
# derivatives will be patchy across all years — better to fail fast.
if (length(missing_baseline_doys) > 18L) {
  stop("Baseline posteriors are >5% incomplete (",
       length(missing_baseline_doys), " of 365 missing). ",
       "Re-run script 02 to backfill before proceeding.")
}
cat("\n")

# ==============================================================================
# RESUME MODE
# ==============================================================================
# A year is "complete" only if BOTH (a) the summary derivatives file exists
# AND is non-trivial in size, AND (b) every DOY-window posterior file the
# summary describes is present and non-empty.

existing_years <- integer(0)
incomplete_years <- list()

for (yr in years) {
  output_file <- file.path(config$output_dir, sprintf("derivatives_%d.rds", yr))
  if (!file.exists(output_file) || file.info(output_file)$size < 1e5) next

  year_post_dir_out <- file.path(config$posteriors_dir, as.character(yr))
  derivative_summary <- readRDS(output_file)
  expected_keys <- unique(derivative_summary[, c("yday", "window")])
  expected_files <- file.path(year_post_dir_out,
                              sprintf("doy_%03d_window_%02d.rds",
                                      expected_keys$yday, expected_keys$window))
  present_sizes <- file.info(expected_files)$size
  missing_count <- sum(is.na(present_sizes) | present_sizes == 0)

  if (missing_count == 0) {
    existing_years <- c(existing_years, yr)
  } else {
    incomplete_years[[as.character(yr)]] <- missing_count
  }
}

if (length(existing_years) > 0) {
  cat("Already complete:", paste(existing_years, collapse = ", "), "\n")
}
if (length(incomplete_years) > 0) {
  cat("Years with summary present but posteriors missing (will reprocess):\n")
  for (yr_str in names(incomplete_years)) {
    cat(sprintf("  %s: %d posterior file(s) missing\n",
                yr_str, incomplete_years[[yr_str]]))
  }
}

years <- setdiff(years, existing_years)

if (length(years) == 0) {
  cat("All years already processed (with complete posteriors)!\n")
  quit(save = "no", status = 0)
}

cat("Will process", length(years), "years:", paste(years, collapse = ", "), "\n\n")

# ==============================================================================
# PROCESS EACH YEAR
# ==============================================================================

cat("Processing change derivatives...\n")
cat("======================================\n\n")

start_time_total <- Sys.time()
year_stats <- list()

for (yr in years) {
  cat(sprintf("=== Processing Year %d ===\n", yr))
  start_time <- Sys.time()

  # Get list of DOYs available for this year
  year_doy_dir <- file.path(config$year_posteriors_dir, as.character(yr))
  if (!dir.exists(year_doy_dir)) {
    cat("  WARNING: Year directory not found, skipping\n\n")
    next
  }

  doy_files <- list.files(year_doy_dir, pattern = "doy_\\d{3}\\.rds")
  available_doys <- as.integer(gsub("doy_(\\d{3})\\.rds", "\\1", doy_files))
  available_doys <- sort(available_doys)

  cat(sprintf("  Available DOYs: %d\n", length(available_doys)))
  cat(sprintf("  Processing with %d future workers...\n", config$n_cores))
  flush.console()

  # Process all DOYs in parallel using the future-recycling pattern from
  # MEMORY.md: plan(multisession) before, plan(sequential) + gc() after,
  # tryCatch fallback to sequential lapply if a worker dies. Replaces
  # mclapply, which on long runs has hit worker memory exhaustion in this
  # project (see RUNNING_ANALYSES.md "Session Summary (Feb 16)").
  plan(multisession, workers = config$n_cores)

  doy_results <- tryCatch({
    future_lapply(available_doys, function(yday) {
      tryCatch({
        process_year_doy(yr, yday, config$window_sizes, valid_pixel_ids,
                          config$baseline_posteriors_dir, config$year_posteriors_dir,
                          config$posteriors_dir)
      }, error = function(e) {
        # Note: no flush.console() here — multisession workers' stdout is
        # captured by future and only ferried to the parent on result resolution,
        # so flushing from inside the worker is a no-op.
        cat(sprintf("ERROR in year %d, DOY %d: %s\n", yr, yday, e$message))
        return(NULL)
      })
    }, future.seed = NULL)
    # future.seed = NULL: process_year_doy loads posterior .rds files and does
    # deterministic matrix arithmetic — no RNG calls. TRUE would gratuitously
    # generate L'Ecuyer-CMRG seeds per task.
  }, error = function(e) {
    cat("WARNING: future_lapply failed for year ", yr, ": ",
        conditionMessage(e), "\n", sep = "")
    cat("Falling back to sequential lapply (slower but safer)...\n")
    flush.console()  # Without this, the warning is invisible until the (multi-hour) fallback completes.
    lapply(available_doys, function(yday) {
      tryCatch({
        process_year_doy(yr, yday, config$window_sizes, valid_pixel_ids,
                          config$baseline_posteriors_dir, config$year_posteriors_dir,
                          config$posteriors_dir)
      }, error = function(e2) {
        cat(sprintf("ERROR in year %d, DOY %d: %s\n", yr, yday, e2$message))
        flush.console()
        NULL
      })
    })
  })

  plan(sequential)
  gc(verbose = FALSE)
  flush.console()

  # Combine results (memory-optimized)
  cat("  Parallel processing complete.\n")
  cat(sprintf("  Received %d results from future_lapply\n", length(doy_results)))

  valid_results <- doy_results[!sapply(doy_results, is.null)]
  cat(sprintf("  Valid results: %d of %d DOYs (%.1f%%)\n",
              length(valid_results), length(available_doys),
              100 * length(valid_results) / length(available_doys)))

  # Free original list immediately
  rm(doy_results)
  gc(verbose = FALSE)

  if (length(valid_results) == 0) {
    cat("  WARNING: No valid results for this year\n\n")
    next
  }

  cat("  Combining results into data frame...\n")

  # Use data.table for memory-efficient binding
  year_df <- tryCatch({
    df <- data.table::rbindlist(valid_results)
    df <- as.data.frame(df)  # Convert back to data.frame
    df$year <- yr
    cat(sprintf("  Combined: %s rows, %d columns\n",
                format(nrow(df), big.mark = ","), ncol(df)))
    df
  }, error = function(e) {
    cat(sprintf("  ERROR during combining: %s\n", e$message))
    cat("  Attempting to save valid_results for debugging...\n")
    debug_file <- file.path(config$output_dir, sprintf("debug_valid_results_%d.rds", yr))
    saveRDS(valid_results, debug_file)
    cat(sprintf("  Saved to: %s\n", debug_file))
    stop(e$message)
  })

  # Free intermediate results
  rm(valid_results)
  gc(verbose = FALSE)

  # Calculate statistics
  n_complete <- nrow(year_df)
  n_significant <- sum(year_df$significant, na.rm = TRUE)
  pct_significant <- 100 * n_significant / n_complete

  # Save year results
  output_file <- file.path(config$output_dir, sprintf("derivatives_%d.rds", yr))
  cat(sprintf("  Saving to: %s\n", output_file))
  saveRDS(year_df, output_file, compress = "xz")

  # Verify the write — guards against NFS/CIFS hiccups producing a truncated
  # file that the resume-mode check would later treat as complete.
  written_size_mb <- file.info(output_file)$size / 1024^2
  if (is.na(written_size_mb) || written_size_mb < 0.1) {
    stop(sprintf("Year file write failed or suspiciously small (%.2f MB): %s",
                 written_size_mb, output_file))
  }
  cat(sprintf("  Wrote %.1f MB\n", written_size_mb))

  # Record statistics
  elapsed_time <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  year_stats[[as.character(yr)]] <- data.frame(
    year = yr,
    n_results = n_complete,
    n_significant = n_significant,
    pct_significant = pct_significant,
    mean_anomaly = mean(year_df$anomaly_change_mean, na.rm = TRUE),
    elapsed_mins = elapsed_time
  )

  cat(sprintf("  Year %d: %.1f%% significant in %.1f minutes\n\n",
              yr, pct_significant, elapsed_time))

  # Clean up memory before next year
  rm(year_df)
  gc(verbose = FALSE)
}

# ==============================================================================
# SUMMARY
# ==============================================================================

elapsed_total <- as.numeric(difftime(Sys.time(), start_time_total, units = "mins"))

cat("======================================\n")
cat("All years complete!\n\n")

# Combine and save statistics
if (length(year_stats) > 0) {
  cat("Saving derivative statistics...\n")
  stats_df <- do.call(rbind, year_stats)
  rownames(stats_df) <- NULL
  saveRDS(stats_df, config$stats_file)

  cat("\nSummary:\n")
  cat("  Years processed:", paste(stats_df$year, collapse = ", "), "\n")
  cat("  Output directory:", config$output_dir, "\n")
  cat("  Posteriors directory:", config$posteriors_dir, "\n")
  cat("  Stats saved to:", config$stats_file, "\n\n")

  cat("Change Derivative Statistics:\n")
  cat(sprintf("  Mean significant results: %.1f%%\n", mean(stats_df$pct_significant)))
  cat(sprintf("  Mean anomaly: %.6f\n", mean(stats_df$mean_anomaly)))
}

cat(sprintf("\nTotal time: %.1f minutes\n", elapsed_total))
