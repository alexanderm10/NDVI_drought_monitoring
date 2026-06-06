# ==============================================================================
# 07_validate_drought_signal.R
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
#     Rscript 07_validate_drought_signal.R --section=align_weekly [--scope=10y|13y]
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
  align_out_13y        = file.path(paths$validation_data, "ndvi_drought_join_weekly_13y.rds")
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

section_categorical_usdm <- function(scope) {
  cat("\n=== Section: categorical_usdm (scope =", scope, ") — STUB ===\n")
  cat("Not yet implemented. USDM-class confusion matrices, per ecoregion +\n")
  cat("Midwest aggregate, NDVI z-anomaly binned at {-0.5, -1, -1.5, -2, -2.5}σ.\n")
  cat("Lead-time variants (USDM is lagging — see header):\n")
  cat("  - synchronous: USDM(t)\n")
  cat("  - lead-K: max(USDM(t), USDM(t+1), ..., USDM(t+K)) for K = 1, 2, 4, 8 wk\n")
  cat("  Report skill (HSS, CSI) as a function of K to surface the lead-time curve.\n")
  cat("Reads: ndvi_drought_join_weekly_", scope, ".rds\n", sep = "")
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
