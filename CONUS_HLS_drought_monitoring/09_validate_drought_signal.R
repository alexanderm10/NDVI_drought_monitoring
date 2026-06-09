# ==============================================================================
# 09_validate_drought_signal.R
#
# Phase 6: validate the NDVI-derived drought signal (anomalies + derivatives)
# against independent references (USDM categorical, SPEI/SPI continuous), at
# pixel-week and ecoregion-week grains.
#
# Five sections, each runnable independently via CLI; later sections read from
# earlier sections' on-disk cache so reruns are cheap.
#
#   align_weekly       — collapse per-DOY NDVI anomalies + derivatives to ISO-week
#                        summaries, join to USDM + SPEI. ONE big cache that the
#                        analysis sections read. ~6-8 GB est.
#   categorical_usdm   — confusion matrices: binned NDVI z-anom vs USDM D0-D4.
#                        Per ecoregion + Midwest aggregate. (STUB)
#   continuous_spei    — pooled FE panel (fixest) for headline β + per-pixel
#                        slope map (data.table by-pixel). Includes additive +
#                        interaction terms for derivative significance. (STUB)
#   event_detection    — drought event = USDM ≥ D1 weeks; classify NDVI hit/
#                        miss/false-alarm across z-score sweep + Bayesian
#                        is_significant operating point. (STUB)
#   qc                 — alignment + completeness audit across all outputs.
#                        (STUB)
#
# Usage (in container):
#   docker exec -w /workspace conus-hls-drought-monitor \
#     Rscript 09_validate_drought_signal.R --section=align_weekly [--scope=10y|13y]
#
# Outputs land in /data/validation/.
#
# Scope flag (single codepath, filter at align_weekly):
#   --scope=10y  → 2016-2025 (full S30+L30 era; default)
#   --scope=13y  → 2013-2025 (includes 2013 launch-lag + 2014/2015 winter gaps;
#                  supplementary)
#
# Design notes:
# - Per-year sequential processing inside align_weekly. data.table by-group is
#   C-level multithreaded; parent peak ~30 GB worst-case (derivatives 11 GB load
#   + R+packages + summary aggregation), fits in 128 GB container.
# - All worker functions are file-scope (NOT closures over the parent frame) to
#   avoid the spei_weekly closure-capture footgun (2026-06-04 finding — see
#   RUNNING_ANALYSES.md "Performance footgun" section).
# - yday→ISO-week is computed via base R as.Date(); rows whose yday lands in
#   the adjacent iso_year (typical for late-Dec / early-Jan) are kept and
#   summarized into their correct (iso_year, iso_week) when years are stacked.
#
# USDM as a lagging indicator (treat throughout the analysis sections):
#   USDM is consensus-authored from multiple inputs (SPEI, PDSI, streamflow,
#   soil moisture, expert reports, sometimes NDVI itself). Drought-class
#   transitions trail actual surface conditions — analysts wait for
#   confirming evidence on the way up and sustained recovery on the way down.
#
#   Implication: a synchronous NDVI(t) vs USDM(t) confusion matrix will
#   UNDERSTATE NDVI's skill. The right framing is leading-indicator:
#     - score an NDVI-anom hit at week t as correct if USDM ≥ D1 anywhere
#       in [t, t+K] (K = 1..8 weeks, swept)
#     - report lead-time skill curves, not just point estimates
#     - keep SPEI as a "less-lagging" reference: SPEI is meteorological so
#       it leads USDM by less than NDVI typically does — confirms whether
#       our NDVI signal earns its keep beyond what SPEI already provides.
#
#   align_weekly does NOT pre-compute lagged USDM columns (would bloat the
#   ~6-8 GB join needlessly). Downstream sections self-join on (pixel_id,
#   iso_year, iso_week + K) to build the lag panel they need.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
})

source("00_setup_paths.R")
source("00_posterior_functions.R")  # saveRDS_validated, readRDS_retry
paths <- setup_hls_paths()

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------

# Hard invariant from script 02's land cover filter (memory: pixel_count_invariant).
# If this ever drifts from nrow(valid_pixels_landcover_filtered.rds), 03/04/06
# will hard-stop; this script will too.
EXPECTED_VALID_PIXELS <- 129310L

# Derivative windows produced by script 06.
DERIV_WINDOWS <- c(3L, 7L, 14L, 30L)

config <- list(
  validation_dir       = paths$validation_data,
  gam_models_dir       = paths$gam_models,
  anomalies_dir        = file.path(paths$gam_models, "modeled_ndvi_anomalies"),
  derivatives_dir      = file.path(paths$gam_models, "change_derivatives"),
  ecoregion_lookup     = file.path(paths$validation_data, "pixel_to_ecoregion_l2.rds"),
  usdm_file            = file.path(paths$validation_data, "usdm_4km_weekly_2013_2025.rds"),
  spei_weekly_file     = file.path(paths$validation_data, "spei_4km_weekly_2013_2025.rds"),
  # Scope-dependent output (set after CLI parse)
  align_out_10y        = file.path(paths$validation_data, "ndvi_drought_join_weekly_10y.rds"),
  align_out_13y        = file.path(paths$validation_data, "ndvi_drought_join_weekly_13y.rds"),
  usdm_confusion_10y   = file.path(paths$validation_data, "usdm_confusion_10y.rds"),
  usdm_confusion_13y   = file.path(paths$validation_data, "usdm_confusion_13y.rds")
)

# ------------------------------------------------------------------------------
# Helpers (file-scope — avoid closure capture of large objects)
# ------------------------------------------------------------------------------

