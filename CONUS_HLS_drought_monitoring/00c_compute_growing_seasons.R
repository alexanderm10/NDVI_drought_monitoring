# ==============================================================================
# 00c_compute_growing_seasons.R
#
# Per-stratum empirical growing-season windows via derivative-threshold rule.
#
# Method (phenology-standard, similar in spirit to Juliana's 15% amplitude rule
# in 05_norms_growing_seasons.R but applied to dNDVI/dyday instead of NDVI):
#   Given the long-term normal NDVI curve y(yday) for a stratum:
#     dy = centered finite-difference of y over yday
#     spring window: yday in (minday, maxday] where minday = which.min(y),
#                                                  maxday = which.max(y)
#     fall window  : yday > maxday
#     spring_peak   = max(dy in spring window)    (yday of fastest greenup)
#     fall_trough   = min(dy in fall window)      (yday of fastest senescence)
#     spring_thresh = 0.25 * spring_peak
#     fall_thresh   = 0.25 * fall_trough          (negative)
#     season_start  = min(yday in spring window where dy >= spring_thresh)
#     season_end    = max(yday in fall window   where dy <= fall_thresh)
#   Interpretation: SOS = first day vigorous greenup is underway (rate >= 25%
#   of peak greenup rate). EOS = last day vigorous senescence is still under-
#   way (rate <= 25% of peak senescence rate). The bracket spans the period
#   of biophysically active change.
#
# Stratum levels written to a single lookup table:
#   - eco_lc : per (L2_code × nlcd_juliana) cell
#   - eco    : per ecoregion (all LCs combined)
#   - lc     : per land cover (all ecos combined)
#   - domain : all Midwest pixels
#
# Aggregation statistic across pixels (for each yday): median (robust; matches
# Fig 6/7/8 ribbon convention).
#
# Flat-normal fallback: if LCmax - LCmin < 0.10 NDVI (e.g., urban_dense in
# some ecos), the stratum window is replaced with the domain window and
# flagged qc_flag = "flat_normal".
#
# Output: /data/gam_models/growing_seasons_stratum.rds
#
# Usage (in container):
#   docker exec -w /workspace conus-hls-drought-monitor \
#     Rscript 00c_compute_growing_seasons.R
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(mgcv)
})

source("00_setup_paths.R")
source("00_posterior_functions.R")
paths <- setup_hls_paths()

FLAT_NORMAL_THRESH <- 0.10   # NDVI peak-to-trough below this → flat fallback
DERIV_FRAC         <- 0.25   # fraction of peak / trough derivative for SOS / EOS
SPLINE_K           <- 12L    # cyclic cubic spline knots (matches Juliana's k=12)

