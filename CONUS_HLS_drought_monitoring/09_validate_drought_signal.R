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
#   align_weekly             — collapse per-DOY NDVI anomalies + derivatives to
#                              ISO-week summaries, join to USDM + SPEI. ONE big
#                              cache that the analysis sections read. ~6-8 GB est.
#   categorical_usdm         — confusion matrices: binned NDVI z-anom vs USDM
#                              D0-D4. Per ecoregion + Midwest aggregate.
#   within_week_diagnostic   — gate diagnostic: within-week SD of daily NDVI
#                              anomalies vs across-week SD per pixel. Tells us
#                              whether daily-resolution event_detection is worth
#                              the cost vs reusing the weekly cache.
#   continuous_spei          — pooled feols + iso_week-FE feols (fixest)
#                              for headline β per (ecoregion × spei window ×
#                              NDVI signal × model type). Per-pixel slope map
#                              + per-eco summary. Five NDVI signals × three
#                              SPEI accumulation windows (4w/13w/26w). Both
#                              pooled and iso_week-FE reported so seasonality
#                              control can be inspected separately from
#                              regional-event signal preservation.
#   event_detection          — anchored on USDM transitions (none→D0 onset,
#                              recovery). Per-event NDVI lead-time at daily or
#                              weekly grain (per within_week_diagnostic gate). (STUB)
#   qc                       — alignment + completeness audit across all outputs.
#                              (STUB)
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
# Null-reps flag (categorical_usdm v3 only):
#   --null-reps=N  → run N permutation null reps after the observed sweep.
#                    Default 5. Use 0 to skip (fast smoke test).
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
  usdm_confusion_13y   = file.path(paths$validation_data, "usdm_confusion_13y.rds"),
  within_week_sd_10y   = file.path(paths$validation_data, "within_week_sd_10y.rds"),
  within_week_sd_13y   = file.path(paths$validation_data, "within_week_sd_13y.rds"),
  continuous_spei_10y  = file.path(paths$validation_data, "continuous_spei_10y.rds"),
  continuous_spei_13y  = file.path(paths$validation_data, "continuous_spei_13y.rds"),
  continuous_spei_nlcd_10y = file.path(paths$validation_data, "continuous_spei_nlcd_10y.rds"),
  continuous_spei_nlcd_13y = file.path(paths$validation_data, "continuous_spei_nlcd_13y.rds"),
  usdm_confusion_nlcd_10y  = file.path(paths$validation_data, "usdm_confusion_nlcd_10y.rds"),
  usdm_confusion_nlcd_13y  = file.path(paths$validation_data, "usdm_confusion_nlcd_13y.rds"),
  nlcd_pixel_lookup    = file.path(paths$gam_models, "valid_pixels_nlcd2019.rds"),
  nlcd_modal_frac_threshold   = 0.60,
  nlcd_min_pixels_per_stratum = 500L,
  event_detection_10y       = file.path(paths$validation_data, "event_detection_10y.rds"),
  event_detection_13y       = file.path(paths$validation_data, "event_detection_13y.rds"),
  event_detection_nlcd_10y  = file.path(paths$validation_data, "event_detection_nlcd_10y.rds"),
  event_detection_nlcd_13y  = file.path(paths$validation_data, "event_detection_nlcd_13y.rds"),
  flash_drought_10y         = file.path(paths$validation_data, "flash_drought_10y.rds"),
  flash_drought_13y         = file.path(paths$validation_data, "flash_drought_13y.rds"),
  ensemble_or_10y           = file.path(paths$validation_data, "ensemble_or_10y.rds"),
  ensemble_or_13y           = file.path(paths$validation_data, "ensemble_or_13y.rds"),
  ensemble_multi_10y        = file.path(paths$validation_data, "ensemble_multi_10y.rds"),
  ensemble_multi_13y        = file.path(paths$validation_data, "ensemble_multi_13y.rds")
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
# SECTION: categorical_usdm (v3 — corrected scale, true lead-K, two-track skill,
#                            permutation null)
#
# History:
#   v1 (2026-06-09 14:58) — "when USDM is high, does NDVI z drop?" HSS≈0;
#     framing was wrong (synchronous level, not transition).
#   v2 (2026-06-09 15:56) — bidirectional level-change; BUT (a) usdm_change
#     used running-max so recovery half had 0 TPs everywhere, and (b) USDM
#     sentinel -1 (= "None"; recoded from NA at 08_validation_data_setup.R:275)
#     was treated as an arithmetic ordinal class, making None→D0 numerically
#     equivalent to D2→D3. Also (c) L2_code labels collapsed 11 EPA Level II
#     ecoregions {"9.3","8.1",…} to 5 integers {9,8,…} via as.integer().
#   v3 (this code) — fixes all three; adds permutation null + two-track design
#     that honors the categorical nature of USDM's "any drought y/n" boundary
#     separately from the within-drought ordinal progression.
#
# v3 design:
#
# (1) USDM in-analysis recode (cache stays valid; source-side fix deferred):
#       usdm_ord  = usdm + 1L                  # {0=None, 1=D0, ..., 5=D4}
#       in_drought = usdm_ord >= 1L
#
# (2) True lead-K via self-join (NOT running max):
#       usdm_ord_lead_K  = usdm_ord  at (week_start + 7*K)
#       in_drought_lead_K = in_drought at (week_start + 7*K)
#       usdm_change_K = usdm_ord_lead_K - usdm_ord     # signed, K ∈ {1,2,4,8}
#       onset_K = !in_drought &  in_drought_lead_K     # binary onset event
#       end_K   =  in_drought & !in_drought_lead_K     # binary end event
#
# (3) Two skill tracks per (stratum × K × signal):
#       BINARY (full population — honors None↔D0 boundary as a binary event):
#         intensification: pred = signal ≤ -T  vs obs = onset_K
#         recovery:        pred = signal ≥ +T  vs obs = end_K
#       ORDINAL (within-drought subset, usdm_ord ≥ 1 — strict ordinal progression):
#         intensification: pred = signal ≤ -T  vs obs = usdm_change_K ≥ +T_chg
#         recovery:        pred = signal ≥ +T  vs obs = usdm_change_K ≤ -T_chg
#
# (4) Spearman ρ side-cache:
#       binary:  ρ(-signal, in_drought_lead_K - in_drought)   # signed {-1,0,+1}
#       ordinal: ρ(-signal, usdm_change_K)  on within-drought subset
#     Negated so positive ρ = NDVI moves opposite to USDM as ecologically expected.
#
# (5) L2_code label fix:
#       Use as.character(stratum), NOT as.integer(). 11 ecoregions preserved
#       distinctly: {"0.0","5.2","6.2","8.1","8.2","8.3","8.4","8.5","9.2",
#       "9.3","9.4"}. L2_name joined into every output table.
#
# (6) Permutation null (default 5 reps, configurable via --null-reps=N):
#       Per rep:
#         Block-permute usdm_ord within (pixel_id × season ∈ DJF/MAM/JJA/SON).
#         Preserves per-pixel + seasonal marginal distribution; breaks temporal
#         alignment with NDVI dynamics. Recompute lead-K + skill sweep on the
#         shuffled USDM. Stores HSS per cell per rep.
#       Aggregated two ways:
#         (a) per-cell: null_mean, null_sd, z_score = (obs - null_mean)/null_sd
#         (b) max-across-windows: per (stratum × K × direction × thresholds),
#             max HSS across the 5 signals; null distribution from per-rep max.
#             Honest "best-of-5-correlated-signals" inflation correction without
#             dropping windows or assuming independence.
#
# bayes_sig comparator: still dropped per v2 reasoning (cached ndvi_n_sig is
# direction-agnostic). Re-enable path same as before.
#
# Reads:  ndvi_drought_join_weekly_<scope>.rds (built by section_align_weekly)
# Writes: usdm_confusion_<scope>.rds  (v2 archived as .v2.rds by hand)
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

# ---- v3 helpers (file-scope; avoid closure capture of large objects) --------

# Compute lead-K USDM columns by self-join (NOT running max). Mutates `dt`
# in place: adds usdm_change_K, onset_K, end_K, in_drought_lead_K for each K.
# `dt` MUST contain (pixel_id, week_start, usdm_ord, in_drought) and be
# sorted on (pixel_id, week_start). Idempotent for re-call (overwrites the
# K-suffixed columns), used by both the observed run and each null rep.
build_lead_K <- function(dt, K_values) {
  panel <- dt[, .(pixel_id, week_start,
                  usdm_ord_src = usdm_ord, in_drought_src = in_drought)]
  setkey(panel, pixel_id, week_start)

  for (K in K_values) {
    # ws_match shifted BACK by 7K days so that joining on equality between
    # the panel's (pixel_id, ws_match) and dt's (pixel_id, week_start)
    # pulls the future value at week_start + 7K into the current row.
    tmp <- panel[, .(pixel_id,
                     ws_match        = week_start - 7L * K,
                     usdm_ord_lead   = usdm_ord_src,
                     in_drought_lead = in_drought_src)]
    dt[tmp, `:=`(usdm_ord_lead_tmp = i.usdm_ord_lead,
                 in_drought_lead_tmp = i.in_drought_lead),
       on = c("pixel_id", "week_start==ws_match")]
    dt[, sprintf("usdm_change_%d", K) := usdm_ord_lead_tmp - usdm_ord]
    dt[, sprintf("onset_%d", K)       := !in_drought &  in_drought_lead_tmp]
    dt[, sprintf("end_%d",   K)       :=  in_drought & !in_drought_lead_tmp]
    dt[, c("usdm_ord_lead_tmp", "in_drought_lead_tmp") := NULL]
    rm(tmp); gc(verbose = FALSE)   # release per-K tmp (~3 cols × 67M rows ≈ 1.6 GB)
  }
  rm(panel); gc(verbose = FALSE)
  invisible(NULL)
}

# Sweep z-thresholds for a single (sig_vec × obs_yes_vec). obs_yes_vec MUST be
# logical and the same length as sig_vec; pre-filter NAs upstream.
sweep_z <- function(sig_vec, obs_yes_vec, n_total, z_thresholds, z_op,
                    direction_label) {
  rbindlist(lapply(z_thresholds, function(zt) {
    pred_yes <- if (z_op == "<=") sig_vec <= zt else sig_vec >= zt
    tp <- sum(pred_yes &  obs_yes_vec)
    fp <- sum(pred_yes & !obs_yes_vec)
    fn <- sum(!pred_yes &  obs_yes_vec)
    tn <- sum(!pred_yes & !obs_yes_vec)
    sk <- compute_skill(tp, fp, fn, tn)
    data.table(
      direction     = direction_label,
      z_threshold   = zt,
      n_pixel_weeks = n_total,
      tp = tp, fp = fp, fn = fn, tn = tn,
      pod = sk[["pod"]], far = sk[["far"]],
      csi = sk[["csi"]], hss = sk[["hss"]]
    )
  }))
}

# Run the two-track skill sweep (binary + ordinal) across all
# (stratum × K × signal). Returns list(binary = dt, ordinal = dt). Used by
# both the observed run and each null rep.
#
# Strata: each value in `eco_codes` matched against dt[[key_col]], optionally
# plus "midwest_aggregate" (NA stratum_id when include_aggregate = TRUE).
# `key_col` defaults to "L2_code" for backward compatibility with v3
# section_categorical_usdm. The LC-stratified caller passes the fused
# stratum_key column name (e.g. "stratum_key_all") + include_aggregate = FALSE.
# The output `L2_code` column always holds the stratum_id (parsed back to
# (L2_code, nlcd_juliana, dom_filter) by the caller if needed).
run_two_track_sweep <- function(dt, eco_codes, K_values, signal_names,
                                z_neg, z_pos, change_pos, change_neg,
                                progress_every = 25L, label = "obs",
                                key_col           = "L2_code",
                                include_aggregate = TRUE) {
  binary_rows  <- list()
  ordinal_rows <- list()
  n_strata     <- length(eco_codes) + as.integer(include_aggregate)
  total_iter   <- n_strata * length(K_values) * length(signal_names)
  iter         <- 0L
  t_sweep      <- Sys.time()

  strata_list <- if (include_aggregate) c(as.list(eco_codes), list(NA_character_))
                 else                    as.list(eco_codes)
  for (stratum in strata_list) {
    is_mw <- is.na(stratum)
    sub_full <- if (is_mw) dt else dt[get(key_col) == stratum]
    if (nrow(sub_full) == 0L) next
    stratum_type <- if (is_mw) "midwest_aggregate" else "ecoregion"
    L2_label     <- if (is_mw) NA_character_       else as.character(stratum)

    # Within-drought subset used by the ordinal track (recomputed once per stratum).
    # in_drought is a CURRENT-ROW property — K-independent — so this subset is
    # the same across all K within a stratum. During null reps, in_drought has
    # been re-derived from the shuffled USDM by the caller BEFORE the sweep,
    # so this subset correctly reflects the rep's shuffled drought status.
    sub_drought_full <- sub_full[in_drought == TRUE]

    for (K in K_values) {
      change_col <- sprintf("usdm_change_%d", K)
      onset_col  <- sprintf("onset_%d", K)
      end_col    <- sprintf("end_%d", K)

      for (sig in signal_names) {
        iter <- iter + 1L

        # --- BINARY track: population = full sub, need (signal, onset, end) non-NA
        sub_bin <- sub_full[!is.na(get(sig)) &
                              !is.na(get(onset_col)) &
                              !is.na(get(end_col))]
        if (nrow(sub_bin) > 0L) {
          sig_vec <- sub_bin[[sig]]
          int_block <- sweep_z(sig_vec, sub_bin[[onset_col]], nrow(sub_bin),
                               z_neg, "<=", "intensification")
          rec_block <- sweep_z(sig_vec, sub_bin[[end_col]],   nrow(sub_bin),
                               z_pos, ">=", "recovery")
          bin_block <- rbind(int_block, rec_block)
          bin_block[, `:=`(stratum_type = stratum_type, L2_code = L2_label,
                            K = K, ndvi_signal = sig)]
          binary_rows[[length(binary_rows) + 1L]] <- bin_block
        }

        # --- ORDINAL track: population = within-drought subset, need (signal, change) non-NA
        sub_ord <- sub_drought_full[!is.na(get(sig)) & !is.na(get(change_col))]
        if (nrow(sub_ord) > 0L) {
          sig_vec_o <- sub_ord[[sig]]
          chg_vec_o <- sub_ord[[change_col]]
          int_o_list <- lapply(change_pos, function(uct) {
            obs_yes <- chg_vec_o >= uct
            blk <- sweep_z(sig_vec_o, obs_yes, nrow(sub_ord),
                           z_neg, "<=", "intensification")
            blk[, usdm_change_threshold := uct]
            blk
          })
          rec_o_list <- lapply(change_neg, function(uct) {
            obs_yes <- chg_vec_o <= uct
            blk <- sweep_z(sig_vec_o, obs_yes, nrow(sub_ord),
                           z_pos, ">=", "recovery")
            blk[, usdm_change_threshold := uct]
            blk
          })
          ord_block <- rbindlist(c(int_o_list, rec_o_list))
          ord_block[, `:=`(stratum_type = stratum_type, L2_code = L2_label,
                            K = K, ndvi_signal = sig)]
          ordinal_rows[[length(ordinal_rows) + 1L]] <- ord_block
        }

        if (iter %% progress_every == 0L) {
          el  <- as.numeric(Sys.time() - t_sweep, units = "mins")
          eta <- el * (total_iter - iter) / iter
          cat(sprintf("    [%s] iter %d/%d (%.1f min, ETA %.1f min)\n",
                      label, iter, total_iter, el, eta))
        }
      }
    }
  }

  list(
    binary  = rbindlist(binary_rows,  use.names = TRUE),
    ordinal = rbindlist(ordinal_rows, use.names = TRUE)
  )
}

# Run the two-track Spearman correlation sweep — observed run only.
# Binary correlation uses signed transition indicator (in_drought_lead - in_drought) ∈ {-1,0,+1}.
# Ordinal correlation uses usdm_change_K restricted to the within-drought subset.
# `key_col` + `include_aggregate` work the same way as in run_two_track_sweep.
# `progress_every` prints a per-stratum log line every N strata; needed because
# Spearman ranking on 10M-row strata can take ~60 sec per cor() call, and the
# LC-stratified version of this helper can run 30-60 min silently otherwise.
# (Caught 2026-06-12 USDM 5-LC run: 59.1 min silent during step [7].)
run_two_track_correlation <- function(dt, eco_codes, K_values, signal_names,
                                      key_col           = "L2_code",
                                      include_aggregate = TRUE,
                                      progress_every    = 10L,
                                      label             = "obs") {
  bin_rows <- list()
  ord_rows <- list()
  strata_list <- if (include_aggregate) c(as.list(eco_codes), list(NA_character_))
                 else                    as.list(eco_codes)
  n_strata <- length(strata_list)
  t_sweep  <- Sys.time()
  iter     <- 0L

  for (stratum in strata_list) {
    iter <- iter + 1L
    is_mw <- is.na(stratum)
    sub_full <- if (is_mw) dt else dt[get(key_col) == stratum]
    if (nrow(sub_full) == 0L) next
    stratum_type <- if (is_mw) "midwest_aggregate" else "ecoregion"
    L2_label     <- if (is_mw) NA_character_       else as.character(stratum)
    sub_drought  <- sub_full[in_drought == TRUE]

    if (iter == 1L || iter %% progress_every == 0L || iter == n_strata) {
      el  <- as.numeric(Sys.time() - t_sweep, units = "mins")
      eta <- if (iter > 0L) el * (n_strata - iter) / iter else NA_real_
      cat(sprintf("    [%s] stratum %d/%d (%.1f min elapsed, ETA %.1f min)\n",
                  label, iter, n_strata, el, eta))
    }

    for (K in K_values) {
      change_col <- sprintf("usdm_change_%d", K)
      onset_col  <- sprintf("onset_%d", K)
      end_col    <- sprintf("end_%d", K)

      # signed transition indicator for the binary track
      # +1 = onset (None → drought), -1 = end (drought → None), 0 = no boundary cross
      for (sig in signal_names) {
        sub_b <- sub_full[!is.na(get(sig)) &
                            !is.na(get(onset_col)) & !is.na(get(end_col))]
        if (nrow(sub_b) > 0L) {
          transition_signed <- as.integer(sub_b[[onset_col]]) -
                                as.integer(sub_b[[end_col]])
          rho_b <- suppressWarnings(
            cor(-sub_b[[sig]], transition_signed, method = "spearman")
          )
          bin_rows[[length(bin_rows) + 1L]] <- data.table(
            stratum_type = stratum_type, L2_code = L2_label,
            K = K, ndvi_signal = sig,
            n_pixel_weeks = nrow(sub_b),
            spearman_rho_neg_signal = rho_b
          )
        }

        sub_o <- sub_drought[!is.na(get(sig)) & !is.na(get(change_col))]
        if (nrow(sub_o) > 0L) {
          # Ordinal correlation uses the same -signal sign convention as the
          # binary track: positive ρ = "NDVI moves opposite USDM" (NDVI below
          # normal precedes USDM going up = drought worsening). usdm_change_K
          # is positive for worsening within-drought; negation of signal keeps
          # the "positive ρ = good skill" convention consistent across tracks.
          rho_o <- suppressWarnings(
            cor(-sub_o[[sig]], sub_o[[change_col]], method = "spearman")
          )
          ord_rows[[length(ord_rows) + 1L]] <- data.table(
            stratum_type = stratum_type, L2_code = L2_label,
            K = K, ndvi_signal = sig,
            n_pixel_weeks = nrow(sub_o),
            spearman_rho_neg_signal = rho_o
          )
        }
      }
    }
  }

  list(
    binary  = rbindlist(bin_rows,  use.names = TRUE),
    ordinal = rbindlist(ord_rows, use.names = TRUE)
  )
}

# Map month → meteorological season {DJF, MAM, JJA, SON}. Used to define
# permutation blocks: shuffling within (pixel × season) preserves per-pixel +
# seasonal marginal distribution of USDM while breaking temporal alignment
# with NDVI dynamics at week-to-week and year-to-year scales.
month_to_season <- function(m) {
  factor(c("DJF","DJF","MAM","MAM","MAM","JJA","JJA","JJA","SON","SON","SON","DJF")[m],
         levels = c("DJF","MAM","JJA","SON"))
}

# ---- end v3 helpers --------------------------------------------------------

section_categorical_usdm <- function(scope, null_reps = 5L) {
  cat("\n=== Section: categorical_usdm v3 (scope =", scope,
      ", null_reps =", null_reps, ") ===\n")
  stopifnot(scope %in% c("10y", "13y"), is.numeric(null_reps), null_reps >= 0L)
  null_reps <- as.integer(null_reps)

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
  USDM_CHANGE_THRESHOLDS_POS <- 1:3            # intensification (within-drought)
  USDM_CHANGE_THRESHOLDS_NEG <- -(1:3)         # recovery (within-drought)
  K_VALUES                   <- c(1L, 2L, 4L, 8L)
  MIN_VALID_WEEKS            <- 30L
  Z_BREAKS                   <- c(-Inf, -2.5, -2.0, -1.5, -1.0, -0.5,
                                  0, 0.5, 1.0, 1.5, 2.0, 2.5, Inf)
  NULL_SEED_BASE             <- 8675309L

  ANOM_COLS    <- c("ndvi_anom_mean",
                    "deriv_w03_anom_mean", "deriv_w07_anom_mean",
                    "deriv_w14_anom_mean", "deriv_w30_anom_mean")
  SIGNAL_NAMES <- c("ndvi_z",
                    "deriv_w03_z", "deriv_w07_z", "deriv_w14_z", "deriv_w30_z")

  # --- 1. Load cache + USDM in-analysis recode (v3 fix) ---------------------
  cat("\n[1] Load cache + USDM in-analysis recode...\n")
  dt <- as.data.table(readRDS_retry(in_file))
  cat(sprintf("  raw: %s rows × %d cols\n",
              format(nrow(dt), big.mark = ","), ncol(dt)))
  keep_cols <- c("pixel_id", "iso_year", "iso_week", "week_start",
                 ANOM_COLS, "usdm", "L2_code", "L2_name")
  dt <- dt[, ..keep_cols]

  # v3 USDM recode: source -1 sentinel ("None") → 0 ordinal; D0..D4 (0..4) → 1..5.
  # See 08_validation_data_setup.R:275 for where the -1 sentinel originates.
  # NA-handling: align_weekly joins USDM with all.x = TRUE so unmatched
  # pixel-weeks (~0.4%) have usdm = NA → propagate to usdm_ord = NA, in_drought
  # = NA. These rows are correctly filtered downstream by the !is.na guards in
  # run_two_track_sweep and by data.table's NA == TRUE → drop in the
  # in_drought == TRUE subset. The NA-rate report below flags any drift from
  # the expected ~0.4% (which would indicate an upstream join regression).
  dt[, usdm_ord   := as.integer(usdm) + 1L]
  dt[, in_drought := usdm_ord >= 1L]
  dt[, usdm := NULL]   # drop raw to prevent accidental arithmetic
  gc(verbose = FALSE)

  n_px_in <- uniqueN(dt$pixel_id)
  cat(sprintf("  pixel count: %d (expected %d)\n", n_px_in, EXPECTED_VALID_PIXELS))
  if (n_px_in != EXPECTED_VALID_PIXELS) {
    cat(sprintf("  WARN: pixel drift %d (see feedback_pixel_count_invariant)\n",
                n_px_in - EXPECTED_VALID_PIXELS))
  }
  na_rate <- 100 * mean(is.na(dt$usdm_ord))
  cat(sprintf("  USDM recoded scale {0..5}: %.2f%% None | %.2f%% in_drought | %.2f%% NA\n",
              100 * mean(dt$usdm_ord == 0L, na.rm = TRUE),
              100 * mean(dt$in_drought,      na.rm = TRUE),
              na_rate))
  if (na_rate > 5.0) {
    cat(sprintf("  WARN: USDM NA rate %.2f%% exceeds 5%% — investigate align_weekly join.\n",
                na_rate))
  }

  # --- 2. Per-pixel z-standardize all 5 NDVI signals (unchanged from v2) ---
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
  dt[, (ANOM_COLS) := NULL]
  gc(verbose = FALSE)

  # --- 3. True lead-K USDM via self-join (v3 fix — replaces running-max) ----
  cat(sprintf("\n[3] Build lead-K USDM (true self-join, K = %s)...\n",
              paste(K_VALUES, collapse = ",")))
  build_lead_K(dt, K_VALUES)

  for (K in K_VALUES) {
    change_col <- sprintf("usdm_change_%d", K)
    onset_col  <- sprintf("onset_%d", K)
    end_col    <- sprintf("end_%d", K)
    cat(sprintf("  K=%d: change non-NA %.2f%% | range [%+d, %+d] | onset %.3f%% | end %.3f%%\n",
                K,
                100 * mean(!is.na(dt[[change_col]])),
                min(dt[[change_col]], na.rm = TRUE),
                max(dt[[change_col]], na.rm = TRUE),
                100 * mean(dt[[onset_col]], na.rm = TRUE),
                100 * mean(dt[[end_col]],   na.rm = TRUE)))
  }

  # --- 4. Observed two-track skill sweep -----------------------------------
  cat("\n[4] Observed skill sweep (binary + ordinal tracks)...\n")
  eco_codes <- sort(unique(dt$L2_code[!is.na(dt$L2_code)]))
  cat(sprintf("  %d ecoregions found: %s\n",
              length(eco_codes), paste(eco_codes, collapse = ", ")))

  obs <- run_two_track_sweep(dt, eco_codes, K_VALUES, SIGNAL_NAMES,
                              Z_THRESHOLDS_NEG, Z_THRESHOLDS_POS,
                              USDM_CHANGE_THRESHOLDS_POS, USDM_CHANGE_THRESHOLDS_NEG,
                              label = "obs")

  # L2_name lookup for self-describing outputs (one row per L2_code)
  L2_name_lookup <- unique(dt[!is.na(L2_code), .(L2_code, L2_name)])

  skill_binary  <- merge(obs$binary,  L2_name_lookup, by = "L2_code",
                          all.x = TRUE, sort = FALSE)
  skill_ordinal <- merge(obs$ordinal, L2_name_lookup, by = "L2_code",
                          all.x = TRUE, sort = FALSE)
  setcolorder(skill_binary,
              c("stratum_type", "L2_code", "L2_name", "K", "ndvi_signal",
                "direction", "z_threshold", "n_pixel_weeks",
                "tp", "fp", "fn", "tn", "pod", "far", "csi", "hss"))
  setcolorder(skill_ordinal,
              c("stratum_type", "L2_code", "L2_name", "K", "ndvi_signal",
                "direction", "z_threshold", "usdm_change_threshold",
                "n_pixel_weeks", "tp", "fp", "fn", "tn",
                "pod", "far", "csi", "hss"))
  setorder(skill_binary,  stratum_type, L2_code, K, ndvi_signal, direction, z_threshold)
  setorder(skill_ordinal, stratum_type, L2_code, K, ndvi_signal, direction,
           z_threshold, usdm_change_threshold)
  cat(sprintf("  skill_binary: %d rows | skill_ordinal: %d rows\n",
              nrow(skill_binary), nrow(skill_ordinal)))

  # --- 5. Observed Spearman ρ (binary + ordinal) ----------------------------
  cat("\n[5] Observed Spearman ρ (per-track)...\n")
  corr <- run_two_track_correlation(dt, eco_codes, K_VALUES, SIGNAL_NAMES)
  correlation_binary  <- merge(corr$binary,  L2_name_lookup, by = "L2_code",
                                all.x = TRUE, sort = FALSE)
  correlation_ordinal <- merge(corr$ordinal, L2_name_lookup, by = "L2_code",
                                all.x = TRUE, sort = FALSE)
  setorder(correlation_binary,  stratum_type, L2_code, K, ndvi_signal)
  setorder(correlation_ordinal, stratum_type, L2_code, K, ndvi_signal)
  cat(sprintf("  correlation_binary: %d | correlation_ordinal: %d\n",
              nrow(correlation_binary), nrow(correlation_ordinal)))

  # --- 6. Full contingency tables (signed z-bins × signed USDM_change) ------
  # Kept from v2 for post-hoc reanalysis. Only the ordinal direction is
  # informative since usdm_change is now scoreable in both signs.
  cat("\n[6] Full contingency tables (binary + ordinal grids)...\n")
  cont_bin_list <- list()
  cont_ord_list <- list()
  for (sig in SIGNAL_NAMES) {
    for (K in K_VALUES) {
      change_col <- sprintf("usdm_change_%d", K)
      onset_col  <- sprintf("onset_%d", K)
      end_col    <- sprintf("end_%d", K)

      # Binary: (z-bin) × (onset, end). Signed transition col {-1,0,+1}.
      sub_b <- dt[!is.na(get(sig)) &
                    !is.na(get(onset_col)) & !is.na(get(end_col)),
                  .(L2_code,
                    sig_val = get(sig),
                    transition_signed = as.integer(get(onset_col)) -
                                        as.integer(get(end_col)))]
      sub_b[, sig_bin := cut(sig_val, breaks = Z_BREAKS,
                              include.lowest = TRUE, right = TRUE)]
      eco_b <- sub_b[!is.na(L2_code), .N,
                      by = .(L2_code, sig_bin, transition = transition_signed)]
      eco_b[, `:=`(stratum_type = "ecoregion", K = K, ndvi_signal = sig)]
      mw_b <- sub_b[, .N, by = .(sig_bin, transition = transition_signed)]
      mw_b[, `:=`(stratum_type = "midwest_aggregate", L2_code = NA_character_,
                   K = K, ndvi_signal = sig)]
      cont_bin_list[[length(cont_bin_list) + 1L]] <- rbind(eco_b, mw_b,
                                                            use.names = TRUE)

      # Ordinal: within-drought × (z-bin × signed change). Drop rows where
      # current state is None (not in scope for ordinal interpretation).
      sub_o <- dt[in_drought == TRUE &
                    !is.na(get(sig)) & !is.na(get(change_col)),
                  .(L2_code,
                    sig_val    = get(sig),
                    change_val = as.integer(get(change_col)))]
      sub_o[, sig_bin := cut(sig_val, breaks = Z_BREAKS,
                              include.lowest = TRUE, right = TRUE)]
      eco_o <- sub_o[!is.na(L2_code), .N,
                      by = .(L2_code, sig_bin, usdm_change = change_val)]
      eco_o[, `:=`(stratum_type = "ecoregion", K = K, ndvi_signal = sig)]
      mw_o <- sub_o[, .N, by = .(sig_bin, usdm_change = change_val)]
      mw_o[, `:=`(stratum_type = "midwest_aggregate", L2_code = NA_character_,
                   K = K, ndvi_signal = sig)]
      cont_ord_list[[length(cont_ord_list) + 1L]] <- rbind(eco_o, mw_o,
                                                            use.names = TRUE)
    }
  }
  contingency_binary  <- rbindlist(cont_bin_list, use.names = TRUE)
  contingency_ordinal <- rbindlist(cont_ord_list, use.names = TRUE)
  setcolorder(contingency_binary,
              c("stratum_type", "L2_code", "K", "ndvi_signal",
                "sig_bin", "transition", "N"))
  setcolorder(contingency_ordinal,
              c("stratum_type", "L2_code", "K", "ndvi_signal",
                "sig_bin", "usdm_change", "N"))
  cat(sprintf("  contingency_binary: %s rows | contingency_ordinal: %s rows\n",
              format(nrow(contingency_binary),  big.mark = ","),
              format(nrow(contingency_ordinal), big.mark = ",")))

  # --- 7. Permutation null --------------------------------------------------
  null_summary_binary           <- NULL
  null_summary_ordinal          <- NULL
  null_max_across_windows_binary  <- NULL
  null_max_across_windows_ordinal <- NULL

  if (null_reps > 0L) {
    cat(sprintf("\n[7] Permutation null (%d reps)...\n", null_reps))

    # Stash the observed USDM scale and prepare season blocks once
    dt[, usdm_ord_real   := usdm_ord]
    dt[, in_drought_real := in_drought]
    dt[, season := month_to_season(lubridate::month(week_start))]

    null_skill_binary_list  <- vector("list", null_reps)
    null_skill_ordinal_list <- vector("list", null_reps)

    # Use `rep_id` not `rep` for the loop var to avoid shadowing base::rep
    for (rep_id in seq_len(null_reps)) {
      t_rep <- Sys.time()
      cat(sprintf("\n  --- null rep %d/%d ---\n", rep_id, null_reps))
      set.seed(NULL_SEED_BASE + rep_id)

      # Shuffle usdm_ord within (pixel × season). Each (pixel, season) group's
      # USDM values get reordered across the group's rows, preserving the
      # marginal distribution but breaking temporal alignment with NDVI.
      cat("    shuffling within (pixel × season)... ")
      dt[, usdm_ord := usdm_ord_real[sample(.N)], by = .(pixel_id, season)]
      dt[, in_drought := usdm_ord >= 1L]
      cat(sprintf("done (%.1f sec)\n",
                  as.numeric(Sys.time() - t_rep, units = "secs")))

      # Recompute lead-K from shuffled USDM
      cat("    rebuilding lead-K columns... ")
      t_lead <- Sys.time()
      build_lead_K(dt, K_VALUES)
      cat(sprintf("done (%.1f sec)\n",
                  as.numeric(Sys.time() - t_lead, units = "secs")))

      # Run skill sweep on shuffled USDM
      rep_skill <- run_two_track_sweep(dt, eco_codes, K_VALUES, SIGNAL_NAMES,
                                        Z_THRESHOLDS_NEG, Z_THRESHOLDS_POS,
                                        USDM_CHANGE_THRESHOLDS_POS,
                                        USDM_CHANGE_THRESHOLDS_NEG,
                                        label = sprintf("null%d", rep_id))
      rep_skill$binary[,  rep_id := rep_id]
      rep_skill$ordinal[, rep_id := rep_id]
      null_skill_binary_list[[rep_id]]  <- rep_skill$binary
      null_skill_ordinal_list[[rep_id]] <- rep_skill$ordinal
      rm(rep_skill)

      el <- as.numeric(Sys.time() - t_rep, units = "mins")
      cat(sprintf("    rep %d complete in %.1f min\n", rep_id, el))
    }

    # Restore observed state (used by subsequent code paths only;
    # everything we care about is already saved to obs / corr / contingency).
    dt[, usdm_ord   := usdm_ord_real]
    dt[, in_drought := in_drought_real]
    dt[, c("usdm_ord_real", "in_drought_real", "season") := NULL]

    null_skill_binary  <- rbindlist(null_skill_binary_list,  use.names = TRUE)
    null_skill_ordinal <- rbindlist(null_skill_ordinal_list, use.names = TRUE)

    # --- Per-cell null aggregation (mean, sd, z_score vs observed) ---
    cat("\n  aggregating per-cell null...\n")
    null_summary_binary <- null_skill_binary[, .(
      null_mean_hss = mean(hss, na.rm = TRUE),
      null_sd_hss   = sd(hss,   na.rm = TRUE),
      n_reps        = .N
    ), by = .(stratum_type, L2_code, K, ndvi_signal, direction, z_threshold)]
    null_summary_binary <- merge(
      null_summary_binary,
      skill_binary[, .(stratum_type, L2_code, K, ndvi_signal, direction,
                       z_threshold, observed_hss = hss)],
      by = c("stratum_type", "L2_code", "K", "ndvi_signal", "direction",
             "z_threshold"),
      all.x = TRUE
    )
    null_summary_binary[, z_score := (observed_hss - null_mean_hss) / null_sd_hss]

    null_summary_ordinal <- null_skill_ordinal[, .(
      null_mean_hss = mean(hss, na.rm = TRUE),
      null_sd_hss   = sd(hss,   na.rm = TRUE),
      n_reps        = .N
    ), by = .(stratum_type, L2_code, K, ndvi_signal, direction,
              z_threshold, usdm_change_threshold)]
    null_summary_ordinal <- merge(
      null_summary_ordinal,
      skill_ordinal[, .(stratum_type, L2_code, K, ndvi_signal, direction,
                        z_threshold, usdm_change_threshold, observed_hss = hss)],
      by = c("stratum_type", "L2_code", "K", "ndvi_signal", "direction",
             "z_threshold", "usdm_change_threshold"),
      all.x = TRUE
    )
    null_summary_ordinal[, z_score := (observed_hss - null_mean_hss) / null_sd_hss]

    # --- Max-across-windows null (best-of-5-signals correction) ---
    # Per (stratum × K × direction × z_threshold [× usdm_change_threshold for ordinal]),
    # take max HSS across the 5 signals. Per rep. Then aggregate to null distribution.
    # Honest correction for correlated multiple comparisons (no independence assumed,
    # no windows dropped).
    cat("  aggregating max-across-windows null...\n")
    # Helper: argmax over hss, NA-safe. which.max() returns integer(0) on an
    # all-NA vector, which would silently drop the group from the by= result;
    # the [1L] subset + NA fallback keeps the row with explicit NA.
    safe_argmax <- function(hss_vec, sig_vec) {
      idx <- which.max(hss_vec)
      if (length(idx) == 0L) NA_character_ else sig_vec[idx[1L]]
    }

    null_max_per_rep_b <- null_skill_binary[, .(max_hss = max(hss, na.rm = TRUE)),
                                             by = .(stratum_type, L2_code, K,
                                                    direction, z_threshold, rep_id)]
    null_max_across_windows_binary <- null_max_per_rep_b[, .(
      max_null_mean = mean(max_hss, na.rm = TRUE),
      max_null_sd   = sd(max_hss,   na.rm = TRUE),
      n_reps        = .N
    ), by = .(stratum_type, L2_code, K, direction, z_threshold)]
    obs_max_b <- skill_binary[, .(max_obs_hss = max(hss, na.rm = TRUE),
                                  argmax_signal = safe_argmax(hss, ndvi_signal)),
                              by = .(stratum_type, L2_code, K,
                                      direction, z_threshold)]
    null_max_across_windows_binary <- merge(
      null_max_across_windows_binary, obs_max_b,
      by = c("stratum_type", "L2_code", "K", "direction", "z_threshold"),
      all.x = TRUE
    )
    null_max_across_windows_binary[, max_z := (max_obs_hss - max_null_mean) /
                                                max_null_sd]

    null_max_per_rep_o <- null_skill_ordinal[, .(max_hss = max(hss, na.rm = TRUE)),
                                              by = .(stratum_type, L2_code, K,
                                                     direction, z_threshold,
                                                     usdm_change_threshold, rep_id)]
    null_max_across_windows_ordinal <- null_max_per_rep_o[, .(
      max_null_mean = mean(max_hss, na.rm = TRUE),
      max_null_sd   = sd(max_hss,   na.rm = TRUE),
      n_reps        = .N
    ), by = .(stratum_type, L2_code, K, direction,
              z_threshold, usdm_change_threshold)]
    obs_max_o <- skill_ordinal[, .(max_obs_hss = max(hss, na.rm = TRUE),
                                   argmax_signal = safe_argmax(hss, ndvi_signal)),
                               by = .(stratum_type, L2_code, K, direction,
                                       z_threshold, usdm_change_threshold)]
    null_max_across_windows_ordinal <- merge(
      null_max_across_windows_ordinal, obs_max_o,
      by = c("stratum_type", "L2_code", "K", "direction", "z_threshold",
             "usdm_change_threshold"),
      all.x = TRUE
    )
    null_max_across_windows_ordinal[, max_z := (max_obs_hss - max_null_mean) /
                                                 max_null_sd]

    cat(sprintf("  null aggregation complete: binary %d cells | ordinal %d cells | max-binary %d | max-ordinal %d\n",
                nrow(null_summary_binary), nrow(null_summary_ordinal),
                nrow(null_max_across_windows_binary),
                nrow(null_max_across_windows_ordinal)))
  } else {
    cat("\n[7] Permutation null SKIPPED (null_reps = 0).\n")
  }

  # --- 8. Assemble + save ---------------------------------------------------
  result <- list(
    skill_binary                    = skill_binary,
    skill_ordinal                   = skill_ordinal,
    correlation_binary              = correlation_binary,
    correlation_ordinal             = correlation_ordinal,
    contingency_binary              = contingency_binary,
    contingency_ordinal             = contingency_ordinal,
    null_summary_binary             = null_summary_binary,
    null_summary_ordinal            = null_summary_ordinal,
    null_max_across_windows_binary  = null_max_across_windows_binary,
    null_max_across_windows_ordinal = null_max_across_windows_ordinal,
    meta = list(
      scope                      = scope,
      version                    = "v3_two_track_lead_K_with_null",
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
      usdm_recode_in_analysis    = "usdm_ord = usdm + 1L; in_drought = usdm_ord >= 1L; raw -1 sentinel = None; D0-D4 = 1-5",
      lead_K_method              = "self-join on (pixel_id, week_start + 7K) — NOT running max",
      L2_code_handling           = "preserved as character; L2_name joined into all outputs",
      null_reps                  = null_reps,
      null_block_strategy        = "block-permute usdm_ord within (pixel_id × season ∈ DJF/MAM/JJA/SON)",
      null_seed_base             = NULL_SEED_BASE,
      bayes_sig_dropped          = paste("ndvi_n_sig on disk is direction-agnostic;",
                                         "would need align_weekly extension to split",
                                         "into ndvi_n_sig_neg/pos to re-enable")
    )
  )

  cat(sprintf("\n[8] Saving %s...\n", basename(out_file)))
  saveRDS_validated(result, out_file, compress = "gzip")
  cat(sprintf("  wrote %.2f MB in %.1f min total\n",
              file.size(out_file) / 1e6,
              result$meta$run_time_minutes))

  # --- 9. Quick summary -----------------------------------------------------
  cat("\n--- Quick summary (Midwest aggregate, ndvi_z + deriv_w14_z) ---\n")
  for (sig in c("ndvi_z", "deriv_w14_z")) {
    cat(sprintf("\n  %s:\n", sig))
    for (K_local in K_VALUES) {
      r_corr_b <- correlation_binary[stratum_type == "midwest_aggregate" &
                                       K == K_local & ndvi_signal == sig]
      r_corr_o <- correlation_ordinal[stratum_type == "midwest_aggregate" &
                                        K == K_local & ndvi_signal == sig]
      r_int_b <- skill_binary[stratum_type == "midwest_aggregate" &
                                K == K_local & ndvi_signal == sig &
                                direction == "intensification" &
                                z_threshold == -1.5]
      r_rec_b <- skill_binary[stratum_type == "midwest_aggregate" &
                                K == K_local & ndvi_signal == sig &
                                direction == "recovery" &
                                z_threshold == 1.5]
      r_int_o <- skill_ordinal[stratum_type == "midwest_aggregate" &
                                 K == K_local & ndvi_signal == sig &
                                 direction == "intensification" &
                                 z_threshold == -1.5 &
                                 usdm_change_threshold == 1L]
      r_rec_o <- skill_ordinal[stratum_type == "midwest_aggregate" &
                                 K == K_local & ndvi_signal == sig &
                                 direction == "recovery" &
                                 z_threshold == 1.5 &
                                 usdm_change_threshold == -1L]
      cat(sprintf(
        "    K=%d  BIN ρ=%+.3f int.HSS=%+.3f rec.HSS=%+.3f  |  ORD ρ=%+.3f int.HSS=%+.3f rec.HSS=%+.3f\n",
        K_local,
        if (nrow(r_corr_b) > 0L) r_corr_b$spearman_rho_neg_signal else NA_real_,
        if (nrow(r_int_b)  > 0L) r_int_b$hss else NA_real_,
        if (nrow(r_rec_b)  > 0L) r_rec_b$hss else NA_real_,
        if (nrow(r_corr_o) > 0L) r_corr_o$spearman_rho_neg_signal else NA_real_,
        if (nrow(r_int_o)  > 0L) r_int_o$hss else NA_real_,
        if (nrow(r_rec_o)  > 0L) r_rec_o$hss else NA_real_))
    }
  }

  invisible(NULL)
}

