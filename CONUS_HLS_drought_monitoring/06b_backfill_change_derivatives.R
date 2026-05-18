# ==============================================================================
# 06b_backfill_change_derivatives.R
#
# Purpose: Backfill the 159 DOYs that were silently lost in 06 v1 cascades
#          for years 2013 (88 missing), 2015 (69 missing), 2016 (2 missing).
#          See RUNNING_ANALYSES.md "Why v2" section for the v1 failure
#          mechanism. v2's resume scan marks these years "complete" because
#          their summaries only reference the DOYs that actually wrote, so
#          the gaps need a targeted patch.
#
# Approach:
#   1. For each target year, list per-window posteriors in
#      change_derivatives_posteriors/YYYY/, find DOYs with fewer than 4
#      windows (i.e. not complete), and target those.
#   2. For each missing DOY, run the same calculate_change_anomaly +
#      saveRDS_validated 4-window write as script 06.
#   3. Load the existing derivatives_YYYY.rds, schema- and key-check the
#      new rows, rbind, re-save via saveRDS_validated. Backup the original
#      to derivatives_YYYY.rds.v1-pre-backfill.bak so the pre-backfill
#      year_df is recoverable.
#
# Coordination with 06 v2:
#   - v2 (commit 511797b) processes years 2017-2025; this script processes
#     years 2013, 2015, 2016. Disjoint target years => no posterior write
#     conflicts.
#   - Hold execution until v2 completes (Friday ~2026-05-22). Running
#     concurrently doubles CIFS write pressure during midnight backup
#     windows — exactly the cascade failure mode v2's saveRDS retry fix
#     was designed to absorb. Avoiding that test for now is cheaper than
#     debugging it.
#
# Code structure:
#   Helper functions (wrap_doy, posterior_exists, load_posteriors,
#   calculate_stats, calculate_change_anomaly, process_year_doy) are
#   duplicated from 06_calculate_change_derivatives.R. Two reasons we
#   accept the duplication:
#     - 06's main block executes on source(), so we can't source() just
#       its function defs from this script without modifying 06.
#     - 06 is mid-flight (v2 running 2026-05-18); refactoring it now to
#       extract functions adds restart risk for negligible reuse benefit.
#   AFTER v2 + this backfill complete, both scripts should be refactored
#   to source a shared 06_change_derivative_functions.R.
#
# Input:
#   - Baseline posteriors from script 02: baseline_posteriors/doy_*.rds
#   - Year posteriors from script 03: year_predictions_posteriors/YYYY/doy_*.rds
#   - Existing year summaries from 06 v1: change_derivatives/derivatives_YYYY.rds
#   - Existing window posteriors from 06 v1: change_derivatives_posteriors/YYYY/
#   - Valid pixels: valid_pixels_landcover_filtered.rds
#
# Output:
#   - New window posteriors filling the gaps:
#     change_derivatives_posteriors/YYYY/doy_XXX_window_YY.rds
#   - Updated year summaries (overwritten via saveRDS_validated):
#     change_derivatives/derivatives_YYYY.rds
#   - Backup of pre-backfill year summaries:
#     change_derivatives/derivatives_YYYY.rds.v1-pre-backfill.bak
# ==============================================================================

# Limit BLAS/LAPACK threads (same as 06)
Sys.setenv(OMP_NUM_THREADS = 2)
Sys.setenv(OPENBLAS_NUM_THREADS = 2)

library(dplyr)
library(future)
library(future.apply)
library(data.table)
library(matrixStats)

# 2 GB future globals cap (same rationale as 06 — worker carries ~4 posteriors
# × 78 MB + anomaly_sims of similar size + buffers)
options(future.globals.maxSize = 2 * 1024^3)