#' Build a yday→(iso_year, iso_week, week_start) lookup for a given calendar year.
#' Returns a data.table keyed on `yday`.
yday_iso_lookup <- function(year) {
  dates <- as.Date(seq_len(if (lubridate::leap_year(year)) 366L else 365L) - 1L,
                   origin = sprintf("%d-01-01", year))
  data.table(
    yday       = seq_along(dates),
    cal_year   = year,
    iso_year   = lubridate::isoyear(dates),
    iso_week   = lubridate::isoweek(dates),
    week_start = dates - (lubridate::wday(dates, week_start = 1L) - 1L)
  )
}

#' Collapse a per-pixel-per-DOY anomaly table to a per-pixel-per-ISO-week table.
#' Aggregations: mean/min/max of anoms_mean; count of DOYs total + significant.
#' Returns data.table with columns:
#'   pixel_id, iso_year, iso_week, week_start, cal_year,
#'   ndvi_anom_mean, ndvi_anom_min, ndvi_anom_max,
#'   ndvi_n_doys, ndvi_n_sig
collapse_anomalies_to_week <- function(anom_dt, iso_lookup) {
  anom_dt <- merge(anom_dt, iso_lookup, by = "yday", all.x = TRUE)
  anom_dt[, .(
    ndvi_anom_mean = mean(anoms_mean,  na.rm = TRUE),
    ndvi_anom_min  = min(anoms_mean,   na.rm = TRUE),
    ndvi_anom_max  = max(anoms_mean,   na.rm = TRUE),
    ndvi_n_doys    = sum(!is.na(anoms_mean)),
    ndvi_n_sig     = sum(significant,  na.rm = TRUE)
  ), by = .(pixel_id, iso_year, iso_week, week_start, cal_year)]
}

#' Collapse a per-pixel-per-DOY-per-window derivative table to a
#' per-pixel-per-window-per-ISO-week table.
#'
#' Per-window summaries (one set of cols per W ∈ DERIV_WINDOWS):
#'   deriv_W_anom_mean — mean of anomaly_change_mean
#'   deriv_W_anom_min  — most-negative anomaly (browning-faster-than-baseline)
#'   deriv_W_n_doys    — total DOYs with data this week-window
#'   deriv_W_n_sig     — count of DOYs significant (95% CI excludes 0)
#'
#' Returned in wide form (one row per pixel-week, all windows as cols) so
#' downstream sections can grab the window they want without re-pivoting.
collapse_derivatives_to_week <- function(deriv_dt, iso_lookup) {
  deriv_dt <- merge(deriv_dt, iso_lookup, by = "yday", all.x = TRUE)

  long <- deriv_dt[, .(
    anom_mean = mean(anomaly_change_mean, na.rm = TRUE),
    anom_min  = min(anomaly_change_mean,  na.rm = TRUE),
    n_doys    = sum(!is.na(anomaly_change_mean)),
    n_sig     = sum(significant,          na.rm = TRUE)
  ), by = .(pixel_id, iso_year, iso_week, week_start, cal_year, window)]

  wide <- dcast(
    long,
    pixel_id + iso_year + iso_week + week_start + cal_year ~ window,
    value.var = c("anom_mean", "anom_min", "n_doys", "n_sig"),
    sep = "_w"
  )
  # dcast naming: anom_mean_w3, anom_mean_w7, ...; rename to deriv_W_anom_*
  setnames(
    wide,
    old = grep("^(anom_mean|anom_min|n_doys|n_sig)_w(3|7|14|30)$",
               names(wide), value = TRUE),
    new = sub("^(anom_mean|anom_min|n_doys|n_sig)_w(\\d+)$",
              "deriv_\\2_\\1", grep("^(anom_mean|anom_min|n_doys|n_sig)_w(3|7|14|30)$",
                                    names(wide), value = TRUE))
  )
  # Rename to the canonical deriv_W_anom_{mean,min}/n_{doys,sig} pattern.
  for (w in DERIV_WINDOWS) {
    setnames(wide,
             old = c(sprintf("deriv_%d_anom_mean", w),
                     sprintf("deriv_%d_anom_min",  w),
                     sprintf("deriv_%d_n_doys",    w),
                     sprintf("deriv_%d_n_sig",     w)),
             new = c(sprintf("deriv_w%02d_anom_mean", w),
                     sprintf("deriv_w%02d_anom_min",  w),
                     sprintf("deriv_w%02d_n_doys",    w),
                     sprintf("deriv_w%02d_n_sig",     w)))
  }
  wide
}