# ==============================================================================
# SECTION: within_week_diagnostic
#
# Quantify how much within-week variability exists in our daily NDVI anomalies.
# The align_weekly section collapses daily values to a weekly mean per pixel-week,
# which is the right grain for joining to USDM (published weekly). The question
# this section answers: is the weekly mean throwing away signal we'd want to
# preserve at daily resolution for event-detection lead-time work?
#
# Strategy: per year, load anomalies_YYYY.rds (~1.2 GB; skip derivatives for
# this first pass — anomalies alone tell the story), compute the SD of
# anoms_mean across the DOYs in each (pixel × iso_week) group. Compare to the
# across-week SD per pixel (computed from the existing align_weekly cache's
# ndvi_anom_mean column).
#
# Decision rule for downstream Section B (event_detection):
#   median(within_week_sd / across_week_sd) << 1  → weekly aggregation preserves
#       the signal; Section B can safely use the existing weekly cache (~6 hr).
#   median ratio approaching 1 or above           → daily-resolution work in
#       Section B is justified (~14 hr).
#
# Anomalies-only first pass costs ~30 min. Extending to derivatives (the
# 11 GB/year files) is a second pass if the ecoregion-level ratios warrant it.
#
# Outputs in within_week_sd_<scope>.rds:
#   pixel_week_sd  — per (pixel × iso_year × iso_week) within-week SD + n_doys
#   pixel_summary  — per pixel: median within-week SD, across-week SD, ratio
#   eco_summary    — per L2 ecoregion: median ratio + IQR
#   meta           — scope, years, runtime, signal_set
# ==============================================================================

#' Per-year driver. Reads anomalies_YYYY.rds, computes per-(pixel, iso_week) SD
#' of anoms_mean across DOYs in that week. Returns a per-year data.table; the
#' caller is responsible for rbinding across years and calling gc().
compute_within_week_sd_for_year <- function(year) {
  t0 <- Sys.time()
  cat(sprintf("\n[year %d] ", year))

  anom_file <- file.path(config$anomalies_dir, sprintf("anomalies_%d.rds", year))
  if (!file.exists(anom_file)) {
    cat(sprintf("WARN: missing %s — skipping\n", basename(anom_file)))
    return(NULL)
  }

  cat(sprintf("load (%s MB)... ",
              format(round(file.size(anom_file) / 1e6), big.mark = ",")))
  anom <- as.data.table(readRDS_retry(anom_file))
  anom <- anom[, .(pixel_id, yday, anoms_mean)]

  iso_lookup <- yday_iso_lookup(year)
  anom <- merge(anom, iso_lookup, by = "yday", all.x = TRUE)

  cat("compute per-pixel-week SD... ")
  pw_sd <- anom[, .(
    within_week_sd     = if (sum(!is.na(anoms_mean)) >= 2L)
                           sd(anoms_mean, na.rm = TRUE) else NA_real_,
    within_week_n_doys = sum(!is.na(anoms_mean))
  ), by = .(pixel_id, iso_year, iso_week)]

  rm(anom); gc(verbose = FALSE)

  cat(sprintf("%s rows in %.1f min\n",
              format(nrow(pw_sd), big.mark = ","),
              as.numeric(Sys.time() - t0, units = "mins")))
  pw_sd
}

#' Combine per-pixel-week within-week SD with across-week SD from the existing
#' align_weekly cache. Returns a per-pixel summary table.
summarize_within_vs_across <- function(pixel_week_sd, weekly_cache_file,
                                       scope_years) {
  cat("\nLoad align_weekly cache for across-week SD... ")
  wk <- as.data.table(readRDS_retry(weekly_cache_file))
  wk <- wk[iso_year %in% scope_years, .(pixel_id, iso_year, iso_week,
                                         ndvi_anom_mean, L2_code, L2_name)]
  cat(sprintf("%s rows\n", format(nrow(wk), big.mark = ",")))

  cat("Compute per-pixel across-week SD... ")
  across <- wk[, .(
    across_week_sd = if (sum(!is.na(ndvi_anom_mean)) >= 2L)
                       sd(ndvi_anom_mean, na.rm = TRUE) else NA_real_,
    n_weeks        = sum(!is.na(ndvi_anom_mean)),
    L2_code        = first(na.omit(L2_code)),
    L2_name        = first(na.omit(L2_name))
  ), by = pixel_id]
  cat(sprintf("%d pixels\n", nrow(across)))

  cat("Compute per-pixel median within-week SD... ")
  within <- pixel_week_sd[!is.na(within_week_sd),
                          .(median_within_week_sd = median(within_week_sd, na.rm = TRUE),
                            mean_within_week_sd   = mean(within_week_sd,   na.rm = TRUE),
                            n_weeks_with_sd       = .N),
                          by = pixel_id]
  cat(sprintf("%d pixels\n", nrow(within)))

  px <- merge(across, within, by = "pixel_id", all = TRUE)
  px[, ratio_within_over_across := median_within_week_sd / across_week_sd]
  px
}

#' Per-ecoregion summary of within/across ratio distribution.
summarize_ecoregion_ratio <- function(pixel_summary) {
  pixel_summary[!is.na(ratio_within_over_across) & !is.na(L2_code),
                .(n_pixels         = .N,
                  median_ratio     = median(ratio_within_over_across),
                  q25_ratio        = quantile(ratio_within_over_across, 0.25),
                  q75_ratio        = quantile(ratio_within_over_across, 0.75),
                  median_within_sd = median(median_within_week_sd, na.rm = TRUE),
                  median_across_sd = median(across_week_sd,        na.rm = TRUE)),
                by = .(L2_code, L2_name)][order(median_ratio)]
}

section_within_week_diagnostic <- function(scope) {
  cat("\n=== Section: within_week_diagnostic (scope =", scope, ") ===\n")
  stopifnot(scope %in% c("10y", "13y"))

  scope_years <- if (scope == "10y") 2016:2025 else 2013:2025
  out_file <- if (scope == "10y") config$within_week_sd_10y else config$within_week_sd_13y
  weekly_cache_file <- if (scope == "10y") config$align_out_10y else config$align_out_13y

  cat(sprintf("Scope: %s (years %d-%d)\n", scope, min(scope_years), max(scope_years)))
  cat(sprintf("Output: %s\n", out_file))
  cat(sprintf("Weekly cache (for across-week SD): %s\n", weekly_cache_file))
  if (!file.exists(weekly_cache_file)) {
    stop("Weekly cache not found; run --section=align_weekly first.")
  }

  t_section <- Sys.time()

  # --- 1. Per-year within-week SD ---
  cat("\n[1/3] Computing within-week SD per year...\n")
  year_list <- vector("list", length(scope_years))
  for (i in seq_along(scope_years)) {
    yr <- scope_years[i]
    year_list[[i]] <- compute_within_week_sd_for_year(yr)
    gc(verbose = FALSE)
  }
  year_list <- Filter(Negate(is.null), year_list)
  if (length(year_list) == 0L) stop("within_week_diagnostic: no per-year outputs.")

  cat(sprintf("\nrbindlist %d years... ", length(year_list)))
  pixel_week_sd <- rbindlist(year_list, use.names = TRUE)
  rm(year_list); gc(verbose = FALSE)
  cat(sprintf("%s rows\n", format(nrow(pixel_week_sd), big.mark = ",")))

  # --- 2. Per-pixel within vs across ---
  cat("\n[2/3] Combining with across-week SD from weekly cache...\n")
  pixel_summary <- summarize_within_vs_across(pixel_week_sd,
                                              weekly_cache_file,
                                              scope_years)

  # --- 3. Per-ecoregion summary ---
  cat("\n[3/3] Ecoregion-level summary of within/across ratio...\n")
  eco_summary <- summarize_ecoregion_ratio(pixel_summary)

  meta <- list(
    scope             = scope,
    scope_years       = scope_years,
    n_pixels_in_pw    = uniqueN(pixel_week_sd$pixel_id),
    n_pixels_summary  = nrow(pixel_summary),
    signal            = "anoms_mean (derivatives deferred — anomalies-only first pass)",
    runtime_minutes   = as.numeric(Sys.time() - t_section, units = "mins"),
    created           = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )

  out <- list(
    pixel_week_sd = pixel_week_sd,
    pixel_summary = pixel_summary,
    eco_summary   = eco_summary,
    meta          = meta
  )

  cat(sprintf("\nSaving %s...\n", basename(out_file)))
  saveRDS_validated(out, out_file, compress = "xz")
  cat(sprintf("  wrote %.2f MB in %.1f min total\n",
              file.size(out_file) / 1e6,
              meta$runtime_minutes))

  # --- Quick summary ---
  cat("\n--- Ecoregion within/across SD ratio (sorted by median ratio asc) ---\n")
  print(eco_summary)

  cat("\n--- Interpretation guide ---\n")
  cat("  ratio << 1:  weekly aggregation preserves the signal (use weekly cache for Section B)\n")
  cat("  ratio ≈ 1:   within-week variability comparable to across-week (daily Section B justified)\n")
  cat("  ratio > 1:   within-week noise dominates (daily Section B essential; or weekly mean is sound)\n")

  invisible(out)
}

# ==============================================================================
# SECTION: continuous_spei
#
# Validate the NDVI-anomaly indicator against continuous SPEI (independent
# meteorological reference; less lagged than USDM; continuous, not binned).
# The operational question: does our pixel-level indicator track meteorological
# drought across the Midwest space-time panel?
#
# Two model variants per (stratum × spei_window × signal):
#   pooled:    feols(signal_z ~ spei_z,                    cluster = ~pixel_id)
#   isowk_fe:  feols(signal_z ~ spei_z | iso_week,         cluster = ~pixel_id)
#
# Rationale for NOT using iso_year × iso_week FE (the standard panel default):
# our upstream pipeline already removes per-pixel climatology (anom = year_fit
# − norm_fit) and per-pixel scale (z-standardization in step [2] below). SPEI
# is already z-scored per pixel × week-of-year against a 42-year climatology.
# Both sides of the regression are deviations from "what would be normal at
# this pixel in this week." Adding year×week FE absorbs regional drought
# events ("week 30 of 2012 was dry across the whole Midwest") — which is
# precisely the signal we want to validate. The pooled model is the operational
# headline. The iso_week-FE variant adds mild seasonal control (allowing
# intercept to shift by week-of-year) without stripping the regional drought
# signal. Pixel FE is redundant with per-pixel z-standardization.
#
# Per-pixel slope map: closed-form covariance per pixel (data.table by-group,
# skipping lm() overhead at 129K × 15 fits = ~1.9M slopes). Single time series
# per pixel — no FE involved.
#
# Permutation null: 5 reps default (overridable via --null-reps=N). Shuffles
# SPEI within (pixel × season) to preserve marginal distributions while
# breaking the SPEI–NDVI relationship. Re-fits POOLED model only (skipping
# iso_week FE for null to halve runtime).
#
# Outputs in continuous_spei_<scope>.rds:
#   fit_table        — per (stratum × window × signal × model_type): β, SE, t,
#                      p, r2_within, n_obs, n_pixels (12 × 3 × 5 × 2 = 360 rows)
#   slope_map        — per (pixel × window × signal): slope, intercept,
#                      r2, n_weeks  (~1.9M rows)
#   slope_map_summary — per (L2_code × window × signal): median slope, IQR,
#                      % positive, % with t > 2  (~ 11 × 3 × 5 = 165 rows)
#   residual_diag    — headline cell residuals binned by season × ecoregion
#   null_summary     — per-cell observed_β, null_mean_β, null_sd_β, z_score
#                      (pooled-model cells only)
#   meta             — scope, n_reps, runtime, signal_set, etc.
# ==============================================================================

#' Per-pixel z-standardize a set of anomaly columns. Adds new columns named
#' in `z_cols` (same length as `anom_cols`). Drops pixels with sd=0 or
#' n_valid < min_valid_weeks in ANY signal (signal-by-signal union).
#'
#' Returns the data.table modified in place. Reports n dropped per signal.
#'
#' Lifted from v3 categorical_usdm inline pattern; shared across analysis
#' sections so future helpers (e.g., event_detection) don't re-implement it.
zstandardize_signals_per_pixel <- function(dt, anom_cols, z_cols,
                                           min_valid_weeks = 30L) {
  stopifnot(length(anom_cols) == length(z_cols),
            all(anom_cols %in% names(dt)))
  drop_px <- integer(0)
  for (i in seq_along(anom_cols)) {
    col_anom <- anom_cols[i]
    col_z    <- z_cols[i]
    cat(sprintf("  [%s → %s] ", col_anom, col_z))

    stats <- dt[!is.na(get(col_anom)), .(
      mu_pix  = mean(get(col_anom)),
      sd_pix  = sd(get(col_anom)),
      n_valid = .N
    ), by = pixel_id]

    drop_this <- stats[n_valid < min_valid_weeks | sd_pix == 0 | is.na(sd_pix),
                       pixel_id]
    drop_px <- union(drop_px, drop_this)
    cat(sprintf("dropping %d pixels (σ=0 or n<%d)\n",
                length(drop_this), min_valid_weeks))

    dt[stats, `:=`(mu_pix = i.mu_pix, sd_pix = i.sd_pix), on = "pixel_id"]
    dt[, (col_z) := (get(col_anom) - mu_pix) / sd_pix]
    dt[, c("mu_pix", "sd_pix") := NULL]
  }
  cat(sprintf("  total unique drop list: %d pixels\n", length(drop_px)))
  if (length(drop_px) > 0L) dt <- dt[!pixel_id %in% drop_px]
  invisible(drop_px)  # return the drop list; caller can re-bind dt if needed
}

#' Fit one feols regression cell. Returns a single-row data.table.
#' model_type ∈ {"pooled", "isowk_fe"}.
#'   pooled:    feols(signal_z ~ spei_col,                cluster = ~pixel_id)
#'   isowk_fe:  feols(signal_z ~ spei_col | iso_week,     cluster = ~pixel_id)
fit_fe_spei_one_cell <- function(dt_sub, spei_col, signal_col,
                                 stratum_label, model_type) {
  stopifnot(model_type %in% c("pooled", "isowk_fe"))

  fml <- if (model_type == "pooled") {
    as.formula(sprintf("%s ~ %s", signal_col, spei_col))
  } else {
    as.formula(sprintf("%s ~ %s | iso_week", signal_col, spei_col))
  }

  # Use is.finite() — drops both NA and ±Inf. SPEI cache has rare ±Inf
  # rows (~0.001% for spei_13w; the SPEI package emits these when the fitted
  # CDF lands at exactly 0 or 1 for extreme observations). See
  # [[spei-cache-inf-quirk]] memory.
  ok <- dt_sub[is.finite(get(signal_col)) & is.finite(get(spei_col))]
  if (nrow(ok) < 1000L) {
    return(data.table(stratum = stratum_label, spei_col = spei_col,
                      signal_col = signal_col, model_type = model_type,
                      beta = NA_real_, se = NA_real_, t = NA_real_,
                      p = NA_real_, r2_within = NA_real_,
                      n_obs = nrow(ok), n_pixels = uniqueN(ok$pixel_id),
                      note = "skipped: n_obs < 1000"))
  }

  fit <- tryCatch(
    fixest::feols(fml, data = ok, cluster = ~pixel_id, notes = FALSE),
    error = function(e) e
  )
  if (inherits(fit, "error")) {
    return(data.table(stratum = stratum_label, spei_col = spei_col,
                      signal_col = signal_col, model_type = model_type,
                      beta = NA_real_, se = NA_real_, t = NA_real_,
                      p = NA_real_, r2_within = NA_real_,
                      n_obs = nrow(ok), n_pixels = uniqueN(ok$pixel_id),
                      note = paste("feols error:", conditionMessage(fit))))
  }

  cf  <- fit$coeftable
  est <- cf[spei_col, "Estimate"]
  se  <- cf[spei_col, "Std. Error"]
  tv  <- cf[spei_col, "t value"]
  pv  <- cf[spei_col, "Pr(>|t|)"]
  r2w <- if (model_type == "pooled") {
    fixest::r2(fit, "r2")
  } else {
    fixest::r2(fit, "wr2")  # within-r2 when FE present
  }

  data.table(stratum    = stratum_label,
             spei_col   = spei_col,
             signal_col = signal_col,
             model_type = model_type,
             beta       = est,
             se         = se,
             t          = tv,
             p          = pv,
             r2_within  = as.numeric(r2w),
             n_obs      = nrow(ok),
             n_pixels   = uniqueN(ok$pixel_id),
             note       = "")
}

#' Loop the (stratum × spei_window × signal × model_type) grid and return one
#' big fit table. Uses data.table keyed indexing for cheap stratum subsets.
#'
#' key_col / include_aggregate: added 2026-06-12 for the NLCD-stratified
#' section. Defaults preserve original Section A behavior (key on L2_code,
#' append a midwest_aggregate stratum). For the LC section we key on a fused
#' "L2|LC|dom" column and skip the aggregate.
run_fe_regression_grid <- function(dt, eco_codes, spei_cols, signal_cols,
                                   model_types       = c("pooled", "isowk_fe"),
                                   key_col           = "L2_code",
                                   include_aggregate = TRUE) {
  setkeyv(dt, key_col)  # cheap stratum subsetting

  strata <- if (include_aggregate) c(eco_codes, "midwest_aggregate") else eco_codes
  rows <- vector("list", length(strata) * length(spei_cols) *
                          length(signal_cols) * length(model_types))
  idx <- 0L
  total <- length(rows)

  for (stratum in strata) {
    is_mw <- include_aggregate && stratum == "midwest_aggregate"
    sub <- if (is_mw) dt else dt[.(stratum), nomatch = NULL]
    n_px_str <- uniqueN(sub$pixel_id)
    cat(sprintf("  [%s] n_obs=%s n_pixels=%d\n",
                stratum, format(nrow(sub), big.mark = ","), n_px_str))

    for (sp_col in spei_cols) {
      for (sg_col in signal_cols) {
        for (mt in model_types) {
          idx <- idx + 1L
          rows[[idx]] <- fit_fe_spei_one_cell(sub, sp_col, sg_col,
                                              stratum, mt)
        }
      }
    }
    rm(sub); gc(verbose = FALSE)
  }
  rbindlist(rows, use.names = TRUE, fill = TRUE)
}

#' Per-pixel slope of signal ~ spei via closed-form covariance (skip lm()).
#' Returns one row per (pixel_id × spei_col × signal_col).
fit_pixel_slope_map <- function(dt, spei_cols, signal_cols,
                                min_valid_weeks = 30L) {
  out_list <- vector("list", length(spei_cols) * length(signal_cols))
  idx <- 0L
  for (sp in spei_cols) {
    for (sg in signal_cols) {
      idx <- idx + 1L
      cat(sprintf("  [%s vs %s] ", sg, sp))
      slopes <- dt[is.finite(get(sp)) & is.finite(get(sg)),
                   {
                     n  <- .N
                     if (n < 2L) {
                       list(slope = NA_real_, intercept = NA_real_,
                            r2 = NA_real_, n_weeks = n)
                     } else {
                       mx <- mean(get(sp))
                       my <- mean(get(sg))
                       dx <- get(sp) - mx
                       dy <- get(sg) - my
                       vx <- sum(dx * dx) / (n - 1L)
                       cv <- sum(dx * dy) / (n - 1L)
                       vy <- sum(dy * dy) / (n - 1L)
                       vx_ok <- !is.na(vx) && vx > 0
                       vy_ok <- !is.na(vy) && vy > 0
                       slope <- if (vx_ok) cv / vx else NA_real_
                       r2    <- if (vx_ok && vy_ok) (cv * cv) / (vx * vy) else NA_real_
                       list(slope = slope,
                            intercept = if (!is.na(slope)) my - slope * mx else NA_real_,
                            r2 = r2,
                            n_weeks = n)
                     }
                   },
                   by = pixel_id]
      slopes <- slopes[n_weeks >= min_valid_weeks]
      slopes[, `:=`(spei_col = sp, signal_col = sg)]
      cat(sprintf("%d pixels (>=%d weeks)\n", nrow(slopes), min_valid_weeks))
      out_list[[idx]] <- slopes
    }
  }
  rbindlist(out_list, use.names = TRUE)
}

#' Per (L2 × spei_col × signal_col) summary of the per-pixel slope distribution.
summarize_slope_map <- function(slope_map, eco_lookup) {
  m <- merge(slope_map,
             eco_lookup[, .(pixel_id, L2_code, L2_name)],
             by = "pixel_id", all.x = TRUE)
  m[, .(n_pixels        = .N,
        median_slope    = median(slope, na.rm = TRUE),
        q25_slope       = quantile(slope, 0.25, na.rm = TRUE),
        q75_slope       = quantile(slope, 0.75, na.rm = TRUE),
        pct_positive    = 100 * mean(slope > 0, na.rm = TRUE),
        median_r2       = median(r2, na.rm = TRUE)),
    by = .(L2_code, L2_name, spei_col, signal_col)][order(L2_code, spei_col, signal_col)]
}

#' Compute residuals from one headline pooled fit, binned by season × eco.
#' Cheap diagnostic for omitted seasonality structure.
#'
#' Computes residuals manually from fitted coefficients (intercept + slope * x)
#' rather than via residuals(fit) — guarantees row alignment with the input
#' data. fixest can drop additional rows internally (singletons, etc.) that
#' break a length-based assignment via residuals(fit).
compute_residual_diagnostics_spei <- function(dt, spei_col, signal_col) {
  ok <- dt[is.finite(get(signal_col)) & is.finite(get(spei_col))]
  if (nrow(ok) < 1000L) {
    cat(sprintf("  WARN: only %d rows for residual diag; skipping\n", nrow(ok)))
    return(data.table())
  }
  fit <- fixest::feols(as.formula(sprintf("%s ~ %s", signal_col, spei_col)),
                       data = ok, cluster = ~pixel_id, notes = FALSE)
  intercept <- as.numeric(fit$coefficients[["(Intercept)"]])
  slope     <- as.numeric(fit$coefficients[[spei_col]])
  ok[, predicted := intercept + slope * get(spei_col)]
  ok[, resid     := get(signal_col) - predicted]
  ok[, season    := month_to_season(lubridate::month(week_start))]
  out <- ok[, .(n          = .N,
                mean_resid = mean(resid),
                sd_resid   = sd(resid),
                p25        = quantile(resid, 0.25),
                p75        = quantile(resid, 0.75)),
            by = .(L2_code, season)]
  out[order(L2_code, season)]
}