source("00_setup_paths.R")
hls_paths <- setup_hls_paths()
source("00_posterior_functions.R")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  baseline_posteriors_dir = file.path(hls_paths$gam_models, "baseline_posteriors"),
  year_posteriors_dir     = file.path(hls_paths$gam_models, "year_predictions_posteriors"),
  valid_pixels_file       = file.path(hls_paths$gam_models, "valid_pixels_landcover_filtered.rds"),
  output_dir              = file.path(hls_paths$gam_models, "change_derivatives"),
  posteriors_dir          = file.path(hls_paths$gam_models, "change_derivatives_posteriors"),
  window_sizes            = c(3, 7, 14, 30),
  target_years            = c(2013L, 2015L, 2016L),

  # Conservative worker count. Backfill total is only ~159 DOYs (vs 06's
  # ~4,250 DOYs across 13 years); the speedup gradient is modest and
  # concurrent CIFS pressure is the bigger risk. 06 v1's 3-worker config
  # was empirically stable; keep it.
  n_cores = 3L
)

EXPECTED_VALID_PIXELS <- 129310L

# ==============================================================================
# HELPER FUNCTIONS (mirror of 06's; see header for the no-source rationale)
# ==============================================================================

wrap_doy <- function(doy) ((doy - 1) %% 365) + 1

posterior_exists <- function(year, doy, posteriors_dir, is_baseline = FALSE) {
  if (is_baseline) {
    file.exists(file.path(posteriors_dir, sprintf("doy_%03d.rds", doy)))
  } else {
    file.exists(file.path(posteriors_dir, as.character(year),
                          sprintf("doy_%03d.rds", doy)))
  }
}

load_posteriors <- function(year, doy, posteriors_dir, is_baseline = FALSE) {
  file_path <- if (is_baseline) {
    file.path(posteriors_dir, sprintf("doy_%03d.rds", doy))
  } else {
    file.path(posteriors_dir, as.character(year),
              sprintf("doy_%03d.rds", doy))
  }
  if (!file.exists(file_path)) return(NULL)
  obj <- readRDS_retry(file_path)
  if (!is.list(obj) || !all(c("pixel_id", "sims") %in% names(obj))) {
    stop("Posterior file ", file_path,
         " not in expected list(pixel_id, sims) format")
  }
  obj
}

calculate_stats <- function(sims) {
  qs <- rowQuantiles(sims, probs = c(0.025, 0.975), na.rm = TRUE)
  data.frame(mean = rowMeans(sims, na.rm = TRUE),
             lwr  = qs[, 1],
             upr  = qs[, 2])
}

calculate_change_anomaly <- function(year, yday, window, valid_pixel_ids,
                                      baseline_post_dir, year_post_dir) {
  yday_lagged <- wrap_doy(yday - window)
  year_lagged <- if (yday_lagged > yday) year - 1 else year

  if (!all(c(
    posterior_exists(NULL, yday,        baseline_post_dir, is_baseline = TRUE),
    posterior_exists(NULL, yday_lagged, baseline_post_dir, is_baseline = TRUE),
    posterior_exists(year,        yday,        year_post_dir),
    posterior_exists(year_lagged, yday_lagged, year_post_dir)
  ))) return(NULL)

  baseline_t     <- load_posteriors(NULL, yday,        baseline_post_dir, is_baseline = TRUE)
  baseline_t_lag <- load_posteriors(NULL, yday_lagged, baseline_post_dir, is_baseline = TRUE)
  year_t         <- load_posteriors(year,        yday,        year_post_dir)
  year_t_lag     <- load_posteriors(year_lagged, yday_lagged, year_post_dir)

  if (is.null(baseline_t) || is.null(baseline_t_lag) ||
      is.null(year_t) || is.null(year_t_lag)) return(NULL)

  ref_pixels <- baseline_t$pixel_id
  align <- function(post) {
    if (identical(post$pixel_id, ref_pixels)) return(post$sims)
    idx <- match(ref_pixels, post$pixel_id)
    if (anyNA(idx)) stop("Pixel mismatch in posterior file")
    post$sims[idx, , drop = FALSE]
  }
  baseline_t_sims     <- align(baseline_t)
  baseline_t_lag_sims <- align(baseline_t_lag)
  year_t_sims         <- align(year_t)
  year_t_lag_sims     <- align(year_t_lag)

  baseline_change_sims <- baseline_t_sims - baseline_t_lag_sims
  year_change_sims     <- year_t_sims - year_t_lag_sims
  anomaly_sims         <- year_change_sims - baseline_change_sims

  baseline_change_stats <- calculate_stats(baseline_change_sims)
  year_change_stats     <- calculate_stats(year_change_sims)
  anomaly_stats         <- calculate_stats(anomaly_sims)

  significant <- (anomaly_stats$lwr > 0) | (anomaly_stats$upr < 0)
  prob_slower <- rowMeans(anomaly_sims < 0, na.rm = TRUE)
  prob_faster <- rowMeans(anomaly_sims > 0, na.rm = TRUE)

  summary_df <- data.frame(
    pixel_id             = valid_pixel_ids,
    baseline_change_mean = baseline_change_stats$mean,
    baseline_change_lwr  = baseline_change_stats$lwr,
    baseline_change_upr  = baseline_change_stats$upr,
    year_change_mean     = year_change_stats$mean,
    year_change_lwr      = year_change_stats$lwr,
    year_change_upr      = year_change_stats$upr,
    anomaly_change_mean  = anomaly_stats$mean,
    anomaly_change_lwr   = anomaly_stats$lwr,
    anomaly_change_upr   = anomaly_stats$upr,
    significant          = significant,
    prob_slower          = prob_slower,
    prob_faster          = prob_faster
  )

  list(summary = summary_df, posteriors = anomaly_sims)
}