#' Process a single calendar year: load anomalies + derivatives, collapse to
#' weekly, merge. Returns a single per-pixel-per-ISO-week data.table for the
#' year (which may include iso_year = Y-1 or Y+1 rows for edge weeks).
process_year_to_weekly <- function(year) {
  t0 <- Sys.time()
  cat(sprintf("\n[year %d]\n", year))

  iso_lookup <- yday_iso_lookup(year)

  # --- anomalies ---
  anom_file <- file.path(config$anomalies_dir, sprintf("anomalies_%d.rds", year))
  if (!file.exists(anom_file)) {
    cat(sprintf("  WARN: missing %s — skipping year\n", basename(anom_file)))
    return(NULL)
  }
  cat(sprintf("  load anomalies (%s MB)... ",
              format(round(file.size(anom_file) / 1e6), big.mark = ",")))
  anom <- as.data.table(readRDS_retry(anom_file))
  cat(sprintf("%d rows\n", nrow(anom)))
  # Keep only cols we need (memory hygiene)
  anom <- anom[, .(pixel_id, yday, anoms_mean, significant)]

  cat("  collapse anomalies → weekly... ")
  ndvi_wk <- collapse_anomalies_to_week(anom, iso_lookup)
  rm(anom); gc(verbose = FALSE)
  cat(sprintf("%d pixel-weeks\n", nrow(ndvi_wk)))

  # --- derivatives ---
  deriv_file <- file.path(config$derivatives_dir, sprintf("derivatives_%d.rds", year))
  if (!file.exists(deriv_file)) {
    cat(sprintf("  WARN: missing %s — skipping derivative side\n", basename(deriv_file)))
    deriv_wk <- NULL
  } else {
    cat(sprintf("  load derivatives (%s MB)... ",
                format(round(file.size(deriv_file) / 1e6), big.mark = ",")))
    deriv <- as.data.table(readRDS_retry(deriv_file))
    cat(sprintf("%d rows\n", nrow(deriv)))
    deriv <- deriv[, .(pixel_id, yday, window, anomaly_change_mean, significant)]

    cat("  collapse derivatives → weekly (wide on window)... ")
    deriv_wk <- collapse_derivatives_to_week(deriv, iso_lookup)
    rm(deriv); gc(verbose = FALSE)
    cat(sprintf("%d pixel-weeks\n", nrow(deriv_wk)))
  }

  # --- merge ---
  if (!is.null(deriv_wk)) {
    out <- merge(ndvi_wk, deriv_wk,
                 by = c("pixel_id", "iso_year", "iso_week",
                        "week_start", "cal_year"),
                 all = TRUE)
    rm(ndvi_wk, deriv_wk); gc(verbose = FALSE)
  } else {
    out <- ndvi_wk
  }

  cat(sprintf("  [year %d] done in %.1f min — %s rows\n",
              year,
              as.numeric(Sys.time() - t0, units = "mins"),
              format(nrow(out), big.mark = ",")))
  out
}

