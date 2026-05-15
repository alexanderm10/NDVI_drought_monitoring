# ==============================================================================
# 04_calculate_anomalies.R
#
# Purpose: Calculate NDVI anomalies (year predictions − baseline norms) using
#          full posterior distributions for proper uncertainty propagation.
#
# Approach:
#   For each (year, DOY) where a year posterior exists:
#     - Load year posterior      → 125k × 100 matrix of NDVI sims
#     - Load baseline posterior  → 125k × 100 matrix of NDVI sims
#     - Verify pixel_id alignment
#     - anomaly_sims = year_sims − baseline_sims  (element-wise)
#     - Summary stats: mean, lwr (2.5%), upr (97.5%) per pixel
#     - Significance flag: 95% CI excludes zero
#     - Optionally save anomaly_sims (for downstream uncertainty propagation)
#
# This replaces the prior naive interval arithmetic on summary CI bounds,
# which gave systematically wider intervals than the proper posterior method
# AND was inconsistent with script 06's posterior-based change derivatives.
#
# Usage:
#   Rscript 04_calculate_anomalies.R                  # all available years
#   Rscript 04_calculate_anomalies.R 2020 2024        # year range
#   Rscript 04_calculate_anomalies.R --save-posteriors  # also save anomaly_sims
#   Rscript 04_calculate_anomalies.R --workers=3      # parallel workers per year
#
# Input:
#   - baseline_posteriors/doy_NNN.rds          (script 02; 365 files)
#   - year_predictions_posteriors/YYYY/doy_NNN.rds  (script 03; per year)
#   - valid_pixels_landcover_filtered.rds      (script 02)
#
# Output (per year):
#   - modeled_ndvi_anomalies/anomalies_YYYY.rds              (summary stats)
#   - modeled_ndvi_anomalies_posteriors/YYYY/doy_NNN.rds     (optional, --save-posteriors)
#
# ==============================================================================

# Limit BLAS/LAPACK threads to be a good neighbor on shared systems
Sys.setenv(OMP_NUM_THREADS = 2)
Sys.setenv(OPENBLAS_NUM_THREADS = 2)

library(dplyr)
library(future)
library(future.apply)
library(matrixStats)  # rowQuantiles — ~1.8x faster than apply(quantile, ...)
                      # at 129K x 100; bit-equivalent to base R's quantile (type 7)

# Required for future.apply globals. The actual posterior loads happen
# inside the worker via readRDS, so the only global shipped is the
# process_doy closure (paths + scalars, ~few KB) — 2 GB is conservative.
options(future.globals.maxSize = 2 * 1024^3)

source("00_setup_paths.R")
hls_paths <- setup_hls_paths()
# Shared readRDS_retry helper (was inline in this script before 2026-05-15;
# moved to 00_posterior_functions.R so 04 and 06 share a single definition).
source("00_posterior_functions.R")

# ==============================================================================
# CLI
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)
save_posteriors <- "--save-posteriors" %in% args
n_workers <- {
  m <- regmatches(args, regexpr("^--workers=\\d+", args))
  if (length(m) > 0) as.integer(sub("^--workers=", "", m[1])) else 3L
}
year_args <- as.integer(args[grepl("^[0-9]+$", args)])

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Inputs
  baseline_posteriors_dir = file.path(hls_paths$gam_models, "baseline_posteriors"),
  year_posteriors_dir     = file.path(hls_paths$gam_models, "year_predictions_posteriors"),
  valid_pixels_file       = file.path(hls_paths$gam_models, "valid_pixels_landcover_filtered.rds"),

  # Outputs
  output_dir          = file.path(hls_paths$gam_models, "modeled_ndvi_anomalies"),
  posteriors_dir      = file.path(hls_paths$gam_models, "modeled_ndvi_anomalies_posteriors"),
  stats_file          = file.path(hls_paths$gam_models, "modeled_ndvi_anomalies_stats.rds"),

  # Behavior
  save_posteriors = save_posteriors,
  n_workers       = n_workers
)