# ------------------------------------------------------------------------------
# Derivative-threshold rule applied to a (yday → mean_ndvi) curve.
# Returns a one-row data.table with start/end + diagnostics + qc_flag.
# ------------------------------------------------------------------------------
compute_growing_window <- function(yday, mean_ndvi, deriv_frac = DERIV_FRAC) {
  na_result <- function(flag, ...) {
    base <- data.table(season_start = NA_integer_, season_end = NA_integer_,
                       LCmin = NA_real_, LCmax = NA_real_,
                       minday = NA_integer_, maxday = NA_integer_,
                       spring_peak = NA_real_, fall_trough = NA_real_,
                       spring_thresh = NA_real_, fall_thresh = NA_real_,
                       qc_flag = flag)
    over <- list(...)
    for (nm in names(over)) base[[nm]] <- over[[nm]]
    base
  }

  ok <- !is.na(mean_ndvi)
  if (sum(ok) < 30L) return(na_result("too_few_yday"))
  ord <- order(yday[ok])
  y_raw <- mean_ndvi[ok][ord]; d_raw <- yday[ok][ord]

  # The per-yday median curve inherits day-to-day wiggle from the underlying
  # doy_looped_norms.rds — each DOY is an independent ±7-day spatial GAM fit
  # with no temporal smoothing. Fit a cyclic cubic spline (k=12, matches
  # Juliana's spatial_analysis/02 baseline GAM) so the derivative is meaningful.
  gam_fit <- tryCatch(
    gam(y_raw ~ s(d_raw, bs = "cc", k = SPLINE_K),
        knots = list(d_raw = c(0.5, 366.5))),
    error = function(e) NULL
  )
  if (is.null(gam_fit)) return(na_result("gam_fit_failed"))
  # Predict on a dense 1-day grid; the resulting smooth curve is what we'd
  # compute summary statistics from.
  d <- seq_len(365L)
  y <- as.numeric(predict(gam_fit, newdata = data.frame(d_raw = d)))

  LCmax <- max(y); LCmin <- min(y)
  maxday <- d[which.max(y)]; minday <- d[which.min(y)]
  if ((LCmax - LCmin) < FLAT_NORMAL_THRESH) {
    return(na_result("flat_normal", LCmin = LCmin, LCmax = LCmax,
                     minday = as.integer(minday), maxday = as.integer(maxday)))
  }

  # Centered finite-difference of the smoothed curve. With 1-day spacing on a
  # cyclic-spline prediction, this is effectively the analytical derivative.
  n <- length(y)
  deriv <- numeric(n)
  deriv[1] <- y[2] - y[1]
  deriv[n] <- y[n] - y[n - 1]
  deriv[2:(n - 1L)] <- (y[3:n] - y[1:(n - 2L)]) / 2

  # Spring window: from minday up to and including maxday.
  spring_mask <- d > minday & d <= maxday
  if (sum(spring_mask) < 2L) {
    return(na_result("degenerate_spring_window",
                     LCmin = LCmin, LCmax = LCmax,
                     minday = as.integer(minday), maxday = as.integer(maxday)))
  }
  spring_peak <- max(deriv[spring_mask], na.rm = TRUE)
  if (!is.finite(spring_peak) || spring_peak <= 0) {
    return(na_result("no_positive_spring_deriv",
                     LCmin = LCmin, LCmax = LCmax,
                     minday = as.integer(minday), maxday = as.integer(maxday),
                     spring_peak = spring_peak))
  }
  spring_thresh <- deriv_frac * spring_peak
  ss_candidates <- d[spring_mask & deriv >= spring_thresh]
  if (length(ss_candidates) == 0L) {
    return(na_result("no_spring_crossing",
                     LCmin = LCmin, LCmax = LCmax,
                     minday = as.integer(minday), maxday = as.integer(maxday),
                     spring_peak = spring_peak,
                     spring_thresh = spring_thresh))
  }
  season_start <- min(ss_candidates)

  # EOS via NDVI-level symmetry (not a second derivative crossing).
  #
  # Reasoning: SOS = first day of vigorous greenup defines an NDVI level —
  # the "start-of-vigorous-activity" value y(SOS). The growing season is then
  # the period during which the smoothed curve is at or above that level.
  # EOS = first yday after the summer peak where y returns to y(SOS).
  #
  # This is more robust than scanning the derivative for a 25% recovery because
  # many strata (grass, forest, urban) senesce gradually and the derivative
  # never recovers above threshold within the calendar year. The NDVI-level
  # crossing always exists for a unimodal yearly curve.
  sos_value <- y[d == season_start]
  fall_mask <- d > maxday
  fall_d <- d[fall_mask]; fall_y <- y[fall_mask]
  if (length(fall_d) == 0L) {
    return(na_result("degenerate_fall_window",
                     LCmin = LCmin, LCmax = LCmax,
                     minday = as.integer(minday), maxday = as.integer(maxday),
                     spring_peak = spring_peak, spring_thresh = spring_thresh))
  }
  fall_trough <- if (any(!is.na(deriv[fall_mask]))) min(deriv[fall_mask], na.rm = TRUE) else NA_real_
  fall_thresh <- if (is.finite(fall_trough)) deriv_frac * fall_trough else NA_real_

  se_candidates <- fall_d[fall_y <= sos_value]
  if (length(se_candidates) == 0L) {
    # Curve never falls back to the SOS level — pin EOS to end of year and flag.
    season_end <- max(fall_d)
    qc_flag_eos <- "no_eos_crossing"
  } else {
    season_end <- min(se_candidates)
    qc_flag_eos <- "ok"
  }

  data.table(season_start = as.integer(season_start),
             season_end   = as.integer(season_end),
             LCmin = LCmin, LCmax = LCmax,
             minday = as.integer(minday), maxday = as.integer(maxday),
             spring_peak = spring_peak, fall_trough = fall_trough,
             spring_thresh = spring_thresh, fall_thresh = fall_thresh,
             qc_flag = qc_flag_eos)
}

