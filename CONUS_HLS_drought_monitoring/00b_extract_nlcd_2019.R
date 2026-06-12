# ==============================================================================
# 00b_extract_nlcd_2019.R
#
# Purpose: Extract standard NLCD 2019 16-class land cover at every valid pixel
#          and write a NEW pixel-attributes file with both raw NLCD codes and a
#          Juliana-style class collapse (crop / forest / grassland / urban_*).
#
# Why: Phase 6 Section A (continuous_spei) found NDVI-vs-SPEI skill REVERSES in
#      ecoregion 9.2 (Temperate Prairies / corn belt heartland; β = -0.124). The
#      working hypothesis is that the reversal is a *cropland* signal (irrigation
#      buffering + planting/harvest masking drought) rather than something
#      intrinsic to the ecoregion's climate.
#
#      The pipeline already carries a per-pixel land-cover code in
#      valid_pixels_landcover_filtered.rds, but it's a 9-class US Labeled
#      Ecosystems collapse where 8=Herbaceous lumps crop + grassland + pasture
#      into one bucket. That schema cannot distinguish corn from prairie.
#
#      This script adds the standard NLCD 16-class info so downstream Phase 6
#      analyses can stratify by (ecoregion × land_cover) and test the crop
#      hypothesis directly.
#
# Approach: terra::segregate() splits the 30m NLCD into one binary 0/1 layer per
#           class, then aggregate(fun="mean") over a 129x129 window converts
#           each layer to "fraction of cells matching this class" at ~4km. The
#           modal class is which.max across the layer stack; the dominance
#           fraction is max across the stack. One pass gives both.
#
# Why segregate+mean and NOT project(method="mode")?
#   terra::project does not support method="mode" (categorical resample is
#   "near" only). aggregate(fun="modal") gives the modal class alone but not
#   the dominance fraction, so we'd need two passes anyway. segregate+aggregate
#   is the standard terra idiom that gets both in one pass and stays within
#   bounded memory (terra streams the per-layer aggregate to disk).
#
# Hard constraint: DO NOT overwrite valid_pixels_landcover_filtered.rds. That
#   file is a pipeline invariant — scripts 03/04/06 do a row-count check
#   against it and hard-stop on drift (see memory feedback_pixel_count_
#   invariant). This script writes a NEW file (valid_pixels_nlcd2019.rds) and
#   never touches the invariant.
#
# Inputs:
#   - /data/input_data/nlcd/Annual_NLCD_LndCov_2019_CU_C1V0.tif (30m, EPSG:5070)
#   - /data/processed_ndvi/land_cover/nlcd_4km_albers.tif (HLS 4km template)
#   - /data/gam_models/valid_pixels_landcover_filtered.rds (129,310 valid pixels)
#
# Outputs:
#   - /data/processed_ndvi/land_cover/nlcd_2019_4km_modal.tif (INT1U)
#   - /data/processed_ndvi/land_cover/nlcd_2019_4km_modal_frac.tif (FLT4S)
#   - /data/gam_models/valid_pixels_nlcd2019.rds (legacy cols + nlcd_code_2019,
#       nlcd_juliana, modal_frac, nlcd_dominant)
#
# Runtime: ~20-35 min total (segregate+aggregate dominates).
# ==============================================================================

suppressPackageStartupMessages({
  library(terra)
  library(dplyr)
})

source("00_setup_paths.R")
source("00_posterior_functions.R")

hls_paths <- setup_hls_paths()

# terra config: control memory + temp space (segregate intermediates are big).
ensure_directory("/data/tmp_nlcd")
terraOptions(memfrac = 0.6, tempdir = "/data/tmp_nlcd")
options(timeout = 600)

cat("=== NLCD 2019 16-CLASS EXTRACTION TO VALID PIXELS ===\n")
cat("Start:", format(Sys.time()), "\n\n")

# ------------------------------------------------------------------------------
# Paths
# ------------------------------------------------------------------------------
nlcd_30m_path  <- "/data/input_data/nlcd/Annual_NLCD_LndCov_2019_CU_C1V0.tif"
template_path  <- file.path(hls_paths$processed_ndvi,
                            "land_cover/nlcd_4km_albers.tif")
valid_px_path  <- file.path(hls_paths$gam_models,
                            "valid_pixels_landcover_filtered.rds")
out_modal_path <- file.path(hls_paths$processed_ndvi,
                            "land_cover/nlcd_2019_4km_modal.tif")
out_frac_path  <- file.path(hls_paths$processed_ndvi,
                            "land_cover/nlcd_2019_4km_modal_frac.tif")
out_rds_path   <- file.path(hls_paths$gam_models,
                            "valid_pixels_nlcd2019.rds")

stopifnot(file.exists(nlcd_30m_path), file.exists(template_path),
          file.exists(valid_px_path))