cat("=== Calculate NDVI Anomalies (posterior-based) ===\n")
cat("Started:           ", as.character(Sys.time()), "\n")
cat("Save posteriors:   ", config$save_posteriors, "\n")
cat("Parallel workers:  ", config$n_workers, "\n")
cat("Output:            ", config$output_dir, "\n")
if (config$save_posteriors) {
  cat("Posteriors output: ", config$posteriors_dir, "\n")
}
cat("\n")

# Create output directories
if (!dir.exists(config$output_dir))     dir.create(config$output_dir, recursive = TRUE)
if (config$save_posteriors && !dir.exists(config$posteriors_dir)) {
  dir.create(config$posteriors_dir, recursive = TRUE)
}

# ==============================================================================
# LOAD VALID PIXELS + ENFORCE INVARIANT
# ==============================================================================

cat("Loading valid pixels mask...\n")
if (!file.exists(config$valid_pixels_file)) {
  stop("Valid pixels file not found: ", config$valid_pixels_file,
       "\nRun script 02 first.")
}
valid_pixels_df <- readRDS(config$valid_pixels_file)

# Sanity check: NLCD-filtered pixel count is invariant across the pipeline.
# Hard stop rather than warning: the count aligns matrix rows across scripts
# 02/03/04/06; a silent mismatch produces wrong anomalies downstream.
# Constant updated 2026-05-08 from 125798 -> 129310 after the May 7-8 v2 backfill
# of script 02 (current NLCD filter: !is.na(nlcd_code) & nlcd_code != 1).
# See WORKFLOW.md "Land Cover Filtering > Maintenance" for the update procedure.
EXPECTED_VALID_PIXELS <- 129310L
if (nrow(valid_pixels_df) != EXPECTED_VALID_PIXELS) {
  stop(sprintf(
    "Valid pixel count %s does not match expected %s. ",
    format(nrow(valid_pixels_df), big.mark = ","),
    format(EXPECTED_VALID_PIXELS, big.mark = ",")
  ),
  "If the NLCD land-cover filter was intentionally changed, update ",
  "EXPECTED_VALID_PIXELS in scripts 04 and 06 to match.")
}
cat("  Valid pixels:", format(nrow(valid_pixels_df), big.mark = ","), "\n\n")

# ==============================================================================
# DETERMINE YEARS TO PROCESS
# ==============================================================================

# Discover available years from year-posteriors directory tree
year_dirs <- list.dirs(config$year_posteriors_dir, full.names = FALSE,
                       recursive = FALSE)
available_years <- as.integer(year_dirs)
available_years <- sort(available_years[!is.na(available_years)])

if (length(available_years) == 0) {
  stop("No year posterior subdirectories found in ",
       config$year_posteriors_dir,
       "\nRun script 03 first.")
}

# Optional CLI year filter
if (length(year_args) == 1) {
  available_years <- intersect(available_years, year_args[1])
} else if (length(year_args) == 2) {
  available_years <- intersect(available_years, year_args[1]:year_args[2])
} else if (length(year_args) > 2) {
  available_years <- intersect(available_years, year_args)
}

if (length(available_years) == 0) {
  stop("No years to process after applying CLI filter.")
}

# Resume: skip years whose anomaly summary file already exists at full size.
# (Per-DOY incompleteness within a year triggers reprocessing of the whole year;
# matches the pattern in script 03.)
#
# Threshold history (2026-05-13):
#   1e6 (1 MB): would have silently passed the 03 v2 truncated 300 MB
#               modeled_ndvi_2019.rds — too lenient.
#   1e9 (1 GB): false-tripped on year 2013 (only 253 DOYs since Landsat 8
#               launched 2013-04-11; produces ~800 MB compressed instead
#               of the ~1.1 GB full-year output) — too strict.
#   5e8 (500 MB) [current]: cleanly catches the known 03 v2 truncation
#               pattern (300 MB) while allowing 2013's legitimate ~800 MB
#               and full years' ~1.0-1.2 GB output. Cross-checked against
#               the modeled_ndvi/ size table from 03.
RESUME_MIN_BYTES <- 5e8
existing_years <- integer(0)
for (yr in available_years) {
  out_file <- file.path(config$output_dir, sprintf("anomalies_%d.rds", yr))
  if (file.exists(out_file) && file.info(out_file)$size > RESUME_MIN_BYTES) {
    existing_years <- c(existing_years, yr)
  }
}

