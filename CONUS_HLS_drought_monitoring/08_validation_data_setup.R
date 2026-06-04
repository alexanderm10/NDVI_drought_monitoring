# ==============================================================================
# 08_validation_data_setup.R
#
# Phase 6 one-time setup: build validation/reference data products clipped to
# the Midwest DEWS extent (the actual analysis domain — NOT full CONUS).
#
# Six sections, each runnable independently via CLI:
#   ecoregion       — EPA Level II → 4 km pixel lookup
#   usdm_download   — fetch weekly USDM ZIPs for 2013-2025
#   usdm_process    — clip + rasterize USDM onto our 4 km grid
#   gridmet         — extract pr/pet at our pixel centroids
#   spei            — compute 1/3/6 month SPI/SPEI per pixel
#   qc              — alignment + completeness checks across all outputs
#   all             — run every section in order
#
# Usage (in container):
#   docker exec -w /workspace conus-hls-drought-monitor \
#     Rscript 08_validation_data_setup.R --section=ecoregion
#
# Outputs land in /data/validation/ (CIFS).
# ==============================================================================

# Add workspace-mounted user lib FIRST so SPEI (installed there) is findable.
local_lib <- "/workspace/.Rlibs"
if (dir.exists(local_lib)) .libPaths(c(local_lib, .libPaths()))

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(terra)
})

source("00_setup_paths.R")
source("00_posterior_functions.R")
paths <- setup_hls_paths()

# ------------------------------------------------------------------------------
# Config
# ------------------------------------------------------------------------------
config <- list(
  validation_dir   = paths$validation_data,                         # /data/validation
  midwest_ext_file = file.path(paths$validation_data, "midwest_extent.rds"),
  valid_pixels_file= file.path(paths$gam_models, "valid_pixels_landcover_filtered.rds"),
  target_crs       = "EPSG:5070",
  # External (read-only mount) sources
  ecoregion_shp    = "/gdo/epa_ecoregions/NA_CEC_Eco_Level2.shp",
  gridmet_pr_dir   = "/gdo/gridMET/pr",
  gridmet_pet_dir  = "/gdo/gridMET/pet",
  # USDM download
  usdm_url_tmpl    = "https://droughtmonitor.unl.edu/data/shapefiles_m/USDM_%s_M.zip",
  usdm_raw_dir     = file.path(paths$validation_data, "usdm_raw"),
  usdm_stage_dir   = file.path(paths$validation_data, "staging"),
  # Year range
  years              = 2013:2025,
  # Extended GridMET range for SPEI/SPI climatology (analysis output still 2013-2025).
  # /gdo/gridMET/{pr,pet}/ has 1984-2026; 2026 partial → drop.
  climatology_years  = 1984:2025
)