# ------------------------------------------------------------------------------
# Load + prep
# ------------------------------------------------------------------------------
cat("=== Per-stratum empirical growing-season windows ===\n")
cat("Loading doy_looped_norms.rds ...\n")
norms <- as.data.table(readRDS_retry(file.path(paths$gam_models,
                                               "doy_looped_norms.rds")))
cat(sprintf("  loaded %s rows (pixel × yday × normal-mean)\n",
            format(nrow(norms), big.mark = ",")))
# Keep only what we need
norms <- norms[, .(pixel_id, yday, mean)]

cat("Loading valid_pixels_nlcd2019.rds + ecoregion lookup ...\n")
nlcd <- as.data.table(readRDS_retry(file.path(paths$gam_models,
                                              "valid_pixels_nlcd2019.rds")))
nlcd <- nlcd[, .(pixel_id, nlcd_juliana)]
nlcd[nlcd_juliana %in% c("urban_high", "urban_med"),
     nlcd_juliana := "urban_dense"]
nlcd[nlcd_juliana %in% c("urban_low", "urban_open"),
     nlcd_juliana := "urban_diffuse"]

eco <- as.data.table(readRDS_retry(file.path(paths$validation_data,
                                             "pixel_to_ecoregion_l2.rds")))
eco <- eco[, .(pixel_id, L2_code)]

# Merge: pixel × yday × (mean, nlcd, eco)
norms <- merge(norms, nlcd, by = "pixel_id", all.x = TRUE)
norms <- merge(norms, eco,  by = "pixel_id", all.x = TRUE)
# Drop pixels we exclude from analysis
norms <- norms[!L2_code %in% c("0.0", "8.5") & nlcd_juliana != "other" &
               !is.na(L2_code) & !is.na(nlcd_juliana)]
cat(sprintf("  after eco/LC filter: %s rows, %s unique pixels\n",
            format(nrow(norms), big.mark = ","),
            format(uniqueN(norms$pixel_id), big.mark = ",")))

# ------------------------------------------------------------------------------
# Build per-stratum normal curves (median NDVI per yday)
# ------------------------------------------------------------------------------
cat("\nAggregating normal curves per stratum (median across pixels per yday)...\n")
curve_eco_lc <- norms[, .(mean_ndvi = median(mean, na.rm = TRUE),
                          n_pix     = uniqueN(pixel_id)),
                      by = .(L2_code, nlcd_juliana, yday)]
curve_eco    <- norms[, .(mean_ndvi = median(mean, na.rm = TRUE),
                          n_pix     = uniqueN(pixel_id)),
                      by = .(L2_code, yday)]
curve_lc     <- norms[, .(mean_ndvi = median(mean, na.rm = TRUE),
                          n_pix     = uniqueN(pixel_id)),
                      by = .(nlcd_juliana, yday)]
curve_dom    <- norms[, .(mean_ndvi = median(mean, na.rm = TRUE),
                          n_pix     = uniqueN(pixel_id)),
                      by = .(yday)]