# ==============================================================================
# SECTION: align_weekly
#
# Build the master pixel-week join table: NDVI anomaly summaries +
# per-window derivative summaries + USDM categorical + SPEI/SPI continuous +
# ecoregion attributes. Cached so the analysis sections can read it cheaply.
# ==============================================================================
section_align_weekly <- function(scope) {
  cat("\n=== Section: align_weekly (scope =", scope, ") ===\n")
  stopifnot(scope %in% c("10y", "13y"))

  scope_years <- if (scope == "10y") 2016:2025 else 2013:2025
  out_file <- if (scope == "10y") config$align_out_10y else config$align_out_13y

  cat(sprintf("Scope: %s (years %d-%d)\n",
              scope, min(scope_years), max(scope_years)))
  cat(sprintf("Output: %s\n", out_file))

  t_section <- Sys.time()

  # --- 1. Per-year collapse, accumulate ---
  year_list <- vector("list", length(scope_years))
  names(year_list) <- as.character(scope_years)
  for (yr in scope_years) {
    year_list[[as.character(yr)]] <- process_year_to_weekly(yr)
  }
  year_list <- Filter(Negate(is.null), year_list)
  if (length(year_list) == 0L) stop("align_weekly: no per-year outputs were produced.")

  cat(sprintf("\nrbindlist %d years...\n", length(year_list)))
  ndvi_long <- rbindlist(year_list, use.names = TRUE, fill = TRUE)
  rm(year_list); gc(verbose = FALSE)
  cat(sprintf("  combined rows (pre-week-collapse): %s\n",
              format(nrow(ndvi_long), big.mark = ",")))

  # Some weeks at year boundaries appear in both year Y and year Y+1's per-year
  # processing (yday 365 of Y and yday 1 of Y+1 can land in the same ISO week).
  # Collapse duplicates by re-aggregating on the join keys. Most weeks have a
  # single row per (pixel, iso_year, iso_week); only the boundary weeks merge.
  cat("Re-collapse cross-year-boundary duplicates... ")
  ndvi_wk <- ndvi_long[, .(
    week_start = min(week_start),
    cal_year   = min(cal_year),  # earliest contributing calendar year
    # NDVI
    ndvi_anom_mean = weighted.mean(ndvi_anom_mean, ndvi_n_doys, na.rm = TRUE),
    ndvi_anom_min  = min(ndvi_anom_min, na.rm = TRUE),
    ndvi_anom_max  = max(ndvi_anom_max, na.rm = TRUE),
    ndvi_n_doys    = sum(ndvi_n_doys, na.rm = TRUE),
    ndvi_n_sig     = sum(ndvi_n_sig,  na.rm = TRUE),
    # Derivatives: collapse each window's stats
    deriv_w03_anom_mean = weighted.mean(deriv_w03_anom_mean, deriv_w03_n_doys, na.rm = TRUE),
    deriv_w03_anom_min  = min(deriv_w03_anom_min,  na.rm = TRUE),
    deriv_w03_n_doys    = sum(deriv_w03_n_doys,    na.rm = TRUE),
    deriv_w03_n_sig     = sum(deriv_w03_n_sig,     na.rm = TRUE),
    deriv_w07_anom_mean = weighted.mean(deriv_w07_anom_mean, deriv_w07_n_doys, na.rm = TRUE),
    deriv_w07_anom_min  = min(deriv_w07_anom_min,  na.rm = TRUE),
    deriv_w07_n_doys    = sum(deriv_w07_n_doys,    na.rm = TRUE),
    deriv_w07_n_sig     = sum(deriv_w07_n_sig,     na.rm = TRUE),
    deriv_w14_anom_mean = weighted.mean(deriv_w14_anom_mean, deriv_w14_n_doys, na.rm = TRUE),
    deriv_w14_anom_min  = min(deriv_w14_anom_min,  na.rm = TRUE),
    deriv_w14_n_doys    = sum(deriv_w14_n_doys,    na.rm = TRUE),
    deriv_w14_n_sig     = sum(deriv_w14_n_sig,     na.rm = TRUE),
    deriv_w30_anom_mean = weighted.mean(deriv_w30_anom_mean, deriv_w30_n_doys, na.rm = TRUE),
    deriv_w30_anom_min  = min(deriv_w30_anom_min,  na.rm = TRUE),
    deriv_w30_n_doys    = sum(deriv_w30_n_doys,    na.rm = TRUE),
    deriv_w30_n_sig     = sum(deriv_w30_n_sig,     na.rm = TRUE)
  ), by = .(pixel_id, iso_year, iso_week)]
  rm(ndvi_long); gc(verbose = FALSE)
  cat(sprintf("%s rows\n", format(nrow(ndvi_wk), big.mark = ",")))

  # --- 2. Join USDM (filter to scope years first) ---
  cat("Load + join USDM... ")
  usdm <- as.data.table(readRDS_retry(config$usdm_file))
  # USDM uses week_date (Tuesday); convert to iso_year/iso_week
  usdm[, `:=`(iso_year = isoyear(week_date), iso_week = isoweek(week_date))]
  usdm <- usdm[iso_year %in% scope_years,
               .(pixel_id, iso_year, iso_week, usdm = dm_max)]
  cat(sprintf("%s rows\n", format(nrow(usdm), big.mark = ",")))

  ndvi_wk <- merge(ndvi_wk, usdm,
                   by = c("pixel_id", "iso_year", "iso_week"),
                   all.x = TRUE)
  rm(usdm); gc(verbose = FALSE)

  # --- 3. Join SPEI weekly (already iso_year/iso_week keyed) ---
  cat("Load + join SPEI weekly... ")
  spei <- as.data.table(readRDS_retry(config$spei_weekly_file))
  spei <- spei[iso_year %in% scope_years,
               .(pixel_id, iso_year, iso_week,
                 spi_4w, spi_13w, spi_26w,
                 spei_4w, spei_13w, spei_26w)]
  cat(sprintf("%s rows\n", format(nrow(spei), big.mark = ",")))

  ndvi_wk <- merge(ndvi_wk, spei,
                   by = c("pixel_id", "iso_year", "iso_week"),
                   all.x = TRUE)
  rm(spei); gc(verbose = FALSE)

  # --- 4. Join ecoregion lookup ---
  cat("Join ecoregion lookup... ")
  eco <- as.data.table(readRDS_retry(config$ecoregion_lookup))
  eco <- eco[, .(pixel_id, L2_code, L2_name)]
  cat(sprintf("%s rows\n", format(nrow(eco), big.mark = ",")))

  ndvi_wk <- merge(ndvi_wk, eco, by = "pixel_id", all.x = TRUE)
  rm(eco); gc(verbose = FALSE)

  # --- 5. Sanity ---
  setorder(ndvi_wk, pixel_id, iso_year, iso_week)
  n_px <- uniqueN(ndvi_wk$pixel_id)
  n_wk <- uniqueN(ndvi_wk[, .(iso_year, iso_week)])

  cat(sprintf("\nFinal join: %s rows (pixels=%s, iso-weeks=%d)\n",
              format(nrow(ndvi_wk), big.mark = ","),
              format(n_px, big.mark = ","),
              n_wk))
  cat(sprintf("  Pixel coverage:    %d / %d expected (drift = %d)\n",
              n_px, EXPECTED_VALID_PIXELS, n_px - EXPECTED_VALID_PIXELS))
  cat(sprintf("  USDM match rate:   %.2f%% non-NA\n",
              100 * mean(!is.na(ndvi_wk$usdm))))
  cat(sprintf("  SPEI-4w match:     %.2f%% non-NA\n",
              100 * mean(!is.na(ndvi_wk$spei_4w))))
  cat(sprintf("  Ecoregion match:   %.2f%% non-NA\n",
              100 * mean(!is.na(ndvi_wk$L2_code))))

  if (n_px != EXPECTED_VALID_PIXELS) {
    cat(sprintf(
      "WARN: pixel count drift (%d vs expected %d). See feedback_pixel_count_invariant.\n",
      n_px, EXPECTED_VALID_PIXELS))
  }

  # --- 6. Save ---
  cat(sprintf("\nSaving %s...\n", basename(out_file)))
  saveRDS_validated(as.data.frame(ndvi_wk), out_file, compress = "gzip")
  cat(sprintf("  wrote %.1f MB in %.1f min total\n",
              file.size(out_file) / 1e6,
              as.numeric(Sys.time() - t_section, units = "mins")))

  invisible(NULL)
}

# ==============================================================================
# SECTION stubs — to be implemented after align_weekly is verified
# ==============================================================================