process_year_doy <- function(year, yday, window_sizes, valid_pixel_ids,
                              baseline_post_dir, year_post_dir, posteriors_output_dir) {
  buffered <- list()

  for (window in window_sizes) {
    result <- tryCatch({
      calculate_change_anomaly(year, yday, window, valid_pixel_ids,
                                baseline_post_dir, year_post_dir)
    }, error = function(e) {
      cat(sprintf("ERROR in year %d, DOY %d, window %d (phase 1): %s\n",
                  year, yday, window, e$message))
      return(NULL)
    })
    if (is.null(result)) next
    result$summary$yday   <- yday
    result$summary$window <- window
    buffered[[as.character(window)]] <- result
  }

  if (length(buffered) == 0L) return(NULL)

  year_post_dir_out <- file.path(posteriors_output_dir, as.character(year))
  if (!dir.exists(year_post_dir_out)) {
    dir.create(year_post_dir_out, recursive = TRUE)
  }

  for (window_key in names(buffered)) {
    window <- as.integer(window_key)
    post_file <- file.path(year_post_dir_out,
                           sprintf("doy_%03d_window_%02d.rds", yday, window))
    # Note orphan overwrites for auditability — diff caught this DOY as
    # missing only because not all 4 windows were complete. The 1-3 windows
    # that DID land in v1 (Phase 2 partial write) are about to be replaced
    # with deterministically-identical recomputed files. r-reviewer 2026-05-18
    # MEDIUM 2: a log line here makes the post-run audit trail explicit.
    if (file.exists(post_file)) {
      cat(sprintf("    Overwriting orphan window file: %s\n",
                  basename(post_file)))
    }
    saveRDS_validated(
      list(pixel_id = valid_pixel_ids,
           sims     = buffered[[window_key]]$posteriors),
      post_file, compress = "xz"
    )
  }

  do.call(rbind, lapply(buffered, function(b) b$summary))
}

# ==============================================================================
# MAIN
# ==============================================================================

cat("=== 06b backfill — fill 06 v1 silent cascade losses ===\n")
cat("Target years:", paste(config$target_years, collapse = ", "), "\n")
cat("Windows:", paste(config$window_sizes, "days"), "\n\n")

if (!file.exists(config$valid_pixels_file)) {
  stop("Valid pixels file not found: ", config$valid_pixels_file)
}
valid_pixels_df <- readRDS(config$valid_pixels_file)
valid_pixels_df <- valid_pixels_df[order(valid_pixels_df$pixel_id), ]
valid_pixel_ids <- valid_pixels_df$pixel_id

