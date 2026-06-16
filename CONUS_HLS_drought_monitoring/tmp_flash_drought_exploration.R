# ==============================================================================
# tmp_flash_drought_exploration.R
#
# Exploratory script: re-score event_detection skill on the "flash drought"
# subset, using a 4-week USDM trajectory definition (Otkin-style).
#
# Flash criterion (onset): pixel reaches D2+ within 4 weeks of onset week
#   AND starting state was none/D0. Equivalently: max(usdm[t..t+4wk]) >= 2.
# Flash criterion (recovery): pixel was at D2+ within 4 weeks BEFORE recovery
#   AND ended at none. Equivalently: max(usdm[t-4wk..t]) >= 2.
#
# Skill scoring reuses the headline-op hit booleans from pixel_event_map
# (ndvi_z + spei_13w at z=1.5, K=2). Reports per-(eco × LC) hit rate on
# flash subset vs all events.
#
# Not productionized — once results land, decide whether to bake into 09
# as `section_flash_drought` or keep as standalone.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

source("00_setup_paths.R")
source("00_posterior_functions.R")
paths <- setup_hls_paths()

cat("\n=== Load Section B events + headline hits + USDM weekly ===\n")
out_b <- readRDS_retry(file.path(paths$validation_data,
                                  "event_detection_nlcd_10y.rds"))
usdm <- as.data.table(readRDS_retry(file.path(paths$validation_data,
                                                "usdm_4km_weekly_2013_2025.rds")))
vp   <- as.data.table(readRDS_retry(file.path(paths$validation_data,
                                                "pixel_to_ecoregion_l2.rds")))
nlcd <- as.data.table(readRDS_retry(file.path(paths$gam_models,
                                                "valid_pixels_nlcd2019.rds")))
nlcd[nlcd_juliana %in% c("urban_high", "urban_med"),
     nlcd_juliana := "urban_dense"]
nlcd[nlcd_juliana %in% c("urban_low", "urban_open"),
     nlcd_juliana := "urban_diffuse"]

cat(sprintf("usdm rows: %s | events_pixel rows: %s | pixel_event_map rows: %s\n",
            format(nrow(usdm), big.mark=","),
            format(nrow(out_b$events_pixel), big.mark=","),
            format(nrow(out_b$pixel_event_map), big.mark=",")))

# --- USDM schema reconciliation ----------------------------------------------
# USDM table uses (week_date = Tuesday, dm_max ∈ {-1, 0, 1, 2, 3, 4}).
# Events use week_start = Monday of the same ISO week → week_start = week_date - 1L.
cat("\nUSDM columns:", paste(names(usdm), collapse=", "), "\n")
cat("USDM dm_max range:\n"); print(table(usdm$dm_max, useNA = "ifany"))
usdm[, week_start := week_date - 1L]

# --- Per-pixel rolling max for forward + backward 4-week windows -------------
cat("\n=== Compute per-pixel rolling max dm_max (5wk = current + 4wk window) ===\n")
setkey(usdm, pixel_id, week_start)
# n=5 = current week + 4 following (or preceding), covers an ~4-week look-ahead/-back
usdm[, usdm_max_next4 := frollmax(dm_max, n=5L, align="left",
                                  fill=NA, na.rm=TRUE), by=pixel_id]
usdm[, usdm_max_prev4 := frollmax(dm_max, n=5L, align="right",
                                  fill=NA, na.rm=TRUE), by=pixel_id]
cat("max_next4 distribution (sample of 100k):\n")
print(quantile(usdm[sample(.N, 100000L), usdm_max_next4],
               probs=c(0.5, 0.75, 0.9, 0.95, 0.99, 1), na.rm=TRUE))

# --- Tag events with flash flag ---------------------------------------------
cat("\n=== Tag events with flash flag ===\n")
ev <- as.data.table(out_b$events_pixel)
# Join trajectory by (pixel_id, week_start)
ev <- merge(ev, usdm[, .(pixel_id, week_start, usdm_max_next4, usdm_max_prev4)],
            by = c("pixel_id", "week_start"), all.x = TRUE)