for (d in c(config$validation_dir, config$usdm_raw_dir, config$usdm_stage_dir)) {
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

# Load Midwest extent (built by phase0_verify_drought_events.R)
if (!file.exists(config$midwest_ext_file)) {
  stop("Midwest extent file missing — run phase0_verify_drought_events.R first")
}
midwest_extent <- readRDS(config$midwest_ext_file)
midwest_bbox   <- midwest_extent$bbox_albers
midwest_poly   <- st_as_sfc(midwest_bbox)

# Load valid pixels
valid_pixels <- readRDS(config$valid_pixels_file)
cat(sprintf("Loaded %s valid pixels (Midwest DEWS extent)\n",
            format(nrow(valid_pixels), big.mark = ",")))

# ==============================================================================
# SECTION: ecoregion
# ==============================================================================
section_ecoregion <- function() {
  cat("\n=== Section: ecoregion (EPA Level II → pixel lookup) ===\n")

  out_file_lookup <- file.path(config$validation_dir, "pixel_to_ecoregion_l2.rds")
  out_file_polys  <- file.path(config$validation_dir, "ecoregions_midwest_l2.rds")

  t0 <- Sys.time()
  cat("Reading EPA Level II ecoregions (45 MB shapefile)...\n")
  eco_all <- st_read(config$ecoregion_shp, quiet = TRUE)

  cat("Reprojecting to EPSG:5070 + healing topology...\n")
  eco_proj <- st_transform(eco_all, crs = config$target_crs)
  eco_proj <- st_make_valid(eco_proj)

  cat("Clipping to Midwest DEWS extent...\n")
  eco_clip <- suppressWarnings(st_intersection(eco_proj, midwest_poly))
  eco_clip$area_m2 <- as.numeric(st_area(eco_clip))
  eco_clip <- eco_clip[eco_clip$area_m2 > 1e6, ]  # > 1 km²
  cat(sprintf("  N polygons in-domain: %d, covering %d Level II ecoregions\n",
              nrow(eco_clip), length(unique(eco_clip$NA_L2CODE))))

  saveRDS_validated(eco_clip, out_file_polys)

  cat("Spatial join: pixels → ecoregion...\n")
  pixel_pts <- st_as_sf(valid_pixels[, c("pixel_id", "x", "y")],
                        coords = c("x", "y"), crs = config$target_crs)
  joined <- st_join(pixel_pts, eco_clip[, c("NA_L2CODE", "NA_L2NAME",
                                            "NA_L1CODE", "NA_L1NAME")],
                    left = TRUE)
  lookup <- data.frame(
    pixel_id = joined$pixel_id,
    L1_code  = joined$NA_L1CODE,
    L1_name  = joined$NA_L1NAME,
    L2_code  = joined$NA_L2CODE,
    L2_name  = joined$NA_L2NAME
  )
  saveRDS_validated(lookup, out_file_lookup)
  cat(sprintf("Saved lookup (%d pixels, %d unjoined). Elapsed %.1fs\n",
              nrow(lookup), sum(is.na(lookup$L2_code)),
              as.numeric(Sys.time() - t0, units = "secs")))
  invisible(lookup)
}

# ==============================================================================
# SECTION: usdm_download
# ==============================================================================
# ------------------------------------------------------------------------------
# Helper: ISO-week assignment.
# Returns a 1-row-per-input-date data.frame with iso_year, iso_week, week_start
# (Monday of the ISO week). Anchors weekly aggregation across year boundaries
# so e.g. 2025-12-29 (Monday) goes to iso_year=2026, iso_week=1.
# ------------------------------------------------------------------------------
iso_week_key <- function(dates) {
  # ISO 8601: week 1 contains the first Thursday of the year; weeks start Monday.
  iso_year <- as.integer(format(dates, "%G"))
  iso_week <- as.integer(format(dates, "%V"))
  # Monday of each date's ISO week:
  wday <- as.POSIXlt(dates)$wday          # 0=Sun, 1=Mon, ..., 6=Sat
  wday[wday == 0] <- 7                    # treat Sunday as day 7 of prior Mon-Sun week
  week_start <- dates - (wday - 1)
  data.frame(iso_year = iso_year, iso_week = iso_week, week_start = week_start)
}

# ==============================================================================
# SECTION: usdm_download
# ==============================================================================
section_usdm_download <- function() {
  cat("\n=== Section: usdm_download (all Tuesdays 2013-01-08 → 2025-12-30) ===\n")

  # USDM weekly publication = Tuesday-stamped URLs
  start <- as.Date("2013-01-08")  # first Tuesday in 2013
  end   <- as.Date("2025-12-30")
  all_tuesdays <- seq(start, end, by = 7)
  cat(sprintf("Target weeks: %d (Tuesdays %s → %s)\n",
              length(all_tuesdays), format(start), format(end)))

  n_existing <- 0; n_downloaded <- 0; n_failed <- 0
  failed <- character(0)
  for (d in all_tuesdays) {
    date_obj <- as.Date(d, origin = "1970-01-01")
    yyyymmdd <- format(date_obj, "%Y%m%d")
    zip_path <- file.path(config$usdm_raw_dir, sprintf("USDM_%s_M.zip", yyyymmdd))
    if (file.exists(zip_path) && file.size(zip_path) > 100e3) {
      n_existing <- n_existing + 1
      next
    }
    url <- sprintf(config$usdm_url_tmpl, yyyymmdd)
    # Retry up to 3 times with exponential backoff for transient net errors
    ok <- FALSE
    for (attempt in 1:3) {
      ok <- tryCatch({
        download.file(url, zip_path, quiet = TRUE, mode = "wb")
        TRUE
      }, error = function(e) FALSE, warning = function(w) FALSE)
      if (ok && file.size(zip_path) > 100e3) break
      if (file.exists(zip_path)) file.remove(zip_path)
      Sys.sleep(c(2, 5)[attempt])  # 2s then 5s before final attempt
      ok <- FALSE
    }
    if (ok && file.size(zip_path) > 100e3) {
      n_downloaded <- n_downloaded + 1
      if (n_downloaded %% 50 == 0)
        cat(sprintf("  ...%d downloaded (%d total processed)\n",
                    n_downloaded, n_existing + n_downloaded + n_failed))
    } else {
      n_failed <- n_failed + 1
      failed <- c(failed, yyyymmdd)
      if (file.exists(zip_path)) file.remove(zip_path)
    }
  }
  cat(sprintf("\nDownload summary: %d existing, %d new, %d failed\n",
              n_existing, n_downloaded, n_failed))
  if (n_failed > 0) {
    cat("Failed Tuesdays:\n  ", paste(head(failed, 10), collapse = ", "),
        if (length(failed) > 10) "..." else "", "\n")
  }
}

# ==============================================================================
# SECTION: usdm_process
# Clip each week's polygons to Midwest extent + rasterize to 4 km template,
# storing per-pixel max DM severity per week.
# ==============================================================================
section_usdm_process <- function() {
  cat("\n=== Section: usdm_process (clip + rasterize) ===\n")

  out_file <- file.path(config$validation_dir, "usdm_4km_weekly_2013_2025.rds")

  zip_files <- list.files(config$usdm_raw_dir, pattern = "^USDM_\\d{8}_M\\.zip$",
                          full.names = TRUE)
  cat(sprintf("USDM ZIPs available: %d\n", length(zip_files)))
  if (length(zip_files) == 0) stop("No USDM ZIPs — run usdm_download first")

  # Build the 4 km raster template from our valid pixels (Albers)
  cat("Building 4 km Albers raster template from valid pixels...\n")
  tmpl <- rast(xmin = midwest_bbox["xmin"], xmax = midwest_bbox["xmax"],
               ymin = midwest_bbox["ymin"], ymax = midwest_bbox["ymax"],
               resolution = 4000, crs = config$target_crs)
  cat(sprintf("  Template: %d x %d cells = %d total\n",
              ncol(tmpl), nrow(tmpl), ncell(tmpl)))

  # Pre-compute lookup from (cell_x, cell_y) → pixel_id for fast extraction.
  # Our valid pixels are on a regular 4 km grid; find matching cell IDs.
  pixel_cells <- cellFromXY(tmpl, as.matrix(valid_pixels[, c("x", "y")]))
  pixel_id_for_cell <- setNames(valid_pixels$pixel_id, pixel_cells)

  # Helper: process one week ZIP → data.frame(pixel_id, week_date, dm_max)
  process_one_week <- function(zip_path) {
    yyyymmdd <- sub("^USDM_(\\d{8})_M\\.zip$", "\\1", basename(zip_path))
    week_date <- as.Date(yyyymmdd, format = "%Y%m%d")
    unzip_dir <- file.path(config$usdm_stage_dir, yyyymmdd)
    if (!dir.exists(unzip_dir) ||
        length(list.files(unzip_dir, pattern = "\\.shp$")) == 0) {
      dir.create(unzip_dir, showWarnings = FALSE, recursive = TRUE)
      unzip(zip_path, exdir = unzip_dir)
    }
    shp <- list.files(unzip_dir, pattern = "\\.shp$", full.names = TRUE)[1]
    s <- tryCatch(st_read(shp, quiet = TRUE), error = function(e) NULL)
    if (is.null(s) || nrow(s) == 0) return(NULL)
    s <- st_transform(s, crs = config$target_crs)
    s_clip <- suppressWarnings(st_intersection(s, midwest_poly))
    if (nrow(s_clip) == 0) return(NULL)
    # Rasterize taking MAX of DM per cell. Convert to SpatVector for terra::rasterize.
    sv <- vect(s_clip)
    r  <- rasterize(sv, tmpl, field = "DM", fun = "max", background = NA)
    # Extract at our valid pixel cells only
    vals <- r[pixel_cells]
    data.frame(
      pixel_id  = valid_pixels$pixel_id,
      week_date = week_date,
      dm_max    = as.integer(vals[, 1])
    )
  }

  cat("Processing ZIPs (may take 30-60 min for full record)...\n")
  out_list <- vector("list", length(zip_files))
  t0 <- Sys.time()
  for (i in seq_along(zip_files)) {
    res <- tryCatch(process_one_week(zip_files[i]),
                    error = function(e) {
                      cat(sprintf("  WARN %s: %s\n", basename(zip_files[i]),
                                  conditionMessage(e)))
                      NULL
                    })
    out_list[[i]] <- res
    if (i %% 50 == 0) {
      elapsed <- as.numeric(Sys.time() - t0, units = "mins")
      cat(sprintf("  ...%d/%d weeks processed (%.1f min elapsed)\n",
                  i, length(zip_files), elapsed))
    }
  }
  ok <- sapply(out_list, is.data.frame)
  cat(sprintf("Successfully processed: %d / %d weeks\n", sum(ok), length(ok)))
  usdm_long <- do.call(rbind, out_list[ok])
  # Set NA → 0 (means "no drought in that week at that pixel")
  usdm_long$dm_max[is.na(usdm_long$dm_max)] <- -1L  # -1 = "out of USDM polygon" sentinel
  cat(sprintf("Output rows: %s\n", format(nrow(usdm_long), big.mark = ",")))
  saveRDS_validated(usdm_long, out_file)
  cat(sprintf("Saved %s (%.1f MB)\n", basename(out_file),
              file.size(out_file) / 1e6))
}

# ==============================================================================
# SECTION: gridmet
# Extract daily pr (mm) + pet (mm) from GridMET annual NetCDFs at our
# 129,310 pixel centroids using bilinear interpolation.
# Output is long-form: pixel_id × date × {pr, pet}.
# ==============================================================================
section_gridmet <- function() {
  cat("\n=== Section: gridmet (extract pr + pet at pixel centroids) ===\n")
  suppressPackageStartupMessages(library(data.table))

  out_file <- file.path(config$validation_dir, "gridmet_4km_daily_2013_2025.rds")

  pixel_pts <- vect(valid_pixels[, c("pixel_id", "x", "y")],
                    geom = c("x", "y"), crs = config$target_crs)
  cat(sprintf("Extracting at %s pixel centroids over years %d-%d\n",
              format(nrow(valid_pixels), big.mark = ","),
              min(config$years), max(config$years)))

  files_for_var <- function(var_dir, var_label) {
    f <- list.files(var_dir, pattern = paste0("^", var_label, "_\\d{4}\\.nc$"),
                    full.names = TRUE)
    yrs <- as.integer(sub(".*_(\\d{4})\\.nc$", "\\1", basename(f)))
    keep <- yrs %in% config$years
    list(files = f[keep][order(yrs[keep])], years = sort(yrs[keep]))
  }

  pr_info  <- files_for_var(config$gridmet_pr_dir,  "pr")
  pet_info <- files_for_var(config$gridmet_pet_dir, "pet")
  years    <- sort(intersect(pr_info$years, pet_info$years))
  cat(sprintf("  pr files: %d  |  pet files: %d  |  shared years to process: %d\n",
              length(pr_info$files), length(pet_info$files), length(years)))
  if (length(years) == 0L) stop("No overlapping pr/pet year files in config$years range")

  # Per-year extract that returns a data.table (single var, long form).
  extract_year_var <- function(file, var_label, yr) {
    r <- rast(file)
    pixel_pts_native <- project(pixel_pts, crs(r))
    vals <- terra::extract(r, pixel_pts_native, method = "bilinear")
    vals$ID <- NULL
    dates_yr <- seq(as.Date(paste0(yr, "-01-01")),
                    as.Date(paste0(yr, "-12-31")), by = 1)
    n_layers <- ncol(vals)
    dates_yr <- dates_yr[seq_len(n_layers)]
    dt <- data.table(
      pixel_id = rep(valid_pixels$pixel_id, n_layers),
      date     = rep(dates_yr, each = nrow(vals)),
      v        = as.numeric(as.matrix(vals))
    )
    setnames(dt, "v", var_label)
    rm(r, vals); gc(verbose = FALSE)
    dt
  }

  # Per-year merge keeps peak memory bounded; rbindlist at the end is zero-copy.
  per_year <- vector("list", length(years))
  for (i in seq_along(years)) {
    yr   <- years[i]
    pr_f <- pr_info$files[pr_info$years  == yr]
    pe_f <- pet_info$files[pet_info$years == yr]
    pr_dt  <- extract_year_var(pr_f, "pr",  yr)
    pet_dt <- extract_year_var(pe_f, "pet", yr)
    yr_merged <- merge(pr_dt, pet_dt, by = c("pixel_id", "date"), all = TRUE)
    per_year[[i]] <- yr_merged
    cat(sprintf("    %d: %d days, %s rows\n",
                yr, length(unique(yr_merged$date)),
                format(nrow(yr_merged), big.mark = ",")))
    rm(pr_dt, pet_dt, yr_merged); gc(verbose = FALSE)
  }

  cat("Combining annual data.tables (rbindlist)...\n")
  merged <- rbindlist(per_year, use.names = TRUE)
  rm(per_year); gc(verbose = FALSE)
  cat(sprintf("Final rows: %s\n", format(nrow(merged), big.mark = ",")))

  # gzip (not the saveRDS_validated default xz): xz on a 614M-row intermediate
  # ran at ~32 MB/min → 60+ min save. gzip finishes in ~5 min; file ~5-8 GB
  # vs ~2-3 GB but this RDS is consumed only by section_spei.
  saveRDS_validated(as.data.frame(merged), out_file, compress = "gzip")
  cat(sprintf("Saved %s (%.1f MB)\n", basename(out_file), file.size(out_file) / 1e6))
}

# ==============================================================================
# SECTION: gridmet_weekly
# Extracts pr + pet at pixel centroids across the FULL climatology range
# (config$climatology_years = 1984-2025), aggregated to ISO weeks inside the
# per-year loop (avoids materializing a daily-grain ~14 GB intermediate).
# Produces a single weekly file used by section_spei_weekly for distribution
# fitting (climatology) and standardized index output (2013-2025).
# ==============================================================================
section_gridmet_weekly <- function() {
  cat("\n=== Section: gridmet_weekly (extract pr+pet 1984-2025, ISO-week agg) ===\n")
  suppressPackageStartupMessages(library(data.table))

  yrs_clim <- config$climatology_years
  out_file <- file.path(config$validation_dir,
                        sprintf("gridmet_4km_weekly_%d_%d.rds",
                                min(yrs_clim), max(yrs_clim)))

  pixel_pts <- vect(valid_pixels[, c("pixel_id", "x", "y")],
                    geom = c("x", "y"), crs = config$target_crs)
  cat(sprintf("Extracting at %s pixel centroids over years %d-%d\n",
              format(nrow(valid_pixels), big.mark = ","),
              min(yrs_clim), max(yrs_clim)))

  files_for_var <- function(var_dir, var_label) {
    f <- list.files(var_dir, pattern = paste0("^", var_label, "_\\d{4}\\.nc$"),
                    full.names = TRUE)
    yrs <- as.integer(sub(".*_(\\d{4})\\.nc$", "\\1", basename(f)))
    keep <- yrs %in% yrs_clim
    list(files = f[keep][order(yrs[keep])], years = sort(yrs[keep]))
  }

  pr_info  <- files_for_var(config$gridmet_pr_dir,  "pr")
  pet_info <- files_for_var(config$gridmet_pet_dir, "pet")
  years    <- sort(intersect(pr_info$years, pet_info$years))
  cat(sprintf("  pr files: %d  |  pet files: %d  |  shared years to process: %d\n",
              length(pr_info$files), length(pet_info$files), length(years)))
  if (length(years) == 0L) stop("No overlapping pr/pet year files in climatology range")

  # Per-year extract → ISO-week aggregate. Returns a data.table keyed by
  # (pixel_id, iso_year, iso_week) with summed weekly pr_mm + pet_mm.
  # NOTE: an ISO week can straddle a calendar-year boundary (e.g. 2024-W01
  # starts 2024-01-01 which is a Mon; but 2023's last few days could share
  # 2024-W01). We tag rows by iso_year (not the loop's calendar year) so
  # the cross-year stitching is correct after rbindlist.
  extract_year_weekly <- function(pr_file, pet_file, yr) {
    r_pr  <- rast(pr_file)
    r_pet <- rast(pet_file)
    pixel_pts_native <- project(pixel_pts, crs(r_pr))

    vals_pr  <- terra::extract(r_pr,  pixel_pts_native, method = "bilinear")
    vals_pet <- terra::extract(r_pet, pixel_pts_native, method = "bilinear")
    vals_pr$ID  <- NULL
    vals_pet$ID <- NULL

    dates_yr <- seq(as.Date(paste0(yr, "-01-01")),
                    as.Date(paste0(yr, "-12-31")), by = 1)
    n_days <- ncol(vals_pr)
    dates_yr <- dates_yr[seq_len(n_days)]

    # Long-form daily for this year
    daily <- data.table(
      pixel_id = rep(valid_pixels$pixel_id, n_days),
      date     = rep(dates_yr, each = nrow(vals_pr)),
      pr       = as.numeric(as.matrix(vals_pr)),
      pet      = as.numeric(as.matrix(vals_pet))
    )

    # ISO week assignment
    wk <- iso_week_key(daily$date)
    daily[, `:=`(iso_year   = wk$iso_year,
                 iso_week   = wk$iso_week,
                 week_start = wk$week_start)]
    rm(wk, vals_pr, vals_pet, r_pr, r_pet)

    # Aggregate to weekly: sum pr + sum pet; preserve week_start (= week's Mon)
    weekly <- daily[, .(pr_mm    = sum(pr,  na.rm = TRUE),
                        pet_mm   = sum(pet, na.rm = TRUE),
                        n_days   = .N,
                        week_start = min(week_start)),
                    by = .(pixel_id, iso_year, iso_week)]
    rm(daily); gc(verbose = FALSE)
    weekly
  }

  per_year <- vector("list", length(years))
  t0 <- Sys.time()
  for (i in seq_along(years)) {
    yr   <- years[i]
    pr_f <- pr_info$files[pr_info$years  == yr]
    pe_f <- pet_info$files[pet_info$years == yr]
    yr_weekly <- extract_year_weekly(pr_f, pe_f, yr)
    per_year[[i]] <- yr_weekly
    el <- as.numeric(Sys.time() - t0, units = "mins")
    cat(sprintf("    %d: %s weekly rows; cumulative elapsed %.1f min\n",
                yr, format(nrow(yr_weekly), big.mark = ","), el))
    rm(yr_weekly); gc(verbose = FALSE)
  }

  cat("Combining annual data.tables (rbindlist) + re-aggregating cross-year ISO weeks...\n")
  combined <- rbindlist(per_year, use.names = TRUE)
  rm(per_year); gc(verbose = FALSE)

  # Re-aggregate: ISO weeks straddling Dec/Jan got split into two per-year
  # rows for the same (pixel_id, iso_year, iso_week). Combine.
  weekly_all <- combined[, .(pr_mm      = sum(pr_mm,  na.rm = TRUE),
                             pet_mm     = sum(pet_mm, na.rm = TRUE),
                             n_days     = sum(n_days),
                             week_start = min(week_start)),
                         by = .(pixel_id, iso_year, iso_week)]
  rm(combined); gc(verbose = FALSE)

  # Drop any week with fewer than 7 days of data (the first/last ISO week of
  # the full record can be partial; downstream rolling sums need consistent
  # weekly intensity, not partial accumulations).
  n_before <- nrow(weekly_all)
  weekly_all <- weekly_all[n_days == 7L]
  n_dropped <- n_before - nrow(weekly_all)
  cat(sprintf("  Dropped %s partial ISO weeks (n_days < 7) at record edges\n",
              format(n_dropped, big.mark = ",")))

  setorder(weekly_all, pixel_id, iso_year, iso_week)
  cat(sprintf("Final rows: %s  (unique pixels: %d, weeks: %d)\n",
              format(nrow(weekly_all), big.mark = ","),
              uniqueN(weekly_all$pixel_id),
              uniqueN(weekly_all[, .(iso_year, iso_week)])))

  saveRDS_validated(as.data.frame(weekly_all), out_file, compress = "gzip")
  cat(sprintf("Saved %s (%.1f MB) in %.1f min total\n",
              basename(out_file), file.size(out_file) / 1e6,
              as.numeric(Sys.time() - t0, units = "mins")))
}

# ==============================================================================
# SECTION: spei
# Compute SPI (precipitation-only) and SPEI (precipitation - PET water-balance)
# at 1/3/6 month accumulation periods, per pixel, monthly resolution.
# Uses data.table for per-pixel grouping — cleaner than dplyr cur_data_all()
# (deprecated since dplyr 1.1.0) and substantially faster.
# ==============================================================================
section_spei <- function() {
  cat("\n=== Section: spei (SPI + SPEI at 1/3/6 month) ===\n")

  if (!requireNamespace("SPEI", quietly = TRUE)) {
    stop("SPEI package not installed. Install to /workspace/.Rlibs/ first.")
  }
  suppressPackageStartupMessages(library(data.table))

  out_file <- file.path(config$validation_dir, "spei_4km_monthly_2013_2025.rds")
  in_file  <- file.path(config$validation_dir, "gridmet_4km_daily_2013_2025.rds")
  if (!file.exists(in_file)) stop("Run gridmet section first: ", in_file, " missing")

  cat("Loading daily GridMET extract...\n")
  daily <- as.data.table(readRDS(in_file))
  cat(sprintf("  %s daily rows\n", format(nrow(daily), big.mark = ",")))

  cat("Aggregating to monthly (sum pr, sum pet, deficit = pr - pet)...\n")
  daily[, `:=`(year  = as.integer(format(date, "%Y")),
               month = as.integer(format(date, "%m")))]
  monthly <- daily[, .(pr_mm  = sum(pr,  na.rm = TRUE),
                       pet_mm = sum(pet, na.rm = TRUE)),
                   by = .(pixel_id, year, month)]
  monthly[, deficit := pr_mm - pet_mm]
  setorder(monthly, pixel_id, year, month)
  rm(daily); gc(verbose = FALSE)
  cat(sprintf("  %s monthly rows\n", format(nrow(monthly), big.mark = ",")))

  # Helper: fit one index for a single per-pixel time series.
  # Returns numeric vector same length as `x`.
  fit_idx <- function(x, scale, fun, start_yr, start_mon) {
    ts_obj <- ts(x, start = c(start_yr, start_mon), frequency = 12)
    out <- tryCatch(as.numeric(fun(ts_obj, scale = scale, na.rm = TRUE)$fitted),
                    error = function(e) rep(NA_real_, length(x)))
    out
  }

  cat("Computing SPI(1,3,6) and SPEI(1,3,6) per pixel (data.table grouping)...\n")
  cat(sprintf("  Expected work: %d pixels x 6 indices = %s SPI/SPEI fits\n",
              uniqueN(monthly$pixel_id),
              format(uniqueN(monthly$pixel_id) * 6, big.mark = ",")))
  t0 <- Sys.time()

  # SPI on pr_mm
  monthly[, `:=`(
    spi_1 = fit_idx(pr_mm, 1, SPEI::spi, year[1], month[1]),
    spi_3 = fit_idx(pr_mm, 3, SPEI::spi, year[1], month[1]),
    spi_6 = fit_idx(pr_mm, 6, SPEI::spi, year[1], month[1])
  ), by = pixel_id]

  cat(sprintf("  SPI done: %.1f min\n",
              as.numeric(Sys.time() - t0, units = "mins")))

  # SPEI on deficit
  monthly[, `:=`(
    spei_1 = fit_idx(deficit, 1, SPEI::spei, year[1], month[1]),
    spei_3 = fit_idx(deficit, 3, SPEI::spei, year[1], month[1]),
    spei_6 = fit_idx(deficit, 6, SPEI::spei, year[1], month[1])
  ), by = pixel_id]

  cat(sprintf("  All done: %.1f min total\n",
              as.numeric(Sys.time() - t0, units = "mins")))

  saveRDS_validated(as.data.frame(monthly), out_file)
  cat(sprintf("Saved %s (%.1f MB)\n", basename(out_file), file.size(out_file) / 1e6))
}

# ==============================================================================
# SECTION: spei_weekly
# Compute weekly SPI + SPEI at 4-, 13-, 26-week accumulation windows
# (~1/3/6 month equivalents). Fits log-logistic/gamma distributions per pixel
# × week-of-year using the FULL 1984-2025 climatology (~42 obs per slot), then
# Z-scores ALL weekly observations. Saves standardized output for analysis
# years (config$years, default 2013-2025).
#
# Parallelization: future::future_lapply over 16 pixel-chunks (4 workers ×
# 4 super-chunks), recycling workers between super-chunks per the project
# parallel-R stability pattern.
# ==============================================================================
section_spei_weekly <- function() {
  cat("\n=== Section: spei_weekly (SPI+SPEI 4w/13w/26w, parallel) ===\n")

  if (!requireNamespace("SPEI", quietly = TRUE)) {
    stop("SPEI package not installed. Install to /workspace/.Rlibs/ first.")
  }
  suppressPackageStartupMessages({
    library(data.table)
    library(future)
    library(future.apply)
  })

  yrs_clim <- config$climatology_years
  yrs_out  <- config$years
  in_file  <- file.path(config$validation_dir,
                        sprintf("gridmet_4km_weekly_%d_%d.rds",
                                min(yrs_clim), max(yrs_clim)))
  out_file <- file.path(config$validation_dir,
                        sprintf("spei_4km_weekly_%d_%d.rds",
                                min(yrs_out), max(yrs_out)))
  if (!file.exists(in_file))
    stop("Run gridmet_weekly section first: ", in_file, " missing")

  cat("Loading weekly GridMET climatology...\n")
  weekly <- as.data.table(readRDS(in_file))
  cat(sprintf("  %s weekly rows over %d pixels, %d-%d ISO years\n",
              format(nrow(weekly), big.mark = ","),
              uniqueN(weekly$pixel_id),
              min(weekly$iso_year), max(weekly$iso_year)))

  # Deficit input for SPEI
  weekly[, deficit := pr_mm - pet_mm]
  setorder(weekly, pixel_id, iso_year, iso_week)

  # Per-pixel SPI/SPEI fitter. Input: one pixel's full weekly time series
  # (assumed sorted, frequency = 52). Returns same-length numeric Z-scores
  # for each (pr, deficit) × scale combination.
  # We use SPEI's ts-based interface with frequency=52 → fits 52 weekly
  # distributions per pixel from the full 42-year record (~42 obs per slot).
  WIN_SPI  <- c(4L, 13L, 26L)
  WIN_SPEI <- c(4L, 13L, 26L)
  fit_pixel <- function(pr_x, def_x) {
    # Frequency=52: SPEI package treats this as 52-period seasonality, fitting
    # one distribution per (cycle position) across all years. start=c(1,1) is
    # a synthetic anchor — only frequency matters for distribution fitting.
    ts_pr  <- ts(pr_x,  start = c(1, 1), frequency = 52)
    ts_def <- ts(def_x, start = c(1, 1), frequency = 52)

    safe_fit <- function(ts_obj, scale, fun) {
      tryCatch(
        as.numeric(fun(ts_obj, scale = scale, na.rm = TRUE)$fitted),
        error = function(e) rep(NA_real_, length(ts_obj))
      )
    }
    out <- list(
      spi_4w   = safe_fit(ts_pr,  WIN_SPI[1],  SPEI::spi),
      spi_13w  = safe_fit(ts_pr,  WIN_SPI[2],  SPEI::spi),
      spi_26w  = safe_fit(ts_pr,  WIN_SPI[3],  SPEI::spi),
      spei_4w  = safe_fit(ts_def, WIN_SPEI[1], SPEI::spei),
      spei_13w = safe_fit(ts_def, WIN_SPEI[2], SPEI::spei),
      spei_26w = safe_fit(ts_def, WIN_SPEI[3], SPEI::spei)
    )
    out
  }

  # Worker function: process a pre-filtered data.table chunk (subset of pixels).
  # Returns a data.table with the same row layout + 6 index columns.
  # Silence SPEI package's per-call print() chatter (no `verbose` param exists
  # in SPEI::spi/spei) by sink()-ing worker stdout to /dev/null. The data
  # return path is unaffected; only printed strings are dropped.
  compute_chunk <- function(chunk_dt) {
    setDTthreads(1L)  # avoid OpenMP-vs-future thread contention
    null_con <- file("/dev/null", open = "wt")
    sink(null_con, type = "output")
    on.exit({ sink(); close(null_con) }, add = TRUE)
    chunk_dt[, c("spi_4w", "spi_13w", "spi_26w",
                 "spei_4w", "spei_13w", "spei_26w") :=
      fit_pixel(pr_mm, deficit), by = pixel_id]
    chunk_dt
  }

  # Chunk pixels into N_CHUNKS slices; process N_WORKERS at a time, recycling
  # workers between super-chunks.
  N_WORKERS <- 4L
  N_CHUNKS  <- 16L  # 4 super-chunks of 4 chunks each
  options(future.globals.maxSize = 4 * 1024^3)

  all_pids   <- sort(unique(weekly$pixel_id))
  chunk_idx  <- split(seq_along(all_pids),
                      ceiling(seq_along(all_pids) /
                              ceiling(length(all_pids) / N_CHUNKS)))
  chunk_pids <- lapply(chunk_idx, function(idx) all_pids[idx])
  cat(sprintf("Pixel chunks: %d (size ~%d each), workers: %d\n",
              length(chunk_pids), length(chunk_pids[[1]]), N_WORKERS))

  # Pre-build per-chunk data.tables (avoid passing the full 9 GB+ weekly table
  # into each future worker via globals).
  pixel_chunks <- lapply(chunk_pids, function(pids) {
    weekly[pixel_id %in% pids]
  })
  rm(weekly); gc(verbose = FALSE)

  # Super-chunk loop: recycle workers between groups of N_WORKERS chunks.
  super_chunk_idx <- split(seq_along(pixel_chunks),
                           ceiling(seq_along(pixel_chunks) / N_WORKERS))
  result_chunks <- vector("list", length(pixel_chunks))
  t0 <- Sys.time()

  for (sci in seq_along(super_chunk_idx)) {
    s_idx <- super_chunk_idx[[sci]]
    cat(sprintf("Super-chunk %d/%d: dispatching chunks %s\n",
                sci, length(super_chunk_idx),
                paste(s_idx, collapse = ",")))
    plan(multisession, workers = N_WORKERS)
    res <- tryCatch(
      future_lapply(pixel_chunks[s_idx], compute_chunk,
                    future.seed = NULL),
      error = function(e) {
        cat(sprintf("  future_lapply ERROR: %s -- falling back to sequential\n",
                    conditionMessage(e)))
        plan(sequential)
        lapply(pixel_chunks[s_idx], compute_chunk)
      }
    )
    plan(sequential); gc(verbose = FALSE)
    for (j in seq_along(s_idx)) result_chunks[[s_idx[j]]] <- res[[j]]
    rm(res); gc(verbose = FALSE)
    el <- as.numeric(Sys.time() - t0, units = "mins")
    cat(sprintf("  Super-chunk %d done: cumulative %.1f min\n", sci, el))
  }
  rm(pixel_chunks); gc(verbose = FALSE)

  cat("Combining chunk results...\n")
  out_dt <- rbindlist(result_chunks, use.names = TRUE)
  rm(result_chunks); gc(verbose = FALSE)

  # Restrict output to analysis years
  cat(sprintf("Filtering to analysis years (%d-%d)...\n",
              min(yrs_out), max(yrs_out)))
  out_dt <- out_dt[iso_year %in% yrs_out]

  # Final column order
  keep_cols <- c("pixel_id", "iso_year", "iso_week", "week_start",
                 "pr_mm", "pet_mm", "deficit",
                 "spi_4w", "spi_13w", "spi_26w",
                 "spei_4w", "spei_13w", "spei_26w")
  out_dt <- out_dt[, ..keep_cols]
  setorder(out_dt, pixel_id, iso_year, iso_week)

  cat(sprintf("Final rows: %s (pixels=%d, weeks=%d, %d-%d)\n",
              format(nrow(out_dt), big.mark = ","),
              uniqueN(out_dt$pixel_id),
              uniqueN(out_dt[, .(iso_year, iso_week)]),
              min(yrs_out), max(yrs_out)))

  saveRDS_validated(as.data.frame(out_dt), out_file, compress = "gzip")
  cat(sprintf("Saved %s (%.1f MB) in %.1f min total\n",
              basename(out_file), file.size(out_file) / 1e6,
              as.numeric(Sys.time() - t0, units = "mins")))
}

# ==============================================================================
# SECTION: qc
# Alignment + completeness checks across all validation outputs.
# ==============================================================================
section_qc <- function() {
  cat("\n=== Section: qc (alignment + completeness) ===\n")

  checks <- list()

  expect_pixel_set <- valid_pixels$pixel_id

  qc_files <- c("pixel_to_ecoregion_l2.rds",
                "usdm_4km_weekly_2013_2025.rds",
                "gridmet_4km_daily_2013_2025.rds",
                "spei_4km_monthly_2013_2025.rds",
                sprintf("gridmet_4km_weekly_%d_%d.rds",
                        min(config$climatology_years),
                        max(config$climatology_years)),
                sprintf("spei_4km_weekly_%d_%d.rds",
                        min(config$years), max(config$years)))
  for (f in qc_files) {
    p <- file.path(config$validation_dir, f)
    if (!file.exists(p)) {
      cat(sprintf("  ⨯ MISSING: %s\n", f))
      checks[[f]] <- list(ok = FALSE, reason = "file missing")
      next
    }
    x <- readRDS(p)
    pids <- unique(x$pixel_id)
    missing_pids <- setdiff(expect_pixel_set, pids)
    extra_pids   <- setdiff(pids, expect_pixel_set)
    cat(sprintf("  ✓ %s — %d rows, %d unique pixels (missing %d, extra %d)\n",
                f, nrow(x), length(pids), length(missing_pids), length(extra_pids)))
    checks[[f]] <- list(ok = TRUE, n_rows = nrow(x),
                        missing_pixels = length(missing_pids),
                        extra_pixels = length(extra_pids))
  }

  saveRDS_validated(checks, file.path(config$validation_dir, "qc_report.rds"))
  cat("\nQC report saved.\n")
}

# ==============================================================================
# CLI dispatcher
# ==============================================================================
args <- commandArgs(trailingOnly = TRUE)
section_arg <- gsub("^--section=", "", grep("^--section=", args, value = TRUE))
# If no --section= flag was provided, do NOT dispatch — this lets the file be
# source()d from smoke-test drivers to use the function definitions only.
if (length(section_arg) == 0) {
  cat("No --section= flag; section functions defined but nothing dispatched.\n")
  if (length(warnings()) > 0) print(warnings())
  invisible(NULL)
} else {

cat("Section:", section_arg, "\n")

switch(section_arg,
  ecoregion       = section_ecoregion(),
  usdm_download   = section_usdm_download(),
  usdm_process    = section_usdm_process(),
  gridmet         = section_gridmet(),
  gridmet_weekly  = section_gridmet_weekly(),
  spei            = section_spei(),
  spei_weekly     = section_spei_weekly(),
  qc              = section_qc(),
  all = {
    section_ecoregion()
    section_usdm_download()
    section_usdm_process()
    section_gridmet()
    section_spei()
    section_qc()
  },
  stop("Unknown section: ", section_arg)
)

if (length(warnings()) > 0) print(warnings())  # per [[feedback-print-warnings-at-end]]
cat("\nDone.\n")

}  # end of dispatch guard