#' Permutation null. For each rep: shuffle SPEI within (pixel × season) and
#' re-fit the POOLED model on the same (stratum × spei_window × signal) grid.
#' Aggregates to per-cell observed-vs-null β z-score.
run_fe_permutation_null_spei <- function(dt, eco_codes, spei_cols, signal_cols,
                                         n_reps = 5L, seed_base = 8675309L) {
  if (n_reps <= 0L) {
    cat("  (null_reps = 0; skipping permutation null)\n")
    return(NULL)
  }
  if (!"season" %in% names(dt)) {
    dt[, season := month_to_season(lubridate::month(week_start))]
  }

  null_rows <- vector("list", n_reps)
  for (rep in seq_len(n_reps)) {
    set.seed(seed_base + rep)
    cat(sprintf("\n  --- null rep %d/%d ---\n", rep, n_reps))
    cat("    shuffling SPEI within (pixel × season)...")
    t0 <- Sys.time()

    # Shuffle each SPEI column within (pixel, season) blocks
    for (sp in spei_cols) {
      dt[, (sp) := sample(get(sp)), by = .(pixel_id, season)]
    }
    cat(sprintf(" done (%.1f sec)\n",
                as.numeric(Sys.time() - t0, units = "secs")))

    cat("    re-fitting pooled grid...\n")
    rep_fits <- run_fe_regression_grid(dt, eco_codes, spei_cols, signal_cols,
                                       model_types = "pooled")
    rep_fits[, rep := rep]
    null_rows[[rep]] <- rep_fits
  }
  null_all <- rbindlist(null_rows, use.names = TRUE)
  null_all[, .(null_mean_beta = mean(beta, na.rm = TRUE),
               null_sd_beta   = sd(beta,   na.rm = TRUE),
               n_reps         = .N),
           by = .(stratum, spei_col, signal_col)]
}

# ------------------------------------------------------------------------------
# LC interaction helpers (used by section_continuous_spei_nlcd)
# ------------------------------------------------------------------------------

#' Fit one ecoregion x dom x spei x signal x model interaction cell.
#'
#' Fits feols(signal ~ spei + i(nlcd_juliana, spei, ref="crop") [| iso_week]).
#' Returns (long) per-LC slopes + a single-row wald test that ALL slope-offsets
#' from the reference are jointly zero — i.e., "do slopes differ across LCs?"
#'
#' Reference LC is "crop" when present; otherwise the most common LC in the
#' subset. If only one LC is present after the min-N filter, returns NA rows
#' with a note.
fit_lc_interaction_one_cell <- function(dt_sub, spei_col, signal_col,
                                        L2_label, dom_label, model_type,
                                        lc_col           = "nlcd_juliana",
                                        min_pixels_per_lc = 500L) {
  stopifnot(model_type %in% c("pooled", "isowk_fe"))

  ok <- dt_sub[is.finite(get(signal_col)) & is.finite(get(spei_col)) &
               !is.na(get(lc_col))]

  # Filter to LCs that meet the min-pixel floor within this ecoregion x dom cell.
  lc_n <- ok[, .(n_pixels = uniqueN(pixel_id)), by = c(lc_col)]
  keep_lcs <- lc_n[n_pixels >= min_pixels_per_lc][[lc_col]]
  ok <- ok[get(lc_col) %in% keep_lcs]
  # Drop unused factor levels so feols doesn't choke.
  ok[, (lc_col) := droplevels(factor(get(lc_col)))]

  na_row <- function(note, slopes_dt = NULL, wald_dt = NULL) {
    if (is.null(slopes_dt)) {
      slopes_dt <- data.table(
        L2_code = L2_label, dom_filter = dom_label,
        spei_col = spei_col, signal_col = signal_col, model_type = model_type,
        lc_level = NA_character_,
        beta = NA_real_, se = NA_real_, t = NA_real_, p = NA_real_,
        n_obs = nrow(ok), n_pixels = uniqueN(ok$pixel_id), note = note
      )
    }
    if (is.null(wald_dt)) {
      wald_dt <- data.table(
        L2_code = L2_label, dom_filter = dom_label,
        spei_col = spei_col, signal_col = signal_col, model_type = model_type,
        wald_chi2 = NA_real_, wald_df = NA_integer_, wald_p = NA_real_,
        n_lc_levels = length(keep_lcs), note = note
      )
    }
    list(slopes = slopes_dt, wald = wald_dt)
  }

  if (length(keep_lcs) < 2L) {
    return(na_row(sprintf("skipped: only %d LC(s) >= %d pixels",
                          length(keep_lcs), min_pixels_per_lc)))
  }
  if (nrow(ok) < 1000L) {
    return(na_row(sprintf("skipped: n_obs %d < 1000", nrow(ok))))
  }

  # Pick reference LC: prefer "crop"; otherwise the most common in this subset.
  ref_lc <- if ("crop" %in% keep_lcs) {
    "crop"
  } else {
    lc_n[get(lc_col) %in% keep_lcs][order(-n_pixels)][[lc_col]][1]
  }

  fml <- if (model_type == "pooled") {
    as.formula(sprintf("%s ~ %s + i(%s, %s, ref=\"%s\")",
                       signal_col, spei_col, lc_col, spei_col, ref_lc))
  } else {
    as.formula(sprintf("%s ~ %s + i(%s, %s, ref=\"%s\") | iso_week",
                       signal_col, spei_col, lc_col, spei_col, ref_lc))
  }

  fit <- tryCatch(
    fixest::feols(fml, data = ok, cluster = ~pixel_id, notes = FALSE),
    error = function(e) e
  )
  if (inherits(fit, "error")) {
    return(na_row(paste("feols error:", conditionMessage(fit))))
  }

  cf <- fit$coeftable
  # Reference slope = the bare spei_col coefficient.
  ref_beta <- cf[spei_col, "Estimate"]
  ref_se   <- cf[spei_col, "Std. Error"]
  ref_t    <- cf[spei_col, "t value"]
  ref_p    <- cf[spei_col, "Pr(>|t|)"]

  # Offsets named like "nlcd_juliana::forest:spei_13w"
  offset_pattern <- sprintf("^%s::", lc_col)
  offset_rows    <- grep(offset_pattern, rownames(cf), value = TRUE)
  # Per-LC slope = reference + offset; reference itself is one of the rows.
  slopes <- vector("list", length(keep_lcs))
  for (i in seq_along(keep_lcs)) {
    lev <- as.character(keep_lcs[i])
    if (lev == ref_lc) {
      slopes[[i]] <- data.table(
        L2_code = L2_label, dom_filter = dom_label,
        spei_col = spei_col, signal_col = signal_col, model_type = model_type,
        lc_level = lev,
        beta = ref_beta, se = ref_se, t = ref_t, p = ref_p,
        n_obs = nrow(ok), n_pixels = uniqueN(ok[get(lc_col) == lev]$pixel_id),
        note = "reference"
      )
    } else {
      # Find this LC's offset row (name contains ":<lev>:" or ends with ":<lev>")
      lc_row <- offset_rows[grepl(sprintf("::%s:", lev), offset_rows, fixed = TRUE)]
      if (length(lc_row) != 1L) {
        slopes[[i]] <- data.table(
          L2_code = L2_label, dom_filter = dom_label,
          spei_col = spei_col, signal_col = signal_col, model_type = model_type,
          lc_level = lev, beta = NA_real_, se = NA_real_, t = NA_real_, p = NA_real_,
          n_obs = nrow(ok), n_pixels = uniqueN(ok[get(lc_col) == lev]$pixel_id),
          note = sprintf("coef row not found (%d matches)", length(lc_row))
        )
        next
      }
      off_b <- cf[lc_row, "Estimate"]
      off_p <- cf[lc_row, "Pr(>|t|)"]
      # The interaction's own t/p is for the OFFSET being zero, not the slope itself.
      # We surface offset SE/p here; per-LC absolute slope is reference + offset.
      slopes[[i]] <- data.table(
        L2_code = L2_label, dom_filter = dom_label,
        spei_col = spei_col, signal_col = signal_col, model_type = model_type,
        lc_level = lev,
        beta = ref_beta + off_b,
        se   = cf[lc_row, "Std. Error"],  # SE of offset (interpretation: vs ref)
        t    = cf[lc_row, "t value"],
        p    = off_p,                      # p of offset (vs ref)
        n_obs = nrow(ok), n_pixels = uniqueN(ok[get(lc_col) == lev]$pixel_id),
        note = sprintf("offset_from_%s", ref_lc)
      )
    }
  }
  slopes_dt <- rbindlist(slopes, use.names = TRUE)

  # Wald: jointly test all offsets == 0 (i.e., all per-LC slopes == reference slope).
  if (length(offset_rows) >= 1L) {
    w <- tryCatch(fixest::wald(fit, keep = offset_rows, print = FALSE),
                  error = function(e) e)
    wald_dt <- if (inherits(w, "error")) {
      data.table(L2_code = L2_label, dom_filter = dom_label,
                 spei_col = spei_col, signal_col = signal_col, model_type = model_type,
                 wald_chi2 = NA_real_, wald_df = NA_integer_, wald_p = NA_real_,
                 n_lc_levels = length(keep_lcs),
                 note = paste("wald error:", conditionMessage(w)))
    } else {
      data.table(L2_code = L2_label, dom_filter = dom_label,
                 spei_col = spei_col, signal_col = signal_col, model_type = model_type,
                 wald_chi2 = as.numeric(w$stat),
                 wald_df   = as.integer(w$df1),
                 wald_p    = as.numeric(w$p),
                 n_lc_levels = length(keep_lcs),
                 note = "")
    }
  } else {
    wald_dt <- data.table(
      L2_code = L2_label, dom_filter = dom_label,
      spei_col = spei_col, signal_col = signal_col, model_type = model_type,
      wald_chi2 = NA_real_, wald_df = NA_integer_, wald_p = NA_real_,
      n_lc_levels = length(keep_lcs),
      note = "no offset terms (single LC?)"
    )
  }

  list(slopes = slopes_dt, wald = wald_dt)
}

#' Loop the LC-interaction grid over (eco × dom × spei × signal × model).
#' Returns a list with $interaction_table (long, one row per lc_level) and
#' $wald_table (one row per cell). dom variants: "all" = no filter; "dom" =
#' only pixels with modal_frac >= modal_frac_threshold.
run_lc_interaction_grid <- function(dt, eco_codes, spei_cols, signal_cols,
                                    model_types          = c("pooled", "isowk_fe"),
                                    lc_col               = "nlcd_juliana",
                                    dom_variants         = c("all", "dom"),
                                    modal_frac_threshold = 0.60,
                                    min_pixels_per_lc    = 500L) {
  stopifnot("L2_code" %in% names(dt), lc_col %in% names(dt),
            "modal_frac" %in% names(dt))
  slopes_list <- list()
  wald_list   <- list()

  for (eco in eco_codes) {
    sub_eco <- dt[L2_code == eco]
    if (nrow(sub_eco) == 0L) {
      cat(sprintf("  [eco %s] no rows; skipping\n", eco))
      next
    }
    for (dom in dom_variants) {
      sub <- if (dom == "dom") sub_eco[modal_frac >= modal_frac_threshold] else sub_eco
      cat(sprintf("  [eco %s | dom=%s] n_obs=%s n_pixels=%d\n",
                  eco, dom, format(nrow(sub), big.mark = ","),
                  uniqueN(sub$pixel_id)))
      for (sp in spei_cols) {
        for (sg in signal_cols) {
          for (mt in model_types) {
            out <- fit_lc_interaction_one_cell(sub, sp, sg, eco, dom, mt,
                                               lc_col = lc_col,
                                               min_pixels_per_lc = min_pixels_per_lc)
            slopes_list[[length(slopes_list) + 1L]] <- out$slopes
            wald_list  [[length(wald_list)   + 1L]] <- out$wald
          }
        }
      }
    }
  }

  list(
    interaction_table = rbindlist(slopes_list, use.names = TRUE, fill = TRUE),
    wald_table        = rbindlist(wald_list,   use.names = TRUE, fill = TRUE)
  )
}

section_continuous_spei <- function(scope, null_reps = 5L) {
  cat("\n=== Section: continuous_spei (scope =", scope,
      ", null_reps =", null_reps, ") ===\n")
  stopifnot(scope %in% c("10y", "13y"), is.numeric(null_reps), null_reps >= 0L)
  null_reps <- as.integer(null_reps)

  in_file  <- if (scope == "10y") config$align_out_10y       else config$align_out_13y
  out_file <- if (scope == "10y") config$continuous_spei_10y else config$continuous_spei_13y

  if (!file.exists(in_file)) {
    stop("Cache file missing: ", in_file,
         "\n  Run --section=align_weekly --scope=", scope, " first.")
  }
  if (!requireNamespace("fixest", quietly = TRUE)) {
    stop("fixest not installed. Run install.packages('fixest') in container.")
  }
  cat(sprintf("Input:  %s (%.1f GB)\n", basename(in_file), file.size(in_file) / 1e9))
  cat(sprintf("Output: %s\n", basename(out_file)))

  t_section <- Sys.time()

  ANOM_COLS    <- c("ndvi_anom_mean",
                    "deriv_w03_anom_mean", "deriv_w07_anom_mean",
                    "deriv_w14_anom_mean", "deriv_w30_anom_mean")
  SIGNAL_NAMES <- c("ndvi_z",
                    "deriv_w03_z", "deriv_w07_z", "deriv_w14_z", "deriv_w30_z")
  SPEI_COLS    <- c("spei_4w", "spei_13w", "spei_26w")
  HEADLINE_CELL <- list(spei = "spei_13w", signal = "ndvi_z")
  MIN_VALID_WEEKS <- 30L

  # --- 1. Load cache, slim columns ---
  cat("\n[1] Load align_weekly cache, slim columns...\n")
  dt <- as.data.table(readRDS_retry(in_file))
  cat(sprintf("  raw: %s rows × %d cols\n",
              format(nrow(dt), big.mark = ","), ncol(dt)))
  keep_cols <- c("pixel_id", "iso_year", "iso_week", "week_start",
                 ANOM_COLS, SPEI_COLS, "L2_code", "L2_name")
  dt <- dt[, ..keep_cols]
  gc(verbose = FALSE)

  n_px_in <- uniqueN(dt$pixel_id)
  cat(sprintf("  pixel count: %d (expected %d)\n", n_px_in, EXPECTED_VALID_PIXELS))
  if (n_px_in != EXPECTED_VALID_PIXELS) {
    cat(sprintf("  WARN: pixel drift %d (see feedback_pixel_count_invariant)\n",
                n_px_in - EXPECTED_VALID_PIXELS))
  }

  # --- 2. Per-pixel z-standardize NDVI signals ---
  cat("\n[2] Per-pixel z-standardize 5 NDVI signals...\n")
  setorder(dt, pixel_id, week_start)
  drop_px <- zstandardize_signals_per_pixel(dt, ANOM_COLS, SIGNAL_NAMES,
                                            min_valid_weeks = MIN_VALID_WEEKS)
  if (length(drop_px) > 0L) dt <- dt[!pixel_id %in% drop_px]
  dt[, (ANOM_COLS) := NULL]
  gc(verbose = FALSE)
  cat(sprintf("  after drops: %s rows × %d pixels\n",
              format(nrow(dt), big.mark = ","), uniqueN(dt$pixel_id)))

  # --- 3. Observed FE regression grid (pooled + iso_week FE) ---
  cat("\n[3] Observed FE regression grid (pooled + iso_week)...\n")
  cat("    12 strata × 3 spei × 5 signals × 2 models = 360 fits expected\n")
  eco_codes <- sort(unique(dt$L2_code[!is.na(dt$L2_code)]))
  cat(sprintf("    eco_codes (%d): %s\n", length(eco_codes),
              paste(eco_codes, collapse = ", ")))
  t_fit <- Sys.time()
  fit_table <- run_fe_regression_grid(dt, eco_codes, SPEI_COLS, SIGNAL_NAMES,
                                      model_types = c("pooled", "isowk_fe"))
  cat(sprintf("  observed grid fit in %.1f min\n",
              as.numeric(Sys.time() - t_fit, units = "mins")))

  # --- 4. Per-pixel slope map ---
  cat("\n[4] Per-pixel slope map (closed-form covariance)...\n")
  t_slope <- Sys.time()
  slope_map <- fit_pixel_slope_map(dt, SPEI_COLS, SIGNAL_NAMES,
                                   min_valid_weeks = MIN_VALID_WEEKS)
  cat(sprintf("  %s slope rows in %.1f min\n",
              format(nrow(slope_map), big.mark = ","),
              as.numeric(Sys.time() - t_slope, units = "mins")))

  cat("  Summarizing slope map by ecoregion...\n")
  eco_lookup <- as.data.table(readRDS_retry(config$ecoregion_lookup))
  slope_map_summary <- summarize_slope_map(slope_map, eco_lookup)

  # --- 5. Residual diagnostics on headline cell ---
  cat(sprintf("\n[5] Residual diagnostics for headline (%s ~ %s, pooled)...\n",
              HEADLINE_CELL$signal, HEADLINE_CELL$spei))
  rm(eco_lookup); gc(verbose = FALSE)
  residual_diag <- compute_residual_diagnostics_spei(
    dt, HEADLINE_CELL$spei, HEADLINE_CELL$signal)

  # --- 6. Permutation null (pooled model only) ---
  cat(sprintf("\n[6] Permutation null (%d reps, pooled model only)...\n", null_reps))
  t_null <- Sys.time()
  null_summary <- run_fe_permutation_null_spei(dt, eco_codes, SPEI_COLS,
                                               SIGNAL_NAMES,
                                               n_reps = null_reps)
  cat(sprintf("  null done in %.1f min\n",
              as.numeric(Sys.time() - t_null, units = "mins")))

  # Join null to observed pooled rows
  if (!is.null(null_summary)) {
    obs_pooled <- fit_table[model_type == "pooled",
                            .(stratum, spei_col, signal_col, obs_beta = beta)]
    null_summary <- merge(null_summary, obs_pooled,
                          by = c("stratum", "spei_col", "signal_col"),
                          all = TRUE)
    null_summary[, z_score := (obs_beta - null_mean_beta) / null_sd_beta]
    setcolorder(null_summary, c("stratum", "spei_col", "signal_col",
                                "obs_beta", "null_mean_beta", "null_sd_beta",
                                "n_reps", "z_score"))
  }

  # --- 7. Assemble + save ---
  meta <- list(
    scope             = scope,
    scope_years       = if (scope == "10y") 2016:2025 else 2013:2025,
    null_reps         = null_reps,
    model_types       = c("pooled", "isowk_fe"),
    headline_cell     = HEADLINE_CELL,
    signal_set        = SIGNAL_NAMES,
    spei_set          = SPEI_COLS,
    min_valid_weeks   = MIN_VALID_WEEKS,
    dropped_pixels    = length(drop_px),
    runtime_minutes   = as.numeric(Sys.time() - t_section, units = "mins"),
    created           = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )

  out <- list(
    fit_table         = fit_table,
    slope_map         = slope_map,
    slope_map_summary = slope_map_summary,
    residual_diag     = residual_diag,
    null_summary      = null_summary,
    meta              = meta
  )

  cat(sprintf("\nSaving %s...\n", basename(out_file)))
  saveRDS_validated(out, out_file, compress = "xz")
  cat(sprintf("  wrote %.2f MB in %.1f min total\n",
              file.size(out_file) / 1e6,
              meta$runtime_minutes))

  # --- Quick summary ---
  cat("\n--- Quick summary: midwest_aggregate × spei_13w ---\n")
  mw <- fit_table[stratum == "midwest_aggregate" & spei_col == "spei_13w"]
  for (sig in SIGNAL_NAMES) {
    p <- mw[signal_col == sig & model_type == "pooled"]
    i <- mw[signal_col == sig & model_type == "isowk_fe"]
    cat(sprintf("  %-14s  pooled β=%+.3f (p=%.1e r2=%.3f) | isowk β=%+.3f (p=%.1e r2w=%.3f)\n",
                sig,
                if (nrow(p)) p$beta else NA, if (nrow(p)) p$p else NA,
                if (nrow(p)) p$r2_within else NA,
                if (nrow(i)) i$beta else NA, if (nrow(i)) i$p else NA,
                if (nrow(i)) i$r2_within else NA))
  }
  cat("\n--- Per-ecoregion pooled β (headline: ndvi_z ~ spei_13w) ---\n")
  print(fit_table[spei_col == "spei_13w" & signal_col == "ndvi_z" &
                  model_type == "pooled",
                  .(stratum, beta = round(beta, 4), se = round(se, 4),
                    p = signif(p, 2), r2_within = round(r2_within, 4),
                    n_pixels)][order(-beta)])

  invisible(out)
}

# ==============================================================================
# SECTION: continuous_spei_nlcd
#
# LC-stratified extension of section_continuous_spei. Tests whether the
# 9.2 (Temperate Prairies / corn belt) SPEI reversal is a cropland effect
# by decomposing each targeted ecoregion into crop / forest / grassland strata.
#
# Two complementary analyses:
#   (1) Per-stratum fits — 10 targeted (L2_code x nlcd_juliana) cells, each
#       run with and without a modal_frac >= 0.60 dominance filter. Reuses
#       run_fe_regression_grid via a fused stratum_key column ("9.2|crop|all").
#   (2) Interaction model — per (ecoregion x dom x spei x signal x model_type),
#       fit signal ~ spei + i(nlcd_juliana, spei, ref="crop") [| iso_week]
#       and Wald-test whether the per-LC slopes differ from the reference.
#
# Null model skipped on first pass (null_reps=0); re-run later if needed.
#
# Output: continuous_spei_nlcd_<scope>.rds with fit_table_lc + interaction_table
#         + wald_table + meta. See plan for full schema.
# ==============================================================================

# LC strata cross is built dynamically inside section_continuous_spei_nlcd
# AND section_categorical_usdm_nlcd: full eco x 5 LC tiers.
#
# Urban schema (2026-06-12): the 4 NLCD urban classes collapse to 2 tiers
# along the 50%-impervious break (NLCD's natural med/low boundary):
#   urban_dense   = urban_high (>=80% impervious) + urban_med  (50-79%) -> 737 px Midwest
#   urban_diffuse = urban_low  (20-49% impervious) + urban_open (<20%)  -> 1,833 px Midwest
# Per-class is statistically infeasible (urban_high has only 28 px CONUS-wide
# in our Midwest extent); single "urban" loses the operationally-relevant
# impervious-cover gradient. The collapse to nlcd_juliana_2tier happens
# in-section right after the NLCD join, leaving valid_pixels_nlcd2019.rds
# untouched.
#
# "other" is excluded (2.2% of Midwest, no operational interpretation).
#
# Dominance handling: the 60% modal_frac floor (the "dom" track) annihilates
# the urban sample (urban_dense_dom ~38 px, urban_diffuse_dom ~8 px) because
# 4 km cells are rarely 60% pure dense urban anywhere in CONUS. Urban will
# therefore only carry meaningful sample in the "all" track. We keep the
# global 60% threshold rather than per-LC thresholds to avoid special-casing;
# downstream readers filter urban "dom" rows by n_pixel_weeks.
#
# Statistical reach by ecoregion (no dominance filter, n_pixels):
#   urban_dense:   8.2 (431), 8.1 (100), 9.2 (91), 8.3 (62), rest <50
#   urban_diffuse: 8.2 (705), 8.1 (564), 8.3 (217), 9.2 (214), rest <100
# Only 8.1 + 8.2 cross the 500-px floor in fit_lc_interaction_one_cell for
# urban_diffuse; urban_dense never crosses it. Urban therefore appears in
# the per-stratum fit_table_lc / skill table but not in the LC-interaction
# Wald tests for most ecoregions.
LC_STRATA_LEVELS <- c("crop", "forest", "grassland", "urban_dense", "urban_diffuse")

# Collapse the 4 NLCD urban classes -> 2 tiers (dense/diffuse). Called by both
# section_continuous_spei_nlcd and section_categorical_usdm_nlcd right after
# the NLCD join. Mutates dt in place by overwriting nlcd_juliana. Returns
# invisibly so it can be used inline. "other" + non-urban values pass through.
collapse_urban_to_2tier <- function(dt, lc_col = "nlcd_juliana") {
  stopifnot(lc_col %in% names(dt))
  dt[, (lc_col) := fcase(
    get(lc_col) %in% c("urban_high", "urban_med"),  "urban_dense",
    get(lc_col) %in% c("urban_low",  "urban_open"), "urban_diffuse",
    default = get(lc_col)
  )]
  invisible(NULL)
}

section_continuous_spei_nlcd <- function(scope, null_reps = 0L) {
  cat("\n=== Section: continuous_spei_nlcd (scope =", scope,
      ", null_reps =", null_reps, ") ===\n")
  stopifnot(scope %in% c("10y", "13y"), is.numeric(null_reps), null_reps >= 0L)
  null_reps <- as.integer(null_reps)

  in_file  <- if (scope == "10y") config$align_out_10y           else config$align_out_13y
  out_file <- if (scope == "10y") config$continuous_spei_nlcd_10y else config$continuous_spei_nlcd_13y

  if (!file.exists(in_file)) {
    stop("Cache file missing: ", in_file,
         "\n  Run --section=align_weekly --scope=", scope, " first.")
  }
  if (!file.exists(config$nlcd_pixel_lookup)) {
    stop("NLCD pixel lookup missing: ", config$nlcd_pixel_lookup,
         "\n  Run 00b_extract_nlcd_2019.R first.")
  }
  if (!requireNamespace("fixest", quietly = TRUE)) {
    stop("fixest not installed.")
  }
  cat(sprintf("Input:  %s (%.1f GB)\n", basename(in_file), file.size(in_file) / 1e9))
  cat(sprintf("NLCD:   %s\n", basename(config$nlcd_pixel_lookup)))
  cat(sprintf("Output: %s\n", basename(out_file)))

  t_section <- Sys.time()

  ANOM_COLS    <- c("ndvi_anom_mean",
                    "deriv_w03_anom_mean", "deriv_w07_anom_mean",
                    "deriv_w14_anom_mean", "deriv_w30_anom_mean")
  SIGNAL_NAMES <- c("ndvi_z",
                    "deriv_w03_z", "deriv_w07_z", "deriv_w14_z", "deriv_w30_z")
  SPEI_COLS    <- c("spei_4w", "spei_13w", "spei_26w")
  MIN_VALID_WEEKS <- 30L

  # --- 1. Load cache, slim columns (same as section_continuous_spei) ---
  cat("\n[1] Load align_weekly cache, slim columns...\n")
  dt <- as.data.table(readRDS_retry(in_file))
  cat(sprintf("  raw: %s rows x %d cols\n",
              format(nrow(dt), big.mark = ","), ncol(dt)))
  keep_cols <- c("pixel_id", "iso_year", "iso_week", "week_start",
                 ANOM_COLS, SPEI_COLS, "L2_code", "L2_name")
  dt <- dt[, ..keep_cols]
  gc(verbose = FALSE)

  n_px_in <- uniqueN(dt$pixel_id)
  cat(sprintf("  pixel count: %d (expected %d)\n", n_px_in, EXPECTED_VALID_PIXELS))

  # --- 2. Join NLCD info (pre-flight: no NA after join) ---
  cat("\n[2] Join nlcd_juliana + modal_frac from valid_pixels_nlcd2019.rds...\n")
  v_nlcd <- as.data.table(readRDS_retry(config$nlcd_pixel_lookup))
  stopifnot(all(c("pixel_id", "nlcd_juliana", "modal_frac") %in% names(v_nlcd)))
  dt <- merge(dt, v_nlcd[, .(pixel_id, nlcd_juliana, modal_frac)],
              by = "pixel_id", all.x = TRUE)
  n_na <- sum(is.na(dt$nlcd_juliana))
  if (n_na > 0L) {
    stop(sprintf("Join drift: %d rows have NA nlcd_juliana. Pixel set mismatch ",
                 n_na),
         "between align_weekly cache and valid_pixels_nlcd2019.rds.")
  }
  cat(sprintf("  joined (raw 9-class); LC distribution (rows): %s\n",
              paste(sprintf("%s=%s", names(table(dt$nlcd_juliana)),
                            format(as.integer(table(dt$nlcd_juliana)),
                                   big.mark = ",")),
                    collapse = ", ")))
  collapse_urban_to_2tier(dt)
  cat(sprintf("  after urban 2-tier collapse; LC distribution (rows): %s\n",
              paste(sprintf("%s=%s", names(table(dt$nlcd_juliana)),
                            format(as.integer(table(dt$nlcd_juliana)),
                                   big.mark = ",")),
                    collapse = ", ")))
  rm(v_nlcd); gc(verbose = FALSE)

  # --- 3. z-standardize signals per pixel (same as Section A) ---
  cat("\n[3] z-standardize 5 NDVI signals...\n")
  setorder(dt, pixel_id, week_start)
  drop_px <- zstandardize_signals_per_pixel(dt, ANOM_COLS, SIGNAL_NAMES,
                                            min_valid_weeks = MIN_VALID_WEEKS)
  if (length(drop_px) > 0L) dt <- dt[!pixel_id %in% drop_px]
  dt[, (ANOM_COLS) := NULL]
  gc(verbose = FALSE)
  cat(sprintf("  after drops: %s rows x %d pixels\n",
              format(nrow(dt), big.mark = ","), uniqueN(dt$pixel_id)))

  # --- 4. Build full (eco x LC) cross + fused stratum_key columns ---
  cat("\n[4] Build stratum_key columns (full eco x LC_STRATA_LEVELS cross)...\n")
  eco_codes_all <- sort(unique(dt$L2_code[!is.na(dt$L2_code)]))
  LC_STRATA <- as.data.table(expand.grid(
    L2_code      = eco_codes_all,
    nlcd_juliana = LC_STRATA_LEVELS,
    stringsAsFactors = FALSE
  ))
  LC_STRATA[, key := paste(L2_code, nlcd_juliana, sep = "|")]
  cat(sprintf("  built %d (eco x LC) cells across %d ecoregions x %d LC classes\n",
              nrow(LC_STRATA), length(eco_codes_all), length(LC_STRATA_LEVELS)))

  dt[, lc_eco_key := paste(L2_code, nlcd_juliana, sep = "|")]
  targeted_set <- LC_STRATA$key
  dt[, stratum_key_all := fifelse(lc_eco_key %in% targeted_set,
                                  paste(lc_eco_key, "all", sep = "|"),
                                  NA_character_)]
  dt[, stratum_key_dom := fifelse(lc_eco_key %in% targeted_set &
                                  modal_frac >= config$nlcd_modal_frac_threshold,
                                  paste(lc_eco_key, "dom", sep = "|"),
                                  NA_character_)]
  dt[, lc_eco_key := NULL]

  # Cells with <500 pixels in the SUBSET stage will be skipped by the per-cell
  # n_obs < 1000 floor in fit_fe_spei_one_cell — print a coverage summary so we
  # can see which (eco x LC) cells got dropped.
  cov_all <- dt[, .(n_obs = .N, n_pixels = uniqueN(pixel_id)),
                by = stratum_key_all][!is.na(stratum_key_all)]
  cat(sprintf("  Stratum coverage (all): %d strata with row counts:\n",
              nrow(cov_all)))
  print(cov_all[order(-n_pixels)])
  cov_dom <- dt[, .(n_obs = .N, n_pixels = uniqueN(pixel_id)),
                by = stratum_key_dom][!is.na(stratum_key_dom)]
  cat(sprintf("  Stratum coverage (dom): %d strata with row counts:\n",
              nrow(cov_dom)))
  print(cov_dom[order(-n_pixels)])

  # --- 5. Per-stratum FE regression grid (TWO calls: all + dom) ---
  cat(sprintf("\n[5] Per-stratum grid: %d strata (all+dom) x %d spei x %d signals x 2 models\n",
              length(targeted_set) * 2L, length(SPEI_COLS), length(SIGNAL_NAMES)))
  t_fit <- Sys.time()

  dt_all <- dt[!is.na(stratum_key_all)]
  fit_all <- run_fe_regression_grid(
    dt_all,
    eco_codes         = sort(unique(dt_all$stratum_key_all)),
    spei_cols         = SPEI_COLS,
    signal_cols       = SIGNAL_NAMES,
    model_types       = c("pooled", "isowk_fe"),
    key_col           = "stratum_key_all",
    include_aggregate = FALSE
  )
  rm(dt_all); gc(verbose = FALSE)

  dt_dom <- dt[!is.na(stratum_key_dom)]
  fit_dom <- run_fe_regression_grid(
    dt_dom,
    eco_codes         = sort(unique(dt_dom$stratum_key_dom)),
    spei_cols         = SPEI_COLS,
    signal_cols       = SIGNAL_NAMES,
    model_types       = c("pooled", "isowk_fe"),
    key_col           = "stratum_key_dom",
    include_aggregate = FALSE
  )
  rm(dt_dom); gc(verbose = FALSE)

  fit_table_lc <- rbindlist(list(fit_all, fit_dom), use.names = TRUE, fill = TRUE)
  # Parse the fused stratum back into (L2_code, nlcd_juliana, dom_filter).
  parts <- tstrsplit(fit_table_lc$stratum, "|", fixed = TRUE)
  fit_table_lc[, `:=`(L2_code      = parts[[1]],
                      nlcd_juliana = parts[[2]],
                      dom_filter   = parts[[3]])]
  setcolorder(fit_table_lc, c("stratum", "L2_code", "nlcd_juliana", "dom_filter",
                              "spei_col", "signal_col", "model_type",
                              "beta", "se", "t", "p", "r2_within",
                              "n_obs", "n_pixels", "note"))
  cat(sprintf("  per-stratum grid: %d rows in %.1f min\n",
              nrow(fit_table_lc),
              as.numeric(Sys.time() - t_fit, units = "mins")))

  # --- 6. LC interaction grid (per ecoregion, FULL — all eco_codes_all) ---
  cat(sprintf("\n[6] Interaction grid: %d eco x 2 dom x %d spei x %d signals x 2 models\n",
              length(eco_codes_all), length(SPEI_COLS), length(SIGNAL_NAMES)))
  t_int <- Sys.time()
  int_out <- run_lc_interaction_grid(
    dt,
    eco_codes            = eco_codes_all,
    spei_cols            = SPEI_COLS,
    signal_cols          = SIGNAL_NAMES,
    model_types          = c("pooled", "isowk_fe"),
    lc_col               = "nlcd_juliana",
    dom_variants         = c("all", "dom"),
    modal_frac_threshold = config$nlcd_modal_frac_threshold,
    min_pixels_per_lc    = config$nlcd_min_pixels_per_stratum
  )
  cat(sprintf("  interaction grid: %d slope rows + %d wald rows in %.1f min\n",
              nrow(int_out$interaction_table), nrow(int_out$wald_table),
              as.numeric(Sys.time() - t_int, units = "mins")))

  # --- 7. Sanity vs Section A (warn-only) ---
  # Section A's best 9.4 cell was spei_26w (β=+0.184). LC-restricted version
  # should be at least as positive (full ecoregion dilutes the grass signal).
  sanity_row <- fit_table_lc[stratum == "9.4|grassland|all" &
                             spei_col == "spei_26w" & signal_col == "ndvi_z" &
                             model_type == "pooled"]
  cat("\n[7] Sanity (9.4|grassland|all x spei_26w x ndvi_z x pooled):\n")
  if (nrow(sanity_row) == 1L && !is.na(sanity_row$beta)) {
    in_range <- sanity_row$beta >= 0.16 && sanity_row$beta <= 0.25
    cat(sprintf("  beta = %+.4f  (expect [+0.16, +0.25] vs Section A's +0.182)\n",
                sanity_row$beta))
    if (!in_range) {
      cat("  WARN: LC-stratified 9.4|grassland beta diverges from Section A baseline.\n")
    }
  } else {
    cat("  WARN: sanity row not present or NA — investigate.\n")
  }

  # --- 8. Assemble + save ---
  meta <- list(
    scope             = scope,
    scope_years       = if (scope == "10y") 2016:2025 else 2013:2025,
    lc_strata         = LC_STRATA,
    interaction_ecoregions = eco_codes_all,
    lc_strata_levels  = LC_STRATA_LEVELS,
    nlcd_modal_frac_threshold   = config$nlcd_modal_frac_threshold,
    nlcd_min_pixels_per_stratum = config$nlcd_min_pixels_per_stratum,
    null_reps         = null_reps,    # 0 on first pass
    model_types       = c("pooled", "isowk_fe"),
    signal_set        = SIGNAL_NAMES,
    spei_set          = SPEI_COLS,
    min_valid_weeks   = MIN_VALID_WEEKS,
    dropped_pixels    = length(drop_px),
    runtime_minutes   = as.numeric(Sys.time() - t_section, units = "mins"),
    created           = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )

  out <- list(
    fit_table_lc      = fit_table_lc,
    interaction_table = int_out$interaction_table,
    wald_table        = int_out$wald_table,
    meta              = meta
  )

  cat(sprintf("\nSaving %s...\n", basename(out_file)))
  saveRDS_validated(out, out_file, compress = "xz")
  cat(sprintf("  wrote %.2f MB in %.1f min total\n",
              file.size(out_file) / 1e6, meta$runtime_minutes))

  # --- Quick summary: print full headline-cell tables across all eco x LC ---
  options(datatable.print.nrows = 200L, datatable.print.topn = 200L)

  cat("\n--- Full per-stratum table (headline cell: spei_13w x ndvi_z x pooled), sorted by beta ---\n")
  print(fit_table_lc[spei_col == "spei_13w" & signal_col == "ndvi_z" &
                     model_type == "pooled",
                     .(stratum, beta = round(beta, 4), se = round(se, 4),
                       p = signif(p, 2), r2_within = round(r2_within, 4),
                       n_pixels, note)][order(beta)])

  cat("\n--- Same, but spei_26w (Section A's headline for 9.4) ---\n")
  print(fit_table_lc[spei_col == "spei_26w" & signal_col == "ndvi_z" &
                     model_type == "pooled",
                     .(stratum, beta = round(beta, 4), se = round(se, 4),
                       p = signif(p, 2), r2_within = round(r2_within, 4),
                       n_pixels, note)][order(beta)])

  cat("\n--- Full Wald 'slopes differ' table (headline: spei_13w x ndvi_z x pooled), sorted by chi2 ---\n")
  print(int_out$wald_table[spei_col == "spei_13w" & signal_col == "ndvi_z" &
                           model_type == "pooled",
                           .(L2_code, dom_filter,
                             wald_chi2 = round(wald_chi2, 1),
                             wald_df, wald_p = signif(wald_p, 3),
                             n_lc_levels, note)][order(-wald_chi2)])

  cat("\n--- Full per-LC slopes table (headline: spei_13w x ndvi_z x pooled, dom=all) ---\n")
  print(int_out$interaction_table[dom_filter == "all" & spei_col == "spei_13w" &
                                  signal_col == "ndvi_z" & model_type == "pooled",
                                  .(L2_code, lc_level,
                                    beta = round(beta, 4),
                                    se   = round(se, 4),
                                    p    = signif(p, 2),
                                    n_pixels, note)][order(L2_code, lc_level)])

  invisible(out)
}