# Onset: flash if usdm reaches D2+ (i.e., max_next4 >= 2) within 4 wk of onset
# Recovery: flash if usdm was D2+ (max_prev4 >= 2) within 4 wk prior to recovery
ev[, is_flash := fifelse(
  event_type == "onset",     usdm_max_next4 >= 2L,
  fifelse(event_type == "recovery", usdm_max_prev4 >= 2L, NA))]

# Also flag a less-strict "≥D1+" variant for sensitivity
ev[, is_flash_d1 := fifelse(
  event_type == "onset",     usdm_max_next4 >= 1L,
  fifelse(event_type == "recovery", usdm_max_prev4 >= 1L, NA))]

cat("\n--- onset events ---\n")
on <- ev[event_type == "onset"]
cat(sprintf("  total: %s\n  flash (D2+ within 4wk): %s (%.1f%%)\n  flash (D1+ within 4wk): %s (%.1f%%)\n",
            format(nrow(on), big.mark=","),
            format(sum(on$is_flash, na.rm=TRUE), big.mark=","),
            100*mean(on$is_flash, na.rm=TRUE),
            format(sum(on$is_flash_d1, na.rm=TRUE), big.mark=","),
            100*mean(on$is_flash_d1, na.rm=TRUE)))

cat("\n--- recovery events ---\n")
rc <- ev[event_type == "recovery"]
cat(sprintf("  total: %s\n  flash (D2+ in prev 4wk): %s (%.1f%%)\n  flash (D1+ in prev 4wk): %s (%.1f%%)\n",
            format(nrow(rc), big.mark=","),
            format(sum(rc$is_flash, na.rm=TRUE), big.mark=","),
            100*mean(rc$is_flash, na.rm=TRUE),
            format(sum(rc$is_flash_d1, na.rm=TRUE), big.mark=","),
            100*mean(rc$is_flash_d1, na.rm=TRUE)))

# --- Join hit booleans from pixel_event_map ----------------------------------
cat("\n=== Join headline-op hits + score flash vs all ===\n")
pem <- as.data.table(out_b$pixel_event_map)
pew <- dcast(pem, pixel_id + week_start + event_type ~ headline_signal,
             value.var = "hit")
# pew has cols pixel_id, week_start, event_type, ndvi_z, spei_13w

ev_full <- merge(ev[, .(pixel_id, week_start, event_type, is_flash, is_flash_d1)],
                 pew, by = c("pixel_id", "week_start", "event_type"))
ev_full <- merge(ev_full, vp[, .(pixel_id, L2_code)], by = "pixel_id")
ev_full <- merge(ev_full, nlcd[, .(pixel_id, nlcd_juliana)],
                 by = "pixel_id", all.x = TRUE)
ev_full <- ev_full[L2_code != "0.0" &
                   nlcd_juliana %in% c("crop", "forest", "grassland",
                                       "urban_dense", "urban_diffuse")]

cat("ev_full rows:", format(nrow(ev_full), big.mark=","), "\n")

# --- Domain-level headline numbers ------------------------------------------
hit_summary <- function(dt, label) {
  cat(sprintf("\n=== %s (n=%s) ===\n", label, format(nrow(dt), big.mark=",")))
  for (et in c("onset", "recovery")) {
    sub <- dt[event_type == et]
    cat(sprintf("  %s (n=%s):\n", et, format(nrow(sub), big.mark=",")))
    cat(sprintf("    ndvi hit:  %.1f%%   spei hit:  %.1f%%   either:  %.1f%%   both:  %.1f%%   ndvi only:  %.1f%%   spei only:  %.1f%%\n",
                100*mean(sub$ndvi_z, na.rm=TRUE),
                100*mean(sub$spei_13w, na.rm=TRUE),
                100*mean(sub$ndvi_z | sub$spei_13w, na.rm=TRUE),
                100*mean(sub$ndvi_z & sub$spei_13w, na.rm=TRUE),
                100*mean(sub$ndvi_z & !sub$spei_13w, na.rm=TRUE),
                100*mean(!sub$ndvi_z & sub$spei_13w, na.rm=TRUE)))
  }
}
hit_summary(ev_full, "ALL events")
hit_summary(ev_full[is_flash_d1 == TRUE], "FLASH (≥D1 within 4wk)")
hit_summary(ev_full[is_flash    == TRUE], "FLASH (≥D2 within 4wk, strict)")