# ==============================================================================
# SECTION: categorical_usdm (v2 — bidirectional, magnitude + 4 derivatives)
#
# v1 (initial, 2026-06-09 14:58 run) asked the wrong question: "when USDM is
# high, does NDVI z exceed a negative threshold?" Resulting HSS≈0 and a wrong-
# direction lead-K trend confirmed the framing was off.
#
# v2 (this code) asks the right question: "when USDM is CHANGING, does NDVI
# move in the corresponding direction?" Drought worsens AND drought eases —
# both directions matter and both are scored.
#
# Five NDVI signals (all per-pixel z-standardized over the loaded record):
#   ndvi_z              — magnitude (anomaly z)
#   deriv_w03_z         — 3-day window rate-of-change (z)
#   deriv_w07_z         — 7-day window rate-of-change (z)
#   deriv_w14_z         — 14-day window rate-of-change (z)
#   deriv_w30_z         — 30-day window rate-of-change (z)
#
# USDM target = SIGNED CHANGE over [t, t+K]:
#   usdm_change_K = usdm_lead_K - usdm[t]
# (positive = drought intensifying, negative = drought receding)
#
# Two confusion-matrix directions per (stratum × K × signal):
#   INTENSIFICATION: pred = signal ≤ -threshold paired with usdm_change ≥ +T
#   RECOVERY:        pred = signal ≥ +threshold paired with usdm_change ≤ -T
#
# Side cache:
#   Spearman ρ between (-signal) and usdm_change per (stratum × K × signal).
#   Negated so positive ρ = "good skill" (NDVI moves opposite to USDM, as
#   expected since drought worsening = USDM up + NDVI down).
#
# bayes_sig comparator: DROPPED in v2. The cached `ndvi_n_sig` is direction-
# agnostic (counts both browning AND greening significance), so it can't honor
# the bidirectional framing without an align_weekly extension that splits into
# ndvi_n_sig_neg / ndvi_n_sig_pos. Re-add if/when that extension lands.
#
# Reads:  ndvi_drought_join_weekly_<scope>.rds (built by section_align_weekly)
# Writes: usdm_confusion_<scope>.rds (overwrites v1 output)
# ==============================================================================
compute_skill <- function(tp, fp, fn, tn) {
  # 2x2 contingency → POD / FAR / CSI / HSS (Heidke). Returns named 4-vector.
  # Cast to double: callers pass integer sums (from sum(logical)), and HSS's
  # denominator (tp+fn)*(fn+tn) overflows R's 32-bit int when subset sizes
  # exceed ~46K (sqrt of .Machine$integer.max); ecoregion subsets here are
  # tens of millions of rows.
  tp <- as.numeric(tp); fp <- as.numeric(fp)
  fn <- as.numeric(fn); tn <- as.numeric(tn)
  p   <- tp + fn
  pp  <- tp + fp
  pod <- if (p > 0)  tp / p   else NA_real_
  far <- if (pp > 0) fp / pp  else NA_real_
  csi <- if ((tp + fp + fn) > 0) tp / (tp + fp + fn) else NA_real_
  denom <- (tp + fn) * (fn + tn) + (tp + fp) * (fp + tn)
  hss <- if (denom > 0) 2 * (tp * tn - fp * fn) / denom else NA_real_
  c(pod = pod, far = far, csi = csi, hss = hss)
}