# ------------------------------------------------------------------------------
# Step 1: Load template + valid_pixels, compute Midwest crop bbox
# ------------------------------------------------------------------------------
cat("Step 1: Load template + valid_pixels, compute crop bbox...\n")
tmpl4k <- rast(template_path)
v_pre  <- readRDS_retry(valid_px_path)
stopifnot(all(c("pixel_id", "x", "y", "nlcd_code") %in% names(v_pre)))
cat("  template extent:", as.vector(ext(tmpl4k)), "\n")
cat("  template res:   ", res(tmpl4k), "m\n")
cat("  valid pixels:   ", nrow(v_pre), "rows\n")

# Crop bbox = valid_pixels bbox + 10 km buffer (protects edges during resample).
# Snap to template grid so coords align cleanly.
buf <- 10000
bbox <- ext(min(v_pre$x) - buf, max(v_pre$x) + buf,
            min(v_pre$y) - buf, max(v_pre$y) + buf)
tmpl_crop <- crop(tmpl4k, bbox, snap = "out")
crop_ext  <- ext(tmpl_crop)
cat("  crop extent (snapped to template):", as.vector(crop_ext), "\n")
cat("  crop 4km dims:  ", nrow(tmpl_crop), "x", ncol(tmpl_crop), "\n")

# ------------------------------------------------------------------------------
# Step 2: Load + crop NLCD 30m
# ------------------------------------------------------------------------------
cat("\nStep 2: Load + crop NLCD 30m...\n")
nlcd30 <- rast(nlcd_30m_path)
cat("  full NLCD dims: ", nrow(nlcd30), "x", ncol(nlcd30), "\n")
cat("  full NLCD CRS:  ", as.character(crs(nlcd30, describe = TRUE)$name), "\n")
cat("  (datum-mismatch warnings between NLCD WGS84 and template NAD83 are\n",
    "   expected and harmless — both nominally EPSG:5070, sub-meter shift.)\n",
    sep = "")
nlcd30c <- crop(nlcd30, crop_ext, snap = "out")
cat("  cropped 30m dims:", nrow(nlcd30c), "x", ncol(nlcd30c),
    " (", format(ncell(nlcd30c), big.mark = ","), "cells)\n")

# ------------------------------------------------------------------------------
# Step 3: Segregate by class + aggregate to ~4km per-class fractions
# ------------------------------------------------------------------------------
# NLCD 16-class codes that may appear in Midwest (probe found 15 of 16; include
# 12=Ice/Snow defensively in case any pixels exist).
classes <- c(11L, 12L, 21L, 22L, 23L, 24L, 31L,
             41L, 42L, 43L, 52L, 71L, 81L, 82L, 90L, 95L)

cat("\nStep 3: segregate() + aggregate(fun='mean') for", length(classes),
    "classes...\n")
cat("  (binary layers \xc3\x97 16; aggregate fact=129; mean(0/1) = class fraction.)\n")
cat("  segregate start:", format(Sys.time()), "\n")
# other=0 is critical: this makes each per-class layer a true 0/1 binary so
# aggregate(fun='mean') gives the FRACTION of cells matching the class.
# A prior version used other=NA, which combined with na.rm=TRUE made every
# non-empty cell average to exactly 1.0 — which.max then tied on the first
# class with any presence (layer 1 = code 11 Open Water), classifying ~77%
# of valid pixels as water. Don't change this back.
nlcd_bin <- segregate(nlcd30c, classes = classes, other = 0L,
                      filename = tempfile(tmpdir = "/data/tmp_nlcd",
                                          fileext = ".tif"),
                      datatype = "INT1U",
                      gdal = c("COMPRESS=LZW", "TILED=YES"))
cat("  segregate done :", format(Sys.time()), "\n")

cat("  aggregate start:", format(Sys.time()), "\n")
nlcd_frac_agg <- aggregate(
  nlcd_bin,
  fact = 129L,
  fun  = "mean",
  na.rm = TRUE,
  filename = tempfile(tmpdir = "/data/tmp_nlcd", fileext = ".tif"),
  wopt = list(datatype = "FLT4S", gdal = c("COMPRESS=LZW", "TILED=YES"))
)
cat("  aggregate done :", format(Sys.time()), "\n")
cat("  aggregated dims:", nrow(nlcd_frac_agg), "x", ncol(nlcd_frac_agg),
    "x", nlyr(nlcd_frac_agg), "layers\n")

# ------------------------------------------------------------------------------
# Step 4: Derive modal class + modal fraction rasters
# ------------------------------------------------------------------------------
cat("\nStep 4: derive modal class + modal fraction...\n")
modal_idx_agg  <- which.max(nlcd_frac_agg)              # 1..16
modal_frac_agg <- max(nlcd_frac_agg, na.rm = TRUE)      # 0..1
modal_code_agg <- subst(modal_idx_agg,
                        from = seq_along(classes),
                        to   = classes)

# ------------------------------------------------------------------------------
# Step 5: Resample to exact 4km HLS template grid (cropped sub-template)
# ------------------------------------------------------------------------------
cat("\nStep 5: resample to exact HLS 4km grid...\n")
modal_code_4k <- resample(
  modal_code_agg, tmpl_crop, method = "near",
  datatype = "INT1U",
  filename = out_modal_path,
  overwrite = TRUE,
  gdal = c("COMPRESS=LZW", "TILED=YES")
)
modal_frac_4k <- resample(
  modal_frac_agg, tmpl_crop, method = "bilinear",
  datatype = "FLT4S",
  filename = out_frac_path,
  overwrite = TRUE,
  gdal = c("COMPRESS=LZW", "TILED=YES")
)
cat("  modal raster: ", out_modal_path, "\n")
cat("  frac raster:  ", out_frac_path, "\n")