# ==============================================================================
# SECTION: categorical_usdm_nlcd
#
# LC-stratified extension of section_categorical_usdm (v3). Mirror of
# section_continuous_spei_nlcd, but on the USDM side: decomposes each
# ecoregion into crop / forest / grassland strata and runs the two-track
# skill sweep (binary + ordinal) + Spearman correlation on each (eco x LC).
#
# Reuses v3 machinery unchanged: build_lead_K, run_two_track_sweep,
# run_two_track_correlation. Per-cell stratification flows through the
# `key_col` argument on the two sweep helpers (fused stratum_key column).
#
# Two complementary stratum sets:
#   (1) "all" — every pixel in (eco x LC), no dominance filter
#   (2) "dom" — modal_frac >= nlcd_modal_frac_threshold (0.60) only
#
# Skipped on first pass (matches continuous_spei_nlcd):
#   - Permutation null (would mirror v3's null loop calling run_two_track_sweep
#     with shuffled USDM; default null_reps=0 to keep first run < 1 hr)
#   - Contingency tables (v3 had per-(stratum x sig_bin x usdm_change); with
#     LC the cell count explodes and isn't the headline)
#   - LC-interaction model (no clean single-equation analog for skill metrics
#     -- POD/FAR/HSS aren't slopes, so the Wald test from continuous_spei_nlcd
#     doesn't transfer)
#
# Output: usdm_confusion_nlcd_<scope>.rds
#   skill_binary_lc         per (eco x LC x K x signal x dir x z_threshold)
#   skill_ordinal_lc        per (eco x LC x K x signal x dir x z_threshold x usdm_change_threshold)
#   correlation_binary_lc   per (eco x LC x K x signal)
#   correlation_ordinal_lc  per (eco x LC x K x signal)
#   meta                    scope, lc_strata, runtime, etc.
# ==============================================================================

section_categorical_usdm_nlcd <- function(scope, null_reps = 0L) {
  cat("\n=== Section: categorical_usdm_nlcd (scope =", scope,
      ", null_reps =", null_reps, ") ===\n")
  stopifnot(scope %in% c("10y", "13y"), is.numeric(null_reps), null_reps >= 0L)
  null_reps <- as.integer(null_reps)
  if (null_reps > 0L) {
    cat("  NOTE: null model not implemented in this section on first pass.\n")
    cat("        null_reps will be stored in meta but no null loop will run.\n")
    cat("        To enable, mirror v3 section_categorical_usdm's null loop\n")
    cat("        passing key_col = stratum_key_all / stratum_key_dom.\n")
  }

  in_file  <- if (scope == "10y") config$align_out_10y           else config$align_out_13y
  out_file <- if (scope == "10y") config$usdm_confusion_nlcd_10y else config$usdm_confusion_nlcd_13y

  if (!file.exists(in_file)) {
    stop("Cache file missing: ", in_file,
         "\n  Run --section=align_weekly --scope=", scope, " first.")
  }
  if (!file.exists(config$nlcd_pixel_lookup)) {
    stop("NLCD pixel lookup missing: ", config$nlcd_pixel_lookup,
         "\n  Run 00b_extract_nlcd_2019.R first.")
  }
  cat(sprintf("Input:  %s (%.1f GB)\n", basename(in_file), file.size(in_file) / 1e9))
  cat(sprintf("NLCD:   %s\n", basename(config$nlcd_pixel_lookup)))
  cat(sprintf("Output: %s\n", basename(out_file)))

  t_section <- Sys.time()

  Z_THRESHOLDS_NEG           <- c(-0.5, -1.0, -1.5, -2.0, -2.5)
  Z_THRESHOLDS_POS           <- c( 0.5,  1.0,  1.5,  2.0,  2.5)
  USDM_CHANGE_THRESHOLDS_POS <- 1:3
  USDM_CHANGE_THRESHOLDS_NEG <- -(1:3)
  K_VALUES                   <- c(1L, 2L, 4L, 8L)
  MIN_VALID_WEEKS            <- 30L

  ANOM_COLS    <- c("ndvi_anom_mean",
                    "deriv_w03_anom_mean", "deriv_w07_anom_mean",
                    "deriv_w14_anom_mean", "deriv_w30_anom_mean")
  SIGNAL_NAMES <- c("ndvi_z",
                    "deriv_w03_z", "deriv_w07_z", "deriv_w14_z", "deriv_w30_z")

  # --- 1. Load cache + USDM in-analysis recode (matches v3) -----------------
  cat("\n[1] Load cache + USDM in-analysis recode...\n")
  dt <- as.data.table(readRDS_retry(in_file))
  cat(sprintf("  raw: %s rows x %d cols\n",
              format(nrow(dt), big.mark = ","), ncol(dt)))
  keep_cols <- c("pixel_id", "iso_year", "iso_week", "week_start",
                 ANOM_COLS, "usdm", "L2_code", "L2_name")
  dt <- dt[, ..keep_cols]
  dt[, usdm_ord   := as.integer(usdm) + 1L]
  dt[, in_drought := usdm_ord >= 1L]
  dt[, usdm := NULL]
  gc(verbose = FALSE)

  n_px_in <- uniqueN(dt$pixel_id)
  cat(sprintf("  pixel count: %d (expected %d)\n", n_px_in, EXPECTED_VALID_PIXELS))
  if (n_px_in != EXPECTED_VALID_PIXELS) {
    cat(sprintf("  WARN: pixel drift %d (see feedback_pixel_count_invariant)\n",
                n_px_in - EXPECTED_VALID_PIXELS))
  }
  na_rate <- 100 * mean(is.na(dt$usdm_ord))
  cat(sprintf("  USDM recoded scale {0..5}: %.2f%% None | %.2f%% in_drought | %.2f%% NA\n",
              100 * mean(dt$usdm_ord == 0L, na.rm = TRUE),
              100 * mean(dt$in_drought,      na.rm = TRUE),
              na_rate))
  if (na_rate > 5.0) {
    cat(sprintf("  WARN: USDM NA rate %.2f%% exceeds 5%% -- investigate align_weekly join.\n",
                na_rate))
  }

  # --- 2. Join NLCD info (matches continuous_spei_nlcd) ---------------------
  cat("\n[2] Join nlcd_juliana + modal_frac from valid_pixels_nlcd2019.rds...\n")
  v_nlcd <- as.data.table(readRDS_retry(config$nlcd_pixel_lookup))
  stopifnot(all(c("pixel_id", "nlcd_juliana", "modal_frac") %in% names(v_nlcd)))
  dt <- merge(dt, v_nlcd[, .(pixel_id, nlcd_juliana, modal_frac)],
              by = "pixel_id", all.x = TRUE)
  n_na <- sum(is.na(dt$nlcd_juliana))
  if (n_na > 0L) {
    stop(sprintf("Join drift: %d rows have NA nlcd_juliana. Pixel set mismatch ",
                 n_na),
         "between align_weekly cache and valid_pixels_nlcd2019.rds.")
  }
  cat(sprintf("  joined (raw 9-class); LC distribution (rows): %s\n",
              paste(sprintf("%s=%s", names(table(dt$nlcd_juliana)),
                            format(as.integer(table(dt$nlcd_juliana)),
                                   big.mark = ",")),
                    collapse = ", ")))
  collapse_urban_to_2tier(dt)
  cat(sprintf("  after urban 2-tier collapse; LC distribution (rows): %s\n",
              paste(sprintf("%s=%s", names(table(dt$nlcd_juliana)),
                            format(as.integer(table(dt$nlcd_juliana)),
                                   big.mark = ",")),
                    collapse = ", ")))
  rm(v_nlcd); gc(verbose = FALSE)

  # --- 3. z-standardize 5 NDVI signals --------------------------------------
  cat("\n[3] z-standardize 5 NDVI signals (per-pixel)...\n")
  setorder(dt, pixel_id, week_start)
  drop_px <- zstandardize_signals_per_pixel(dt, ANOM_COLS, SIGNAL_NAMES,
                                            min_valid_weeks = MIN_VALID_WEEKS)
  if (length(drop_px) > 0L) dt <- dt[!pixel_id %in% drop_px]
  dt[, (ANOM_COLS) := NULL]
  gc(verbose = FALSE)
  cat(sprintf("  after drops: %s rows x %d pixels\n",
              format(nrow(dt), big.mark = ","), uniqueN(dt$pixel_id)))

  # --- 4. True lead-K USDM via self-join (matches v3) -----------------------
  cat(sprintf("\n[4] Build lead-K USDM (true self-join, K = %s)...\n",
              paste(K_VALUES, collapse = ",")))
  build_lead_K(dt, K_VALUES)

  for (K in K_VALUES) {
    change_col <- sprintf("usdm_change_%d", K)
    onset_col  <- sprintf("onset_%d", K)
    end_col    <- sprintf("end_%d", K)
    cat(sprintf("  K=%d: change non-NA %.2f%% | range [%+d, %+d] | onset %.3f%% | end %.3f%%\n",
                K,
                100 * mean(!is.na(dt[[change_col]])),
                min(dt[[change_col]], na.rm = TRUE),
                max(dt[[change_col]], na.rm = TRUE),
                100 * mean(dt[[onset_col]], na.rm = TRUE),
                100 * mean(dt[[end_col]],   na.rm = TRUE)))
  }

  # --- 5. Build full (eco x LC) cross + fused stratum_key columns -----------
  cat("\n[5] Build stratum_key columns (full eco x LC_STRATA_LEVELS cross)...\n")
  eco_codes_all <- sort(unique(dt$L2_code[!is.na(dt$L2_code)]))
  LC_STRATA <- as.data.table(expand.grid(
    L2_code      = eco_codes_all,
    nlcd_juliana = LC_STRATA_LEVELS,
    stringsAsFactors = FALSE
  ))
  LC_STRATA[, key := paste(L2_code, nlcd_juliana, sep = "|")]
  cat(sprintf("  built %d (eco x LC) cells across %d ecoregions x %d LC classes\n",
              nrow(LC_STRATA), length(eco_codes_all), length(LC_STRATA_LEVELS)))

  dt[, lc_eco_key := paste(L2_code, nlcd_juliana, sep = "|")]
  targeted_set <- LC_STRATA$key
  dt[, stratum_key_all := fifelse(lc_eco_key %in% targeted_set,
                                  paste(lc_eco_key, "all", sep = "|"),
                                  NA_character_)]
  dt[, stratum_key_dom := fifelse(lc_eco_key %in% targeted_set &
                                  modal_frac >= config$nlcd_modal_frac_threshold,
                                  paste(lc_eco_key, "dom", sep = "|"),
                                  NA_character_)]
  dt[, lc_eco_key := NULL]

  cov_all <- dt[, .(n_obs = .N, n_pixels = uniqueN(pixel_id)),
                by = stratum_key_all][!is.na(stratum_key_all)]
  cat(sprintf("  Stratum coverage (all): %d strata with row counts:\n",
              nrow(cov_all)))
  print(cov_all[order(-n_pixels)])
  cov_dom <- dt[, .(n_obs = .N, n_pixels = uniqueN(pixel_id)),
                by = stratum_key_dom][!is.na(stratum_key_dom)]
  cat(sprintf("  Stratum coverage (dom): %d strata with row counts:\n",
              nrow(cov_dom)))
  print(cov_dom[order(-n_pixels)])

  # --- 6. Two-track skill sweep (TWO calls: all + dom) ----------------------
  cat(sprintf("\n[6] Skill sweep: %d strata (all+dom) x %d K x %d signals\n",
              length(targeted_set) * 2L, length(K_VALUES), length(SIGNAL_NAMES)))
  t_skill <- Sys.time()

  dt_all <- dt[!is.na(stratum_key_all)]
  obs_all <- run_two_track_sweep(dt_all,
                                  eco_codes         = sort(unique(dt_all$stratum_key_all)),
                                  K_values          = K_VALUES,
                                  signal_names      = SIGNAL_NAMES,
                                  z_neg             = Z_THRESHOLDS_NEG,
                                  z_pos             = Z_THRESHOLDS_POS,
                                  change_pos        = USDM_CHANGE_THRESHOLDS_POS,
                                  change_neg        = USDM_CHANGE_THRESHOLDS_NEG,
                                  label             = "obs-all",
                                  key_col           = "stratum_key_all",
                                  include_aggregate = FALSE)
  rm(dt_all); gc(verbose = FALSE)

  dt_dom <- dt[!is.na(stratum_key_dom)]
  obs_dom <- run_two_track_sweep(dt_dom,
                                  eco_codes         = sort(unique(dt_dom$stratum_key_dom)),
                                  K_values          = K_VALUES,
                                  signal_names      = SIGNAL_NAMES,
                                  z_neg             = Z_THRESHOLDS_NEG,
                                  z_pos             = Z_THRESHOLDS_POS,
                                  change_pos        = USDM_CHANGE_THRESHOLDS_POS,
                                  change_neg        = USDM_CHANGE_THRESHOLDS_NEG,
                                  label             = "obs-dom",
                                  key_col           = "stratum_key_dom",
                                  include_aggregate = FALSE)
  rm(dt_dom); gc(verbose = FALSE)

  skill_binary_lc  <- rbindlist(list(obs_all$binary,  obs_dom$binary),
                                use.names = TRUE, fill = TRUE)
  skill_ordinal_lc <- rbindlist(list(obs_all$ordinal, obs_dom$ordinal),
                                use.names = TRUE, fill = TRUE)
  cat(sprintf("  skill sweep: binary %d rows + ordinal %d rows in %.1f min\n",
              nrow(skill_binary_lc), nrow(skill_ordinal_lc),
              as.numeric(Sys.time() - t_skill, units = "mins")))

  # --- 7. Two-track Spearman correlation (TWO calls: all + dom) -------------
  cat(sprintf("\n[7] Spearman correlation: %d strata (all+dom) x %d K x %d signals\n",
              length(targeted_set) * 2L, length(K_VALUES), length(SIGNAL_NAMES)))
  t_corr <- Sys.time()

  dt_all <- dt[!is.na(stratum_key_all)]
  corr_all <- run_two_track_correlation(dt_all,
                                         eco_codes         = sort(unique(dt_all$stratum_key_all)),
                                         K_values          = K_VALUES,
                                         signal_names      = SIGNAL_NAMES,
                                         key_col           = "stratum_key_all",
                                         include_aggregate = FALSE,
                                         label             = "corr-all")
  rm(dt_all); gc(verbose = FALSE)

  dt_dom <- dt[!is.na(stratum_key_dom)]
  corr_dom <- run_two_track_correlation(dt_dom,
                                         eco_codes         = sort(unique(dt_dom$stratum_key_dom)),
                                         K_values          = K_VALUES,
                                         signal_names      = SIGNAL_NAMES,
                                         key_col           = "stratum_key_dom",
                                         include_aggregate = FALSE,
                                         label             = "corr-dom")
  rm(dt_dom); gc(verbose = FALSE)

  correlation_binary_lc  <- rbindlist(list(corr_all$binary,  corr_dom$binary),
                                       use.names = TRUE, fill = TRUE)
  correlation_ordinal_lc <- rbindlist(list(corr_all$ordinal, corr_dom$ordinal),
                                       use.names = TRUE, fill = TRUE)
  cat(sprintf("  correlation: binary %d rows + ordinal %d rows in %.1f min\n",
              nrow(correlation_binary_lc), nrow(correlation_ordinal_lc),
              as.numeric(Sys.time() - t_corr, units = "mins")))

  # --- 8. Parse fused stratum -> (L2_code, nlcd_juliana, dom_filter) --------
  # The sweep/correlation helpers write the stratum_id into the L2_code column
  # (legacy naming). Parse it back to per-source components for downstream use.
  # L2_name is joined from a per-ecoregion lookup. Done AFTER the parse so the
  # original stratum_id is preserved in the parse rather than overwritten.
  cat("\n[8] Parse fused stratum_id back to (L2_code, nlcd_juliana, dom_filter)...\n")
  L2_name_lookup <- unique(dt[!is.na(L2_code), .(L2_code, L2_name)])

  parse_and_label <- function(tbl) {
    tbl[, stratum_id := L2_code]   # preserve original fused key
    parts <- tstrsplit(tbl$stratum_id, "|", fixed = TRUE)
    tbl[, `:=`(L2_code      = parts[[1]],
               nlcd_juliana = parts[[2]],
               dom_filter   = parts[[3]])]
    tbl <- merge(tbl, L2_name_lookup, by = "L2_code", all.x = TRUE, sort = FALSE)
    tbl
  }

  skill_binary_lc        <- parse_and_label(skill_binary_lc)
  skill_ordinal_lc       <- parse_and_label(skill_ordinal_lc)
  correlation_binary_lc  <- parse_and_label(correlation_binary_lc)
  correlation_ordinal_lc <- parse_and_label(correlation_ordinal_lc)

  setcolorder(skill_binary_lc,
              c("stratum_id", "L2_code", "L2_name", "nlcd_juliana", "dom_filter",
                "stratum_type", "K", "ndvi_signal",
                "direction", "z_threshold", "n_pixel_weeks",
                "tp", "fp", "fn", "tn", "pod", "far", "csi", "hss"))
  setcolorder(skill_ordinal_lc,
              c("stratum_id", "L2_code", "L2_name", "nlcd_juliana", "dom_filter",
                "stratum_type", "K", "ndvi_signal",
                "direction", "z_threshold", "usdm_change_threshold",
                "n_pixel_weeks", "tp", "fp", "fn", "tn",
                "pod", "far", "csi", "hss"))
  setcolorder(correlation_binary_lc,
              c("stratum_id", "L2_code", "L2_name", "nlcd_juliana", "dom_filter",
                "stratum_type", "K", "ndvi_signal",
                "n_pixel_weeks", "spearman_rho_neg_signal"))
  setcolorder(correlation_ordinal_lc,
              c("stratum_id", "L2_code", "L2_name", "nlcd_juliana", "dom_filter",
                "stratum_type", "K", "ndvi_signal",
                "n_pixel_weeks", "spearman_rho_neg_signal"))
  setorder(skill_binary_lc,        L2_code, nlcd_juliana, dom_filter, K, ndvi_signal,
                                    direction, z_threshold)
  setorder(skill_ordinal_lc,       L2_code, nlcd_juliana, dom_filter, K, ndvi_signal,
                                    direction, z_threshold, usdm_change_threshold)
  setorder(correlation_binary_lc,  L2_code, nlcd_juliana, dom_filter, K, ndvi_signal)
  setorder(correlation_ordinal_lc, L2_code, nlcd_juliana, dom_filter, K, ndvi_signal)

  # --- 9. Sanity vs v3 (warn-only) ------------------------------------------
  # v3 categorical_usdm headline within-drought ρ at K=4, ndvi_z, midwest_aggregate
  # was ~0 (small +/-). LC-stratified should sit in roughly the same range when
  # weighted-averaged across crop+forest+grass. We don't compute the full
  # weighted average here; just print 9.2-crop's ρ as a smoke check (expected
  # negative, since 9.2 reverses on the SPEI side and we expect similar on USDM).
  cat("\n[9] Sanity check (9.2|crop|all, K=4, ndvi_z within-drought correlation):\n")
  sanity_row <- correlation_ordinal_lc[L2_code == "9.2" & nlcd_juliana == "crop" &
                                       dom_filter == "all" & K == 4L &
                                       ndvi_signal == "ndvi_z"]
  if (nrow(sanity_row) == 1L && !is.na(sanity_row$spearman_rho_neg_signal)) {
    cat(sprintf("  rho_neg_signal = %+.4f  (n_pixel_weeks = %s)\n",
                sanity_row$spearman_rho_neg_signal,
                format(sanity_row$n_pixel_weeks, big.mark = ",")))
  } else {
    cat("  WARN: sanity row not present or NA -- investigate.\n")
  }

  # --- 10. Assemble + save --------------------------------------------------
  meta <- list(
    scope             = scope,
    scope_years       = if (scope == "10y") 2016:2025 else 2013:2025,
    version           = "v1_lc_stratified_two_track",
    lc_strata         = LC_STRATA,
    lc_strata_levels  = LC_STRATA_LEVELS,
    nlcd_modal_frac_threshold   = config$nlcd_modal_frac_threshold,
    nlcd_min_pixels_per_stratum = config$nlcd_min_pixels_per_stratum,
    n_pixels_in       = n_px_in,
    n_pixels_dropped  = length(drop_px),
    n_pixels_kept     = n_px_in - length(drop_px),
    z_thresholds_negative      = Z_THRESHOLDS_NEG,
    z_thresholds_positive      = Z_THRESHOLDS_POS,
    K_values                   = K_VALUES,
    usdm_change_thresholds_pos = USDM_CHANGE_THRESHOLDS_POS,
    usdm_change_thresholds_neg = USDM_CHANGE_THRESHOLDS_NEG,
    min_valid_weeks            = MIN_VALID_WEEKS,
    signal_set                 = SIGNAL_NAMES,
    usdm_recode_in_analysis    = "usdm_ord = usdm + 1L; in_drought = usdm_ord >= 1L; raw -1 sentinel = None; D0-D4 = 1-5",
    lead_K_method              = "self-join on (pixel_id, week_start + 7K) -- NOT running max",
    null_reps                  = null_reps,
    null_implementation_note   = "Null model not implemented in this section on first pass; mirror v3 categorical_usdm null loop passing key_col arg if needed",
    runtime_minutes            = as.numeric(Sys.time() - t_section, units = "mins"),
    created                    = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )

  out <- list(
    skill_binary_lc        = skill_binary_lc,
    skill_ordinal_lc       = skill_ordinal_lc,
    correlation_binary_lc  = correlation_binary_lc,
    correlation_ordinal_lc = correlation_ordinal_lc,
    meta                   = meta
  )

  cat(sprintf("\nSaving %s...\n", basename(out_file)))
  saveRDS_validated(out, out_file, compress = "xz")
  cat(sprintf("  wrote %.2f MB in %.1f min total\n",
              file.size(out_file) / 1e6, meta$runtime_minutes))

  # --- 11. Quick summary ----------------------------------------------------
  options(datatable.print.nrows = 200L, datatable.print.topn = 200L)

  cat("\n--- Per-stratum within-drought Spearman rho (K=4, ndvi_z, dom=all), sorted by rho ---\n")
  print(correlation_ordinal_lc[K == 4L & ndvi_signal == "ndvi_z" & dom_filter == "all",
                                .(L2_code, nlcd_juliana,
                                  rho = round(spearman_rho_neg_signal, 4),
                                  n   = n_pixel_weeks)][order(rho)])

  cat("\n--- Per-stratum recovery HSS (K=4, ndvi_z, z=+1.5, dom=all), sorted by HSS ---\n")
  print(skill_binary_lc[K == 4L & ndvi_signal == "ndvi_z" &
                         direction == "recovery" & z_threshold == 1.5 &
                         dom_filter == "all",
                         .(L2_code, nlcd_juliana,
                           hss = round(hss, 4),
                           pod = round(pod, 3),
                           far = round(far, 3),
                           n   = n_pixel_weeks)][order(-hss)])

  cat("\n--- Per-stratum intensification HSS (K=4, ndvi_z, z=-1.5, dom=all), sorted by HSS ---\n")
  print(skill_binary_lc[K == 4L & ndvi_signal == "ndvi_z" &
                         direction == "intensification" & z_threshold == -1.5 &
                         dom_filter == "all",
                         .(L2_code, nlcd_juliana,
                           hss = round(hss, 4),
                           pod = round(pod, 3),
                           far = round(far, 3),
                           n   = n_pixel_weeks)][order(-hss)])

  invisible(out)
}

# ==============================================================================
# SECTION: event_detection
#
# Anchored on USDM transitions, measure the lead/lag of our NDVI signals.
# Uses weekly grain (per Section C diagnostic gate decision: within-week SD is
# only 22-35% of across-week SD, so weekly aggregation preserves the signal).
#
# Events tracked:
#   onset:    none → D0 (dm_max = -1 → 0)        — earliest USDM signal
#   recovery: any drought → none (≥0 → -1)       — exit signal
#
# Two grains of events:
#   per-pixel events:        chronological transitions per pixel. ~10-15M rows.
#                            For spatial maps of lead/lag.
#   ecoregion-aggregate:     per (L2 × week), in_drought fraction change ≥
#                            MAJORITY_DELTA = 0.10. Catches coordinated regional
#                            events. (User initially suggested ≥50%; that's
#                            structurally rare in 4 km USDM data.)
#
# Signal fire detection (weekly grain):
#   For each (pixel × signal × z × K), find runs of K consecutive weeks where
#   signal_z ≤ -z (onset direction) or ≥ +z (recovery direction). First week
#   of a qualifying run = the fire time. ndvi_z + 4 derivative windows = 5
#   signals.
#
# Operating-point sweep:
#   z_threshold  ∈ {1.0, 1.5, 2.0}                — magnitude threshold
#   K (weeks)    ∈ {1, 2, 4}                      — sustained-weeks requirement
#   lead_window  ∈ {4, 8, 12} weeks               — search radius around event
#   5 NDVI signals × 2 directions                 — magnitude + 4 derivatives
#
# Total ops per direction: 5 signals × 3 z × 3 K = 45 fire tables per dir,
# 90 across dirs. × 3 lead_windows for matching = 270 op-points per stratum.
#
# Per-cell skill: hit_rate, FAR (false alarms per pixel-year), median lead_weeks
# + percentile distribution, n_events.
#
# Permutation null: 5 reps default. Shuffle event dates within (pixel × season)
# and re-match to (unchanged) fires. Fires don't need re-detection.
#
# Outputs in event_detection_<scope>.rds:
#   events_pixel       — per-pixel USDM transitions
#   events_ecoregion   — ecoregion-aggregate events
#   skill_pixel        — per (L2 × event_type × signal × op_point) skill
#   skill_ecoregion    — same shape, ecoregion-aggregate events
#   lead_distributions — percentile distribution of lead_weeks per cell
#   pixel_event_map    — per pixel × event_type × headline op_point (for maps)
#   null_summary       — per-cell observed vs null skill metrics
#   meta               — scope, op_points, runtime, etc.
# ==============================================================================

# Headline op-points used for pixel_event_map (two ops chosen post-hoc;
# spatial maps kept only at these ops to control output size). Magnitude
# (ndvi_z) and 2-week derivative (deriv_w14_z) so we can compare magnitude
# vs derivative spatial patterns directly.
EVENT_HEADLINES <- list(
  list(signal = "ndvi_z",      z = 1.5, K = 2L, lead_window = 8L),
  list(signal = "deriv_w14_z", z = 1.5, K = 2L, lead_window = 8L)
)

#' Build per-pixel USDM transitions. Returns one row per transition.
#'   event_type ∈ {"onset", "recovery"}
#'   onset:    usdm_lag = -1, usdm_curr ≥ 0  (none → any drought, captures D0+)
#'   recovery: usdm_lag ≥ 0, usdm_curr = -1  (any drought → none)
build_pixel_events <- function(usdm_dt) {
  setorder(usdm_dt, pixel_id, iso_year, iso_week)
  usdm_dt[, usdm_lag := shift(usdm, 1L, type = "lag"), by = pixel_id]

  onset_dt <- usdm_dt[!is.na(usdm_lag) & usdm_lag == -1L & usdm >= 0L,
                      .(pixel_id, iso_year, iso_week, week_start,
                        event_type = "onset", usdm_pre = usdm_lag,
                        usdm_post = usdm)]
  recov_dt <- usdm_dt[!is.na(usdm_lag) & usdm_lag >= 0L & usdm == -1L,
                      .(pixel_id, iso_year, iso_week, week_start,
                        event_type = "recovery", usdm_pre = usdm_lag,
                        usdm_post = usdm)]
  rbindlist(list(onset_dt, recov_dt), use.names = TRUE)
}