section_categorical_usdm <- function(scope) {
  cat("\n=== Section: categorical_usdm v2 (scope =", scope, ") ===\n")
  stopifnot(scope %in% c("10y", "13y"))

  in_file  <- if (scope == "10y") config$align_out_10y      else config$align_out_13y
  out_file <- if (scope == "10y") config$usdm_confusion_10y else config$usdm_confusion_13y

  if (!file.exists(in_file)) {
    stop("Cache file missing: ", in_file,
         "\n  Run --section=align_weekly --scope=", scope, " first.")
  }
  cat(sprintf("Input:  %s (%.1f GB)\n", basename(in_file), file.size(in_file) / 1e9))
  cat(sprintf("Output: %s\n", basename(out_file)))

  t_section <- Sys.time()

  Z_THRESHOLDS_NEG           <- c(-0.5, -1.0, -1.5, -2.0, -2.5)
  Z_THRESHOLDS_POS           <- c( 0.5,  1.0,  1.5,  2.0,  2.5)
  USDM_CHANGE_THRESHOLDS_POS <- 1:3            # intensification
  USDM_CHANGE_THRESHOLDS_NEG <- -(1:3)         # recovery
  K_VALUES                   <- c(1L, 2L, 4L, 8L)   # K=0 dropped (change is always 0)
  MAX_K                      <- max(K_VALUES)
  MIN_VALID_WEEKS            <- 30L
  Z_BREAKS                   <- c(-Inf, -2.5, -2.0, -1.5, -1.0, -0.5,
                                  0, 0.5, 1.0, 1.5, 2.0, 2.5, Inf)

  ANOM_COLS    <- c("ndvi_anom_mean",
                    "deriv_w03_anom_mean", "deriv_w07_anom_mean",
                    "deriv_w14_anom_mean", "deriv_w30_anom_mean")
  SIGNAL_NAMES <- c("ndvi_z",
                    "deriv_w03_z", "deriv_w07_z", "deriv_w14_z", "deriv_w30_z")

  # --- 1. Load cache, keep only required columns ---
  cat("\n[1] Load cache...\n")
  dt <- as.data.table(readRDS_retry(in_file))
  cat(sprintf("  raw: %s rows × %d cols\n", format(nrow(dt), big.mark = ","), ncol(dt)))
  keep_cols <- c("pixel_id", "iso_year", "iso_week", "week_start",
                 ANOM_COLS, "usdm", "L2_code", "L2_name")
  dt <- dt[, ..keep_cols]
  gc(verbose = FALSE)

  n_px_in <- uniqueN(dt$pixel_id)
  cat(sprintf("  pixel count: %d (expected %d)\n", n_px_in, EXPECTED_VALID_PIXELS))
  if (n_px_in != EXPECTED_VALID_PIXELS) {
    cat(sprintf("  WARN: pixel drift %d (see feedback_pixel_count_invariant)\n",
                n_px_in - EXPECTED_VALID_PIXELS))
  }

  # --- 2. Per-pixel z-standardize all 5 NDVI signals ---
  cat("\n[2] Per-pixel z-standardize 5 NDVI signals...\n")
  setorder(dt, pixel_id, week_start)

  drop_px <- integer(0)
  for (i in seq_along(ANOM_COLS)) {
    col_anom <- ANOM_COLS[i]
    col_z    <- SIGNAL_NAMES[i]
    cat(sprintf("  [%s → %s] ", col_anom, col_z))

    stats <- dt[!is.na(get(col_anom)), .(
      mu_pix  = mean(get(col_anom)),
      sd_pix  = sd(get(col_anom)),
      n_valid = .N
    ), by = pixel_id]

    drop_this <- stats[n_valid < MIN_VALID_WEEKS | sd_pix == 0 | is.na(sd_pix),
                       pixel_id]
    drop_px <- union(drop_px, drop_this)
    cat(sprintf("dropping %d pixels (signal-specific σ=0 or n<%d)\n",
                length(drop_this), MIN_VALID_WEEKS))

    dt[stats, `:=`(mu_pix = i.mu_pix, sd_pix = i.sd_pix), on = "pixel_id"]
    dt[, (col_z) := (get(col_anom) - mu_pix) / sd_pix]
    dt[, c("mu_pix", "sd_pix") := NULL]
  }
  cat(sprintf("  total unique drop list: %d pixels (across all 5 signals)\n",
              length(drop_px)))
  if (length(drop_px) > 0L) dt <- dt[!pixel_id %in% drop_px]
  # Drop raw anomaly cols — keep only z variants
  dt[, (ANOM_COLS) := NULL]
  gc(verbose = FALSE)

  # --- 3. Build lead-K USDM + signed USDM_change columns ---
  cat(sprintf("\n[3] Build lead-K USDM + USDM_change (K = %s)...\n",
              paste(K_VALUES, collapse = ",")))

  usdm_panel <- dt[, .(pixel_id, week_start, usdm)]
  setkey(usdm_panel, pixel_id, week_start)

  # Running max iterates K = 0..MAX_K. Snapshot to usdm_lead_K + usdm_change_K
  # for K ∈ K_VALUES. na.rm = FALSE: any missing week in the window drops that
  # (pixel, t, K) from downstream stats. USDM coverage ~99.6%, loss is small.
  dt[, running_max := usdm]
  for (K in 0:MAX_K) {
    if (K > 0L) {
      tmp <- usdm_panel[, .(pixel_id,
                            ws_match = week_start - 7L * K,
                            usdm_at_K = usdm)]
      dt[tmp, usdm_at_K := i.usdm_at_K,
         on = c("pixel_id", "week_start==ws_match")]
      dt[, running_max := pmax(running_max, usdm_at_K, na.rm = FALSE)]
      dt[, usdm_at_K := NULL]
      rm(tmp)
    }
    if (K %in% K_VALUES) {
      dt[, sprintf("usdm_lead_%d",   K) := running_max]
      dt[, sprintf("usdm_change_%d", K) := running_max - usdm]
      change_col <- sprintf("usdm_change_%d", K)
      cat(sprintf("  K=%d: lead %.2f%% non-NA | change range [%+d, %+d]\n",
                  K,
                  100 * mean(!is.na(dt[[sprintf("usdm_lead_%d", K)]])),
                  min(dt[[change_col]], na.rm = TRUE),
                  max(dt[[change_col]], na.rm = TRUE)))
    }
  }
  dt[, running_max := NULL]
  rm(usdm_panel); gc(verbose = FALSE)

  # --- 4. Skill sweep + Spearman correlation, loop over (stratum × K × signal) ---
  cat("\n[4] Skill + correlation sweep over (stratum × K × signal)...\n")

  # Inner helper: confusion-cell sweep for one (sub, signal_col, change_col,
  # direction). Builds z × usdm_change_threshold grid of contingency tables +
  # POD/FAR/CSI/HSS rows.
  sweep_one_direction <- function(sub, signal_col, change_col,
                                  z_thresholds, change_thresholds,
                                  z_op, change_op, direction_label) {
    sig_vec <- sub[[signal_col]]
    chg_vec <- sub[[change_col]]
    rbindlist(lapply(change_thresholds, function(uct) {
      obs_yes <- if (change_op == ">=") chg_vec >= uct else chg_vec <= uct
      rbindlist(lapply(z_thresholds, function(zt) {
        pred_yes <- if (z_op == "<=") sig_vec <= zt else sig_vec >= zt
        tp <- sum(pred_yes &  obs_yes)
        fp <- sum(pred_yes & !obs_yes)
        fn <- sum(!pred_yes &  obs_yes)
        tn <- sum(!pred_yes & !obs_yes)
        sk <- compute_skill(tp, fp, fn, tn)
        data.table(
          direction             = direction_label,
          z_threshold           = zt,
          usdm_change_threshold = uct,
          n_pixel_weeks         = nrow(sub),
          tp = tp, fp = fp, fn = fn, tn = tn,
          pod = sk[["pod"]], far = sk[["far"]],
          csi = sk[["csi"]], hss = sk[["hss"]]
        )
      }))
    }))
  }

  eco_codes <- sort(unique(dt$L2_code[!is.na(dt$L2_code)]))
  cat(sprintf("  %d ecoregions found\n", length(eco_codes)))

  skill_rows  <- list()
  corr_rows   <- list()
  total_iter  <- (length(eco_codes) + 1L) * length(K_VALUES) * length(SIGNAL_NAMES)
  iter        <- 0L
  t_sweep     <- Sys.time()

  strata_list <- c(as.list(eco_codes), list(NA_integer_))   # NA = Midwest aggregate
  for (stratum in strata_list) {
    is_mw    <- is.na(stratum)
    sub_full <- if (is_mw) dt else dt[L2_code == stratum]
    if (nrow(sub_full) == 0L) next
    stratum_type <- if (is_mw) "midwest_aggregate" else "ecoregion"
    L2_label     <- if (is_mw) NA_integer_         else as.integer(stratum)

    for (K in K_VALUES) {
      change_col <- sprintf("usdm_change_%d", K)
      for (sig in SIGNAL_NAMES) {
        iter <- iter + 1L
        sub <- sub_full[!is.na(get(sig)) & !is.na(get(change_col))]
        if (nrow(sub) == 0L) next

        intens <- sweep_one_direction(sub, sig, change_col,
                                      Z_THRESHOLDS_NEG, USDM_CHANGE_THRESHOLDS_POS,
                                      "<=", ">=", "intensification")
        recov  <- sweep_one_direction(sub, sig, change_col,
                                      Z_THRESHOLDS_POS, USDM_CHANGE_THRESHOLDS_NEG,
                                      ">=", "<=", "recovery")
        block <- rbind(intens, recov)
        block[, `:=`(stratum_type = stratum_type, L2_code = L2_label,
                     K = K, ndvi_signal = sig)]
        skill_rows[[length(skill_rows) + 1L]] <- block

        # Spearman ρ between -signal and usdm_change. Negated so positive ρ =
        # "good" (NDVI drops when USDM rises). Uses the full sub (no extra NAs).
        rho <- suppressWarnings(
          cor(-sub[[sig]], sub[[change_col]], method = "spearman")
        )
        corr_rows[[length(corr_rows) + 1L]] <- data.table(
          stratum_type = stratum_type, L2_code = L2_label,
          K = K, ndvi_signal = sig,
          n_pixel_weeks = nrow(sub),
          spearman_rho_neg_signal = rho
        )

        if (iter %% 25L == 0L) {
          el  <- as.numeric(Sys.time() - t_sweep, units = "mins")
          eta <- el * (total_iter - iter) / iter
          cat(sprintf("    iter %d/%d (%.1f min elapsed, ETA %.1f min)\n",
                      iter, total_iter, el, eta))
        }
      }
    }
  }

  skill <- rbindlist(skill_rows)
  setcolorder(skill, c("stratum_type", "L2_code", "K", "ndvi_signal",
                       "direction", "z_threshold", "usdm_change_threshold",
                       "n_pixel_weeks", "tp", "fp", "fn", "tn",
                       "pod", "far", "csi", "hss"))
  setorder(skill, stratum_type, L2_code, K, ndvi_signal, direction,
           z_threshold, usdm_change_threshold)
  correlation <- rbindlist(corr_rows)
  setorder(correlation, stratum_type, L2_code, K, ndvi_signal)
  cat(sprintf("  skill: %d rows | correlation: %d rows\n",
              nrow(skill), nrow(correlation)))

  # --- 5. Full contingency tables (signed z-bins × signed USDM_change) ---
  cat("\n[5] Full contingency tables (signed bins)...\n")
  cont_list <- list()
  for (sig in SIGNAL_NAMES) {
    for (K in K_VALUES) {
      change_col <- sprintf("usdm_change_%d", K)
      sub <- dt[!is.na(get(sig)) & !is.na(get(change_col)),
                .(L2_code,
                  sig_val    = get(sig),
                  change_val = as.integer(get(change_col)))]
      sub[, sig_bin := cut(sig_val, breaks = Z_BREAKS,
                            include.lowest = TRUE, right = TRUE)]

      eco_cont <- sub[!is.na(L2_code), .N,
                       by = .(L2_code, sig_bin, usdm_change = change_val)]
      eco_cont[, `:=`(stratum_type = "ecoregion", K = K, ndvi_signal = sig)]

      mw_cont <- sub[, .N,
                      by = .(sig_bin, usdm_change = change_val)]
      mw_cont[, `:=`(stratum_type = "midwest_aggregate", L2_code = NA_integer_,
                     K = K, ndvi_signal = sig)]

      cont_list[[length(cont_list) + 1L]] <-
        rbind(eco_cont, mw_cont, use.names = TRUE)
    }
  }
  contingency_full <- rbindlist(cont_list, use.names = TRUE)
  setcolorder(contingency_full,
              c("stratum_type", "L2_code", "K", "ndvi_signal",
                "sig_bin", "usdm_change", "N"))
  cat(sprintf("  %s rows\n", format(nrow(contingency_full), big.mark = ",")))

  # --- 6. Assemble + save ---
  result <- list(
    skill            = skill,
    correlation      = correlation,
    contingency_full = contingency_full,
    meta = list(
      scope                      = scope,
      version                    = "v2_bidirectional_magnitude_plus_4_derivatives",
      n_pixels_in                = n_px_in,
      n_pixels_dropped           = length(drop_px),
      n_pixels_kept              = n_px_in - length(drop_px),
      run_time_minutes           = as.numeric(Sys.time() - t_section, units = "mins"),
      z_thresholds_negative      = Z_THRESHOLDS_NEG,
      z_thresholds_positive      = Z_THRESHOLDS_POS,
      K_values                   = K_VALUES,
      usdm_change_thresholds_pos = USDM_CHANGE_THRESHOLDS_POS,
      usdm_change_thresholds_neg = USDM_CHANGE_THRESHOLDS_NEG,
      min_valid_weeks            = MIN_VALID_WEEKS,
      z_breaks                   = Z_BREAKS,
      ndvi_signals               = SIGNAL_NAMES,
      bayes_sig_dropped          = paste("ndvi_n_sig on disk is direction-agnostic;",
                                         "would need align_weekly extension to split",
                                         "into ndvi_n_sig_neg/pos to re-enable")
    )
  )

  cat(sprintf("\n[6] Saving %s...\n", basename(out_file)))
  saveRDS_validated(result, out_file, compress = "gzip")
  cat(sprintf("  wrote %.2f MB in %.1f min total\n",
              file.size(out_file) / 1e6,
              result$meta$run_time_minutes))

  # --- 7. Quick summary: Midwest aggregate, magnitude + w14 derivative ---
  cat("\n--- Quick summary (Midwest aggregate) ---\n")
  for (sig in c("ndvi_z", "deriv_w14_z")) {
    cat(sprintf("\n  %s:\n", sig))
    for (K in K_VALUES) {
      r_corr <- correlation[stratum_type == "midwest_aggregate" & K == ..K &
                              ndvi_signal == sig]
      r_int <- skill[stratum_type == "midwest_aggregate" & K == ..K &
                       ndvi_signal == sig & direction == "intensification" &
                       z_threshold == -1.5 & usdm_change_threshold == 1L]
      r_rec <- skill[stratum_type == "midwest_aggregate" & K == ..K &
                       ndvi_signal == sig & direction == "recovery" &
                       z_threshold == 1.5 & usdm_change_threshold == -1L]
      cat(sprintf(
        "    K=%d  ρ=%+.3f  INT(z≤-1.5,ΔU≥+1):HSS=%+.3f POD=%.3f  REC(z≥+1.5,ΔU≤-1):HSS=%+.3f POD=%.3f\n",
        K, r_corr$spearman_rho_neg_signal,
        r_int$hss, r_int$pod,
        r_rec$hss, r_rec$pod))
    }
  }

  invisible(NULL)
}