if (length(valid_pixel_ids) != EXPECTED_VALID_PIXELS) {
  stop(sprintf(
    "Valid pixel count %s does not match expected %s. ",
    format(length(valid_pixel_ids), big.mark = ","),
    format(EXPECTED_VALID_PIXELS, big.mark = ",")
  ))
}
cat("Valid pixels:", format(length(valid_pixel_ids), big.mark = ","), "\n\n")

# ==============================================================================
# DIFF — find DOYs needing backfill per year
# ==============================================================================

cat("--- Per-year diff ---\n")
missing_by_year <- list()

# Size floor for "complete" window posteriors. Matches 06's PER_WINDOW_MIN_BYTES:
# empirical baseline-posterior min is 77 MB; 50 MB is 35% below that floor and
# catches the 48 MB / 76 MB corruption classes observed in 03 v2 / v3 plus any
# legacy v1 window files truncated by a mid-write CIFS hiccup before the
# saveRDS retry fix landed. Existence-only counting would silently classify a
# corrupt file as complete (r-reviewer 2026-05-18 HIGH 3).
PER_WINDOW_MIN_BYTES <- 50e6

for (yr in config$target_years) {
  yr_str <- as.character(yr)

  # Expected = whatever year posteriors exist in 03's output dir for this year
  expected_dir <- file.path(config$year_posteriors_dir, yr_str)
  if (!dir.exists(expected_dir)) {
    stop("Year posteriors dir missing: ", expected_dir)
  }
  expected_files <- list.files(expected_dir, pattern = "^doy_\\d{3}\\.rds$")
  expected_doys <- sort(as.integer(sub("doy_(\\d{3})\\.rds", "\\1", expected_files)))

  # Present = DOYs with ALL 4 windows written AND each >= PER_WINDOW_MIN_BYTES.
  present_dir <- file.path(config$posteriors_dir, yr_str)
  complete_doys <- integer(0)
  if (dir.exists(present_dir)) {
    present_files <- list.files(present_dir,
                                pattern = "^doy_\\d{3}_window_\\d{2}\\.rds$",
                                full.names = TRUE)
    if (length(present_files) > 0) {
      present_info <- file.info(present_files)
      valid_idx <- !is.na(present_info$size) &
                   present_info$size >= PER_WINDOW_MIN_BYTES
      valid_files <- basename(present_files[valid_idx])
      doy_per_file <- as.integer(sub("doy_(\\d{3})_window_\\d{2}\\.rds",
                                     "\\1", valid_files))
      counts <- table(doy_per_file)
      complete_doys <- as.integer(names(counts)[counts == length(config$window_sizes)])
    }
  }

  missing <- setdiff(expected_doys, complete_doys)
  missing_by_year[[yr_str]] <- missing
  cat(sprintf("  %s: %d expected, %d complete, %d missing\n",
              yr_str, length(expected_doys), length(complete_doys), length(missing)))
}
cat("\n")

total_missing <- sum(lengths(missing_by_year))
if (total_missing == 0) {
  cat("Nothing to backfill — all target years already complete.\n")
  quit(save = "no", status = 0)
}
cat(sprintf("Total DOYs to backfill: %d\n\n", total_missing))

# ==============================================================================
# PROCESS each year — compute windows in parallel, then merge year summary
# ==============================================================================

start_time_total <- Sys.time()
year_stats <- list()