#' Build ecoregion-aggregate events from per-pixel USDM trace. For each
#' (L2 × week), compute the in_drought fraction; an aggregate event = week
#' where the week-over-week change in that fraction exceeds majority_delta.
#'   onset:    +majority_delta (in_drought fraction rises by ≥10pp w/w)
#'   recovery: -majority_delta (in_drought fraction falls by ≥10pp w/w)
build_ecoregion_events <- function(usdm_dt, majority_delta = 0.10) {
  setorder(usdm_dt, L2_code, iso_year, iso_week)
  weekly_frac <- usdm_dt[!is.na(L2_code) & !is.na(usdm),
                         .(in_drought_frac = mean(usdm >= 0L),
                           n_pixels        = .N),
                         by = .(L2_code, L2_name, iso_year, iso_week, week_start)]
  setorder(weekly_frac, L2_code, iso_year, iso_week)
  weekly_frac[, frac_lag := shift(in_drought_frac, 1L, type = "lag"), by = L2_code]
  weekly_frac[, delta := in_drought_frac - frac_lag]

  onset_rows <- weekly_frac[!is.na(delta) & delta >= majority_delta,
                            .(L2_code, L2_name, iso_year, iso_week, week_start,
                              event_type = "onset",
                              in_drought_pre = frac_lag,
                              in_drought_post = in_drought_frac,
                              delta)]
  recov_rows <- weekly_frac[!is.na(delta) & delta <= -majority_delta,
                            .(L2_code, L2_name, iso_year, iso_week, week_start,
                              event_type = "recovery",
                              in_drought_pre = frac_lag,
                              in_drought_post = in_drought_frac,
                              delta)]
  rbindlist(list(onset_rows, recov_rows), use.names = TRUE)
}

#' Detect signal fires per pixel: runs of K consecutive weeks where signal
#' satisfies the threshold in the given direction. Returns one row per
#' (pixel × fire_week_start). fire_week_start = the FIRST week of the run.
#'
#' For very large K relative to a pixel's record, no fires fire. Memory-safe:
#' uses data.table's rleid pattern within pixel groups.
detect_signal_fires_weekly <- function(dt, signal_col, z_threshold,
                                       sustained_weeks, direction) {
  stopifnot(direction %in% c("onset", "recovery"))
  setorder(dt, pixel_id, iso_year, iso_week)

  threshold_test <- if (direction == "onset") {
    quote(is.finite(get(signal_col)) & get(signal_col) <= -z_threshold)
  } else {
    quote(is.finite(get(signal_col)) & get(signal_col) >= z_threshold)
  }

  # Per pixel: find rleid-runs of TRUE, keep those with length >= K, fire week
  # is the first of the run.
  fires <- dt[, {
    flag <- eval(threshold_test)
    if (!any(flag, na.rm = TRUE)) {
      data.table()
    } else {
      run_id  <- rleid(flag)
      run_len <- ave(seq_along(run_id), run_id, FUN = length)
      qual    <- which(flag & run_len >= sustained_weeks)
      if (length(qual) == 0L) {
        data.table()
      } else {
        # Keep only the START of each qualifying run
        run_starts <- qual[!duplicated(run_id[qual])]
        data.table(iso_year   = iso_year[run_starts],
                   iso_week   = iso_week[run_starts],
                   week_start = week_start[run_starts])
      }
    }
  }, by = pixel_id]
  fires
}

#' Match signal fires to events. For each event (pixel × event_date), find the
#' nearest fire within +/- lead_window_weeks. lead_weeks = event_week - fire_week
#' (positive = NDVI led USDM event; negative = NDVI lagged).
#'
#' KNOWN BUG (2026-06-15): the `by = pixel_id` reduction and the subsequent
#' positional assignment back into `events_out` are NOT order-aligned, so per-
#' event hit/lead_weeks values get scrambled within a pixel. Pixel-aggregate
#' counts are also affected. Use `match_fires_to_events_vec` instead; this
#' scalar version is retained only as a reference / corner-case fallback.
#'
#' Returns matches data.table with one row per event:
#'   pixel_id, event_iso_year, event_iso_week, event_week_start, event_type,
#'   hit (logical), lead_weeks, n_fires_in_window
match_fires_to_events <- function(events_dt, fires_dt, lead_window_weeks) {
  if (nrow(fires_dt) == 0L) {
    out <- copy(events_dt)
    out[, `:=`(hit = FALSE, lead_weeks = NA_integer_, n_fires_in_window = 0L)]
    return(out)
  }

  # Compute a numeric week index per pixel for non-equi join
  events_dt[, ev_idx  := as.integer(week_start)]
  fires_dt[,  fr_idx  := as.integer(week_start)]

  # Inner foverlaps would require interval representations; use a manual
  # data.table per-pixel sub-search instead. Cheap because each pixel has
  # few events (~5-15) and few fires (~5-30) over 10y.
  # Build pixel-keyed list and search per event.
  setkey(fires_dt, pixel_id, fr_idx)

  match_one <- function(pid, ev_idx_vec) {
    fires_pid <- fires_dt[.(pid), nomatch = 0L]
    if (nrow(fires_pid) == 0L) {
      return(list(rep(FALSE, length(ev_idx_vec)),
                  rep(NA_integer_, length(ev_idx_vec)),
                  rep(0L, length(ev_idx_vec))))
    }
    n_fires_window <- integer(length(ev_idx_vec))
    lead_weeks_vec <- integer(length(ev_idx_vec))
    hit_vec        <- logical(length(ev_idx_vec))
    fr_idx_pid <- fires_pid$fr_idx
    for (i in seq_along(ev_idx_vec)) {
      delta_days <- ev_idx_vec[i] - fr_idx_pid
      within <- abs(delta_days) <= lead_window_weeks * 7L
      n_fires_window[i] <- sum(within)
      if (n_fires_window[i] == 0L) {
        hit_vec[i]        <- FALSE
        lead_weeks_vec[i] <- NA_integer_
      } else {
        # Nearest fire wins (smallest |delta|); positive lead_weeks = NDVI led
        best <- which.min(abs(delta_days[within]))
        win_idx <- which(within)[best]
        hit_vec[i]        <- TRUE
        lead_weeks_vec[i] <- as.integer(round(delta_days[win_idx] / 7))
      }
    }
    list(hit_vec, lead_weeks_vec, n_fires_window)
  }

  events_out <- copy(events_dt)
  # data.table per-group apply
  res <- events_out[, {
    m <- match_one(pixel_id[1], ev_idx)
    list(hit = m[[1]], lead_weeks = m[[2]], n_fires_in_window = m[[3]])
  }, by = pixel_id]
  events_out[, `:=`(hit = res$hit,
                    lead_weeks = res$lead_weeks,
                    n_fires_in_window = res$n_fires_in_window)]
  events_out[, ev_idx := NULL]
  fires_dt[,  fr_idx := NULL]
  events_out
}

#' Proper false-alarm count: fires that do NOT have ANY event within
#' ±lead_window_weeks. Symmetric to match_fires_to_events but starting from
#' fires instead of events. Returns per-pixel false-alarm count (not rate).
#'
#' Same row-ordering caveat as match_fires_to_events — use
#' `count_false_alarms_vec` for production. This scalar reference can drift by
#' ~1 per several hundred fires vs the vectorized version on random data.
count_false_alarms <- function(fires_dt, events_dt, lead_window_weeks) {
  if (nrow(fires_dt) == 0L) {
    return(data.table(pixel_id = integer(0), false_alarms = integer(0)))
  }
  if (nrow(events_dt) == 0L) {
    # No events at all → every fire is a false alarm
    fa <- fires_dt[, .(false_alarms = .N), by = pixel_id]
    return(fa)
  }

  fires_dt[, fr_idx := as.integer(week_start)]
  events_dt[, ev_idx := as.integer(week_start)]
  setkey(events_dt, pixel_id)
  lead_days <- lead_window_weeks * 7L

  # Per-pixel: for each fire, check if any event within ±lead_days
  fa_per_pixel <- fires_dt[, {
    events_pid <- events_dt[.(pixel_id[1]), nomatch = 0L]
    if (nrow(events_pid) == 0L) {
      .(false_alarms = .N)
    } else {
      ev_idx_pid <- events_pid$ev_idx
      is_fa <- vapply(fr_idx, function(fi) {
        !any(abs(fi - ev_idx_pid) <= lead_days)
      }, logical(1))
      .(false_alarms = sum(is_fa))
    }
  }, by = pixel_id]

  fires_dt[, fr_idx := NULL]
  events_dt[, ev_idx := NULL]
  fa_per_pixel
}

#' Summarize per (L2 × event_type × signal × op_point): hit_rate, false-alarm
#' count (fires NOT matched to any event), median lead_weeks, percentile
#' distribution, n_events. Proper FAR = count_false_alarms / n_fires.
summarize_lead_skill <- function(matches_dt, fires_dt, events_dir_full,
                                 eco_lookup,
                                 signal_col, z_threshold, sustained_weeks,
                                 lead_window_weeks, direction,
                                 grain = c("pixel", "ecoregion")) {
  grain <- match.arg(grain)
  if (grain == "pixel") {
    m <- merge(matches_dt, eco_lookup[, .(pixel_id, L2_code, L2_name)],
               by = "pixel_id", all.x = TRUE)
    by_cols <- c("L2_code", "L2_name", "event_type")
  } else {
    m <- matches_dt
    by_cols <- c("L2_code", "L2_name", "event_type")
  }

  skill <- m[!is.na(L2_code), .(
    n_events     = .N,
    n_hits       = sum(hit, na.rm = TRUE),
    hit_rate     = mean(hit, na.rm = TRUE),
    median_lead  = if (any(hit, na.rm = TRUE)) as.numeric(median(lead_weeks[hit], na.rm = TRUE)) else NA_real_,
    mean_lead    = if (any(hit, na.rm = TRUE)) as.numeric(mean(lead_weeks[hit],   na.rm = TRUE)) else NA_real_,
    p10_lead     = if (any(hit, na.rm = TRUE)) as.numeric(quantile(lead_weeks[hit], 0.10, na.rm = TRUE)) else NA_real_,
    p25_lead     = if (any(hit, na.rm = TRUE)) as.numeric(quantile(lead_weeks[hit], 0.25, na.rm = TRUE)) else NA_real_,
    p75_lead     = if (any(hit, na.rm = TRUE)) as.numeric(quantile(lead_weeks[hit], 0.75, na.rm = TRUE)) else NA_real_,
    p90_lead     = if (any(hit, na.rm = TRUE)) as.numeric(quantile(lead_weeks[hit], 0.90, na.rm = TRUE)) else NA_real_,
    pct_lead_pos = if (any(hit, na.rm = TRUE)) as.numeric(mean(lead_weeks[hit] > 0, na.rm = TRUE)) else NA_real_
  ), by = by_cols]

  # Proper FAR: per-pixel count_false_alarms aggregated to ecoregion
  if (grain == "pixel") {
    fa_per_pixel <- count_false_alarms(fires_dt, events_dir_full, lead_window_weeks)
    fa_per_pixel_eco <- merge(fa_per_pixel,
                              eco_lookup[, .(pixel_id, L2_code, L2_name)],
                              by = "pixel_id", all.x = TRUE)
    fa_per_eco <- fa_per_pixel_eco[!is.na(L2_code),
                                   .(false_alarms = sum(false_alarms)),
                                   by = .(L2_code, L2_name)]
    fires_with_eco <- merge(fires_dt,
                            eco_lookup[, .(pixel_id, L2_code, L2_name)],
                            by = "pixel_id", all.x = TRUE)
    nfires_per_eco <- fires_with_eco[!is.na(L2_code), .(n_fires = .N),
                                     by = .(L2_code, L2_name)]
    fa_eco <- merge(fa_per_eco, nfires_per_eco,
                    by = c("L2_code", "L2_name"), all = TRUE)
    skill <- merge(skill, fa_eco, by = c("L2_code", "L2_name"), all.x = TRUE)
    skill[, false_alarm_rate := false_alarms / n_fires]
  } else {
    skill[, `:=`(n_fires = NA_integer_, false_alarms = NA_integer_,
                 false_alarm_rate = NA_real_)]
  }

  skill[, `:=`(signal_col      = signal_col,
               z_threshold     = z_threshold,
               sustained_weeks = sustained_weeks,
               lead_window     = lead_window_weeks,
               direction       = direction,
               grain           = grain)]
  skill
}

#' Match fires to ecoregion-aggregate events. For each eco-aggregate event
#' (L2 × week), find fires (from any pixel in that L2) within ±lead_window.
#' "Hit" = at least MAJORITY_DELTA fraction of L2's pixels fired in window
#' (mirrors how the eco event itself was defined).
match_fires_to_eco_events <- function(events_eco_dt, fires_dt, eco_lookup,
                                      lead_window_weeks,
                                      majority_delta = 0.10) {
  if (nrow(fires_dt) == 0L || nrow(events_eco_dt) == 0L) {
    out <- copy(events_eco_dt)
    out[, `:=`(hit = FALSE, lead_weeks = NA_integer_,
               n_fires_in_window = 0L, frac_pixels_firing = 0)]
    return(out)
  }

  # Join L2_code to fires + count eco size
  fires_e <- merge(fires_dt, eco_lookup[, .(pixel_id, L2_code)],
                   by = "pixel_id")
  eco_sizes <- eco_lookup[, .N, by = L2_code]
  setnames(eco_sizes, "N", "eco_n_pixels")

  fires_e[, fr_idx := as.integer(week_start)]
  events_out <- copy(events_eco_dt)
  events_out[, ev_idx := as.integer(week_start)]
  lead_days <- lead_window_weeks * 7L

  # Pre-index fires by L2 for cheap subsetting
  setkey(fires_e, L2_code)

  res <- events_out[, {
    l2 <- L2_code[1]
    fp <- fires_e[.(l2), nomatch = 0L]
    if (nrow(fp) == 0L) {
      list(n_fires_in_window = rep(0L, .N),
           n_pixels_firing   = rep(0L, .N),
           lead_weeks        = rep(NA_integer_, .N))
    } else {
      n_fires_w <- integer(.N)
      n_pix_w   <- integer(.N)
      lead_w    <- integer(.N)
      ev_ix     <- ev_idx
      for (i in seq_len(.N)) {
        delta_days <- ev_ix[i] - fp$fr_idx
        within <- abs(delta_days) <= lead_days
        n_fires_w[i] <- sum(within)
        if (n_fires_w[i] > 0L) {
          n_pix_w[i] <- uniqueN(fp$pixel_id[within])
          # Median lead across firing pixels (positive = NDVI led)
          lead_w[i] <- as.integer(round(median(delta_days[within]) / 7))
        } else {
          n_pix_w[i] <- 0L
          lead_w[i]  <- NA_integer_
        }
      }
      list(n_fires_in_window = n_fires_w,
           n_pixels_firing   = n_pix_w,
           lead_weeks        = lead_w)
    }
  }, by = L2_code]

  events_out[, `:=`(n_fires_in_window = res$n_fires_in_window,
                    n_pixels_firing   = res$n_pixels_firing,
                    lead_weeks        = res$lead_weeks)]
  events_out <- merge(events_out, eco_sizes, by = "L2_code", all.x = TRUE)
  events_out[, frac_pixels_firing := n_pixels_firing / eco_n_pixels]
  events_out[, hit := frac_pixels_firing >= majority_delta]
  events_out[, ev_idx := NULL]
  events_out
}

#' Process one direction × (signal × z × K) cell, iterating across leads.
#' Detects fires ONCE per (signal × z × K × direction), then iterates lead
#' windows for matching + FAR. ~3x speedup over per-lead fire detection.
process_signal_cell <- function(dt, events_pixel, events_eco, eco_lookup,
                                signal_col, z_threshold, sustained_weeks,
                                lead_windows, direction, majority_delta = 0.10) {
  # Detect fires once
  fires <- detect_signal_fires_weekly(dt, signal_col, z_threshold,
                                       sustained_weeks, direction)
  if (nrow(fires) == 0L) {
    cat(sprintf("    [%s z=%g K=%d %s] 0 fires\n",
                signal_col, z_threshold, sustained_weeks, direction))
    return(list(skill_pixel = list(), skill_eco = list(), headline = list(),
                fires_cache = NULL))
  }

  events_dir_pixel <- events_pixel[event_type == direction]
  events_dir_eco   <- events_eco[event_type == direction]

  pix_results <- vector("list", length(lead_windows))
  eco_results <- vector("list", length(lead_windows))
  hdl_results <- list()

  for (i in seq_along(lead_windows)) {
    lead <- lead_windows[i]
    # Per-pixel match + FAR
    matches_pix <- match_fires_to_events(events_dir_pixel, fires, lead)
    pix_results[[i]] <- summarize_lead_skill(matches_pix, fires,
                                             events_dir_pixel, eco_lookup,
                                             signal_col, z_threshold,
                                             sustained_weeks, lead, direction,
                                             grain = "pixel")
    # Eco match
    matches_eco <- match_fires_to_eco_events(events_dir_eco, fires, eco_lookup,
                                             lead, majority_delta)
    eco_results[[i]] <- summarize_lead_skill(matches_eco, fires,
                                             events_dir_eco, eco_lookup,
                                             signal_col, z_threshold,
                                             sustained_weeks, lead, direction,
                                             grain = "ecoregion")
    # Headline check
    is_headline <- vapply(EVENT_HEADLINES, function(h) {
      signal_col == h$signal && z_threshold == h$z &&
        sustained_weeks == h$K && lead == h$lead_window
    }, logical(1))
    if (any(is_headline)) {
      hdl_results[[length(hdl_results) + 1L]] <-
        matches_pix[, .(pixel_id, headline_signal = signal_col,
                        event_type = direction, hit, lead_weeks)]
    }
  }

  # Return fires too — fires_cache is used by null re-match. Each (signal × z ×
  # K × dir) fire set is paired with all its lead windows.
  fires_cache_entries <- lapply(lead_windows, function(lead) {
    list(fires = fires, signal_col = signal_col,
         z_threshold = z_threshold, sustained_weeks = sustained_weeks,
         lead_window_weeks = lead, direction = direction)
  })

  list(skill_pixel = pix_results,
       skill_eco   = eco_results,
       headline    = hdl_results,
       fires_cache = fires_cache_entries)
}

#' Main op-point grid loop. Iterates (signal × z × K × direction) and
#' processes all lead_windows inside via process_signal_cell. Returns skill
#' tables, headline maps, AND fires_cache for the null re-match path.
run_event_grid <- function(dt, events_pixel, events_eco, eco_lookup,
                           signals, z_thresholds, K_weeks, lead_windows,
                           directions = c("onset", "recovery"),
                           majority_delta = 0.10) {
  n_cells <- length(signals) * length(z_thresholds) * length(K_weeks) *
             length(directions)
  total_ops <- n_cells * length(lead_windows)
  cat(sprintf("  %d (signal × z × K × dir) cells × %d leads = %d total op-points\n",
              n_cells, length(lead_windows), total_ops))

  skill_pix_list <- list()
  skill_eco_list <- list()
  headline_list  <- list()
  fires_cache    <- list()
  cell_idx <- 0L
  t_start <- Sys.time()

  for (sig in signals) {
    for (z in z_thresholds) {
      for (K in K_weeks) {
        for (dir_ in directions) {
          cell_idx <- cell_idx + 1L
          res <- process_signal_cell(dt, events_pixel, events_eco, eco_lookup,
                                     sig, z, K, lead_windows, dir_,
                                     majority_delta = majority_delta)
          skill_pix_list <- c(skill_pix_list, res$skill_pixel)
          skill_eco_list <- c(skill_eco_list, res$skill_eco)
          headline_list  <- c(headline_list,  res$headline)
          if (!is.null(res$fires_cache)) {
            fires_cache <- c(fires_cache, res$fires_cache)
          }
          if (cell_idx %% 6L == 0L) {
            elapsed <- as.numeric(Sys.time() - t_start, units = "mins")
            cat(sprintf("    cell %d/%d (%.1f min, ETA %.1f min)\n",
                        cell_idx, n_cells, elapsed,
                        elapsed * (n_cells - cell_idx) / cell_idx))
          }
        }
      }
    }
  }
  cat(sprintf("  observed grid: %d cells (%d ops) in %.1f min\n",
              cell_idx, total_ops,
              as.numeric(Sys.time() - t_start, units = "mins")))

  list(skill_pixel     = rbindlist(skill_pix_list, use.names = TRUE, fill = TRUE),
       skill_ecoregion = rbindlist(skill_eco_list, use.names = TRUE, fill = TRUE),
       headline_map    = if (length(headline_list))
                           rbindlist(headline_list, use.names = TRUE, fill = TRUE)
                         else data.table(),
       fires_cache     = fires_cache)
}

#' Permutation null: shuffle event dates within (pixel × season) and re-match
#' to (unchanged) fires. Fires don't need re-detection — they're a property of
#' the NDVI signal, not the USDM target. Each rep re-runs match + summarize for
#' all op-points. Output: per-cell observed vs null mean hit_rate / median_lead.
run_event_permutation_null <- function(dt, events_pixel, fires_cache,
                                       eco_lookup, n_reps, seed_base = 8675309L) {
  if (n_reps <= 0L) {
    cat("  (null_reps = 0; skipping permutation null)\n")
    return(NULL)
  }
  if (!"season" %in% names(events_pixel)) {
    events_pixel[, season := month_to_season(lubridate::month(week_start))]
  }

  null_skill_list <- list()
  for (rep in seq_len(n_reps)) {
    set.seed(seed_base + rep)
    cat(sprintf("\n  --- null rep %d/%d ---\n", rep, n_reps))
    t0 <- Sys.time()

    # Shuffle event dates within (pixel × season).
    ev_shuf <- copy(events_pixel)
    ev_shuf[, week_start := sample(week_start), by = .(pixel_id, season)]
    cat(sprintf("    shuffle done (%.1f sec); matching...\n",
                as.numeric(Sys.time() - t0, units = "secs")))

    rep_skill <- vector("list", length(fires_cache))
    for (i in seq_along(fires_cache)) {
      f <- fires_cache[[i]]
      ev_dir <- ev_shuf[event_type == f$direction]
      matches <- match_fires_to_events(ev_dir, f$fires, f$lead_window_weeks)
      sk <- summarize_lead_skill(matches, f$fires, ev_dir, eco_lookup,
                                 f$signal_col, f$z_threshold, f$sustained_weeks,
                                 f$lead_window_weeks, f$direction, grain = "pixel")
      sk[, rep := rep]
      rep_skill[[i]] <- sk
    }
    null_skill_list[[rep]] <- rbindlist(rep_skill, use.names = TRUE, fill = TRUE)
    cat(sprintf("    rep %d done in %.1f min\n", rep,
                as.numeric(Sys.time() - t0, units = "mins")))
  }

  all_null <- rbindlist(null_skill_list, use.names = TRUE, fill = TRUE)
  all_null[, .(null_mean_hit_rate    = mean(hit_rate, na.rm = TRUE),
               null_sd_hit_rate      = sd(hit_rate,   na.rm = TRUE),
               null_mean_median_lead = mean(median_lead, na.rm = TRUE),
               null_sd_median_lead   = sd(median_lead,   na.rm = TRUE),
               n_reps                = .N),
           by = .(L2_code, event_type, signal_col, z_threshold, sustained_weeks,
                  lead_window, direction)]
}

# ==============================================================================
# Helpers for section_event_detection_nlcd (LC-stratified + SPEI integration)
# ==============================================================================

#' Vectorized replacement for match_fires_to_events. Same input/output schema,
#' replaces the per-pixel for-loop with a single non-equi data.table join. ~5-10x
#' faster on the full Midwest population; identical results on the smoke fixture.
#'
#' For each event, returns the nearest fire within ±lead_window_weeks (in weeks).
#'   hit               = TRUE if any fire in window
#'   lead_weeks        = event_week - fire_week (positive = NDVI led USDM)
#'   n_fires_in_window = number of fires in the window
match_fires_to_events_vec <- function(events_dt, fires_dt, lead_window_weeks) {
  if (nrow(fires_dt) == 0L) {
    out <- copy(events_dt)
    out[, `:=`(hit = FALSE, lead_weeks = NA_integer_, n_fires_in_window = 0L)]
    return(out)
  }
  events_out <- copy(events_dt)
  events_out[, ev_idx := as.integer(week_start)]
  events_out[, ev_row := .I]
  f <- copy(fires_dt)
  f[, fr_idx := as.integer(week_start)]
  lead_days <- lead_window_weeks * 7L

  # Non-equi join: join on pixel_id, narrow to events within ±lead_days of each
  # fire. allow.cartesian = TRUE because events × fires can multiply per pixel.
  ef <- f[events_out, on = "pixel_id", allow.cartesian = TRUE,
          .(ev_row, pixel_id, ev_idx, fr_idx,
            lag_days = i.ev_idx - fr_idx)]
  ef <- ef[!is.na(fr_idx) & abs(lag_days) <= lead_days]

  if (nrow(ef) == 0L) {
    events_out[, `:=`(hit = FALSE, lead_weeks = NA_integer_,
                      n_fires_in_window = 0L)]
  } else {
    ef[, abs_lag := abs(lag_days)]
    # Per event: count fires + nearest fire's lag
    summary_dt <- ef[, .(n_fires_in_window = .N,
                         best_lag_days     = lag_days[which.min(abs_lag)]),
                     by = ev_row]
    events_out[, `:=`(hit = FALSE, lead_weeks = NA_integer_,
                      n_fires_in_window = 0L)]
    events_out[summary_dt, on = "ev_row",
               `:=`(hit               = TRUE,
                    lead_weeks        = as.integer(round(i.best_lag_days / 7)),
                    n_fires_in_window = i.n_fires_in_window)]
  }
  events_out[, c("ev_idx", "ev_row") := NULL]
  events_out
}

#' Vectorized replacement for count_false_alarms. Returns per-pixel
#' false_alarms count (fires with NO event within ±lead_window_weeks).
count_false_alarms_vec <- function(fires_dt, events_dt, lead_window_weeks) {
  if (nrow(fires_dt) == 0L) {
    return(data.table(pixel_id = integer(0), false_alarms = integer(0)))
  }
  f <- copy(fires_dt)
  f[, fr_row := .I]
  f[, fr_idx := as.integer(week_start)]

  if (nrow(events_dt) == 0L) {
    # No events → every fire is a false alarm
    return(f[, .(false_alarms = .N), by = pixel_id])
  }

  e <- copy(events_dt)
  e[, ev_idx := as.integer(week_start)]
  lead_days <- lead_window_weeks * 7L

  # Non-equi join: keep fire-event pairs within window
  fe <- e[f, on = "pixel_id", allow.cartesian = TRUE,
          .(fr_row, pixel_id, fr_idx, ev_idx,
            lag_days = ev_idx - fr_idx)]
  matched_fr_rows <- fe[!is.na(ev_idx) & abs(lag_days) <= lead_days,
                        unique(fr_row)]
  # False alarms = fires NOT in matched_fr_rows
  f[, is_fa := !(fr_row %in% matched_fr_rows)]
  fa_per_pixel <- f[is_fa == TRUE, .(false_alarms = .N), by = pixel_id]
  # Fill in pixels with zero false alarms (so downstream merge handles them)
  zero_px <- setdiff(unique(f$pixel_id), fa_per_pixel$pixel_id)
  if (length(zero_px) > 0L) {
    fa_per_pixel <- rbind(fa_per_pixel,
                          data.table(pixel_id = zero_px, false_alarms = 0L))
  }
  fa_per_pixel
}

#' Detect fires once globally for a (signal × z × K × direction) cell. Wrapper
#' around detect_signal_fires_weekly that returns NULL fast when no fires fire,
#' and tags the fires with the signal_col so downstream code can carry them in
#' a single rbindlist.
detect_fires_global <- function(dt, signal_col, z_threshold, sustained_weeks,
                                direction, is_raw_spei = FALSE) {
  # SPEI is raw (not z-scored); same direction logic, same per-pixel rleid pattern.
  # detect_signal_fires_weekly already handles is.finite filter.
  fires <- detect_signal_fires_weekly(dt, signal_col, z_threshold,
                                      sustained_weeks, direction)
  if (nrow(fires) == 0L) return(NULL)
  fires[, `:=`(signal_col      = signal_col,
               z_threshold     = z_threshold,
               sustained_weeks = sustained_weeks,
               direction       = direction,
               is_raw_spei     = is_raw_spei)]
  fires
}

#' Extract SPEI trajectory descriptors per event. For each event (one row in
#' events_dt with pixel_id + week_start), pull the weekly SPEI series in
#' [-lookback, +lookforward] weeks and compute summary descriptors using
#' spei_13w as the canonical window plus mean of spei_4w/spei_26w in the same
#' window for context.
#'
#' Returns events_dt augmented with these columns:
#'   spei13_at_event       SPEI value at the event week
#'   spei13_mean_pre       mean of spei_13w in [-lookback, -1]
#'   spei13_mean_post      mean of spei_13w in [0, +lookforward]
#'   spei13_min_window     min of spei_13w over the full window
#'   spei13_max_window     max of spei_13w over the full window
#'   spei13_trend_post     OLS slope of spei_13w vs week-offset in the post window
#'   spei13_crossed_m1     TRUE if any spei_13w ≤ -1 in window
#'   spei13_crossed_m15    TRUE if any spei_13w ≤ -1.5 in window
#'   spei4_mean_window     mean of spei_4w  over the full window (short-window context)
#'   spei26_mean_window    mean of spei_26w over the full window (long-window context)
extract_spei_trajectory_per_event <- function(events_dt, weekly_dt,
                                              lookback = 8L, lookforward = 8L,
                                              pixel_chunk = 5000L) {
  stopifnot(all(c("pixel_id", "week_start") %in% names(events_dt)),
            all(c("pixel_id", "week_start", "spei_4w", "spei_13w", "spei_26w") %in%
                names(weekly_dt)))

  spei_cols <- c("spei13_at_event", "spei13_mean_pre", "spei13_mean_post",
                 "spei13_min_window", "spei13_max_window", "spei13_trend_post",
                 "spei4_mean_window", "spei26_mean_window")
  bool_cols <- c("spei13_crossed_m1", "spei13_crossed_m15")

  if (nrow(events_dt) == 0L) {
    cat("    (no events; skipping SPEI trajectory extraction)\n")
    out <- copy(events_dt)
    for (col in spei_cols) out[, (col) := NA_real_]
    for (col in bool_cols) out[, (col) := NA]
    return(out)
  }

  cat(sprintf("    extracting SPEI trajectory for %s events (window ±%dw)...\n",
              format(nrow(events_dt), big.mark = ","), max(lookback, lookforward)))
  t0 <- Sys.time()

  ev <- copy(events_dt)
  ev[, ev_idx := as.integer(week_start)]
  ev[, ev_row := .I]

  # Chunk events by pixel_id to bound memory of the non-equi join.
  pixel_batches <- split(unique(ev$pixel_id),
                         ceiling(seq_along(unique(ev$pixel_id)) / pixel_chunk))
  cat(sprintf("      %d pixel chunks of <= %d pixels each\n",
              length(pixel_batches), pixel_chunk))

  desc_list <- vector("list", length(pixel_batches))
  for (bi in seq_along(pixel_batches)) {
    pxs <- pixel_batches[[bi]]
    ev_b <- ev[pixel_id %in% pxs]
    w_b  <- weekly_dt[pixel_id %in% pxs,
                      .(pixel_id, week_start, spei_4w, spei_13w, spei_26w)]
    w_b[, w_idx := as.integer(week_start)]

    # Per-pixel cartesian join is bounded: ev pixel rows × ~520 weekly rows per
    # pixel for that single chunk only.
    ew <- w_b[ev_b, on = "pixel_id", allow.cartesian = TRUE,
              .(ev_row, w_idx, ev_idx,
                spei_4w, spei_13w, spei_26w,
                week_offset = (w_idx - ev_idx) %/% 7L)]
    ew <- ew[!is.na(w_idx) &
             week_offset >= -lookback &
             week_offset <=  lookforward]

    desc_list[[bi]] <- ew[, .(
      spei13_at_event    = {
        x <- spei_13w[week_offset == 0]
        if (length(x) > 0L && is.finite(x[1])) x[1] else NA_real_
      },
      spei13_mean_pre    = {
        x <- spei_13w[week_offset < 0 & is.finite(spei_13w)]
        if (length(x) > 0L) mean(x) else NA_real_
      },
      spei13_mean_post   = {
        x <- spei_13w[week_offset >= 0 & is.finite(spei_13w)]
        if (length(x) > 0L) mean(x) else NA_real_
      },
      spei13_min_window  = {
        x <- spei_13w[is.finite(spei_13w)]
        if (length(x) > 0L) min(x) else NA_real_
      },
      spei13_max_window  = {
        x <- spei_13w[is.finite(spei_13w)]
        if (length(x) > 0L) max(x) else NA_real_
      },
      spei13_trend_post  = {
        ok <- week_offset >= 0 & is.finite(spei_13w)
        x  <- spei_13w[ok]
        wk <- week_offset[ok]
        if (length(x) >= 3L && stats::sd(wk) > 0) {
          unname(stats::coef(stats::lm(x ~ wk))[2])
        } else {
          NA_real_
        }
      },
      spei13_crossed_m1  = any(spei_13w <= -1.0, na.rm = TRUE),
      spei13_crossed_m15 = any(spei_13w <= -1.5, na.rm = TRUE),
      spei4_mean_window  = {
        x <- spei_4w[is.finite(spei_4w)]
        if (length(x) > 0L) mean(x) else NA_real_
      },
      spei26_mean_window = {
        x <- spei_26w[is.finite(spei_26w)]
        if (length(x) > 0L) mean(x) else NA_real_
      }
    ), by = ev_row]

    if (bi %% 5L == 0L || bi == length(pixel_batches)) {
      cat(sprintf("      chunk %d/%d done (%.1f min elapsed)\n",
                  bi, length(pixel_batches),
                  as.numeric(Sys.time() - t0, units = "mins")))
    }
    rm(ev_b, w_b, ew); gc(verbose = FALSE)
  }
  desc <- rbindlist(desc_list, use.names = TRUE, fill = TRUE)
  rm(desc_list); gc(verbose = FALSE)

  out <- copy(events_dt)
  out[, ev_row := .I]
  out <- merge(out, desc, by = "ev_row", all.x = TRUE)
  out[, ev_row := NULL]
  # Defensive: any event without window matches → set bools to FALSE
  for (col in bool_cols) {
    out[is.na(get(col)), (col) := FALSE]
  }
  cat(sprintf("      SPEI trajectory done in %.1f min\n",
              as.numeric(Sys.time() - t0, units = "mins")))
  out
}