# --- Per-stratum (eco × LC) headline (flash D2+ subset) ----------------------
strat_flash <- ev_full[is_flash == TRUE,
                       .(n_flash      = .N,
                         ndvi_hit     = mean(ndvi_z, na.rm=TRUE),
                         spei_hit     = mean(spei_13w, na.rm=TRUE),
                         either_hit   = mean(ndvi_z | spei_13w, na.rm=TRUE),
                         ndvi_only    = mean(ndvi_z & !spei_13w, na.rm=TRUE)),
                       by = .(L2_code, nlcd_juliana, event_type)]
strat_all <- ev_full[, .(n_all = .N,
                         ndvi_hit_all = mean(ndvi_z, na.rm=TRUE),
                         spei_hit_all = mean(spei_13w, na.rm=TRUE)),
                     by = .(L2_code, nlcd_juliana, event_type)]
strat <- merge(strat_flash, strat_all,
               by = c("L2_code","nlcd_juliana","event_type"))
strat[, ndvi_lift := ndvi_hit - ndvi_hit_all]
strat[, spei_lift := spei_hit - spei_hit_all]
strat[, pct_flash := round(100*n_flash/n_all, 1)]
strat <- strat[n_flash >= 50L]  # min sample for stable rates

cat("\n\n=== Top per-stratum NDVI lift on FLASH (≥D2) — onset, n_flash≥50 ===\n")
print(strat[event_type=="onset"][order(-ndvi_lift)][1:15,
      .(L2_code, nlcd_juliana, n_all, n_flash, pct_flash,
        ndvi_hit_all=round(ndvi_hit_all,3), ndvi_hit=round(ndvi_hit,3),
        ndvi_lift=round(ndvi_lift,3),
        spei_hit_all=round(spei_hit_all,3), spei_hit=round(spei_hit,3),
        spei_lift=round(spei_lift,3))])

cat("\n=== Same — recovery ===\n")
print(strat[event_type=="recovery"][order(-ndvi_lift)][1:15,
      .(L2_code, nlcd_juliana, n_all, n_flash, pct_flash,
        ndvi_hit_all=round(ndvi_hit_all,3), ndvi_hit=round(ndvi_hit,3),
        ndvi_lift=round(ndvi_lift,3),
        spei_hit_all=round(spei_hit_all,3), spei_hit=round(spei_hit,3),
        spei_lift=round(spei_lift,3))])

# --- Save intermediate for figure use later ----------------------------------
out_path <- file.path(paths$validation_data, "flash_drought_exploration.rds")
saveRDS(list(
  ev_full = ev_full,
  strat = strat,
  domain_summary = list(
    all_onset      = ev_full[event_type=="onset"],
    flash_d2_onset = ev_full[event_type=="onset"     & is_flash == TRUE],
    flash_d1_onset = ev_full[event_type=="onset"     & is_flash_d1 == TRUE],
    all_recov      = ev_full[event_type=="recovery"],
    flash_d2_recov = ev_full[event_type=="recovery"  & is_flash == TRUE],
    flash_d1_recov = ev_full[event_type=="recovery"  & is_flash_d1 == TRUE]
  ),
  meta = list(
    flash_d2_def = "max(usdm) in ±4wk window >= D2 (Otkin-style strict)",
    flash_d1_def = "max(usdm) in ±4wk window >= D1 (lenient)",
    headline_op = "ndvi_z z=1.5 K=2; spei_13w z=1.5 K=2; lead_window=8wk",
    created = format(Sys.time())
  )
), out_path, compress = "xz")
cat(sprintf("\nWrote %s (%.2f MB)\n", out_path, file.size(out_path) / 1e6))
cat("\nDone.\n")