years_to_process <- setdiff(available_years, existing_years)

if (length(existing_years) > 0) {
  cat("Already complete:", paste(existing_years, collapse = ", "), "\n")
}
if (length(years_to_process) == 0) {
  cat("All years already processed!\n")
  quit(save = "no", status = 0)
}
cat("Will process:", paste(years_to_process, collapse = ", "), "\n\n")

# ==============================================================================
# PROCESS EACH YEAR
# ==============================================================================

start_time_total <- Sys.time()
year_stats <- list()

for (yr in years_to_process) {
  cat(sprintf("=== Year %d ===\n", yr))
  year_start <- Sys.time()

  year_post_dir   <- file.path(config$year_posteriors_dir, as.character(yr))
  year_anom_post_dir <- file.path(config$posteriors_dir, as.character(yr))
  if (config$save_posteriors && !dir.exists(year_anom_post_dir)) {
    dir.create(year_anom_post_dir, recursive = TRUE)
  }

  # Enumerate DOYs that have BOTH a year posterior and a baseline posterior
  year_doy_files     <- list.files(year_post_dir,
                                   pattern = "^doy_\\d{3}\\.rds$",
                                   full.names = FALSE)
  year_doys          <- as.integer(sub("^doy_(\\d{3})\\.rds$", "\\1",
                                       year_doy_files))
  baseline_doy_files <- list.files(config$baseline_posteriors_dir,
                                   pattern = "^doy_\\d{3}\\.rds$",
                                   full.names = FALSE)
  baseline_doys      <- as.integer(sub("^doy_(\\d{3})\\.rds$", "\\1",
                                       baseline_doy_files))

  joint_doys <- sort(intersect(year_doys, baseline_doys))
  year_only  <- setdiff(year_doys, baseline_doys)
  if (length(year_only) > 0) {
    cat(sprintf("  Note: %d DOY(s) in year %d have no baseline posterior — skipping\n",
                length(year_only), yr))
  }
  cat(sprintf("  DOYs to process: %d (intersection of year + baseline)\n",
              length(joint_doys)))

  # ---------------------------------------------------------------
  # Per-DOY worker
  # ---------------------------------------------------------------
  process_doy <- function(doy) {
    tryCatch({
      year_path     <- file.path(year_post_dir,
                                 sprintf("doy_%03d.rds", doy))
      baseline_path <- file.path(config$baseline_posteriors_dir,
                                 sprintf("doy_%03d.rds", doy))

      year_post     <- readRDS_retry(year_path)
      baseline_post <- readRDS_retry(baseline_path)

      # Both files use the new posterior format: list(pixel_id, sims).
      # If pixel_id ordering differs between the two (shouldn't happen given
      # the pixel_coords sort in scripts 02 and 03, but defend anyway), align
      # by pixel_id.
      if (!identical(year_post$pixel_id, baseline_post$pixel_id)) {
        # Reorder baseline to match year ordering
        idx <- match(year_post$pixel_id, baseline_post$pixel_id)
        if (anyNA(idx)) {
          stop("Pixel mismatch between year and baseline posteriors at DOY ",
               doy, ": ", sum(is.na(idx)), " year pixels not in baseline.")
        }
        baseline_sims <- baseline_post$sims[idx, , drop = FALSE]
      } else {
        baseline_sims <- baseline_post$sims
      }

      year_sims <- year_post$sims

      # Element-wise anomaly: each of the 100 sims is independent (per the
      # seed-per-(year,DOY) draw in script 03 and the seed-per-DOY draw in
      # script 02), so anomaly_sims correctly captures variance of the difference.
      anomaly_sims <- year_sims - baseline_sims

      # Summary stats — explicit column-only sweep, no df.sim junk.
      # rowQuantiles returns N x 2 matrix; both probs in one C call.
      anom_mean <- rowMeans(anomaly_sims, na.rm = TRUE)
      anom_qs   <- rowQuantiles(anomaly_sims, probs = c(0.025, 0.975),
                                na.rm = TRUE)
      anom_lwr  <- anom_qs[, 1]
      anom_upr  <- anom_qs[, 2]
      significant <- (anom_lwr > 0) | (anom_upr < 0)
      prob_below_zero <- rowMeans(anomaly_sims < 0, na.rm = TRUE)

      # Optional posterior persistence (--save-posteriors)
      if (config$save_posteriors) {
        post_file <- file.path(year_anom_post_dir,
                               sprintf("doy_%03d.rds", doy))
        saveRDS(
          list(pixel_id = year_post$pixel_id, sims = anomaly_sims),
          post_file, compress = "xz"
        )
      }

      data.frame(
        pixel_id        = year_post$pixel_id,
        yday            = doy,
        anoms_mean      = anom_mean,
        anoms_lwr       = anom_lwr,
        anoms_upr       = anom_upr,
        significant     = significant,
        prob_below_zero = prob_below_zero
      )
    }, error = function(e) {
      # Worker stdout is not forwarded by future.apply, so cat() inside the
      # worker is invisible from the parent. Return a structured sentinel
      # the parent can detect after future_lapply completes (HIGH 2 in r-reviewer
      # 2026-05-13 audit).
      structure(
        list(doy = doy, msg = conditionMessage(e)),
        class = "doy_error"
      )
    })
  }

  # ---------------------------------------------------------------
  # Run DOYs in parallel via the future-recycling pattern (per MEMORY.md)
  # ---------------------------------------------------------------
  cat(sprintf("  Processing with %d future workers...\n", config$n_workers))
  flush.console()
  plan(multisession, workers = config$n_workers)

  results_list <- tryCatch({
    future_lapply(joint_doys, function(doy) {
      library(dplyr)
      library(matrixStats)
      process_doy(doy)
    }, future.seed = NULL)
    # future.seed = NULL: process_doy is pure arithmetic on posterior matrices —
    # no RNG calls. TRUE would gratuitously generate L'Ecuyer-CMRG seeds per task.
  }, error = function(e) {
    cat("  WARNING: future_lapply failed: ", conditionMessage(e), "\n", sep = "")
    cat("  Falling back to sequential lapply for year ", yr, "...\n", sep = "")
    flush.console()  # Without this, the warning is invisible until the fallback completes.
    lapply(joint_doys, process_doy)
  })

  plan(sequential)
  gc(verbose = FALSE)
  flush.console()

  # Surface per-DOY worker errors that the parallel path swallowed silently.
  # (Sequential fallback path's cat() prints reach stdout; parallel path's
  # don't — both produce the same doy_error sentinels here.)
  doy_errors <- Filter(function(x) inherits(x, "doy_error"), results_list)
  if (length(doy_errors) > 0) {
    cat(sprintf("  WARNING: %d DOY(s) failed in year %d:\n",
                length(doy_errors), yr))
    for (err in doy_errors) {
      cat(sprintf("    DOY %d: %s\n", err$doy, err$msg))
    }
    flush.console()
  }
  results_list <- Filter(
    Negate(function(x) inherits(x, "doy_error") || is.null(x)),
    results_list
  )
  n_doys_successful <- length(results_list)

  if (n_doys_successful == 0) {
    cat("  WARNING: no successful DOYs for year ", yr, " — skipping save\n", sep = "")
    flush.console()
    rm(results_list); gc(verbose = FALSE)
    next
  }
  if (n_doys_successful < length(joint_doys)) {
    cat(sprintf("  %d of %d DOYs succeeded (%d failed)\n",
                n_doys_successful, length(joint_doys),
                length(joint_doys) - n_doys_successful))
    flush.console()
  }

  year_df <- bind_rows(results_list)
  # Free results_list (~1.8 GB at 47M rows) before left_join allocates a
  # second copy of year_df (~2.7 GB). Cuts parent peak from ~6 GB to ~4 GB.
  # MEDIUM 2 in r-reviewer 2026-05-13 audit.
  rm(results_list); gc(verbose = FALSE)

  year_df$year <- yr

  # Attach x, y from the valid_pixels_df for downstream visualization
  year_df <- year_df %>%
    left_join(valid_pixels_df[, c("pixel_id", "x", "y")], by = "pixel_id")

  # ---------------------------------------------------------------
  # Save year file with write-integrity guard
  # ---------------------------------------------------------------
  out_file <- file.path(config$output_dir, sprintf("anomalies_%d.rds", yr))
  cat("  Saving to: ", out_file, "\n", sep = "")
  saveRDS(year_df, out_file, compress = "gzip")

  # Post-write integrity guard. Threshold matches the resume check
  # (RESUME_MIN_BYTES = 500 MB) so that a truncated mid-saveRDS — exactly
  # the failure mode that bit 03 v2 — fails LOUDLY at write time rather
  # than silently passing both the post-write log line ("Wrote 200 MB")
  # and the next-run resume scan. HIGH 1 in r-reviewer 2026-05-13 audit.
  # Expected sizes: 2013 ~800 MB (253 DOYs), 2014-2025 ~1.0-1.2 GB (full year).
  written_size <- file.info(out_file)$size
  written_size_mb <- written_size / 1024^2
  if (is.na(written_size) || written_size < RESUME_MIN_BYTES) {
    stop(sprintf(
      "Year file write failed or suspiciously small (%.0f MB, expected ~800-1200): %s",
      written_size_mb, out_file
    ))
  }
  cat(sprintf("  Wrote %.1f MB\n", written_size_mb))

  # Per-year stats for the summary table
  n_pixel_doy   <- nrow(year_df)
  n_significant <- sum(year_df$significant, na.rm = TRUE)
  pct_significant <- 100 * n_significant / n_pixel_doy
  mean_anom     <- mean(year_df$anoms_mean, na.rm = TRUE)
  sd_anom       <- sd(year_df$anoms_mean, na.rm = TRUE)
  elapsed_min   <- as.numeric(difftime(Sys.time(), year_start, units = "mins"))

  year_stats[[as.character(yr)]] <- data.frame(
    year              = yr,
    n_doys_expected   = length(joint_doys),
    n_doys_successful = n_doys_successful,
    n_pixel_doy       = n_pixel_doy,
    pct_significant   = pct_significant,
    mean_anom         = mean_anom,
    sd_anom           = sd_anom,
    elapsed_mins      = elapsed_min
  )

  cat(sprintf("  Year %d: %d/%d DOYs successful, %.1f%% significant in %.1f min\n\n",
              yr, n_doys_successful, length(joint_doys),
              pct_significant, elapsed_min))
  flush.console()

  rm(year_df); gc(verbose = FALSE)
}