#' Compute a per-stratum 2×2 contingency for HSS/ETS using the temporal-block
#' formulation. Each (pixel × block) cell is a trial:
#'   event_in_block = any USDM event in block (of this event_type/direction)
#'   fire_in_block  = any matching NDVI fire in block (of this signal × op-point)
#'
#' Returns one row per stratum × direction with hits/misses/false_alarms/
#' correct_negatives + n_blocks_total. Caller computes POD/FAR/HSS/ETS from it.
#'
#'   events_dt       — events filtered to direction; needs pixel_id + week_start
#'   fires_dt        — fires for one (signal × z × K × direction); needs
#'                     pixel_id + week_start (the start week of the run)
#'   stratum_map     — data.table mapping pixel_id → stratum_key
#'   block_weeks     — bin width in weeks (4 default)
#'   period_weeks    — total study period in weeks (for n_blocks_total)
compute_temporal_block_contingency <- function(events_dt, fires_dt, stratum_map,
                                               block_weeks = 4L,
                                               period_start_wk, period_end_wk) {
  # block_id = floor((week_idx - period_start) / block_weeks)
  period_start_idx <- as.integer(period_start_wk)
  period_end_idx   <- as.integer(period_end_wk)
  n_blocks <- as.integer(ceiling((period_end_idx - period_start_idx + 1L) /
                                 (block_weeks * 7L)))

  # Build (pixel × block) flags from events and fires
  ev_blk <- if (nrow(events_dt) == 0L) {
    data.table(pixel_id = integer(0), block_id = integer(0))
  } else {
    e <- copy(events_dt)
    e[, block_id := as.integer((as.integer(week_start) - period_start_idx) %/%
                               (block_weeks * 7L))]
    unique(e[, .(pixel_id, block_id)])
  }

  fr_blk <- if (nrow(fires_dt) == 0L) {
    data.table(pixel_id = integer(0), block_id = integer(0))
  } else {
    f <- copy(fires_dt)
    f[, block_id := as.integer((as.integer(week_start) - period_start_idx) %/%
                               (block_weeks * 7L))]
    unique(f[, .(pixel_id, block_id)])
  }

  # Combine into a single flag table over the pixels in stratum_map.
  ev_blk[, event_flag := TRUE]
  fr_blk[, fire_flag  := TRUE]
  both <- merge(ev_blk, fr_blk, by = c("pixel_id", "block_id"), all = TRUE)
  both[is.na(event_flag), event_flag := FALSE]
  both[is.na(fire_flag),  fire_flag  := FALSE]

  # Restrict to pixels in stratum_map; merge stratum_key
  both <- merge(both, stratum_map, by = "pixel_id")
  if (nrow(both) == 0L) {
    return(data.table(stratum_key = character(0),
                      hits = integer(0), misses = integer(0),
                      false_alarms = integer(0), correct_negatives = integer(0),
                      n_blocks_total = integer(0)))
  }

  # Per-stratum non-zero counts (any cell with event or fire)
  nonzero <- both[, .(hits         = sum(event_flag &  fire_flag),
                      misses       = sum(event_flag & !fire_flag),
                      false_alarms = sum(!event_flag & fire_flag)),
                  by = stratum_key]
  # Correct negatives = total cells in stratum - any non-zero cells
  stratum_n_pix <- stratum_map[, .N, by = stratum_key]
  setnames(stratum_n_pix, "N", "n_pixels")
  out <- merge(stratum_n_pix, nonzero, by = "stratum_key", all.x = TRUE)
  for (col in c("hits", "misses", "false_alarms")) {
    out[is.na(get(col)), (col) := 0L]
  }
  out[, n_blocks_total    := n_pixels * n_blocks]
  out[, correct_negatives := n_blocks_total - hits - misses - false_alarms]
  out[, n_pixels := NULL]
  out[]
}

#' Append POD/FAR/HSS/ETS/Bias columns to a contingency table.
compute_skill_metrics <- function(cont_dt) {
  out <- copy(cont_dt)
  H  <- as.numeric(out$hits)
  M  <- as.numeric(out$misses)
  FA <- as.numeric(out$false_alarms)
  CN <- as.numeric(out$correct_negatives)
  N  <- H + M + FA + CN
  E  <- (H + M) * (H + FA) / pmax(N, 1)  # expected hits under independence

  out[, `:=`(
    pod  = H / pmax(H + M, 1),
    far  = FA / pmax(H + FA, 1),
    bias = (H + FA) / pmax(H + M, 1),
    hss  = (2 * (H * CN - M * FA)) /
           pmax((H + M) * (M + CN) + (H + FA) * (FA + CN), 1),
    ets  = (H - E) / pmax(H + M + FA - E, 1)
  )]
  # Handle degenerate cells: zero events OR zero positives → metrics NA
  out[(H + M) == 0L, `:=`(pod = NA_real_, bias = NA_real_,
                          hss = NA_real_, ets = NA_real_)]
  out[(H + FA) == 0L, `:=`(far = NA_real_, bias = NA_real_)]
  out[]
}

section_event_detection <- function(scope, null_reps = 5L) {
  cat("\n=== Section: event_detection (scope =", scope,
      ", null_reps =", null_reps, ", grain = WEEKLY) ===\n")
  stopifnot(scope %in% c("10y", "13y"), is.numeric(null_reps), null_reps >= 0L)
  null_reps <- as.integer(null_reps)

  in_file  <- if (scope == "10y") config$align_out_10y        else config$align_out_13y
  out_file <- if (scope == "10y") config$event_detection_10y  else config$event_detection_13y
  if (!file.exists(in_file)) {
    stop("Cache file missing: ", in_file,
         "\n  Run --section=align_weekly --scope=", scope, " first.")
  }
  cat(sprintf("Input:  %s (%.1f GB)\n", basename(in_file), file.size(in_file) / 1e9))
  cat(sprintf("Output: %s\n", basename(out_file)))

  t_section <- Sys.time()

  ANOM_COLS    <- c("ndvi_anom_mean",
                    "deriv_w03_anom_mean", "deriv_w07_anom_mean",
                    "deriv_w14_anom_mean", "deriv_w30_anom_mean")
  SIGNAL_NAMES <- c("ndvi_z",
                    "deriv_w03_z", "deriv_w07_z", "deriv_w14_z", "deriv_w30_z")
  Z_THRESHOLDS <- c(1.0, 1.5, 2.0)
  K_WEEKS      <- c(1L, 2L, 4L)
  LEAD_WINDOWS <- c(4L, 8L, 12L)
  MAJORITY_DELTA  <- 0.10
  MIN_VALID_WEEKS <- 30L

  # --- 1. Load cache, slim, z-standardize ---
  cat("\n[1] Load cache, slim, z-standardize 5 NDVI signals...\n")
  dt <- as.data.table(readRDS_retry(in_file))
  keep_cols <- c("pixel_id", "iso_year", "iso_week", "week_start",
                 ANOM_COLS, "usdm", "L2_code", "L2_name")
  dt <- dt[, ..keep_cols]
  gc(verbose = FALSE)

  drop_px <- zstandardize_signals_per_pixel(dt, ANOM_COLS, SIGNAL_NAMES,
                                            min_valid_weeks = MIN_VALID_WEEKS)
  if (length(drop_px) > 0L) dt <- dt[!pixel_id %in% drop_px]
  dt[, (ANOM_COLS) := NULL]
  gc(verbose = FALSE)

  # --- 2. Build USDM events (pixel + ecoregion-aggregate) ---
  cat("\n[2] Build USDM events (pixel + ecoregion-aggregate)...\n")
  events_pixel <- build_pixel_events(dt[, .(pixel_id, iso_year, iso_week,
                                            week_start, usdm)])
  cat(sprintf("  Per-pixel events: %s onset + %s recovery\n",
              format(sum(events_pixel$event_type == "onset"), big.mark = ","),
              format(sum(events_pixel$event_type == "recovery"), big.mark = ",")))

  events_eco <- build_ecoregion_events(
    dt[, .(pixel_id, iso_year, iso_week, week_start, usdm, L2_code, L2_name)],
    majority_delta = MAJORITY_DELTA)
  cat(sprintf("  Eco-aggregate events (≥%.0f%% w/w shift): %d onset + %d recovery\n",
              100 * MAJORITY_DELTA,
              sum(events_eco$event_type == "onset"),
              sum(events_eco$event_type == "recovery")))

  eco_lookup <- as.data.table(readRDS_retry(config$ecoregion_lookup))

  # --- 3. Observed op-point grid ---
  cat("\n[3] Observed op-point grid...\n")
  grid_out <- run_event_grid(dt, events_pixel, events_eco, eco_lookup,
                             signals       = SIGNAL_NAMES,
                             z_thresholds  = Z_THRESHOLDS,
                             K_weeks       = K_WEEKS,
                             lead_windows  = LEAD_WINDOWS)

  # --- 4. Lead distributions table (sliced from skill_pixel) ---
  cat("\n[4] Lead distribution table (per cell percentiles)...\n")
  lead_distributions <- grid_out$skill_pixel[, .(
    L2_code, L2_name, event_type, signal_col, z_threshold, sustained_weeks,
    lead_window, direction, n_events, n_hits, hit_rate,
    p10_lead, p25_lead, median_lead, p75_lead, p90_lead,
    mean_lead, pct_lead_pos
  )]

  # --- 5. Permutation null (reuses fires_cache from grid run — no re-detection) ---
  cat(sprintf("\n[5] Permutation null (re-match against %d cached fire-tables)...\n",
              length(grid_out$fires_cache)))
  null_summary <- run_event_permutation_null(dt, events_pixel,
                                             grid_out$fires_cache,
                                             eco_lookup, n_reps = null_reps)

  # --- 6. Assemble + save ---
  meta <- list(
    scope               = scope,
    scope_years         = if (scope == "10y") 2016:2025 else 2013:2025,
    null_reps           = null_reps,
    grain               = "weekly",
    signals             = SIGNAL_NAMES,
    z_thresholds        = Z_THRESHOLDS,
    K_weeks             = K_WEEKS,
    lead_windows        = LEAD_WINDOWS,
    majority_delta      = MAJORITY_DELTA,
    event_headlines     = EVENT_HEADLINES,
    dropped_pixels      = length(drop_px),
    runtime_minutes     = as.numeric(Sys.time() - t_section, units = "mins"),
    created             = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )

  out <- list(
    events_pixel       = events_pixel,
    events_ecoregion   = events_eco,
    skill_pixel        = grid_out$skill_pixel,
    skill_ecoregion    = grid_out$skill_ecoregion,
    lead_distributions = lead_distributions,
    pixel_event_map    = grid_out$headline_map,
    null_summary       = null_summary,
    meta               = meta
  )

  cat(sprintf("\nSaving %s...\n", basename(out_file)))
  saveRDS_validated(out, out_file, compress = "xz")
  cat(sprintf("  wrote %.2f MB in %.1f min total\n",
              file.size(out_file) / 1e6, meta$runtime_minutes))

  # --- Quick summary ---
  cat("\n--- Quick summary: hit rate per ecoregion (ndvi_z, z=1.5, K=2, lead=8w) ---\n")
  q <- grid_out$skill_pixel[signal_col == "ndvi_z" & z_threshold == 1.5 &
                            sustained_weeks == 2L & lead_window == 8L &
                            !L2_code %in% c("0.0", "8.5")]
  print(q[order(direction, -hit_rate),
          .(L2_code, event_type, n_events, hit_rate = round(hit_rate, 3),
            median_lead, false_alarm_rate = round(false_alarm_rate, 3))])

  invisible(out)
}

# ==============================================================================
# SECTION: event_detection_nlcd
#
# LC-stratified, SPEI-aware extension of section_event_detection. Mirrors the
# NLCD pattern from section_continuous_spei_nlcd / section_categorical_usdm_nlcd
# and the SKILL framing in [[phase6-question-is-skill]].
#
# Differences vs section_event_detection (the predecessor):
#   1. Stratified per (L2_code × nlcd_juliana × dom_filter) — 5 LC classes (with
#      collapse_urban_to_2tier) × 11 ecoregions × 2 dom variants ≈ 100 stratum
#      groups. Each is reported in the skill table.
#   2. Adds SPEI as an additional fire-signal family (spei_4w, spei_13w,
#      spei_26w used raw, since SPEI is already standardized upstream). Same
#      threshold semantics: onset fires at SPEI ≤ -z, recovery at SPEI ≥ +z.
#      Total fire signals = 8 (ndvi_z + 4 derivative windows + 3 SPEI windows).
#   3. Augments events_pixel with SPEI within-window trajectory descriptors
#      (±8wk around each event): mean_pre, mean_post, min/max, trend, crossings.
#   4. Replaces hit-rate-only skill with proper POD/FAR/HSS/ETS/Bias from a 2×2
#      contingency built via 4-week temporal blocks (the only way to get a
#      defensible correct_negatives count for HSS).
#   5. Uses vectorized match_fires_to_events_vec / count_false_alarms_vec
#      (5–10x faster than the scalar predecessors for the full population).
#   6. Trimmed op-point grid: 3 z × 3 K × 2 dirs (36 ops/signal) × 8 signals = 288
#      ops/stratum × 2 match tolerances (4w/8w) for lead-distribution diagnostic.
#
# Skipped on first pass (matches NLCD-section convention):
#   - Permutation null (null_reps=0 default; add later if needed)
#   - LC-interaction Wald test (no clean single-equation analog for skill metrics
#     -- POD/FAR/HSS aren't slopes)
#
# Output: event_detection_nlcd_<scope>.rds
#   events_pixel       per-pixel USDM transitions + SPEI trajectory cols
#   events_ecoregion   per (L2 × week) majority-shift events (no SPEI cols)
#   skill_lc           per (stratum × signal × z × K × dir): HSS/ETS/POD/FAR/Bias
#   lead_distributions_lc per (stratum × signal × z × K × dir × lead_window):
#                      hit_rate + lead percentiles (4w + 8w match tolerances)
#   pixel_event_map    per (pixel × event_type × headline_op): hit + lead_weeks
#                      at 2 headline op-points (ndvi_z + spei_13w) for maps
#   meta               scope, op_point grid, runtime, signal definitions
# ==============================================================================

# Headline op-points for pixel_event_map (carry 2 ops × 2 dirs = 4 spatial layers
# per event_type). NDVI magnitude side-by-side with SPEI's medium window.
EVENT_DETECTION_NLCD_HEADLINES <- list(
  list(signal = "ndvi_z",   z = 1.5, K = 2L, lead_window = 8L),
  list(signal = "spei_13w", z = 1.5, K = 2L, lead_window = 8L)
)

section_event_detection_nlcd <- function(scope, null_reps = 0L, smoke = FALSE) {
  cat("\n=== Section: event_detection_nlcd (scope =", scope,
      ", null_reps =", null_reps, ", smoke =", smoke, ") ===\n")
  stopifnot(scope %in% c("10y", "13y"), is.numeric(null_reps), null_reps >= 0L)
  null_reps <- as.integer(null_reps)
  if (null_reps > 0L) {
    cat("  NOTE: null model not implemented on first pass.\n")
    cat("        null_reps will be stored in meta but no null loop will run.\n")
  }

  in_file  <- if (scope == "10y") config$align_out_10y           else config$align_out_13y
  out_file <- if (scope == "10y") config$event_detection_nlcd_10y else config$event_detection_nlcd_13y

  if (!file.exists(in_file)) {
    stop("Cache file missing: ", in_file,
         "\n  Run --section=align_weekly --scope=", scope, " first.")
  }
  if (!file.exists(config$nlcd_pixel_lookup)) {
    stop("NLCD pixel lookup missing: ", config$nlcd_pixel_lookup,
         "\n  Run 00b_extract_nlcd_2019.R first.")
  }
  cat(sprintf("Input:  %s (%.1f GB)\n", basename(in_file), file.size(in_file) / 1e9))
  cat(sprintf("NLCD:   %s\n", basename(config$nlcd_pixel_lookup)))
  cat(sprintf("Output: %s\n", basename(out_file)))

  t_section <- Sys.time()

  ANOM_COLS    <- c("ndvi_anom_mean",
                    "deriv_w03_anom_mean", "deriv_w07_anom_mean",
                    "deriv_w14_anom_mean", "deriv_w30_anom_mean")
  NDVI_SIGNALS <- c("ndvi_z",
                    "deriv_w03_z", "deriv_w07_z", "deriv_w14_z", "deriv_w30_z")
  SPEI_SIGNALS <- c("spei_4w", "spei_13w", "spei_26w")
  ALL_SIGNALS  <- c(NDVI_SIGNALS, SPEI_SIGNALS)
  Z_THRESHOLDS <- c(1.0, 1.5, 2.0)
  K_WEEKS      <- c(1L, 2L, 4L)
  LEAD_WINDOWS <- c(4L, 8L)
  DIRECTIONS   <- c("onset", "recovery")
  BLOCK_WEEKS  <- 4L              # for temporal-block contingency
  MAJORITY_DELTA  <- 0.10
  MIN_VALID_WEEKS <- 30L

  if (smoke) {
    cat("\n  SMOKE MODE: trimming to 2 ecoregions × 3 LCs × 1 signal × 1 op-point\n")
    SMOKE_ECOS    <- c("9.4", "8.4")
    ALL_SIGNALS   <- c("ndvi_z", "spei_13w")
    Z_THRESHOLDS  <- 1.5
    K_WEEKS       <- 2L
    LEAD_WINDOWS  <- c(4L, 8L)
  }

  # --- 1. Load cache, slim columns ---
  cat("\n[1] Load align_weekly cache, slim columns...\n")
  dt <- as.data.table(readRDS_retry(in_file))
  cat(sprintf("  raw: %s rows x %d cols\n",
              format(nrow(dt), big.mark = ","), ncol(dt)))
  keep_cols <- c("pixel_id", "iso_year", "iso_week", "week_start",
                 ANOM_COLS, SPEI_SIGNALS, "usdm", "L2_code", "L2_name")
  dt <- dt[, ..keep_cols]
  gc(verbose = FALSE)

  n_px_in <- uniqueN(dt$pixel_id)
  cat(sprintf("  pixel count: %d (expected %d)\n", n_px_in, EXPECTED_VALID_PIXELS))

  # --- 2. Join NLCD info ---
  cat("\n[2] Join nlcd_juliana + modal_frac from valid_pixels_nlcd2019.rds...\n")
  v_nlcd <- as.data.table(readRDS_retry(config$nlcd_pixel_lookup))
  stopifnot(all(c("pixel_id", "nlcd_juliana", "modal_frac") %in% names(v_nlcd)))
  dt <- merge(dt, v_nlcd[, .(pixel_id, nlcd_juliana, modal_frac)],
              by = "pixel_id", all.x = TRUE)
  n_na <- sum(is.na(dt$nlcd_juliana))
  if (n_na > 0L) {
    stop(sprintf("Join drift: %d rows have NA nlcd_juliana. Pixel set mismatch ",
                 n_na),
         "between align_weekly cache and valid_pixels_nlcd2019.rds.")
  }
  collapse_urban_to_2tier(dt)
  cat(sprintf("  after urban 2-tier collapse; LC distribution (rows): %s\n",
              paste(sprintf("%s=%s", names(table(dt$nlcd_juliana)),
                            format(as.integer(table(dt$nlcd_juliana)),
                                   big.mark = ",")),
                    collapse = ", ")))
  rm(v_nlcd); gc(verbose = FALSE)

  # --- 3. z-standardize NDVI signals (NOT SPEI — used raw) ---
  cat("\n[3] z-standardize 5 NDVI signals (SPEI stays raw)...\n")
  setorder(dt, pixel_id, week_start)
  drop_px <- zstandardize_signals_per_pixel(dt, ANOM_COLS, NDVI_SIGNALS,
                                            min_valid_weeks = MIN_VALID_WEEKS)
  if (length(drop_px) > 0L) dt <- dt[!pixel_id %in% drop_px]
  dt[, (ANOM_COLS) := NULL]
  gc(verbose = FALSE)
  cat(sprintf("  after drops: %s rows x %d pixels\n",
              format(nrow(dt), big.mark = ","), uniqueN(dt$pixel_id)))

  # --- 4. Build stratum_key columns (eco × LC × dom) ---
  cat("\n[4] Build stratum_key columns (full eco x LC_STRATA_LEVELS cross)...\n")
  eco_codes_all <- sort(unique(dt$L2_code[!is.na(dt$L2_code)]))
  if (smoke) eco_codes_all <- intersect(eco_codes_all, SMOKE_ECOS)
  LC_STRATA <- as.data.table(expand.grid(
    L2_code      = eco_codes_all,
    nlcd_juliana = LC_STRATA_LEVELS,
    stringsAsFactors = FALSE
  ))
  LC_STRATA[, key := paste(L2_code, nlcd_juliana, sep = "|")]
  cat(sprintf("  built %d (eco x LC) cells across %d ecoregions x %d LC classes\n",
              nrow(LC_STRATA), length(eco_codes_all), length(LC_STRATA_LEVELS)))

  dt[, lc_eco_key := paste(L2_code, nlcd_juliana, sep = "|")]
  targeted_set <- LC_STRATA$key
  dt[, stratum_key_all := fifelse(lc_eco_key %in% targeted_set,
                                  paste(lc_eco_key, "all", sep = "|"),
                                  NA_character_)]
  dt[, stratum_key_dom := fifelse(lc_eco_key %in% targeted_set &
                                  modal_frac >= config$nlcd_modal_frac_threshold,
                                  paste(lc_eco_key, "dom", sep = "|"),
                                  NA_character_)]
  dt[, lc_eco_key := NULL]

  if (smoke) {
    # In smoke mode, drop rows outside the smoke ecoregions to make the fire
    # detection + contingency loops tractable in ~10 min.
    dt <- dt[L2_code %in% SMOKE_ECOS]
    cat(sprintf("  smoke filter: %s rows in %d ecoregions\n",
                format(nrow(dt), big.mark = ","), length(SMOKE_ECOS)))
  }

  # --- 5. Build USDM events (pixel + ecoregion-aggregate) ---
  cat("\n[5] Build USDM events (pixel + ecoregion-aggregate)...\n")
  events_pixel <- build_pixel_events(dt[, .(pixel_id, iso_year, iso_week,
                                            week_start, usdm)])
  cat(sprintf("  Per-pixel events: %s onset + %s recovery\n",
              format(sum(events_pixel$event_type == "onset"),    big.mark = ","),
              format(sum(events_pixel$event_type == "recovery"), big.mark = ",")))

  events_eco <- build_ecoregion_events(
    dt[, .(pixel_id, iso_year, iso_week, week_start, usdm, L2_code, L2_name)],
    majority_delta = MAJORITY_DELTA)
  cat(sprintf("  Eco-aggregate events (≥%.0f%% w/w shift): %d onset + %d recovery\n",
              100 * MAJORITY_DELTA,
              sum(events_eco$event_type == "onset"),
              sum(events_eco$event_type == "recovery")))

  # --- 6. Augment events_pixel with SPEI trajectory ---
  cat("\n[6] Augment events_pixel with SPEI within-window trajectory (±8wk)...\n")
  spei_weekly <- dt[, .(pixel_id, week_start,
                        spei_4w, spei_13w, spei_26w)]
  events_pixel <- extract_spei_trajectory_per_event(events_pixel, spei_weekly,
                                                    lookback = 8L,
                                                    lookforward = 8L)
  rm(spei_weekly); gc(verbose = FALSE)

  # --- 7. Detect fires globally per (signal × z × K × direction) ---
  cat("\n[7] Detect fires globally per op-cell...\n")
  t_fires <- Sys.time()
  fires_list <- list()
  fire_idx <- 0L
  total_fire_cells <- length(ALL_SIGNALS) * length(Z_THRESHOLDS) *
                      length(K_WEEKS) * length(DIRECTIONS)
  cat(sprintf("  %d total fire-detection passes\n", total_fire_cells))

  for (sig in ALL_SIGNALS) {
    is_spei <- startsWith(sig, "spei_")
    # For SPEI fires, use the raw col directly; for NDVI use the z col.
    sig_col_in_dt <- sig
    if (!(sig_col_in_dt %in% names(dt))) {
      cat(sprintf("    WARN: signal %s not in dt; skipping\n", sig))
      next
    }
    for (z in Z_THRESHOLDS) {
      for (K in K_WEEKS) {
        for (dir_ in DIRECTIONS) {
          fire_idx <- fire_idx + 1L
          fires <- detect_fires_global(dt, sig_col_in_dt, z, K, dir_,
                                       is_raw_spei = is_spei)
          if (!is.null(fires)) {
            fires_list[[length(fires_list) + 1L]] <- fires
          }
          if (fire_idx %% 12L == 0L) {
            elapsed <- as.numeric(Sys.time() - t_fires, units = "mins")
            cat(sprintf("    %d/%d fire cells (%.1f min, ETA %.1f min)\n",
                        fire_idx, total_fire_cells, elapsed,
                        elapsed * (total_fire_cells - fire_idx) / fire_idx))
          }
        }
      }
    }
  }
  fires_all <- rbindlist(fires_list, use.names = TRUE, fill = TRUE)
  rm(fires_list); gc(verbose = FALSE)
  cat(sprintf("  fires detected: %s total rows in %.1f min\n",
              format(nrow(fires_all), big.mark = ","),
              as.numeric(Sys.time() - t_fires, units = "mins")))

  # --- 8. Per-stratum skill loop ---
  # For each (stratum_track in c("all","dom"), signal × z × K × dir):
  #   - Build stratum_map (pixel_id → stratum_key) restricted to the track
  #   - Restrict events_pixel + fires to that stratum's pixels
  #   - Build 2×2 contingency (4-week blocks), compute POD/FAR/HSS/ETS/Bias
  #   - For each lead_window: match fires to events for lead percentiles
  cat("\n[8] Per-stratum skill loop (contingency + lead percentiles)...\n")
  t_skill <- Sys.time()

  # Period bounds for n_blocks_total in the contingency:
  period_start_wk <- min(dt$week_start)
  period_end_wk   <- max(dt$week_start)
  cat(sprintf("  period: %s to %s (%.0f weeks)\n",
              period_start_wk, period_end_wk,
              as.numeric(period_end_wk - period_start_wk) / 7))

  # Cache the two stratum_maps (pixel_id → stratum_key); unique by pixel.
  stratum_map_all <- unique(dt[!is.na(stratum_key_all),
                               .(pixel_id, stratum_key = stratum_key_all)])
  stratum_map_dom <- unique(dt[!is.na(stratum_key_dom),
                               .(pixel_id, stratum_key = stratum_key_dom)])
  cat(sprintf("  stratum maps: %d (all) + %d (dom) pixel→stratum rows\n",
              nrow(stratum_map_all), nrow(stratum_map_dom)))

  # Pre-index fires by op for quick slicing
  setkey(fires_all, signal_col, z_threshold, sustained_weeks, direction)
  # Pre-index events by direction for quick slicing
  setkey(events_pixel, event_type)

  skill_rows <- list()
  lead_rows  <- list()
  total_ops  <- length(ALL_SIGNALS) * length(Z_THRESHOLDS) * length(K_WEEKS) *
                length(DIRECTIONS)
  op_idx <- 0L

  for (sig in ALL_SIGNALS) {
    for (z in Z_THRESHOLDS) {
      for (K in K_WEEKS) {
        for (dir_ in DIRECTIONS) {
          op_idx <- op_idx + 1L
          # Pull this op's fires
          f_op <- fires_all[.(sig, z, K, dir_), nomatch = 0L,
                            .(pixel_id, week_start)]
          # Pull this direction's events (same for both stratum tracks)
          e_op <- events_pixel[event_type == dir_,
                               .(pixel_id, week_start, iso_year, iso_week)]

          for (stratum_track in c("all", "dom")) {
            stratum_map <- if (stratum_track == "all") stratum_map_all else stratum_map_dom
            if (nrow(stratum_map) == 0L) next
            # Restrict events + fires to pixels in this track
            f_t <- f_op[pixel_id %in% stratum_map$pixel_id]
            e_t <- e_op[pixel_id %in% stratum_map$pixel_id]

            # 2×2 contingency + skill metrics (block-based)
            cont <- compute_temporal_block_contingency(
              e_t, f_t, stratum_map,
              block_weeks    = BLOCK_WEEKS,
              period_start_wk = period_start_wk,
              period_end_wk   = period_end_wk)
            if (nrow(cont) > 0L) {
              cont <- compute_skill_metrics(cont)
              cont[, `:=`(signal_col      = sig,
                          z_threshold     = z,
                          sustained_weeks = K,
                          direction       = dir_,
                          dom_filter      = stratum_track)]
              skill_rows[[length(skill_rows) + 1L]] <- cont
            }

            # Per-event matching for lead percentiles (per lead_window)
            for (lead in LEAD_WINDOWS) {
              matches <- match_fires_to_events_vec(e_t, f_t, lead)
              if (nrow(matches) == 0L) next
              # Attach stratum_key for grouping
              matches <- merge(matches, stratum_map, by = "pixel_id")
              ld <- matches[, .(
                n_events     = .N,
                n_hits       = sum(hit, na.rm = TRUE),
                hit_rate     = mean(hit, na.rm = TRUE),
                median_lead  = if (any(hit, na.rm = TRUE)) as.numeric(median(lead_weeks[hit], na.rm = TRUE)) else NA_real_,
                mean_lead    = if (any(hit, na.rm = TRUE)) as.numeric(mean(lead_weeks[hit],   na.rm = TRUE)) else NA_real_,
                p10_lead     = if (any(hit, na.rm = TRUE)) as.numeric(quantile(lead_weeks[hit], 0.10, na.rm = TRUE)) else NA_real_,
                p25_lead     = if (any(hit, na.rm = TRUE)) as.numeric(quantile(lead_weeks[hit], 0.25, na.rm = TRUE)) else NA_real_,
                p75_lead     = if (any(hit, na.rm = TRUE)) as.numeric(quantile(lead_weeks[hit], 0.75, na.rm = TRUE)) else NA_real_,
                p90_lead     = if (any(hit, na.rm = TRUE)) as.numeric(quantile(lead_weeks[hit], 0.90, na.rm = TRUE)) else NA_real_,
                pct_lead_pos = if (any(hit, na.rm = TRUE)) as.numeric(mean(lead_weeks[hit] > 0, na.rm = TRUE)) else NA_real_
              ), by = stratum_key]
              ld[, `:=`(signal_col      = sig,
                        z_threshold     = z,
                        sustained_weeks = K,
                        direction       = dir_,
                        lead_window     = lead,
                        dom_filter      = stratum_track)]
              lead_rows[[length(lead_rows) + 1L]] <- ld
            }
          }
          if (op_idx %% 8L == 0L) {
            elapsed <- as.numeric(Sys.time() - t_skill, units = "mins")
            cat(sprintf("    op %d/%d (%.1f min, ETA %.1f min)\n",
                        op_idx, total_ops, elapsed,
                        elapsed * (total_ops - op_idx) / op_idx))
          }
        }
      }
    }
  }
  skill_lc <- rbindlist(skill_rows, use.names = TRUE, fill = TRUE)
  lead_distributions_lc <- rbindlist(lead_rows, use.names = TRUE, fill = TRUE)
  rm(skill_rows, lead_rows); gc(verbose = FALSE)
  # Parse stratum_key into (L2_code, nlcd_juliana, dom_filter_token)
  for (tbl in list(skill_lc, lead_distributions_lc)) {
    if (nrow(tbl) > 0L) {
      parts <- tstrsplit(tbl$stratum_key, "|", fixed = TRUE)
      tbl[, `:=`(L2_code        = parts[[1]],
                 nlcd_juliana   = parts[[2]],
                 dom_filter_tok = parts[[3]])]
    }
  }
  cat(sprintf("  skill_lc rows: %s | lead rows: %s | %.1f min total\n",
              format(nrow(skill_lc), big.mark = ","),
              format(nrow(lead_distributions_lc), big.mark = ","),
              as.numeric(Sys.time() - t_skill, units = "mins")))

  # --- 9. Pixel-level event map at headline op-points ---
  cat("\n[9] Build pixel_event_map at headline op-points...\n")
  hdl_rows <- list()
  for (hdl in EVENT_DETECTION_NLCD_HEADLINES) {
    for (dir_ in DIRECTIONS) {
      f_op <- fires_all[.(hdl$signal, hdl$z, hdl$K, dir_), nomatch = 0L,
                        .(pixel_id, week_start)]
      e_op <- events_pixel[event_type == dir_,
                           .(pixel_id, week_start, iso_year, iso_week)]
      if (nrow(e_op) == 0L) next
      m <- match_fires_to_events_vec(e_op, f_op, hdl$lead_window)
      m[, `:=`(headline_signal = hdl$signal, event_type = dir_)]
      hdl_rows[[length(hdl_rows) + 1L]] <- m[, .(pixel_id, week_start,
                                                  iso_year, iso_week,
                                                  headline_signal,
                                                  event_type, hit, lead_weeks,
                                                  n_fires_in_window)]
    }
  }
  pixel_event_map <- if (length(hdl_rows)) {
    rbindlist(hdl_rows, use.names = TRUE, fill = TRUE)
  } else {
    data.table()
  }
  cat(sprintf("  pixel_event_map rows: %s\n",
              format(nrow(pixel_event_map), big.mark = ",")))

  # --- 10. Assemble + save ---
  meta <- list(
    scope             = scope,
    scope_years       = if (scope == "10y") 2016:2025 else 2013:2025,
    lc_strata         = LC_STRATA,
    lc_strata_levels  = LC_STRATA_LEVELS,
    nlcd_modal_frac_threshold   = config$nlcd_modal_frac_threshold,
    null_reps         = null_reps,
    all_signals       = ALL_SIGNALS,
    ndvi_signals      = NDVI_SIGNALS,
    spei_signals      = SPEI_SIGNALS,
    z_thresholds      = Z_THRESHOLDS,
    K_weeks           = K_WEEKS,
    lead_windows      = LEAD_WINDOWS,
    directions        = DIRECTIONS,
    block_weeks       = BLOCK_WEEKS,
    majority_delta    = MAJORITY_DELTA,
    event_headlines   = EVENT_DETECTION_NLCD_HEADLINES,
    min_valid_weeks   = MIN_VALID_WEEKS,
    dropped_pixels    = length(drop_px),
    period_start_wk   = period_start_wk,
    period_end_wk     = period_end_wk,
    smoke             = smoke,
    runtime_minutes   = as.numeric(Sys.time() - t_section, units = "mins"),
    created           = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )

  out <- list(
    events_pixel          = events_pixel,
    events_ecoregion      = events_eco,
    skill_lc              = skill_lc,
    lead_distributions_lc = lead_distributions_lc,
    pixel_event_map       = pixel_event_map,
    meta                  = meta
  )

  cat(sprintf("\nSaving %s...\n", basename(out_file)))
  saveRDS_validated(out, out_file, compress = "xz")
  cat(sprintf("  wrote %.2f MB in %.1f min total\n",
              file.size(out_file) / 1e6, meta$runtime_minutes))

  # --- Quick summary ---
  options(datatable.print.nrows = 60L, datatable.print.topn = 60L)
  cat("\n--- HSS summary (ndvi_z, z=1.5, K=2, onset, dom=all), sorted by HSS ---\n")
  q1 <- skill_lc[signal_col == "ndvi_z" & z_threshold == 1.5 &
                 sustained_weeks == 2L & direction == "onset" &
                 dom_filter == "all"]
  if (nrow(q1) > 0L) {
    print(q1[order(-hss),
             .(L2_code, nlcd_juliana,
               hits, misses, false_alarms,
               pod = round(pod, 3), far = round(far, 3),
               hss = round(hss, 3), ets = round(ets, 3))])
  }

  cat("\n--- SPEI sanity (mean spei13_mean_post per event_type) ---\n")
  if (all(c("spei13_mean_post", "event_type") %in% names(events_pixel))) {
    print(events_pixel[, .(n_events    = .N,
                           mean_spei13_post = round(mean(spei13_mean_post,
                                                         na.rm = TRUE), 3),
                           med_spei13_post  = round(median(spei13_mean_post,
                                                           na.rm = TRUE), 3)),
                       by = event_type])
  }

  invisible(out)
}

