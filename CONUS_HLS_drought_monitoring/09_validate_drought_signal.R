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
# both the observed run and each null rep. Strata: each of the L2_code values
# in `eco_codes` plus "midwest_aggregate" (NA L2_code).
run_two_track_sweep <- function(dt, eco_codes, K_values, signal_names,
                                z_neg, z_pos, change_pos, change_neg,
                                progress_every = 25L, label = "obs") {
  binary_rows  <- list()
  ordinal_rows <- list()
  total_iter   <- (length(eco_codes) + 1L) * length(K_values) * length(signal_names)
  iter         <- 0L
  t_sweep      <- Sys.time()

  strata_list <- c(as.list(eco_codes), list(NA_character_))   # NA = midwest agg
  for (stratum in strata_list) {
    is_mw <- is.na(stratum)
    sub_full <- if (is_mw) dt else dt[L2_code == stratum]
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
run_two_track_correlation <- function(dt, eco_codes, K_values, signal_names) {
  bin_rows <- list()
  ord_rows <- list()
  strata_list <- c(as.list(eco_codes), list(NA_character_))

  for (stratum in strata_list) {
    is_mw <- is.na(stratum)
    sub_full <- if (is_mw) dt else dt[L2_code == stratum]
    if (nrow(sub_full) == 0L) next
    stratum_type <- if (is_mw) "midwest_aggregate" else "ecoregion"
    L2_label     <- if (is_mw) NA_character_       else as.character(stratum)
    sub_drought  <- sub_full[in_drought == TRUE]

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
section_arg   <- gsub("^--section=",   "", grep("^--section=",   args, value = TRUE))
scope_arg     <- gsub("^--scope=",     "", grep("^--scope=",     args, value = TRUE))
null_reps_arg <- gsub("^--null-reps=", "", grep("^--null-reps=", args, value = TRUE))
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

cat(sprintf("Section: %s | Scope: %s%s\n", section_arg, scope_arg,
            if (section_arg %in% c("categorical_usdm", "all"))
              sprintf(" | null_reps: %d", null_reps) else ""))

switch(section_arg,
  align_weekly      = section_align_weekly(scope_arg),
  categorical_usdm  = section_categorical_usdm(scope_arg, null_reps = null_reps),
  continuous_spei   = section_continuous_spei(scope_arg),
  event_detection   = section_event_detection(scope_arg),
  qc                = section_qc(scope_arg),
  all = {
    section_align_weekly(scope_arg)
    section_categorical_usdm(scope_arg, null_reps = null_reps)
    section_continuous_spei(scope_arg)
    section_event_detection(scope_arg)
    section_qc(scope_arg)
  },
  stop("Unknown section: ", section_arg)
)

if (length(warnings()) > 0) print(warnings())  # per feedback_print_warnings_at_end
cat("\nDone.\n")

}  # end dispatch guard