# ==============================================================================
# SUMMARY
# ==============================================================================

elapsed_total <- as.numeric(difftime(Sys.time(), start_time_total,
                                     units = "mins"))

cat("======================================\n")
cat("All years complete.\n\n")

if (length(year_stats) > 0) {
  cat("Saving anomaly statistics...\n")
  stats_df <- do.call(rbind, year_stats); rownames(stats_df) <- NULL
  saveRDS(stats_df, config$stats_file)

  cat("\nSummary:\n")
  cat("  Years processed:    ", paste(stats_df$year, collapse = ", "), "\n")
  cat("  Output directory:   ", config$output_dir, "\n")
  cat("  Stats saved to:     ", config$stats_file, "\n")
  if (config$save_posteriors) {
    cat("  Posteriors written: ", config$posteriors_dir, "\n")
  }

  cat("\nAcross-year statistics:\n")
  cat(sprintf("  Mean anomaly range: %.4f to %.4f\n",
              min(stats_df$mean_anom), max(stats_df$mean_anom)))
  cat(sprintf("  Mean SD anomaly:    %.4f\n", mean(stats_df$sd_anom)))
  cat(sprintf("  Mean %% significant: %.1f%%\n", mean(stats_df$pct_significant)))
}

cat(sprintf("\nTotal time: %.1f minutes\n", elapsed_total))