# ==============================================================================
# section_flash_drought
# ==============================================================================
# Productionized version of tmp_flash_drought_exploration.R (2026-06-16).
# Re-scores Section B (event_detection_nlcd) skill on the FLASH DROUGHT subset
# using an Otkin-style 4-week USDM trajectory definition.
#
# Subset definitions (per event_type):
#   all       : every event (baseline)
#   flash_d1  : max(USDM in +/-4wk window) >= 1  (any drought)        -- lenient
#   flash_d2  : max(USDM in +/-4wk window) >= 2  (severe+)            -- strict (Otkin-ish)
#
# Two skill scoring layers per (eco x LC x direction x subset x signal):
#   1. Per-event hit rate (POD-equivalent) from pixel_event_map at headline op.
#      Matches the exploration script's primary metric. Cheap.
#   2. Temporal-block contingency HSS (4-wk blocks) for the proper 2x2 skill
#      panel (POD/FAR/HSS/ETS). Requires re-detecting fires from the align
#      cache because Section B only stored per-event hits, not fire-week tables.
#
# Inputs:
#   - event_detection_nlcd_{scope}.rds  (events_pixel + pixel_event_map)
#   - align_weekly cache                (for fire re-detection)
#   - usdm_4km_weekly_2013_2025.rds     (USDM trajectory)
#   - valid_pixels_nlcd2019.rds         (LC stratification)
#
# Output: flash_drought_{scope}.rds
#   - events_pixel_flash    : Section B's events + (is_flash_d1, is_flash_d2)
#   - hit_rate_flash_lc     : per-stratum hit rate per subset (POD-equivalent)
#   - skill_flash_lc        : per-stratum POD/FAR/HSS/ETS per subset (block-based)
#   - domain_summary        : domain-wide pooled numbers per subset
#   - meta                  : params, runtime, source files
# ==============================================================================

FLASH_DROUGHT_HEADLINES <- list(
  list(signal = "ndvi_z",   z = 1.5, K = 2L, lead_window = 8L),
  list(signal = "spei_13w", z = 1.5, K = 2L, lead_window = 8L)
)

section_flash_drought <- function(scope, smoke = FALSE) {
  cat("\n=== Section: flash_drought (scope =", scope,
      ", smoke =", smoke, ") ===\n")
  stopifnot(scope %in% c("10y", "13y"))

  in_b_file <- if (scope == "10y") config$event_detection_nlcd_10y else config$event_detection_nlcd_13y
  in_a_file <- if (scope == "10y") config$align_out_10y           else config$align_out_13y
  out_file  <- if (scope == "10y") config$flash_drought_10y       else config$flash_drought_13y

  if (!file.exists(in_b_file)) {
    stop("Section B output missing: ", in_b_file,
         "\n  Run --section=event_detection_nlcd --scope=", scope, " first.")
  }
  if (!file.exists(in_a_file)) {
    stop("align_weekly cache missing: ", in_a_file,
         "\n  Run --section=align_weekly --scope=", scope, " first.")
  }
  if (!file.exists(config$usdm_file)) {
    stop("USDM weekly cache missing: ", config$usdm_file)
  }
  if (!file.exists(config$nlcd_pixel_lookup)) {
    stop("NLCD lookup missing: ", config$nlcd_pixel_lookup)
  }
  cat(sprintf("Section B in: %s (%.0f MB)\n",
              basename(in_b_file), file.size(in_b_file) / 1e6))
  cat(sprintf("align cache:  %s (%.1f GB)\n",
              basename(in_a_file), file.size(in_a_file) / 1e9))
  cat(sprintf("Output:       %s\n", basename(out_file)))

  t_section <- Sys.time()
  BLOCK_WEEKS <- 4L

  # --- 1. Load Section B output (events_pixel + pixel_event_map) ---
  cat("\n[1] Load Section B output...\n")
  out_b <- readRDS_retry(in_b_file)
  events_pixel    <- as.data.table(out_b$events_pixel)
  pixel_event_map <- as.data.table(out_b$pixel_event_map)
  stopifnot("week_start" %in% names(events_pixel),
            "headline_signal" %in% names(pixel_event_map))
  cat(sprintf("  events_pixel:    %s rows\n",
              format(nrow(events_pixel), big.mark = ",")))
  cat(sprintf("  pixel_event_map: %s rows\n",
              format(nrow(pixel_event_map), big.mark = ",")))

  # --- 2. Load USDM + compute rolling-max trajectory ---
  cat("\n[2] Load USDM + compute rolling-max trajectory...\n")
  usdm <- as.data.table(readRDS_retry(config$usdm_file))
  # USDM table uses (week_date = Tuesday, dm_max in {-1,0,1,2,3,4}).
  # Events use week_start = Monday of the same ISO week.
  usdm[, week_start := week_date - 1L]
  setkey(usdm, pixel_id, week_start)
  # n=5 weeks = current + 4 following (or preceding) ~ Otkin's 4-wk window
  usdm[, usdm_max_next4 := frollmax(dm_max, n = 5L, align = "left",
                                    fill = NA, na.rm = TRUE), by = pixel_id]
  usdm[, usdm_max_prev4 := frollmax(dm_max, n = 5L, align = "right",
                                    fill = NA, na.rm = TRUE), by = pixel_id]
  cat(sprintf("  USDM rows: %s\n", format(nrow(usdm), big.mark = ",")))

  # --- 3. Tag events with flash flags ---
  cat("\n[3] Tag events with flash flags...\n")
  events_pixel <- merge(events_pixel,
                        usdm[, .(pixel_id, week_start, usdm_max_next4, usdm_max_prev4)],
                        by = c("pixel_id", "week_start"), all.x = TRUE)
  events_pixel[, is_flash_d1 := fifelse(
    event_type == "onset",     usdm_max_next4 >= 1L,
    fifelse(event_type == "recovery", usdm_max_prev4 >= 1L, NA))]
  events_pixel[, is_flash_d2 := fifelse(
    event_type == "onset",     usdm_max_next4 >= 2L,
    fifelse(event_type == "recovery", usdm_max_prev4 >= 2L, NA))]
  rm(usdm); gc(verbose = FALSE)
  cat(sprintf("  onset:    n=%s  flash_d1=%s (%.1f%%)  flash_d2=%s (%.1f%%)\n",
              format(events_pixel[event_type=="onset", .N], big.mark=","),
              format(events_pixel[event_type=="onset", sum(is_flash_d1, na.rm=TRUE)], big.mark=","),
              100*events_pixel[event_type=="onset", mean(is_flash_d1, na.rm=TRUE)],
              format(events_pixel[event_type=="onset", sum(is_flash_d2, na.rm=TRUE)], big.mark=","),
              100*events_pixel[event_type=="onset", mean(is_flash_d2, na.rm=TRUE)]))
  cat(sprintf("  recovery: n=%s  flash_d1=%s (%.1f%%)  flash_d2=%s (%.1f%%)\n",
              format(events_pixel[event_type=="recovery", .N], big.mark=","),
              format(events_pixel[event_type=="recovery", sum(is_flash_d1, na.rm=TRUE)], big.mark=","),
              100*events_pixel[event_type=="recovery", mean(is_flash_d1, na.rm=TRUE)],
              format(events_pixel[event_type=="recovery", sum(is_flash_d2, na.rm=TRUE)], big.mark=","),
              100*events_pixel[event_type=="recovery", mean(is_flash_d2, na.rm=TRUE)]))

  # --- 4. Join NLCD + ecoregion (ensure stratification cols present) ---
  cat("\n[4] Join NLCD juliana + ecoregion lookup...\n")
  if (!"nlcd_juliana" %in% names(events_pixel)) {
    v_nlcd <- as.data.table(readRDS_retry(config$nlcd_pixel_lookup))
    events_pixel <- merge(events_pixel,
                          v_nlcd[, .(pixel_id, nlcd_juliana)],
                          by = "pixel_id", all.x = TRUE)
    collapse_urban_to_2tier(events_pixel)
    rm(v_nlcd); gc(verbose = FALSE)
  }
  if (!"L2_code" %in% names(events_pixel)) {
    vp <- as.data.table(readRDS_retry(config$ecoregion_lookup))
    events_pixel <- merge(events_pixel,
                          vp[, .(pixel_id, L2_code)],
                          by = "pixel_id", all.x = TRUE)
    rm(vp); gc(verbose = FALSE)
  }
  # Drop events lacking strata or LC out-of-set (matches Phase 6 convention)
  LC_LEVELS <- c("crop", "forest", "grassland", "urban_dense", "urban_diffuse")
  events_pixel <- events_pixel[!is.na(L2_code) & L2_code != "0.0" &
                                nlcd_juliana %in% LC_LEVELS]
  cat(sprintf("  events after LC+eco filter: %s\n",
              format(nrow(events_pixel), big.mark = ",")))

  # --- 5. Per-event hit rates from pixel_event_map (POD-equivalent) ---
  cat("\n[5] Compute per-event hit rates per (stratum x subset x signal)...\n")
  pew <- dcast(pixel_event_map,
               pixel_id + week_start + event_type ~ headline_signal,
               value.var = "hit")
  hit_signals <- intersect(c("ndvi_z", "spei_13w"), names(pew))
  if (length(hit_signals) < 2L) {
    stop("pixel_event_map missing expected headline signals; ",
         "found: ", paste(names(pew), collapse=", "))
  }
  ev_hits <- merge(events_pixel[, .(pixel_id, week_start, event_type,
                                     L2_code, nlcd_juliana,
                                     is_flash_d1, is_flash_d2)],
                   pew, by = c("pixel_id", "week_start", "event_type"))

  hit_rate_subset <- function(dt, subset_label) {
    if (nrow(dt) == 0L) return(NULL)
    dt[, .(n_events = .N,
           ndvi_hit = mean(ndvi_z, na.rm = TRUE),
           spei_hit = mean(spei_13w, na.rm = TRUE),
           both_hit = mean(ndvi_z & spei_13w, na.rm = TRUE),
           either_hit = mean(ndvi_z | spei_13w, na.rm = TRUE),
           ndvi_only_hit = mean(ndvi_z & !spei_13w, na.rm = TRUE),
           spei_only_hit = mean(!ndvi_z & spei_13w, na.rm = TRUE)),
       by = .(L2_code, nlcd_juliana, event_type)][, subset := subset_label][]
  }
  hit_rate_flash_lc <- rbindlist(list(
    hit_rate_subset(ev_hits,                              "all"),
    hit_rate_subset(ev_hits[is_flash_d1 == TRUE],         "flash_d1"),
    hit_rate_subset(ev_hits[is_flash_d2 == TRUE],         "flash_d2")
  ), use.names = TRUE, fill = TRUE)
  cat(sprintf("  hit_rate_flash_lc: %s rows\n",
              format(nrow(hit_rate_flash_lc), big.mark = ",")))

  # Domain-wide summary (matches exploration table; sanity-check vs RDS)
  domain_subset <- function(dt, label) {
    list(
      label = label, n = nrow(dt),
      onset    = list(
        n         = dt[event_type=="onset", .N],
        ndvi_hit  = dt[event_type=="onset", mean(ndvi_z,   na.rm=TRUE)],
        spei_hit  = dt[event_type=="onset", mean(spei_13w, na.rm=TRUE)],
        both      = dt[event_type=="onset", mean(ndvi_z &  spei_13w, na.rm=TRUE)],
        ndvi_only = dt[event_type=="onset", mean(ndvi_z & !spei_13w, na.rm=TRUE)],
        spei_only = dt[event_type=="onset", mean(!ndvi_z &  spei_13w, na.rm=TRUE)]
      ),
      recovery = list(
        n         = dt[event_type=="recovery", .N],
        ndvi_hit  = dt[event_type=="recovery", mean(ndvi_z,   na.rm=TRUE)],
        spei_hit  = dt[event_type=="recovery", mean(spei_13w, na.rm=TRUE)],
        both      = dt[event_type=="recovery", mean(ndvi_z &  spei_13w, na.rm=TRUE)],
        ndvi_only = dt[event_type=="recovery", mean(ndvi_z & !spei_13w, na.rm=TRUE)],
        spei_only = dt[event_type=="recovery", mean(!ndvi_z &  spei_13w, na.rm=TRUE)]
      )
    )
  }
  domain_summary <- list(
    all       = domain_subset(ev_hits,                       "all"),
    flash_d1  = domain_subset(ev_hits[is_flash_d1 == TRUE],  "flash_d1"),
    flash_d2  = domain_subset(ev_hits[is_flash_d2 == TRUE],  "flash_d2")
  )

  # --- 6. Re-detect fires from align cache for temporal-block HSS ---
  cat("\n[6] Re-detect fires from align cache (ndvi_z + spei_13w @ headline op)...\n")
  t_fires <- Sys.time()
  dt_align <- as.data.table(readRDS_retry(in_a_file))
  ANOM_COLS    <- "ndvi_anom_mean"
  NDVI_SIGNALS <- "ndvi_z"
  keep <- c("pixel_id", "iso_year", "iso_week", "week_start",
            ANOM_COLS, "spei_13w", "L2_code")
  dt_align <- dt_align[, ..keep]
  gc(verbose = FALSE)
  cat(sprintf("  align cache slimmed: %s rows x %d cols\n",
              format(nrow(dt_align), big.mark = ","), ncol(dt_align)))

  # z-standardize ndvi_z (matches Section B's per-pixel z-standardization)
  setorder(dt_align, pixel_id, week_start)
  drop_px <- zstandardize_signals_per_pixel(dt_align, ANOM_COLS, NDVI_SIGNALS,
                                            min_valid_weeks = 30L)
  if (length(drop_px) > 0L) {
    dt_align <- dt_align[!pixel_id %in% drop_px]
    cat(sprintf("  dropped %d pixels with <30 valid weeks\n", length(drop_px)))
  }
  dt_align[, (ANOM_COLS) := NULL]

  if (smoke) {
    cat("\n  SMOKE MODE: restricting to ecoregions 9.4 + 8.4 for fire detection\n")
    dt_align <- dt_align[L2_code %in% c("9.4", "8.4")]
  }

  fires_list <- list()
  for (hdl in FLASH_DROUGHT_HEADLINES) {
    for (dir_ in c("onset", "recovery")) {
      fires <- detect_fires_global(dt_align, hdl$signal,
                                   hdl$z, hdl$K, dir_,
                                   is_raw_spei = grepl("^spei", hdl$signal))
      if (!is.null(fires)) fires_list[[length(fires_list) + 1L]] <- fires
    }
  }
  fires_all <- rbindlist(fires_list, use.names = TRUE, fill = TRUE)
  rm(fires_list); gc(verbose = FALSE)

  # Period bounds = align cache full date range
  period_start_wk <- min(dt_align$week_start)
  period_end_wk   <- max(dt_align$week_start)
  rm(dt_align); gc(verbose = FALSE)
  cat(sprintf("  fires: %s rows (%.1f min)\n",
              format(nrow(fires_all), big.mark = ","),
              as.numeric(Sys.time() - t_fires, units = "mins")))

  # --- 7. Temporal-block contingency per stratum x subset x signal x direction ---
  cat("\n[7] Compute temporal-block HSS per (stratum x subset x signal x direction)...\n")
  t_skill <- Sys.time()
  # Stratum map: per-pixel (L2_code, nlcd_juliana) for all pixels with events
  stratum_map <- unique(events_pixel[, .(pixel_id, L2_code, nlcd_juliana)])
  if (smoke) {
    stratum_map <- stratum_map[L2_code %in% c("9.4", "8.4")]
  }
  stratum_map[, stratum_key := sprintf("%s|%s", L2_code, nlcd_juliana)]

  setkey(fires_all, signal_col, direction)
  subset_filter <- list(
    all      = function(dt) dt,
    flash_d1 = function(dt) dt[is_flash_d1 == TRUE],
    flash_d2 = function(dt) dt[is_flash_d2 == TRUE]
  )

  skill_rows <- list()
  for (subset_name in names(subset_filter)) {
    ev_sub_full <- subset_filter[[subset_name]](events_pixel)
    for (hdl in FLASH_DROUGHT_HEADLINES) {
      sig <- hdl$signal
      for (dir_ in c("onset", "recovery")) {
        ev_sub <- ev_sub_full[event_type == dir_,
                              .(pixel_id, week_start)]
        f_sub  <- fires_all[.(sig, dir_), nomatch = 0L,
                            .(pixel_id, week_start)]
        cont <- compute_temporal_block_contingency(
          ev_sub, f_sub, stratum_map,
          block_weeks    = BLOCK_WEEKS,
          period_start_wk = period_start_wk,
          period_end_wk   = period_end_wk
        )
        if (nrow(cont) > 0L) {
          cont <- compute_skill_metrics(cont)
          # Split stratum_key back into L2_code, nlcd_juliana
          cont[, c("L2_code", "nlcd_juliana") :=
                  tstrsplit(stratum_key, "|", fixed = TRUE)]
          cont[, `:=`(subset = subset_name,
                      signal_col = sig,
                      direction  = dir_,
                      z_threshold = hdl$z,
                      sustained_weeks = hdl$K,
                      lead_window = hdl$lead_window)]
          skill_rows[[length(skill_rows) + 1L]] <- cont
        }
      }
    }
  }
  skill_flash_lc <- rbindlist(skill_rows, use.names = TRUE, fill = TRUE)
  rm(skill_rows, fires_all); gc(verbose = FALSE)
  cat(sprintf("  skill_flash_lc: %s rows (%.1f min)\n",
              format(nrow(skill_flash_lc), big.mark = ","),
              as.numeric(Sys.time() - t_skill, units = "mins")))

  # --- 8. Assemble + save ---
  meta <- list(
    scope             = scope,
    scope_years       = if (scope == "10y") 2016:2025 else 2013:2025,
    flash_d1_def      = "max(USDM in +/-4wk window) >= 1  (any drought)",
    flash_d2_def      = "max(USDM in +/-4wk window) >= 2  (severe+, Otkin-ish)",
    headline_op       = "ndvi_z + spei_13w at z=1.5, K=2, lead +/-8wk",
    headlines         = FLASH_DROUGHT_HEADLINES,
    block_weeks       = BLOCK_WEEKS,
    lc_levels         = LC_LEVELS,
    period_start_wk   = period_start_wk,
    period_end_wk     = period_end_wk,
    smoke             = smoke,
    n_events_in       = nrow(events_pixel),
    sources           = list(
      event_detection_nlcd = in_b_file,
      align_weekly         = in_a_file,
      usdm_file            = config$usdm_file,
      nlcd_pixel_lookup    = config$nlcd_pixel_lookup
    ),
    runtime_minutes   = as.numeric(Sys.time() - t_section, units = "mins"),
    created           = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )

  # Reorder events_pixel_flash columns for tidiness
  setcolorder(events_pixel,
              intersect(c("pixel_id", "week_start", "event_type",
                          "L2_code", "L2_name", "nlcd_juliana",
                          "is_flash_d1", "is_flash_d2",
                          "usdm_max_next4", "usdm_max_prev4"),
                        names(events_pixel)))

  out <- list(
    events_pixel_flash = events_pixel,
    hit_rate_flash_lc  = hit_rate_flash_lc,
    skill_flash_lc     = skill_flash_lc,
    domain_summary     = domain_summary,
    meta               = meta
  )

  cat(sprintf("\nSaving %s...\n", basename(out_file)))
  saveRDS_validated(out, out_file, compress = "xz")
  cat(sprintf("  wrote %.2f MB in %.1f min total\n",
              file.size(out_file) / 1e6, meta$runtime_minutes))

  # --- Quick summary ---
  options(datatable.print.nrows = 30L, datatable.print.topn = 30L)
  cat("\n--- Domain-wide hit rates by subset x event_type ---\n")
  for (sub in c("all", "flash_d1", "flash_d2")) {
    d <- domain_summary[[sub]]
    cat(sprintf("[%s]\n  onset    n=%s  NDVI=%.1f%%  SPEI=%.1f%%  both=%.1f%%  NDVI-only=%.1f%%  SPEI-only=%.1f%%\n",
                sub, format(d$onset$n, big.mark=","),
                100*d$onset$ndvi_hit, 100*d$onset$spei_hit,
                100*d$onset$both, 100*d$onset$ndvi_only, 100*d$onset$spei_only))
    cat(sprintf("  recovery n=%s  NDVI=%.1f%%  SPEI=%.1f%%  both=%.1f%%  NDVI-only=%.1f%%  SPEI-only=%.1f%%\n",
                format(d$recovery$n, big.mark=","),
                100*d$recovery$ndvi_hit, 100*d$recovery$spei_hit,
                100*d$recovery$both, 100*d$recovery$ndvi_only, 100*d$recovery$spei_only))
  }

  cat("\n--- Top HSS per (subset x direction) ---\n")
  for (sub in c("all", "flash_d1", "flash_d2")) {
    for (dir_ in c("onset", "recovery")) {
      cat(sprintf("\n[%s %s] top 5 by HSS:\n", sub, dir_))
      q <- skill_flash_lc[subset == sub & direction == dir_ & is.finite(hss)]
      if (nrow(q) > 0L) {
        print(q[order(-hss)][1:5L,
                .(L2_code, nlcd_juliana, signal_col,
                  hits, misses, false_alarms,
                  pod = round(pod, 3), far = round(far, 3),
                  hss = round(hss, 3), ets = round(ets, 3))])
      }
    }
  }

  invisible(out)
}

# ==============================================================================
# section_ensemble_or
# ==============================================================================
# Tests whether ndvi_z OR spei_13w at the headline op beats either alone.
# Motivated by Section B's 4-5% concurrent firing finding + Fig 10's seasonally
# asymmetric complementarity: signals are largely independent, so the logical
# OR should lift hit rate substantially over the better single signal.
#
# Two skill layers per (eco x LC x direction x signal_set):
#   1. Per-event hit rate (POD-equivalent) from pixel_event_map at headline op.
#   2. Temporal-block contingency HSS for the union signal -- fires_or built by
#      rbind(ndvi_fires, spei_fires) -> contingency sees the union by virtue of
#      unique(pixel, block) inside compute_temporal_block_contingency.
#
# signal_set in {ndvi, spei, or}. The OR signal fires whenever either
# constituent fires (at z=1.5, K=2 sustained) at the same pixel.
#
# Inputs: same as section_flash_drought.
# Output: ensemble_or_{scope}.rds
#   - events_pixel_or       : events with per-event hit_or column
#   - hit_rate_or_lc        : per-stratum hit rates for 3 signal_sets + lift
#   - skill_or_lc           : POD/FAR/HSS/ETS for 3 signal_sets + lift
#   - domain_summary        : domain-wide pooled numbers
#   - meta                  : params, runtime, source files
# ==============================================================================

ENSEMBLE_OR_HEADLINES <- list(
  list(signal = "ndvi_z",   z = 1.5, K = 2L, lead_window = 8L),
  list(signal = "spei_13w", z = 1.5, K = 2L, lead_window = 8L)
)