section_continuous_spei <- function(scope) {
  cat("\n=== Section: continuous_spei (scope =", scope, ") — STUB ===\n")
  cat("Not yet implemented. Two model families:\n")
  cat("  (a) fixest::feols per ecoregion: ndvi_anom ~ spei | year_week,\n")
  cat("      with additive deriv-sig term + (anom × deriv-sig) interaction.\n")
  cat("      SPEI is concurrent meteorology — match-window on timescale only\n")
  cat("      (no temporal lag; NDVI vs SPEI(t) and SPEI(t-K) for K=2,4,8 wk).\n")
  cat("  (b) data.table by pixel: per-pixel slope map of NDVI vs SPEI.\n")
  cat("Notes:\n")
  cat("  - USDM enters here only as a stratifier (within-event vs outside)\n")
  cat("    so the lagging-indicator concern is sidestepped at this stage.\n")
  cat("Reads: ndvi_drought_join_weekly_", scope, ".rds\n", sep = "")
  invisible(NULL)
}

section_event_detection <- function(scope) {
  cat("\n=== Section: event_detection (scope =", scope, ") — STUB ===\n")
  cat("Not yet implemented. USDM-anchored drought events (consecutive weeks\n")
  cat("where USDM ≥ D1; minimum-duration filter to drop single-week flickers).\n")
  cat("Treat USDM as a LAGGING reference — credit NDVI for early warning:\n")
  cat("  - 'event_start' = first week of qualifying run\n")
  cat("  - for each event, search backward up to K weeks for prior NDVI hits\n")
  cat("    (z ≤ θ or is_significant TRUE or derivative-w14 sig run ≥ M weeks)\n")
  cat("  - report lead-time distribution (median weeks NDVI leads event_start)\n")
  cat("  - rapid-onset / flash-drought subclass: events where USDM transitions\n")
  cat("    D0→D2+ within 4 weeks → expect derivative signal to outperform\n")
  cat("    static anomaly here (the user's flash-drought hypothesis)\n")
  cat("Outputs: per-event hit/miss/lead-time table; ROC-style POD vs FAR\n")
  cat("curves sweeping z and lead-tolerance window K. Per ecoregion + aggregate.\n")
  cat("Reads: ndvi_drought_join_weekly_", scope, ".rds\n", sep = "")
  invisible(NULL)
}