for (yr in config$target_years) {
  yr_str  <- as.character(yr)
  missing <- missing_by_year[[yr_str]]

  if (length(missing) == 0) {
    cat(sprintf("=== Year %d — nothing to do ===\n\n", yr))
    next
  }

  cat(sprintf("=== Processing Year %d (%d DOYs) ===\n", yr, length(missing)))
  doy_str <- paste(head(missing, 20), collapse = ", ")
  if (length(missing) > 20) doy_str <- paste0(doy_str, " ...")
  cat(sprintf("  DOYs: %s\n", doy_str))
  start_time <- Sys.time()

  # Same future-recycling pattern as 06 (see MEMORY.md for the 6-element
  # stability checklist).
  plan(multisession, workers = config$n_cores)

  doy_results <- tryCatch({
    future_lapply(missing, function(yday) {
      tryCatch({
        process_year_doy(yr, yday, config$window_sizes, valid_pixel_ids,
                          config$baseline_posteriors_dir,
                          config$year_posteriors_dir,
                          config$posteriors_dir)
      }, error = function(e) {
        cat(sprintf("ERROR in year %d, DOY %d: %s\n", yr, yday, e$message))
        return(NULL)
      })
    }, future.seed = NULL)
  }, error = function(e) {
    cat("WARNING: future_lapply failed for year ", yr, ": ",
        conditionMessage(e), "\n", sep = "")
    cat("Falling back to sequential lapply...\n")
    flush.console()
    lapply(missing, function(yday) {
      tryCatch({
        process_year_doy(yr, yday, config$window_sizes, valid_pixel_ids,
                          config$baseline_posteriors_dir,
                          config$year_posteriors_dir,
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

  valid_results <- doy_results[!sapply(doy_results, is.null)]
  n_completed <- length(valid_results)
  cat(sprintf("  Valid: %d of %d (%.1f%%)\n",
              n_completed, length(missing),
              100 * n_completed / length(missing)))
  rm(doy_results)
  gc(verbose = FALSE)

  if (n_completed == 0) {
    cat("  WARNING: No valid results — skipping year-summary update\n\n")
    next
  }

  new_rows <- data.table::rbindlist(valid_results)
  new_rows[, year := yr]
  rm(valid_results)
  gc(verbose = FALSE)
  n_new_rows <- nrow(new_rows)
  cat(sprintf("  New rows to merge: %s\n",
              format(n_new_rows, big.mark = ",")))

  # ============================================================
  # Merge into existing year summary
  # ============================================================
  output_file <- file.path(config$output_dir,
                           sprintf("derivatives_%d.rds", yr))
  if (!file.exists(output_file)) {
    stop("Existing year summary missing: ", output_file,
         ". Refusing to write — this script is for backfill, not initial fit.")
  }

  # Backup FIRST, before loading anything heavy (r-reviewer 2026-05-18
  # CRITICAL). Two reasons:
  #   1. Reduces memory peak: the backup file.copy runs against the original
  #      compressed file (4.5-11 GB) instead of overlapping with the
  #      decompressed existing (~17 GB) + new_rows + combined in memory.
  #   2. Closes the inconsistent-state window where the script could die
  #      between rm(existing) and file.copy completing.
  # Atomic backup via .tmp + rename (r-reviewer 2026-05-18 HIGH 2): mid-copy
  # kills would otherwise leave a truncated .bak that the "already exists"
  # branch silently trusts on restart.
  backup_file <- paste0(output_file, ".v1-pre-backfill.bak")
  if (!file.exists(backup_file)) {
    cat(sprintf("  Backing up original to %s\n", basename(backup_file)))
    bak_tmp <- paste0(backup_file, ".tmp")
    if (file.exists(bak_tmp)) suppressWarnings(file.remove(bak_tmp))
    if (!isTRUE(file.copy(output_file, bak_tmp, copy.mode = TRUE))) {
      stop(sprintf("file.copy of %s -> %s failed", output_file, bak_tmp))
    }
    if (!isTRUE(file.rename(bak_tmp, backup_file))) {
      suppressWarnings(file.remove(bak_tmp))
      stop(sprintf("file.rename of %s -> %s failed", bak_tmp, backup_file))
    }
  } else {
    # Validate the existing backup isn't a truncated leftover from a prior
    # killed attempt. CIFS file.copy is not atomic, so a partial .bak from
    # before the rename-pattern fix could exist; require it to be within 1%
    # of the original size before trusting it.
    bak_size  <- file.info(backup_file)$size
    orig_size <- file.info(output_file)$size
    if (is.na(bak_size) || bak_size < orig_size * 0.99) {
      stop(sprintf(
        "Backup %s exists but is truncated (%.0f MB vs original %.0f MB). ",
        basename(backup_file), bak_size / 1e6, orig_size / 1e6),
        "Delete or fix the .bak before retrying."
      )
    }
    cat(sprintf("  Backup already exists (verified %.0f MB): %s\n",
                bak_size / 1e6, basename(backup_file)))
  }

  cat(sprintf("  Loading existing year summary: %s\n", basename(output_file)))
  existing <- readRDS_retry(output_file)
  # 06 saves year_df as a data.table (created via data.table::rbindlist). Force
  # the type here so the data.table-syntax key-defense below behaves correctly
  # — base data.frame[,c("a","b")] subsets columns, but data.table[,c("a","b")]
  # returns the column-name vector, which would break the overlap_pairs merge.
  if (!data.table::is.data.table(existing)) {
    existing <- data.table::as.data.table(existing)
  }
  cat(sprintf("  Existing rows: %s\n",
              format(nrow(existing), big.mark = ",")))

  # Schema defense — column set must match exactly. Mismatch means 06 has
  # diverged from this script's column definitions or the existing file is
  # corrupt. Either way, refuse to merge.
  if (!setequal(colnames(existing), colnames(new_rows))) {
    stop(sprintf(
      "Column schema mismatch in year %d: existing-only=[%s], new-only=[%s]",
      yr,
      paste(setdiff(colnames(existing), colnames(new_rows)), collapse = ", "),
      paste(setdiff(colnames(new_rows), colnames(existing)), collapse = ", ")
    ))
  }

  # Key defense at the (yday, window) grain (r-reviewer 2026-05-18 HIGH 1).
  # Per-row paste0 across ~143 M rows of `existing` allocates ~5 GB of
  # transient character strings; unique pairs are ~1500 integers and the
  # check is effectively free. Either v1's resume scan was wrong, or our
  # diff missed a partially-written DOY — halt rather than silently dup.
  # data.table .() syntax (not c(...)) is required: existing[, c("a","b")]
  # returns the character vector, not a subsetted table.
  existing_pairs <- unique(existing[, .(yday, window)])
  new_pairs      <- unique(new_rows[, .(yday, window)])
  overlap_pairs  <- merge(new_pairs, existing_pairs,
                          by = c("yday", "window"))
  if (nrow(overlap_pairs) > 0) {
    stop(sprintf(
      "Overlap on (yday, window) in year %d: %d pair(s). First 5: %s. ",
      yr, nrow(overlap_pairs),
      paste(sprintf("(%d,%d)",
                    head(overlap_pairs$yday, 5),
                    head(overlap_pairs$window, 5)),
            collapse = ", ")
    ),
    "This indicates the diff under-counted complete DOYs OR v1 wrote ",
    "partial DOYs that the resume scan missed. Investigate before merge.")
  }
  rm(existing_pairs, new_pairs, overlap_pairs)

  combined <- data.table::rbindlist(list(existing, new_rows), use.names = TRUE)
  rm(existing, new_rows)
  gc(verbose = FALSE)
  cat(sprintf("  Combined rows: %s\n",
              format(nrow(combined), big.mark = ",")))

  cat(sprintf("  Saving combined summary to: %s\n", basename(output_file)))
  saveRDS_validated(combined, output_file, compress = "xz")

  # Belt-and-suspenders size guard (r-reviewer 2026-05-18 MEDIUM 1).
  # saveRDS_validated round-trips a read of the .tmp before atomic rename, so
  # an outright corrupt write would have already stop()-ed. Kept here because
  # an unexpectedly tiny `combined` (e.g. all valid_results dropped at
  # rbindlist for an unforeseen reason) wouldn't trigger the read-back check.
  # Threshold matches 06's YEAR_SUMMARY_MIN_BYTES = 500 MB.
  written_size <- file.info(output_file)$size
  written_size_mb <- written_size / 1024^2
  if (is.na(written_size) || written_size < 5e8) {
    stop(sprintf(
      "Combined summary unexpectedly small (%.0f MB, expected ~5000+): %s",
      written_size_mb, output_file
    ))
  }
  cat(sprintf("  Wrote %.1f MB\n", written_size_mb))

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
  year_stats[[yr_str]] <- data.frame(
    year         = yr,
    n_attempted  = length(missing),
    n_completed  = n_completed,
    n_new_rows   = n_new_rows,
    n_total_rows = nrow(combined),
    elapsed_mins = elapsed
  )

  cat(sprintf("  Year %d backfill done in %.1f min\n\n", yr, elapsed))

  rm(combined)
  gc(verbose = FALSE)
}

# ==============================================================================
# SUMMARY
# ==============================================================================

elapsed_total <- as.numeric(difftime(Sys.time(), start_time_total, units = "mins"))
cat("======================================\n")
cat("Backfill complete!\n\n")

if (length(year_stats) > 0) {
  cat("Per-year results:\n")
  for (yr_str in names(year_stats)) {
    s <- year_stats[[yr_str]]
    cat(sprintf("  %s: %d/%d DOYs attempted, %s total rows in summary, %.1f min\n",
                yr_str, s$n_completed, s$n_attempted,
                format(s$n_total_rows, big.mark = ","), s$elapsed_mins))
  }
}

cat(sprintf("\nTotal time: %.1f min\n", elapsed_total))

# ==============================================================================
# Post-run integrity audit (r-reviewer 2026-05-18 focus area 4)
#
# Covers the silent-gap failure mode where a prior run wrote per-window
# posteriors successfully but died before / during the year-summary save.
# On retry, the diff would find 0 missing DOYs (window files all there)
# and skip the year, leaving the summary inconsistent with disk. This audit
# runs on every invocation — cheap (~5-15 min for 3 years of summary reads)
# vs the cost of an inconsistency going unnoticed downstream.
# ==============================================================================

cat("\n--- Integrity audit ---\n")
cat("Checking summary keys vs window file inventory for target years...\n")
any_inconsistent <- FALSE
for (yr in config$target_years) {
  yr_str <- as.character(yr)
  output_file <- file.path(config$output_dir, sprintf("derivatives_%d.rds", yr))
  present_dir <- file.path(config$posteriors_dir, yr_str)
  if (!file.exists(output_file) || !dir.exists(present_dir)) {
    cat(sprintf("  %s: SKIPPED (missing summary or posteriors dir)\n", yr_str))
    next
  }

  # Window file DOYs that meet the size floor.
  pf <- list.files(present_dir,
                   pattern = "^doy_\\d{3}_window_\\d{2}\\.rds$",
                   full.names = TRUE)
  info <- file.info(pf)
  pf_valid <- pf[!is.na(info$size) & info$size >= PER_WINDOW_MIN_BYTES]
  pf_doys <- sort(unique(as.integer(
    sub("doy_(\\d{3})_window_\\d{2}\\.rds", "\\1", basename(pf_valid))
  )))

  # Summary DOYs.
  summ <- readRDS_retry(output_file)
  summ_doys <- sort(unique(summ$yday))
  rm(summ); gc(verbose = FALSE)

  in_files_not_summary <- setdiff(pf_doys, summ_doys)
  in_summary_not_files <- setdiff(summ_doys, pf_doys)

  if (length(in_files_not_summary) == 0 && length(in_summary_not_files) == 0) {
    cat(sprintf("  %s: OK (%d DOYs match in summary + posteriors)\n",
                yr_str, length(pf_doys)))
  } else {
    any_inconsistent <- TRUE
    cat(sprintf("  %s: INCONSISTENT\n", yr_str))
    if (length(in_files_not_summary) > 0) {
      cat(sprintf("    %d DOY(s) have window files but NO summary row (re-run 06b to merge): %s\n",
                  length(in_files_not_summary),
                  paste(head(in_files_not_summary, 20), collapse = ", ")))
    }
    if (length(in_summary_not_files) > 0) {
      cat(sprintf("    %d DOY(s) in summary but NO window file (investigate): %s\n",
                  length(in_summary_not_files),
                  paste(head(in_summary_not_files, 20), collapse = ", ")))
    }
  }
}

if (any_inconsistent) {
  cat("\nIntegrity audit FAILED for at least one year. See messages above.\n")
  quit(save = "no", status = 1)
} else {
  cat("\nIntegrity audit PASSED.\n")
}

cat("\nNext: re-audit by running 04 (if downstream anomalies need refresh) or\n")
cat("inspect derivatives_YYYY.rds for the previously missing DOYs.\n")