section_ensemble_or <- function(scope, smoke = FALSE) {
  cat("\n=== Section: ensemble_or (scope =", scope,
      ", smoke =", smoke, ") ===\n")
  stopifnot(scope %in% c("10y", "13y"))

  in_b_file <- if (scope == "10y") config$event_detection_nlcd_10y else config$event_detection_nlcd_13y
  in_a_file <- if (scope == "10y") config$align_out_10y           else config$align_out_13y
  out_file  <- if (scope == "10y") config$ensemble_or_10y         else config$ensemble_or_13y

  if (!file.exists(in_b_file)) {
    stop("Section B output missing: ", in_b_file,
         "\n  Run --section=event_detection_nlcd --scope=", scope, " first.")
  }
  if (!file.exists(in_a_file)) {
    stop("align_weekly cache missing: ", in_a_file)
  }
  if (!file.exists(config$nlcd_pixel_lookup)) {
    stop("NLCD lookup missing: ", config$nlcd_pixel_lookup)
  }
  cat(sprintf("Section B in: %s (%.0f MB)\n",
              basename(in_b_file), file.size(in_b_file) / 1e6))
  cat(sprintf("align cache:  %s (%.1f GB)\n",
              basename(in_a_file), file.size(in_a_file) / 1e9))
  cat(sprintf("Output:       %s\n", basename(out_file)))

  t_section <- Sys.time()
  BLOCK_WEEKS <- 4L
  LC_LEVELS   <- c("crop", "forest", "grassland", "urban_dense", "urban_diffuse")

  # --- 1. Load Section B output ---
  cat("\n[1] Load Section B output...\n")
  out_b <- readRDS_retry(in_b_file)
  events_pixel    <- as.data.table(out_b$events_pixel)
  pixel_event_map <- as.data.table(out_b$pixel_event_map)
  cat(sprintf("  events_pixel:    %s rows\n",
              format(nrow(events_pixel), big.mark = ",")))
  cat(sprintf("  pixel_event_map: %s rows\n",
              format(nrow(pixel_event_map), big.mark = ",")))

  # --- 2. Ensure NLCD + ecoregion present, restrict to standard LCs ---
  cat("\n[2] Join NLCD juliana + ecoregion (if missing); restrict to 5-LC universe...\n")
  if (!"nlcd_juliana" %in% names(events_pixel)) {
    v_nlcd <- as.data.table(readRDS_retry(config$nlcd_pixel_lookup))
    events_pixel <- merge(events_pixel,
                          v_nlcd[, .(pixel_id, nlcd_juliana)],
                          by = "pixel_id", all.x = TRUE)
    collapse_urban_to_2tier(events_pixel)
    rm(v_nlcd); gc(verbose = FALSE)
  }
  if (!"L2_code" %in% names(events_pixel)) {
    vp <- as.data.table(readRDS_retry(config$ecoregion_lookup))
    events_pixel <- merge(events_pixel,
                          vp[, .(pixel_id, L2_code)],
                          by = "pixel_id", all.x = TRUE)
    rm(vp); gc(verbose = FALSE)
  }
  events_pixel <- events_pixel[!is.na(L2_code) & L2_code != "0.0" &
                                nlcd_juliana %in% LC_LEVELS]
  cat(sprintf("  events after LC+eco filter: %s\n",
              format(nrow(events_pixel), big.mark = ",")))

  # --- 3. Per-event hit rates: ndvi, spei, OR ---
  cat("\n[3] Compute per-event hit rates per (stratum x signal_set)...\n")
  pew <- dcast(pixel_event_map,
               pixel_id + week_start + event_type ~ headline_signal,
               value.var = "hit")
  hit_signals <- intersect(c("ndvi_z", "spei_13w"), names(pew))
  if (length(hit_signals) < 2L) {
    stop("pixel_event_map missing expected headline signals; ",
         "found: ", paste(names(pew), collapse=", "))
  }
  ev_hits <- merge(events_pixel[, .(pixel_id, week_start, event_type,
                                     L2_code, nlcd_juliana)],
                   pew, by = c("pixel_id", "week_start", "event_type"))
  ev_hits[, hit_or  := ndvi_z | spei_13w]
  ev_hits[, hit_and := ndvi_z & spei_13w]  # bonus: AND ensemble for reference

  hit_rate_or_lc <- ev_hits[, .(
    n_events     = .N,
    hit_ndvi     = mean(ndvi_z,   na.rm = TRUE),
    hit_spei     = mean(spei_13w, na.rm = TRUE),
    hit_or       = mean(hit_or,   na.rm = TRUE),
    hit_and      = mean(hit_and,  na.rm = TRUE)
  ), by = .(L2_code, nlcd_juliana, event_type)]
  # Lift over best single signal (max of ndvi, spei)
  hit_rate_or_lc[, best_single := pmax(hit_ndvi, hit_spei)]
  hit_rate_or_lc[, lift_or_pts := 100 * (hit_or - best_single)]
  cat(sprintf("  hit_rate_or_lc: %s rows\n",
              format(nrow(hit_rate_or_lc), big.mark = ",")))

  # Domain-wide hit rate summary
  domain_summary <- list(
    onset    = ev_hits[event_type == "onset", .(
      n         = .N,
      hit_ndvi  = mean(ndvi_z,   na.rm = TRUE),
      hit_spei  = mean(spei_13w, na.rm = TRUE),
      hit_or    = mean(hit_or,   na.rm = TRUE),
      hit_and   = mean(hit_and,  na.rm = TRUE),
      lift_or_over_best_pts = 100 * (mean(hit_or, na.rm = TRUE) -
                                      max(mean(ndvi_z,   na.rm = TRUE),
                                          mean(spei_13w, na.rm = TRUE))))],
    recovery = ev_hits[event_type == "recovery", .(
      n         = .N,
      hit_ndvi  = mean(ndvi_z,   na.rm = TRUE),
      hit_spei  = mean(spei_13w, na.rm = TRUE),
      hit_or    = mean(hit_or,   na.rm = TRUE),
      hit_and   = mean(hit_and,  na.rm = TRUE),
      lift_or_over_best_pts = 100 * (mean(hit_or, na.rm = TRUE) -
                                      max(mean(ndvi_z,   na.rm = TRUE),
                                          mean(spei_13w, na.rm = TRUE))))]
  )
  rm(pew); gc(verbose = FALSE)

  # --- 4. Re-detect fires from align cache for block-based HSS ---
  cat("\n[4] Re-detect fires from align cache (ndvi_z + spei_13w @ headline op)...\n")
  t_fires <- Sys.time()
  dt_align <- as.data.table(readRDS_retry(in_a_file))
  ANOM_COLS    <- "ndvi_anom_mean"
  NDVI_SIGNALS <- "ndvi_z"
  keep <- c("pixel_id", "iso_year", "iso_week", "week_start",
            ANOM_COLS, "spei_13w", "L2_code")
  dt_align <- dt_align[, ..keep]
  gc(verbose = FALSE)
  setorder(dt_align, pixel_id, week_start)
  drop_px <- zstandardize_signals_per_pixel(dt_align, ANOM_COLS, NDVI_SIGNALS,
                                            min_valid_weeks = 30L)
  if (length(drop_px) > 0L) {
    dt_align <- dt_align[!pixel_id %in% drop_px]
    cat(sprintf("  dropped %d pixels with <30 valid weeks\n", length(drop_px)))
  }
  dt_align[, (ANOM_COLS) := NULL]

  if (smoke) {
    cat("\n  SMOKE MODE: restricting to ecoregions 9.4 + 8.4 for fire detection\n")
    dt_align <- dt_align[L2_code %in% c("9.4", "8.4")]
  }

  fires_list <- list()
  for (hdl in ENSEMBLE_OR_HEADLINES) {
    for (dir_ in c("onset", "recovery")) {
      fires <- detect_fires_global(dt_align, hdl$signal,
                                   hdl$z, hdl$K, dir_,
                                   is_raw_spei = grepl("^spei", hdl$signal))
      if (!is.null(fires)) fires_list[[length(fires_list) + 1L]] <- fires
    }
  }
  fires_all <- rbindlist(fires_list, use.names = TRUE, fill = TRUE)
  rm(fires_list); gc(verbose = FALSE)

  period_start_wk <- min(dt_align$week_start)
  period_end_wk   <- max(dt_align$week_start)
  rm(dt_align); gc(verbose = FALSE)
  cat(sprintf("  fires: %s rows (%.1f min)\n",
              format(nrow(fires_all), big.mark = ","),
              as.numeric(Sys.time() - t_fires, units = "mins")))

  # --- 5. Temporal-block contingency per (stratum x signal_set x direction) ---
  cat("\n[5] Compute temporal-block HSS for {ndvi, spei, or} x direction...\n")
  t_skill <- Sys.time()
  stratum_map <- unique(events_pixel[, .(pixel_id, L2_code, nlcd_juliana)])
  if (smoke) {
    stratum_map <- stratum_map[L2_code %in% c("9.4", "8.4")]
  }
  stratum_map[, stratum_key := sprintf("%s|%s", L2_code, nlcd_juliana)]

  setkey(fires_all, signal_col, direction)

  build_fires_for_set <- function(signal_set, dir_) {
    # ndvi -> just NDVI fires; spei -> just SPEI fires; or -> rbind both
    # (unique inside compute_temporal_block_contingency dedupes pixel-blocks).
    if (signal_set == "ndvi") {
      fires_all[.("ndvi_z",   dir_), nomatch = 0L, .(pixel_id, week_start)]
    } else if (signal_set == "spei") {
      fires_all[.("spei_13w", dir_), nomatch = 0L, .(pixel_id, week_start)]
    } else if (signal_set == "or") {
      rbind(
        fires_all[.("ndvi_z",   dir_), nomatch = 0L, .(pixel_id, week_start)],
        fires_all[.("spei_13w", dir_), nomatch = 0L, .(pixel_id, week_start)]
      )
    } else {
      stop("Unknown signal_set: ", signal_set)
    }
  }

  skill_rows <- list()
  for (signal_set in c("ndvi", "spei", "or")) {
    for (dir_ in c("onset", "recovery")) {
      ev_sub <- events_pixel[event_type == dir_, .(pixel_id, week_start)]
      f_sub  <- build_fires_for_set(signal_set, dir_)
      cont <- compute_temporal_block_contingency(
        ev_sub, f_sub, stratum_map,
        block_weeks    = BLOCK_WEEKS,
        period_start_wk = period_start_wk,
        period_end_wk   = period_end_wk
      )
      if (nrow(cont) > 0L) {
        cont <- compute_skill_metrics(cont)
        cont[, c("L2_code", "nlcd_juliana") :=
                tstrsplit(stratum_key, "|", fixed = TRUE)]
        cont[, `:=`(signal_set      = signal_set,
                    direction       = dir_,
                    z_threshold     = 1.5,
                    sustained_weeks = 2L,
                    lead_window     = 8L)]
        skill_rows[[length(skill_rows) + 1L]] <- cont
      }
    }
  }
  skill_or_lc <- rbindlist(skill_rows, use.names = TRUE, fill = TRUE)
  rm(skill_rows, fires_all); gc(verbose = FALSE)

  # --- 5b. Wide-format lift table: skill diff of OR vs best single ---
  cat("\n[5b] Compute HSS lift (OR vs max(NDVI, SPEI)) per stratum...\n")
  hss_wide <- dcast(skill_or_lc[, .(L2_code, nlcd_juliana, direction,
                                     signal_set, hss, pod, far)],
                    L2_code + nlcd_juliana + direction ~ signal_set,
                    value.var = c("hss", "pod", "far"))
  hss_wide[, best_single_hss := pmax(hss_ndvi, hss_spei, na.rm = TRUE)]
  hss_wide[, lift_or_hss     := hss_or - best_single_hss]
  hss_wide[, best_single_pod := pmax(pod_ndvi, pod_spei, na.rm = TRUE)]
  hss_wide[, lift_or_pod     := pod_or - best_single_pod]

  cat(sprintf("  skill_or_lc: %s rows (%.1f min)\n",
              format(nrow(skill_or_lc), big.mark = ","),
              as.numeric(Sys.time() - t_skill, units = "mins")))

  # --- 6. Assemble + save ---
  meta <- list(
    scope             = scope,
    scope_years       = if (scope == "10y") 2016:2025 else 2013:2025,
    headline_op       = "ndvi_z + spei_13w at z=1.5, K=2, lead +/-8wk",
    headlines         = ENSEMBLE_OR_HEADLINES,
    block_weeks       = BLOCK_WEEKS,
    lc_levels         = LC_LEVELS,
    signal_sets       = c("ndvi", "spei", "or"),
    or_definition     = "fires_or = union(ndvi_fires, spei_fires) at headline op",
    period_start_wk   = period_start_wk,
    period_end_wk     = period_end_wk,
    smoke             = smoke,
    n_events_in       = nrow(events_pixel),
    sources           = list(
      event_detection_nlcd = in_b_file,
      align_weekly         = in_a_file,
      nlcd_pixel_lookup    = config$nlcd_pixel_lookup
    ),
    runtime_minutes   = as.numeric(Sys.time() - t_section, units = "mins"),
    created           = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )

  out <- list(
    events_pixel_or   = events_pixel,
    hit_rate_or_lc    = hit_rate_or_lc,
    skill_or_lc       = skill_or_lc,
    skill_lift_wide   = hss_wide,
    domain_summary    = domain_summary,
    meta              = meta
  )

  cat(sprintf("\nSaving %s...\n", basename(out_file)))
  saveRDS_validated(out, out_file, compress = "xz")
  cat(sprintf("  wrote %.2f MB in %.1f min total\n",
              file.size(out_file) / 1e6, meta$runtime_minutes))

  # --- Quick summary ---
  options(datatable.print.nrows = 30L, datatable.print.topn = 30L)
  cat("\n--- Domain-wide hit rates (per-event POD-equivalent) ---\n")
  for (dir_ in c("onset", "recovery")) {
    d <- domain_summary[[dir_]]
    cat(sprintf("  %s n=%s: NDVI=%.1f%%  SPEI=%.1f%%  OR=%.1f%%  AND=%.1f%%  | OR lift over best single = +%.1f pts\n",
                dir_, format(d$n, big.mark=","),
                100*d$hit_ndvi, 100*d$hit_spei,
                100*d$hit_or, 100*d$hit_and,
                d$lift_or_over_best_pts))
  }

  cat("\n--- Top 10 strata by HSS lift (OR vs best single), n_blocks_total >= 5000 ---\n")
  big_strata <- skill_or_lc[signal_set == "or" & n_blocks_total >= 5000L,
                            .(L2_code, nlcd_juliana, direction)]
  show <- merge(big_strata, hss_wide, by = c("L2_code", "nlcd_juliana", "direction"))
  show <- show[is.finite(lift_or_hss)][order(-lift_or_hss)][1:10L]
  print(show[, .(L2_code, nlcd_juliana, direction,
                  hss_ndvi = round(hss_ndvi, 3),
                  hss_spei = round(hss_spei, 3),
                  hss_or   = round(hss_or, 3),
                  lift_hss = round(lift_or_hss, 3),
                  pod_or   = round(pod_or, 3),
                  far_or   = round(far_or, 3))])

  cat("\n--- Domain-wide HSS comparison (signal_set rollup, weighted by n_blocks_total) ---\n")
  agg <- skill_or_lc[, .(
    hss_weighted = weighted.mean(hss, w = n_blocks_total, na.rm = TRUE),
    pod_weighted = weighted.mean(pod, w = n_blocks_total, na.rm = TRUE),
    far_weighted = weighted.mean(far, w = n_blocks_total, na.rm = TRUE)
  ), by = .(signal_set, direction)]
  print(agg[order(direction, signal_set),
            .(direction, signal_set,
              hss = round(hss_weighted, 3),
              pod = round(pod_weighted, 3),
              far = round(far_weighted, 3))])

  invisible(out)
}

# ==============================================================================
# section_ensemble_multi
# ==============================================================================
# Extension of section_ensemble_or to a broader ensemble configuration grid.
# Tests Tier 1 (8 single-signal baselines) + Tier 3 (3 cross-family pairs)
# across a 3-z sweep at K=2 fixed. The headline question: does OR'ing a
# pair beat the best single component, and does that lift hold across z?
#
# Signal sets (11 total):
#   Tier 1 — single (8):  ndvi_z, deriv_w{03,07,14,30}_z, spei_{4,13,26}w
#   Tier 3 — cross-pair (3): ndvi_z + spei_{4w | 13w | 26w}
#
# Op sweep (3 z thresholds, K=2 fixed, lead +/-8wk):
#   z = 1.0 (lenient), z = 1.5 (headline), z = 2.0 (strict)
#
# Two skill layers per cell (= signal_set x z x direction x stratum):
#   1. Per-event hit rate (POD-equivalent) via match_fires_to_events_vec
#   2. Temporal-block contingency HSS via compute_temporal_block_contingency
#      (fires_dt for OR cells = union of constituent fires; the unique()
#      inside the contingency helper handles dedup of overlap blocks)
#
# Inputs:  event_detection_nlcd_{scope}.rds  + align cache + NLCD lookup
# Output:  ensemble_multi_{scope}.rds (long format; one row per cell)
#   - signal_sets       : config table (which signals compose each cell)
#   - hit_rate_multi_lc : long format per (signal_set x z x direction x stratum)
#   - skill_multi_lc    : long format with POD/FAR/HSS/ETS per cell
#   - lift_pairs_wide   : wide table per (z x direction x stratum) with
#                         best_single_hss + pair_hss + lift_hss
#   - meta              : params, runtime, sources
# ==============================================================================

ENSEMBLE_MULTI_OPS <- list(
  list(z = 1.0, K = 2L, lead_window = 8L, label = "lenient"),
  list(z = 1.5, K = 2L, lead_window = 8L, label = "headline"),
  list(z = 2.0, K = 2L, lead_window = 8L, label = "strict")
)

ENSEMBLE_MULTI_SIGNAL_SETS <- list(
  # Tier 1 — single signals (8)
  list(name = "ndvi_z",      components = "ndvi_z",       tier = "single"),
  list(name = "deriv_w03_z", components = "deriv_w03_z",  tier = "single"),
  list(name = "deriv_w07_z", components = "deriv_w07_z",  tier = "single"),
  list(name = "deriv_w14_z", components = "deriv_w14_z",  tier = "single"),
  list(name = "deriv_w30_z", components = "deriv_w30_z",  tier = "single"),
  list(name = "spei_4w",     components = "spei_4w",      tier = "single"),
  list(name = "spei_13w",    components = "spei_13w",     tier = "single"),
  list(name = "spei_26w",    components = "spei_26w",     tier = "single"),
  # Tier 3 — cross-family OR pairs (3)
  list(name = "ndvi_z_OR_spei_4w",  components = c("ndvi_z", "spei_4w"),  tier = "cross_pair"),
  list(name = "ndvi_z_OR_spei_13w", components = c("ndvi_z", "spei_13w"), tier = "cross_pair"),
  list(name = "ndvi_z_OR_spei_26w", components = c("ndvi_z", "spei_26w"), tier = "cross_pair")
)

section_ensemble_multi <- function(scope, smoke = FALSE) {
  cat("\n=== Section: ensemble_multi (scope =", scope,
      ", smoke =", smoke, ") ===\n")
  stopifnot(scope %in% c("10y", "13y"))

  in_b_file <- if (scope == "10y") config$event_detection_nlcd_10y else config$event_detection_nlcd_13y
  in_a_file <- if (scope == "10y") config$align_out_10y           else config$align_out_13y
  out_file  <- if (scope == "10y") config$ensemble_multi_10y      else config$ensemble_multi_13y

  if (!file.exists(in_b_file)) {
    stop("Section B output missing: ", in_b_file)
  }
  if (!file.exists(in_a_file)) {
    stop("align_weekly cache missing: ", in_a_file)
  }
  if (!file.exists(config$nlcd_pixel_lookup)) {
    stop("NLCD lookup missing: ", config$nlcd_pixel_lookup)
  }
  cat(sprintf("Section B in: %s (%.0f MB)\n",
              basename(in_b_file), file.size(in_b_file) / 1e6))
  cat(sprintf("align cache:  %s (%.1f GB)\n",
              basename(in_a_file), file.size(in_a_file) / 1e9))
  cat(sprintf("Output:       %s\n", basename(out_file)))

  t_section <- Sys.time()
  BLOCK_WEEKS <- 4L
  LC_LEVELS   <- c("crop", "forest", "grassland", "urban_dense", "urban_diffuse")

  # All unique constituent signals
  all_signals <- unique(unlist(lapply(ENSEMBLE_MULTI_SIGNAL_SETS,
                                      function(x) x$components)))
  ndvi_signals <- intersect(all_signals,
                            c("ndvi_z","deriv_w03_z","deriv_w07_z",
                              "deriv_w14_z","deriv_w30_z"))
  spei_signals <- intersect(all_signals, c("spei_4w","spei_13w","spei_26w"))
  anom_cols <- c(
    if ("ndvi_z"      %in% ndvi_signals) "ndvi_anom_mean",
    if ("deriv_w03_z" %in% ndvi_signals) "deriv_w03_anom_mean",
    if ("deriv_w07_z" %in% ndvi_signals) "deriv_w07_anom_mean",
    if ("deriv_w14_z" %in% ndvi_signals) "deriv_w14_anom_mean",
    if ("deriv_w30_z" %in% ndvi_signals) "deriv_w30_anom_mean"
  )
  z_thresholds <- sapply(ENSEMBLE_MULTI_OPS, function(o) o$z)

  cat(sprintf("\nSignal sets: %d (8 single + 3 cross-pair)\n",
              length(ENSEMBLE_MULTI_SIGNAL_SETS)))
  cat(sprintf("Constituent signals to detect: %d (%d NDVI + %d SPEI)\n",
              length(all_signals), length(ndvi_signals), length(spei_signals)))
  cat(sprintf("Op sweep: %s (K=2 fixed, lead +/-8wk fixed)\n",
              paste(sprintf("z=%.1f", z_thresholds), collapse = ", ")))

  # --- 1. Load Section B events ---
  cat("\n[1] Load Section B output (events_pixel only)...\n")
  out_b <- readRDS_retry(in_b_file)
  events_pixel <- as.data.table(out_b$events_pixel)
  rm(out_b); gc(verbose = FALSE)
  cat(sprintf("  events_pixel: %s rows\n", format(nrow(events_pixel), big.mark=",")))

  # --- 2. Join NLCD + ecoregion; restrict to 5-LC universe ---
  cat("\n[2] Join NLCD juliana + ecoregion; restrict to 5-LC universe...\n")
  if (!"nlcd_juliana" %in% names(events_pixel)) {
    v_nlcd <- as.data.table(readRDS_retry(config$nlcd_pixel_lookup))
    events_pixel <- merge(events_pixel,
                          v_nlcd[, .(pixel_id, nlcd_juliana)],
                          by = "pixel_id", all.x = TRUE)
    collapse_urban_to_2tier(events_pixel)
    rm(v_nlcd); gc(verbose = FALSE)
  }
  if (!"L2_code" %in% names(events_pixel)) {
    vp <- as.data.table(readRDS_retry(config$ecoregion_lookup))
    events_pixel <- merge(events_pixel,
                          vp[, .(pixel_id, L2_code)],
                          by = "pixel_id", all.x = TRUE)
    rm(vp); gc(verbose = FALSE)
  }
  events_pixel <- events_pixel[!is.na(L2_code) & L2_code != "0.0" &
                                nlcd_juliana %in% LC_LEVELS]
  cat(sprintf("  events after LC+eco filter: %s\n",
              format(nrow(events_pixel), big.mark = ",")))

  # --- 3. Load align cache; slim; z-standardize NDVI signals ---
  cat("\n[3] Load align cache, slim, z-standardize NDVI signals...\n")
  dt_align <- as.data.table(readRDS_retry(in_a_file))
  keep <- c("pixel_id", "iso_year", "iso_week", "week_start",
            anom_cols, spei_signals, "L2_code")
  dt_align <- dt_align[, ..keep]
  gc(verbose = FALSE)
  cat(sprintf("  align cache slimmed: %s rows x %d cols\n",
              format(nrow(dt_align), big.mark = ","), ncol(dt_align)))

  setorder(dt_align, pixel_id, week_start)
  drop_px <- zstandardize_signals_per_pixel(dt_align, anom_cols, ndvi_signals,
                                            min_valid_weeks = 30L)
  if (length(drop_px) > 0L) {
    dt_align <- dt_align[!pixel_id %in% drop_px]
    cat(sprintf("  dropped %d pixels with <30 valid weeks\n", length(drop_px)))
  }
  dt_align[, (anom_cols) := NULL]

  if (smoke) {
    cat("\n  SMOKE MODE: restricting to ecoregions 9.4 + 8.4 for fire detection\n")
    dt_align <- dt_align[L2_code %in% c("9.4", "8.4")]
  }

  # --- 4. Detect fires for all (signal x z x direction) combos ---
  cat(sprintf("\n[4] Detect fires for %d combos (%d signals x %d z x 2 dir)...\n",
              length(all_signals) * length(z_thresholds) * 2L,
              length(all_signals), length(z_thresholds)))
  t_fires <- Sys.time()
  fires_list <- list()
  fire_idx <- 0L
  total_fires <- length(all_signals) * length(z_thresholds) * 2L
  for (sig in all_signals) {
    for (z in z_thresholds) {
      for (dir_ in c("onset", "recovery")) {
        fire_idx <- fire_idx + 1L
        fires <- detect_fires_global(dt_align, sig, z, 2L, dir_,
                                     is_raw_spei = grepl("^spei", sig))
        if (!is.null(fires)) {
          fires_list[[length(fires_list) + 1L]] <- fires
        }
        if (fire_idx %% 12L == 0L) {
          elapsed <- as.numeric(Sys.time() - t_fires, units = "mins")
          cat(sprintf("    %d/%d fire cells (%.1f min, ETA %.1f min)\n",
                      fire_idx, total_fires, elapsed,
                      elapsed * (total_fires - fire_idx) / fire_idx))
        }
      }
    }
  }
  fires_all <- rbindlist(fires_list, use.names = TRUE, fill = TRUE)
  rm(fires_list); gc(verbose = FALSE)
  period_start_wk <- min(dt_align$week_start)
  period_end_wk   <- max(dt_align$week_start)
  rm(dt_align); gc(verbose = FALSE)
  cat(sprintf("  fires: %s rows (%.1f min)\n",
              format(nrow(fires_all), big.mark = ","),
              as.numeric(Sys.time() - t_fires, units = "mins")))

  # --- 5. Per-cell skill computation ---
  cat("\n[5] Compute per-event hits + temporal-block HSS for each cell...\n")
  t_skill <- Sys.time()
  stratum_map <- unique(events_pixel[, .(pixel_id, L2_code, nlcd_juliana)])
  if (smoke) {
    stratum_map <- stratum_map[L2_code %in% c("9.4", "8.4")]
  }
  stratum_map[, stratum_key := sprintf("%s|%s", L2_code, nlcd_juliana)]
  setkey(fires_all, signal_col, z_threshold, sustained_weeks, direction)

  build_fires_for_cell <- function(components, z, K, dir_) {
    # Components is a chr vec of constituent signals; OR = rbind union.
    parts <- lapply(components, function(sig) {
      fires_all[.(sig, z, K, dir_), nomatch = 0L,
                .(pixel_id, week_start)]
    })
    rbindlist(parts, use.names = TRUE)
  }

  hit_rows   <- list()
  skill_rows <- list()
  cell_idx <- 0L
  total_cells <- length(ENSEMBLE_MULTI_SIGNAL_SETS) * length(ENSEMBLE_MULTI_OPS) * 2L
  for (ss in ENSEMBLE_MULTI_SIGNAL_SETS) {
    for (op in ENSEMBLE_MULTI_OPS) {
      for (dir_ in c("onset", "recovery")) {
        cell_idx <- cell_idx + 1L
        ev_sub <- events_pixel[event_type == dir_,
                                .(pixel_id, week_start, L2_code, nlcd_juliana)]
        f_sub  <- build_fires_for_cell(ss$components, op$z, op$K, dir_)
        # Per-event hits
        matched <- match_fires_to_events_vec(ev_sub, f_sub, op$lead_window)
        ev_sub[, hit := matched$hit]
        # Aggregate per-stratum hit rate
        hit_summary <- ev_sub[, .(n_events = .N,
                                  hit_rate = mean(hit, na.rm = TRUE)),
                              by = .(L2_code, nlcd_juliana)]
        hit_summary[, `:=`(signal_set    = ss$name,
                            tier          = ss$tier,
                            z_threshold   = op$z,
                            sustained_weeks = op$K,
                            lead_window   = op$lead_window,
                            direction     = dir_)]
        hit_rows[[length(hit_rows) + 1L]] <- hit_summary
        # Block-based contingency + skill
        cont <- compute_temporal_block_contingency(
          ev_sub[, .(pixel_id, week_start)], f_sub, stratum_map,
          block_weeks    = BLOCK_WEEKS,
          period_start_wk = period_start_wk,
          period_end_wk   = period_end_wk
        )
        if (nrow(cont) > 0L) {
          cont <- compute_skill_metrics(cont)
          cont[, c("L2_code", "nlcd_juliana") :=
                  tstrsplit(stratum_key, "|", fixed = TRUE)]
          cont[, `:=`(signal_set      = ss$name,
                      tier            = ss$tier,
                      z_threshold     = op$z,
                      sustained_weeks = op$K,
                      lead_window     = op$lead_window,
                      direction       = dir_)]
          skill_rows[[length(skill_rows) + 1L]] <- cont
        }
        if (cell_idx %% 12L == 0L) {
          elapsed <- as.numeric(Sys.time() - t_skill, units = "mins")
          cat(sprintf("    %d/%d cells (%.1f min, ETA %.1f min)\n",
                      cell_idx, total_cells, elapsed,
                      elapsed * (total_cells - cell_idx) / cell_idx))
        }
      }
    }
  }
  hit_rate_multi_lc <- rbindlist(hit_rows,   use.names = TRUE, fill = TRUE)
  skill_multi_lc    <- rbindlist(skill_rows, use.names = TRUE, fill = TRUE)
  rm(hit_rows, skill_rows, fires_all); gc(verbose = FALSE)
  cat(sprintf("  hit_rate_multi_lc: %s rows; skill_multi_lc: %s rows (%.1f min)\n",
              format(nrow(hit_rate_multi_lc), big.mark = ","),
              format(nrow(skill_multi_lc),    big.mark = ","),
              as.numeric(Sys.time() - t_skill, units = "mins")))

  # --- 6. Cross-pair lift table (HSS) ---
  cat("\n[6] Build cross-pair lift table (HSS) per (z x direction x stratum)...\n")
  pair_specs <- Filter(function(ss) ss$tier == "cross_pair",
                       ENSEMBLE_MULTI_SIGNAL_SETS)
  lift_rows <- list()
  for (pair in pair_specs) {
    a <- pair$components[1]; b <- pair$components[2]
    pair_name <- pair$name
    A_skill <- skill_multi_lc[signal_set == a,
                              .(L2_code, nlcd_juliana, direction, z_threshold,
                                hss_a = hss, pod_a = pod, far_a = far)]
    B_skill <- skill_multi_lc[signal_set == b,
                              .(L2_code, nlcd_juliana, direction, z_threshold,
                                hss_b = hss, pod_b = pod, far_b = far)]
    P_skill <- skill_multi_lc[signal_set == pair_name,
                              .(L2_code, nlcd_juliana, direction, z_threshold,
                                hss_pair = hss, pod_pair = pod, far_pair = far,
                                n_blocks_total = n_blocks_total)]
    merged <- merge(merge(A_skill, B_skill,
                          by = c("L2_code","nlcd_juliana","direction","z_threshold")),
                    P_skill,
                    by = c("L2_code","nlcd_juliana","direction","z_threshold"))
    merged[, `:=`(pair_name = pair_name,
                  signal_a  = a,
                  signal_b  = b,
                  best_single_hss = pmax(hss_a, hss_b, na.rm = TRUE),
                  best_single_pod = pmax(pod_a, pod_b, na.rm = TRUE))]
    merged[, `:=`(lift_hss = hss_pair - best_single_hss,
                  lift_pod = pod_pair - best_single_pod)]
    lift_rows[[length(lift_rows) + 1L]] <- merged
  }
  lift_pairs_wide <- rbindlist(lift_rows, use.names = TRUE, fill = TRUE)
  rm(lift_rows)

  # --- 7. Assemble + save ---
  signal_sets_dt <- rbindlist(lapply(ENSEMBLE_MULTI_SIGNAL_SETS, function(ss) {
    data.table(name = ss$name, tier = ss$tier,
               components = paste(ss$components, collapse = " + "))
  }))

  meta <- list(
    scope             = scope,
    scope_years       = if (scope == "10y") 2016:2025 else 2013:2025,
    op_sweep          = ENSEMBLE_MULTI_OPS,
    signal_sets       = ENSEMBLE_MULTI_SIGNAL_SETS,
    block_weeks       = BLOCK_WEEKS,
    lc_levels         = LC_LEVELS,
    period_start_wk   = period_start_wk,
    period_end_wk     = period_end_wk,
    smoke             = smoke,
    n_events_in       = nrow(events_pixel),
    sources           = list(
      event_detection_nlcd = in_b_file,
      align_weekly         = in_a_file,
      nlcd_pixel_lookup    = config$nlcd_pixel_lookup
    ),
    runtime_minutes   = as.numeric(Sys.time() - t_section, units = "mins"),
    created           = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")
  )

  out <- list(
    signal_sets        = signal_sets_dt,
    hit_rate_multi_lc  = hit_rate_multi_lc,
    skill_multi_lc     = skill_multi_lc,
    lift_pairs_wide    = lift_pairs_wide,
    meta               = meta
  )

  cat(sprintf("\nSaving %s...\n", basename(out_file)))
  saveRDS_validated(out, out_file, compress = "xz")
  cat(sprintf("  wrote %.2f MB in %.1f min total\n",
              file.size(out_file) / 1e6, meta$runtime_minutes))

  # --- Quick summary ---
  options(datatable.print.nrows = 50L, datatable.print.topn = 50L)
  cat("\n--- Domain-wide hit rate by (signal_set x z x direction), weighted by n_events ---\n")
  hit_agg <- hit_rate_multi_lc[, .(
    hit_rate = weighted.mean(hit_rate, w = n_events, na.rm = TRUE),
    n_events_total = sum(n_events)
  ), by = .(signal_set, tier, z_threshold, direction)]
  setorder(hit_agg, direction, z_threshold, -hit_rate)
  print(hit_agg[, .(direction, z_threshold, signal_set, tier,
                    hit_rate = round(hit_rate, 3),
                    n_events = n_events_total)])

  cat("\n--- Domain-wide HSS by (signal_set x z x direction), weighted by n_blocks_total ---\n")
  hss_agg <- skill_multi_lc[, .(
    hss = weighted.mean(hss, w = n_blocks_total, na.rm = TRUE),
    pod = weighted.mean(pod, w = n_blocks_total, na.rm = TRUE),
    far = weighted.mean(far, w = n_blocks_total, na.rm = TRUE)
  ), by = .(signal_set, tier, z_threshold, direction)]
  setorder(hss_agg, direction, z_threshold, -hss)
  print(hss_agg[, .(direction, z_threshold, signal_set, tier,
                    hss = round(hss, 3),
                    pod = round(pod, 3),
                    far = round(far, 3))])

  cat("\n--- Pair lift summary: median lift_hss per (pair x z x direction), n>=3 cells ---\n")
  pair_lift_agg <- lift_pairs_wide[n_blocks_total >= 5000L,
                                   .(n_cells = .N,
                                     median_lift_hss = median(lift_hss, na.rm = TRUE),
                                     mean_lift_hss   = mean(lift_hss,   na.rm = TRUE),
                                     n_positive      = sum(lift_hss > 0, na.rm = TRUE),
                                     median_lift_pod = median(lift_pod, na.rm = TRUE)),
                                   by = .(pair_name, z_threshold, direction)]
  setorder(pair_lift_agg, direction, z_threshold, -median_lift_hss)
  print(pair_lift_agg[, .(direction, z_threshold, pair_name, n_cells,
                          median_lift_hss = round(median_lift_hss, 3),
                          n_positive,
                          median_lift_pod = round(median_lift_pod, 3))])

  invisible(out)
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
section_arg   <- gsub("^--section=",   "", grep("^--section=",   args, value = TRUE))
scope_arg     <- gsub("^--scope=",     "", grep("^--scope=",     args, value = TRUE))
null_reps_arg <- gsub("^--null-reps=", "", grep("^--null-reps=", args, value = TRUE))
smoke_flag    <- any(args == "--smoke")
if (length(scope_arg) == 0L) scope_arg <- "10y"  # default per design sketch
if (!scope_arg %in% c("10y", "13y")) stop("--scope must be '10y' or '13y'")

# --null-reps: only used by categorical_usdm. Default 5 reps (per Phase 1 plan).
# Pass 0 to skip the null model entirely (e.g., for fast smoke tests).
null_reps <- if (length(null_reps_arg) == 0L) 5L else as.integer(null_reps_arg)
if (is.na(null_reps) || null_reps < 0L) {
  stop("--null-reps must be a non-negative integer; got: ",
       paste(null_reps_arg, collapse = ","))
}

if (length(section_arg) == 0L) {
  cat("No --section= flag; section functions defined but nothing dispatched.\n")
  if (length(warnings()) > 0) print(warnings())
  invisible(NULL)
} else {

cat(sprintf("Section: %s | Scope: %s%s%s\n", section_arg, scope_arg,
            if (section_arg %in% c("categorical_usdm", "categorical_usdm_nlcd",
                                   "continuous_spei", "continuous_spei_nlcd",
                                   "event_detection", "event_detection_nlcd",
                                   "all"))
              sprintf(" | null_reps: %d", null_reps) else "",
            if (smoke_flag) " | SMOKE" else ""))

switch(section_arg,
  align_weekly             = section_align_weekly(scope_arg),
  categorical_usdm         = section_categorical_usdm(scope_arg, null_reps = null_reps),
  categorical_usdm_nlcd    = section_categorical_usdm_nlcd(scope_arg, null_reps = null_reps),
  within_week_diagnostic   = section_within_week_diagnostic(scope_arg),
  continuous_spei          = section_continuous_spei(scope_arg, null_reps = null_reps),
  continuous_spei_nlcd     = section_continuous_spei_nlcd(scope_arg, null_reps = null_reps),
  event_detection          = section_event_detection(scope_arg, null_reps = null_reps),
  event_detection_nlcd     = section_event_detection_nlcd(scope_arg, null_reps = null_reps, smoke = smoke_flag),
  flash_drought            = section_flash_drought(scope_arg, smoke = smoke_flag),
  ensemble_or              = section_ensemble_or(scope_arg, smoke = smoke_flag),
  ensemble_multi           = section_ensemble_multi(scope_arg, smoke = smoke_flag),
  qc                       = section_qc(scope_arg),
  all = {
    section_align_weekly(scope_arg)
    section_categorical_usdm(scope_arg, null_reps = null_reps)
    section_categorical_usdm_nlcd(scope_arg, null_reps = null_reps)
    section_within_week_diagnostic(scope_arg)
    section_continuous_spei(scope_arg, null_reps = null_reps)
    section_continuous_spei_nlcd(scope_arg, null_reps = null_reps)
    section_event_detection_nlcd(scope_arg, null_reps = null_reps)
    section_flash_drought(scope_arg)
    section_ensemble_or(scope_arg)
    section_qc(scope_arg)
  },
  stop("Unknown section: ", section_arg)
)

if (length(warnings()) > 0) print(warnings())  # per feedback_print_warnings_at_end
cat("\nDone.\n")

}  # end dispatch guard