section_qc <- function(scope) {
  cat("\n=== Section: qc (scope =", scope, ") — STUB ===\n")
  cat("Not yet implemented. Will audit:\n")
  cat("  - pixel-set completeness vs valid_pixels_landcover_filtered.rds\n")
  cat("  - iso-week completeness vs USDM 678-week reference\n")
  cat("  - join-rate stability across analysis sections\n")
  invisible(NULL)
}

# ==============================================================================
# CLI dispatcher (mirrors 08's pattern; no --section= = source-only mode)
# ==============================================================================
args <- commandArgs(trailingOnly = TRUE)
section_arg <- gsub("^--section=", "", grep("^--section=", args, value = TRUE))
scope_arg   <- gsub("^--scope=",   "", grep("^--scope=",   args, value = TRUE))
if (length(scope_arg) == 0L) scope_arg <- "10y"  # default per design sketch
if (!scope_arg %in% c("10y", "13y")) stop("--scope must be '10y' or '13y'")

if (length(section_arg) == 0L) {
  cat("No --section= flag; section functions defined but nothing dispatched.\n")
  if (length(warnings()) > 0) print(warnings())
  invisible(NULL)
} else {

cat(sprintf("Section: %s | Scope: %s\n", section_arg, scope_arg))

switch(section_arg,
  align_weekly      = section_align_weekly(scope_arg),
  categorical_usdm  = section_categorical_usdm(scope_arg),
  continuous_spei   = section_continuous_spei(scope_arg),
  event_detection   = section_event_detection(scope_arg),
  qc                = section_qc(scope_arg),
  all = {
    section_align_weekly(scope_arg)
    section_categorical_usdm(scope_arg)
    section_continuous_spei(scope_arg)
    section_event_detection(scope_arg)
    section_qc(scope_arg)
  },
  stop("Unknown section: ", section_arg)
)

if (length(warnings()) > 0) print(warnings())  # per feedback_print_warnings_at_end
cat("\nDone.\n")

}  # end dispatch guard