cat(sprintf("  curves: eco_lc=%d, eco=%d, lc=%d, domain=%d\n",
            uniqueN(curve_eco_lc[, .(L2_code, nlcd_juliana)]),
            uniqueN(curve_eco$L2_code), uniqueN(curve_lc$nlcd_juliana), 1L))

# Free large parent table
rm(norms); invisible(gc(verbose = FALSE))

# ------------------------------------------------------------------------------
# Apply 15% rule per stratum
# ------------------------------------------------------------------------------
cat("\nApplying 15% threshold rule per stratum...\n")
win_eco_lc <- curve_eco_lc[, c(compute_growing_window(yday, mean_ndvi),
                                .(n_pix = max(n_pix))),
                            by = .(L2_code, nlcd_juliana)]
win_eco    <- curve_eco[, c(compute_growing_window(yday, mean_ndvi),
                             .(n_pix = max(n_pix))),
                         by = .(L2_code)]
win_lc     <- curve_lc[, c(compute_growing_window(yday, mean_ndvi),
                            .(n_pix = max(n_pix))),
                        by = .(nlcd_juliana)]
win_dom_raw <- compute_growing_window(curve_dom$yday, curve_dom$mean_ndvi)
win_dom <- cbind(data.table(stub = 1L), win_dom_raw,
                 n_pix = max(curve_dom$n_pix))
win_dom[, stub := NULL]

# Tag stratum_type
win_eco_lc[, stratum_type := "eco_lc"]
win_eco[,    stratum_type := "eco"]
win_lc[,     stratum_type := "lc"]
win_dom[,    stratum_type := "domain"]

# Domain fallback for flat / unclear strata
dom_start <- win_dom$season_start
dom_end   <- win_dom$season_end
fallback <- function(dt) {
  bad <- dt$qc_flag != "ok"
  dt[bad, season_start := dom_start]
  dt[bad, season_end   := dom_end]
  dt[bad, qc_flag      := paste0(qc_flag, ":domain_fallback")]
  dt[]
}
win_eco_lc <- fallback(win_eco_lc)
win_eco    <- fallback(win_eco)
win_lc     <- fallback(win_lc)
# (domain itself: no fallback needed; if domain fails we have a bigger problem)

# Combine into one table
all_cols <- c("stratum_type","L2_code","nlcd_juliana","n_pix",
              "season_start","season_end",
              "LCmin","LCmax","minday","maxday",
              "spring_peak","fall_trough","spring_thresh","fall_thresh","qc_flag")
for (dt in list(win_eco_lc, win_eco, win_lc, win_dom)) {
  for (col in setdiff(all_cols, names(dt))) dt[, (col) := NA]
}
setcolorder(win_eco_lc, all_cols)
setcolorder(win_eco,    all_cols)
setcolorder(win_lc,     all_cols)
setcolorder(win_dom,    all_cols)
windows <- rbindlist(list(win_eco_lc, win_eco, win_lc, win_dom), use.names = TRUE)

cat(sprintf("\n  total stratum rows: %d\n", nrow(windows)))
cat("  qc_flag breakdown:\n")
print(windows[, .N, by = qc_flag][order(-N)])

cat("\nDomain window:\n")
print(win_dom[, .(season_start, season_end, LCmin, LCmax, maxday)])

cat("\nFlagged strata (non-ok qc_flag):\n")
print(windows[!startsWith(qc_flag, "ok"),
              .(stratum_type, L2_code, nlcd_juliana, n_pix,
                LCmin, LCmax, qc_flag, season_start, season_end)])

# ------------------------------------------------------------------------------
# Save
# ------------------------------------------------------------------------------
out_path <- file.path(paths$gam_models, "growing_seasons_stratum.rds")
saveRDS(windows, out_path)
cat(sprintf("\n  wrote %s (%.1f KB)\n",
            out_path, file.size(out_path) / 1024))
cat("\nDone.\n")