# ------------------------------------------------------------------------------
# Step 6: Point-extract at valid_pixels (matches 02_doy_looped_norms.R:282-290)
# ------------------------------------------------------------------------------
cat("\nStep 6: point-extract at", nrow(v_pre), "valid pixels...\n")
v <- v_pre
pts <- vect(v[, c("x", "y")], geom = c("x", "y"), crs = "EPSG:5070")
v$nlcd_code_2019 <- extract(modal_code_4k, pts)[, 2]
v$modal_frac     <- extract(modal_frac_4k, pts)[, 2]

# ------------------------------------------------------------------------------
# Step 7: Juliana class collapse
# ------------------------------------------------------------------------------
# - forest = 41 (Deciduous) U 42 (Evergreen) U 43 (Mixed) U 90 (Woody Wetlands).
#   Juliana tested forest-wet vs forest empirically in her Chicago analysis and
#   found no meaningful difference; she relabeled forest-wet -> forest. We
#   follow that convention (memory: feedback_forest_wet_collapses_to_forest).
# - grassland = 71 (Grassland/Herbaceous) U 81 (Pasture/Hay). Lumped per
#   Juliana's Chicago convention; pasture and grassland phenology are similar
#   in non-irrigated systems.
# - other = 11 (Open Water), 12 (Ice/Snow), 31 (Barren), 52 (Shrub/Scrub),
#   95 (Emergent Herbaceous Wetlands). Minor in Midwest.
juliana_map <- c(
  "11" = "other",       "12" = "other",
  "21" = "urban_open",  "22" = "urban_low",
  "23" = "urban_med",   "24" = "urban_high",
  "31" = "other",
  "41" = "forest",      "42" = "forest",  "43" = "forest",
  "52" = "other",
  "71" = "grassland",   "81" = "grassland",
  "82" = "crop",
  "90" = "forest",
  "95" = "other"
)
v$nlcd_juliana  <- unname(juliana_map[as.character(v$nlcd_code_2019)])
v$nlcd_dominant <- v$modal_frac >= 0.60

# ------------------------------------------------------------------------------
# Step 8: Verification (hard-stop on failure)
# ------------------------------------------------------------------------------
cat("\nStep 8: verification...\n")
stopifnot(nrow(v) == 129310L)
stopifnot(sum(is.na(v$nlcd_code_2019)) == 0L)
stopifnot(sum(is.na(v$nlcd_juliana))  == 0L)
stopifnot(all(v$nlcd_code_2019 %in% classes))
cat("  invariants OK (n=", nrow(v),
    ", no NA codes, no spurious classes)\n", sep = "")

cat("\n--- Juliana class distribution (Midwest) ---\n")
print(sort(table(v$nlcd_juliana), decreasing = TRUE))

cat("\n--- Juliana class \xc3\x97 dominant flag (modal_frac >= 0.60) ---\n")
print(table(v$nlcd_juliana, v$nlcd_dominant, dnn = c("juliana", "dominant>=60%")))

cat("\n--- modal_frac summary ---\n")
print(summary(v$modal_frac))

cat("\n--- Cross-tab: legacy 9-class vs Juliana collapse ---\n")
cat("(legacy code lookup: 2=Shrub 3=HerbWet 4=Forest 5=WoodyWet 6=MixedWet",
    "7=Steppe 8=Herbaceous 9=Barren)\n")
print(table(legacy_9class = v$nlcd_code,
            juliana       = v$nlcd_juliana))

cat("\n--- Raw NLCD 16-class counts (Midwest, modal at 4km) ---\n")
print(sort(table(v$nlcd_code_2019), decreasing = TRUE))

# ------------------------------------------------------------------------------
# Step 9: Save valid_pixels_nlcd2019.rds (CIFS-safe atomic write)
# ------------------------------------------------------------------------------
cat("\nStep 9: save valid_pixels_nlcd2019.rds...\n")
saveRDS_validated(v, out_rds_path)
cat("  wrote:", out_rds_path, "\n")
cat("  size: ", round(file.info(out_rds_path)$size / 1024, 1), "KB\n")

# Confirm pipeline invariant untouched.
inv_mtime <- file.info(valid_px_path)$mtime
cat("  invariant file mtime (unchanged):", format(inv_mtime), "\n")

# ------------------------------------------------------------------------------
# Cleanup
# ------------------------------------------------------------------------------
cat("\nCleanup terra tempfiles...\n")
tmp_files <- list.files("/data/tmp_nlcd", full.names = TRUE)
if (length(tmp_files)) {
  unlink(tmp_files, recursive = FALSE)
  cat("  removed", length(tmp_files), "tempfiles\n")
}

cat("\n=== DONE ===\n")
cat("End:", format(Sys.time()), "\n")
print(warnings())
