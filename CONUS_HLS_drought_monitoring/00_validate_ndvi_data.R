# 00_validate_ndvi_data.R
# Pre-pipeline validation of processed NDVI raster files.
# Run this BEFORE starting the aggregation pipeline to catch issues early.
#
# Usage:
#   Rscript 00_validate_ndvi_data.R              # validates 2013:2018
#   Rscript 00_validate_ndvi_data.R 2013 2025    # validates all years
#   Rscript 00_validate_ndvi_data.R 2018 2018    # single year

library(terra)
library(data.table)
library(future)
library(future.apply)

# ==============================================================================
# CONFIG
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)
year_start <- if (length(args) >= 1) as.integer(args[1]) else 2013L
year_end   <- if (length(args) >= 2) as.integer(args[2]) else 2018L
target_years <- year_start:year_end

# Auto-detect Docker vs host environment
in_docker <- file.exists("/.dockerenv") || file.exists("/workspace")

if (in_docker) {
  base_dir       <- "/data/processed_ndvi/daily"
  tile_list_file <- "/workspace/bulk_downloads/midwest_tiles_overlapping.txt"
  report_dir     <- "/workspace/validation_reports"
} else {
  base_dir       <- "/mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily"
  tile_list_file <- "bulk_downloads/midwest_tiles_overlapping.txt"
  if (!file.exists(tile_list_file)) {
    tile_list_file <- file.path(dirname(normalizePath(".")),
                                "CONUS_HLS_drought_monitoring/bulk_downloads/midwest_tiles_overlapping.txt")
  }
  report_dir <- "validation_reports"
}

sample_size    <- 500L
n_workers      <- 4L

dir.create(report_dir, recursive = TRUE, showWarnings = FALSE)
timestamp_str <- format(Sys.time(), "%Y%m%d_%H%M%S")

expected_tiles <- trimws(readLines(tile_list_file))
expected_tiles <- expected_tiles[nchar(expected_tiles) > 0]

cat("==============================================================================\n")
cat("  NDVI DATA VALIDATION\n")
cat("==============================================================================\n")
cat("  Years:          ", paste(range(target_years), collapse = " - "), "\n")
cat("  Base dir:       ", base_dir, "\n")
cat("  Expected tiles: ", length(expected_tiles), "\n")
cat("  Sample size:    ", sample_size, "files/year (Tier 2)\n")
cat("  Workers:        ", n_workers, "\n")
cat("  Report dir:     ", report_dir, "\n")
cat("  Timestamp:      ", timestamp_str, "\n")
cat("==============================================================================\n\n")

# Filename regex — matches HLS.{SENSOR}.{TILE}.{YEARYDAY}T{TIME}.v{VER}_NDVI.tif
fname_pattern <- "^HLS\\.(L30|S30)\\.(T[0-9]{2}[A-Z]{3})\\.([0-9]{4})([0-9]{3})T[0-9]{6}\\.v[0-9]+\\.[0-9]+_NDVI\\.tif$"

flagged_files <- list()

# ==============================================================================
# TIER 1: FILESYSTEM CHECKS
# ==============================================================================

cat("==============================================================================\n")
cat("  TIER 1: FILESYSTEM CHECKS\n")
cat("==============================================================================\n\n")

# ── 1.1 List all files per year ──────────────────────────────────────────────

cat("── 1.1 File listing ──\n")
all_file_data <- list()

for (yr in target_years) {
  year_dir <- file.path(base_dir, yr)
  if (!dir.exists(year_dir)) {
    cat("  [FAIL] Year", yr, "— directory does not exist:", year_dir, "\n")
    next
  }

  raw <- system(paste0("find '", year_dir, "' -maxdepth 1 -name '*_NDVI.tif' -printf '%f\\t%s\\n'"),
                intern = TRUE)

  if (length(raw) == 0) {
    cat("  [FAIL] Year", yr, "— no NDVI files found\n")
    next
  }

  parts <- strsplit(raw, "\t")
  dt <- data.table(
    filename = vapply(parts, `[`, character(1), 1),
    filesize = as.numeric(vapply(parts, `[`, character(1), 2)),
    year_dir = yr
  )

  all_file_data[[as.character(yr)]] <- dt
  cat("  [OK]   Year", yr, "—", formatC(nrow(dt), big.mark = ","), "files\n")
}

if (length(all_file_data) == 0) {
  stop("No data found for any target year. Check base_dir path.")
}

file_dt <- rbindlist(all_file_data)
cat("\n  Total files:", formatC(nrow(file_dt), big.mark = ","), "\n\n")


# ── 1.2 Filename parsing ────────────────────────────────────────────────────

cat("── 1.2 Filename parsing ──\n")

matches <- regmatches(file_dt$filename, regexec(fname_pattern, file_dt$filename))
parsed_ok <- vapply(matches, length, integer(1)) > 0

file_dt[, sensor := fifelse(parsed_ok, vapply(matches, `[`, character(1), 2), NA_character_)]
file_dt[, tile   := fifelse(parsed_ok, vapply(matches, `[`, character(1), 3), NA_character_)]
file_dt[, year   := fifelse(parsed_ok, as.integer(vapply(matches, `[`, character(1), 4)), NA_integer_)]
file_dt[, yday   := fifelse(parsed_ok, as.integer(vapply(matches, `[`, character(1), 5)), NA_integer_)]

n_unparseable <- sum(!parsed_ok)
if (n_unparseable == 0) {
  cat("  [OK]   All", formatC(nrow(file_dt), big.mark = ","), "filenames parse correctly\n\n")
} else {
  cat("  [FAIL]", n_unparseable, "filenames could not be parsed\n")
  bad_names <- file_dt[!parsed_ok, .(filename, year_dir)]
  cat("  Examples:\n")
  print(head(bad_names, 10))
  cat("\n")
  flagged_files[["unparseable"]] <- file_dt[!parsed_ok, .(
    filepath = file.path(base_dir, year_dir, filename),
    year = year_dir, tile = NA_character_,
    check_failed = "unparseable_filename",
    details = "Filename does not match expected HLS pattern"
  )]
}


# ── 1.3 Truncated files ─────────────────────────────────────────────────────

cat("── 1.3 Truncated file check (< 1KB) ──\n")

truncated <- file_dt[filesize < 1024]
if (nrow(truncated) == 0) {
  cat("  [OK]   No truncated files found\n\n")
} else {
  cat("  [WARN]", nrow(truncated), "files < 1KB\n")
  for (yr in unique(truncated$year_dir)) {
    n <- nrow(truncated[year_dir == yr])
    cat("    Year", yr, ":", n, "files\n")
  }
  cat("\n")
  flagged_files[["truncated"]] <- truncated[, .(
    filepath = file.path(base_dir, year_dir, filename),
    year = year_dir, tile = tile,
    check_failed = "truncated",
    details = paste0("File size: ", filesize, " bytes")
  )]
}

# Also report small files (< 100KB) as a warning
small <- file_dt[filesize >= 1024 & filesize < 102400]
if (nrow(small) > 0) {
  cat("  [INFO]", nrow(small), "files between 1KB-100KB (may be mostly-masked scenes)\n\n")
}


# ── 1.4 Tile coverage per year ───────────────────────────────────────────────

cat("── 1.4 Tile coverage ──\n")

parsed_dt <- file_dt[parsed_ok]
tile_year_counts <- parsed_dt[, .N, by = .(tile, year_dir)]

for (yr in target_years) {
  yr_tiles <- unique(tile_year_counts[year_dir == yr, tile])
  missing <- setdiff(expected_tiles, yr_tiles)
  extra   <- setdiff(yr_tiles, expected_tiles)

  if (length(missing) == 0) {
    cat("  [OK]   Year", yr, "— all", length(expected_tiles), "expected tiles present")
  } else {
    cat("  [WARN] Year", yr, "—", length(missing), "missing tiles out of", length(expected_tiles))
  }

  if (length(extra) > 0) {
    cat(" (+", length(extra), "extra)")
  }
  cat("\n")

  if (length(missing) > 0 && length(missing) <= 20) {
    cat("    Missing:", paste(missing, collapse = ", "), "\n")
  } else if (length(missing) > 20) {
    cat("    Missing (first 20):", paste(head(missing, 20), collapse = ", "), "...\n")
  }
}
cat("\n")


# ── 1.5 Cross-year tile consistency ──────────────────────────────────────────

cat("── 1.5 Cross-year tile consistency ──\n")

tile_matrix <- dcast(tile_year_counts, tile ~ year_dir, value.var = "N", fill = 0)
tiles_all_years <- tile_matrix[, {
  vals <- unlist(.SD)
  all(vals > 0)
}, by = tile, .SDcols = as.character(target_years)]

tiles_present_all <- sum(tiles_all_years$V1)
tiles_missing_some <- sum(!tiles_all_years$V1)

cat("  Tiles present in ALL target years:", tiles_present_all, "\n")
if (tiles_missing_some > 0) {
  cat("  [WARN] Tiles missing from at least one year:", tiles_missing_some, "\n")
  problem_tiles <- tiles_all_years[V1 == FALSE, tile]
  if (length(problem_tiles) <= 30) {
    for (pt in problem_tiles) {
      years_with <- tile_year_counts[tile == pt, year_dir]
      years_without <- setdiff(target_years, years_with)
      cat("    ", pt, "— missing in:", paste(years_without, collapse = ", "), "\n")
    }
  } else {
    cat("    (too many to list individually; see summary CSV)\n")
  }
}

# Per-year count stats
cat("\n  File counts per tile (across years):\n")
year_cols <- as.character(target_years)
for (yr_col in year_cols) {
  if (yr_col %in% names(tile_matrix)) {
    vals <- tile_matrix[[yr_col]]
    vals_nz <- vals[vals > 0]
    cat("    Year", yr_col, ": median =", median(vals_nz), ", min =", min(vals_nz),
        ", max =", max(vals_nz), ", tiles =", length(vals_nz), "\n")
  }
}
cat("\n")


# ── 1.6 Temporal coverage ───────────────────────────────────────────────────

cat("── 1.6 Temporal coverage (DOY gaps) ──\n")

month_breaks <- c(1, 32, 60, 91, 121, 152, 182, 213, 244, 274, 305, 335, 366)
month_names  <- c("Jan", "Feb", "Mar", "Apr", "May", "Jun",
                   "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

for (yr in target_years) {
  yr_data <- parsed_dt[year_dir == yr]
  if (nrow(yr_data) == 0) next

  yr_data[, month := findInterval(yday, month_breaks)]
  month_counts <- yr_data[, .N, by = month]

  missing_months <- setdiff(1:12, month_counts$month)
  if (length(missing_months) == 0) {
    cat("  [OK]   Year", yr, "— all 12 months have data\n")
  } else {
    cat("  [WARN] Year", yr, "— no data in:",
        paste(month_names[missing_months], collapse = ", "), "\n")
  }
}
cat("\n")


# ── 1.7 Sensor breakdown ────────────────────────────────────────────────────

cat("── 1.7 Sensor breakdown ──\n")

sensor_counts <- parsed_dt[, .N, by = .(year_dir, sensor)]
sensor_wide <- dcast(sensor_counts, year_dir ~ sensor, value.var = "N", fill = 0)
cat("  Year    L30        S30        Total\n")
cat("  ----    ---        ---        -----\n")
for (i in seq_len(nrow(sensor_wide))) {
  yr <- sensor_wide$year_dir[i]
  l30 <- if ("L30" %in% names(sensor_wide)) sensor_wide[i, L30] else 0
  s30 <- if ("S30" %in% names(sensor_wide)) sensor_wide[i, S30] else 0
  cat(sprintf("  %s    %-10s %-10s %s\n", yr,
              formatC(l30, big.mark = ","),
              formatC(s30, big.mark = ","),
              formatC(l30 + s30, big.mark = ",")))
}

# Sentinel-2 data should be absent before ~2016
s30_early <- sensor_counts[sensor == "S30" & year_dir < 2016]
if (nrow(s30_early) > 0) {
  cat("\n  [WARN] S30 (Sentinel-2) data found before 2016 — unexpected\n")
}
cat("\n")


# ── Tier 1 Summary ──────────────────────────────────────────────────────────

cat("==============================================================================\n")
cat("  TIER 1 SUMMARY\n")
cat("==============================================================================\n")
n_flagged_t1 <- sum(vapply(flagged_files, nrow, integer(1)))
cat("  Files parsed:    ", formatC(sum(parsed_ok), big.mark = ","), "\n")
cat("  Unparseable:     ", n_unparseable, "\n")
cat("  Truncated (<1KB):", nrow(truncated), "\n")
cat("  Flagged total:   ", n_flagged_t1, "\n")
if (n_flagged_t1 == 0) {
  cat("  STATUS: PASS\n")
} else {
  cat("  STATUS: REVIEW FLAGGED FILES\n")
}
cat("==============================================================================\n\n")


# ==============================================================================
# TIER 2: RASTER SAMPLING
# ==============================================================================

cat("==============================================================================\n")
cat("  TIER 2: RASTER SAMPLING CHECKS\n")
cat("==============================================================================\n\n")

validate_raster <- function(filepath) {
  result <- list(
    filepath = filepath,
    readable = FALSE,
    ndvi_range_ok = NA,
    ndvi_min = NA_real_,
    ndvi_max = NA_real_,
    pct_out_of_range = NA_real_,
    pct_extreme = NA_real_,
    dtype_ok = NA,
    has_crs = NA,
    non_empty = NA,
    n_valid = NA_integer_,
    n_total = NA_integer_,
    pct_valid = NA_real_,
    res_ok = NA,
    res_x = NA_real_,
    issues = character(0)
  )

  tryCatch({
    r <- terra::rast(filepath)
    result$readable <- TRUE

    result$has_crs <- !is.na(terra::crs(r)) && nchar(terra::crs(r)) > 0
    if (!result$has_crs) result$issues <- c(result$issues, "no_crs")

    res <- terra::res(r)
    result$res_x <- res[1]
    result$res_ok <- res[1] >= 25 && res[1] <= 35
    if (!result$res_ok) result$issues <- c(result$issues, paste0("resolution_", round(res[1])))

    dtype <- terra::datatype(r)
    result$dtype_ok <- dtype == "FLT4S"
    if (!result$dtype_ok) result$issues <- c(result$issues, paste0("dtype_", dtype))

    vals <- terra::values(r, mat = FALSE)
    valid_vals <- vals[!is.na(vals)]
    result$n_total <- length(vals)
    result$n_valid <- length(valid_vals)
    result$pct_valid <- result$n_valid / result$n_total * 100

    result$non_empty <- result$n_valid > 0
    if (!result$non_empty) result$issues <- c(result$issues, "all_na")

    if (result$non_empty) {
      result$ndvi_min <- min(valid_vals)
      result$ndvi_max <- max(valid_vals)

      # Pixels outside [-1, 1] — likely unmasked fill values or edge artifacts
      n_oor <- sum(valid_vals < -1 | valid_vals > 1)
      result$pct_out_of_range <- n_oor / length(valid_vals) * 100

      # Extreme values (|NDVI| > 10) — almost certainly fill value artifacts
      n_extreme <- sum(abs(valid_vals) > 10)
      result$pct_extreme <- n_extreme / length(valid_vals) * 100

      # Pass if <=5% of pixels are out of range (minor edge effects are normal)
      result$ndvi_range_ok <- result$pct_out_of_range <= 5.0

      if (!result$ndvi_range_ok) {
        result$issues <- c(result$issues,
                           sprintf("%.1f%%_out_of_range_(min=%.1f_max=%.1f)",
                                   result$pct_out_of_range,
                                   result$ndvi_min, result$ndvi_max))
      }
      if (result$pct_extreme > 0) {
        result$issues <- c(result$issues,
                           sprintf("%.2f%%_extreme_values_(|NDVI|>10)", result$pct_extreme))
      }
    }

    terra::tmpFiles(orphan = TRUE, remove = TRUE)
  }, error = function(e) {
    result$issues <<- c(result$issues, paste0("read_error: ", conditionMessage(e)))
  })

  result$issues <- paste(result$issues, collapse = "; ")
  result
}

# Sample files stratified by year
cat("── Sampling", sample_size, "files per year ──\n\n")

sample_results <- list()

for (yr in target_years) {
  yr_dt <- file_dt[year_dir == yr & parsed_ok[file_dt$year_dir == yr]]
  if (nrow(yr_dt) == 0) {
    cat("  Year", yr, "— no files to sample\n")
    next
  }

  set.seed(yr)
  n_sample <- min(sample_size, nrow(yr_dt))
  sample_idx <- sample(nrow(yr_dt), n_sample)
  sample_files <- file.path(base_dir, yr, yr_dt$filename[sample_idx])

  cat("  Year", yr, "— sampling", n_sample, "files...")

  plan(multisession, workers = n_workers)
  results <- future_lapply(sample_files, validate_raster, future.seed = TRUE)
  plan(sequential)
  gc(verbose = FALSE)

  results_dt <- rbindlist(lapply(results, as.data.table))
  results_dt[, year := yr]

  n_readable    <- sum(results_dt$readable)
  n_range_ok    <- sum(results_dt$ndvi_range_ok, na.rm = TRUE)
  n_dtype_ok    <- sum(results_dt$dtype_ok, na.rm = TRUE)
  n_crs_ok      <- sum(results_dt$has_crs, na.rm = TRUE)
  n_nonempty    <- sum(results_dt$non_empty, na.rm = TRUE)
  n_res_ok      <- sum(results_dt$res_ok, na.rm = TRUE)
  n_any_issue   <- sum(nchar(results_dt$issues) > 0)

  cat(" done\n")
  cat(sprintf("    readable: %d/%d | range: %d/%d | dtype: %d/%d | crs: %d/%d | non-empty: %d/%d | res: %d/%d\n",
              n_readable, n_sample, n_range_ok, n_sample, n_dtype_ok, n_sample,
              n_crs_ok, n_sample, n_nonempty, n_sample, n_res_ok, n_sample))

  if (n_any_issue > 0) {
    cat("    [ISSUES]", n_any_issue, "files had issues\n")
  }

  # NDVI value distribution summary
  if (sum(!is.na(results_dt$ndvi_min)) > 0) {
    cat(sprintf("    NDVI range across sample: [%.3f, %.3f] | median valid%%: %.1f%%\n",
                min(results_dt$ndvi_min, na.rm = TRUE),
                max(results_dt$ndvi_max, na.rm = TRUE),
                median(results_dt$pct_valid, na.rm = TRUE)))
    cat(sprintf("    Out-of-range pixels: median %.2f%% | extreme (|v|>10): median %.3f%%\n",
                median(results_dt$pct_out_of_range, na.rm = TRUE),
                median(results_dt$pct_extreme, na.rm = TRUE)))
  }
  cat("\n")

  sample_results[[as.character(yr)]] <- results_dt

  # Collect flagged
  issues_dt <- results_dt[nchar(issues) > 0]
  if (nrow(issues_dt) > 0) {
    flagged_files[[paste0("raster_", yr)]] <- issues_dt[, .(
      filepath = filepath,
      year = yr,
      tile = NA_character_,
      check_failed = "raster_check",
      details = issues
    )]
  }
}


# ── Tier 2 Summary ──────────────────────────────────────────────────────────

all_samples <- rbindlist(sample_results)

cat("==============================================================================\n")
cat("  TIER 2 SUMMARY\n")
cat("==============================================================================\n")
cat("  Total sampled:     ", nrow(all_samples), "\n")
cat("  Readable:          ", sum(all_samples$readable), "/", nrow(all_samples), "\n")
cat("  NDVI range valid:  ", sum(all_samples$ndvi_range_ok, na.rm = TRUE), "/", nrow(all_samples),
    "(<=5% pixels outside [-1,1])\n")
cat("  Data type correct: ", sum(all_samples$dtype_ok, na.rm = TRUE), "/", nrow(all_samples), "\n")
cat("  CRS present:       ", sum(all_samples$has_crs, na.rm = TRUE), "/", nrow(all_samples), "\n")
cat("  Non-empty:         ", sum(all_samples$non_empty, na.rm = TRUE), "/", nrow(all_samples), "\n")
cat("  Resolution ~30m:   ", sum(all_samples$res_ok, na.rm = TRUE), "/", nrow(all_samples), "\n")
cat("\n")
cat("  Out-of-range pixel stats (across all sampled files):\n")
cat(sprintf("    Median %% pixels outside [-1,1]: %.2f%%\n",
            median(all_samples$pct_out_of_range, na.rm = TRUE)))
cat(sprintf("    Median %% extreme pixels (|v|>10): %.3f%%\n",
            median(all_samples$pct_extreme, na.rm = TRUE)))
cat(sprintf("    Files with any extreme values: %d / %d\n",
            sum(all_samples$pct_extreme > 0, na.rm = TRUE), nrow(all_samples)))

n_flagged_t2 <- sum(nchar(all_samples$issues) > 0)
if (n_flagged_t2 == 0) {
  cat("  STATUS: PASS\n")
} else {
  cat("  STATUS: REVIEW —", n_flagged_t2, "files with issues\n")
}
cat("==============================================================================\n\n")


# ==============================================================================
# FINAL REPORT
# ==============================================================================

cat("==============================================================================\n")
cat("  FINAL REPORT\n")
cat("==============================================================================\n\n")

# Combine all flagged
if (length(flagged_files) > 0) {
  all_flagged <- rbindlist(flagged_files, fill = TRUE)
  flagged_path <- file.path(report_dir, paste0("validation_flagged_files_", timestamp_str, ".csv"))
  fwrite(all_flagged, flagged_path)
  cat("  Flagged files:", nrow(all_flagged), "\n")
  cat("  Saved to:", flagged_path, "\n\n")
} else {
  all_flagged <- data.table()
  cat("  No flagged files!\n\n")
}

# Summary CSV
summary_dt <- data.table(
  year = target_years,
  total_files = vapply(target_years, function(yr) {
    nrow(file_dt[year_dir == yr])
  }, integer(1)),
  tiles_found = vapply(target_years, function(yr) {
    length(unique(parsed_dt[year_dir == yr, tile]))
  }, integer(1)),
  tiles_expected = length(expected_tiles),
  pct_tiles = vapply(target_years, function(yr) {
    round(length(unique(parsed_dt[year_dir == yr, tile])) / length(expected_tiles) * 100, 1)
  }, numeric(1)),
  truncated_files = vapply(target_years, function(yr) {
    nrow(file_dt[year_dir == yr & filesize < 1024])
  }, integer(1)),
  sample_n = vapply(target_years, function(yr) {
    if (as.character(yr) %in% names(sample_results)) nrow(sample_results[[as.character(yr)]]) else 0L
  }, integer(1)),
  sample_readable_pct = vapply(target_years, function(yr) {
    if (as.character(yr) %in% names(sample_results)) {
      sr <- sample_results[[as.character(yr)]]
      round(sum(sr$readable) / nrow(sr) * 100, 1)
    } else NA_real_
  }, numeric(1)),
  sample_range_ok_pct = vapply(target_years, function(yr) {
    if (as.character(yr) %in% names(sample_results)) {
      sr <- sample_results[[as.character(yr)]]
      round(sum(sr$ndvi_range_ok, na.rm = TRUE) / nrow(sr) * 100, 1)
    } else NA_real_
  }, numeric(1)),
  median_valid_pct = vapply(target_years, function(yr) {
    if (as.character(yr) %in% names(sample_results)) {
      round(median(sample_results[[as.character(yr)]]$pct_valid, na.rm = TRUE), 1)
    } else NA_real_
  }, numeric(1)),
  median_pct_out_of_range = vapply(target_years, function(yr) {
    if (as.character(yr) %in% names(sample_results)) {
      round(median(sample_results[[as.character(yr)]]$pct_out_of_range, na.rm = TRUE), 2)
    } else NA_real_
  }, numeric(1)),
  median_pct_extreme = vapply(target_years, function(yr) {
    if (as.character(yr) %in% names(sample_results)) {
      round(median(sample_results[[as.character(yr)]]$pct_extreme, na.rm = TRUE), 3)
    } else NA_real_
  }, numeric(1))
)

summary_path <- file.path(report_dir, paste0("validation_summary_", timestamp_str, ".csv"))
fwrite(summary_dt, summary_path)

cat("  Summary table:\n\n")
print(summary_dt)
cat("\n  Saved to:", summary_path, "\n\n")

# Overall verdict
total_flagged <- nrow(all_flagged)
if (total_flagged == 0) {
  cat("  ============================================\n")
  cat("  VERDICT: ALL CHECKS PASSED\n")
  cat("  Safe to proceed with aggregation pipeline.\n")
  cat("  ============================================\n")
} else {
  cat("  ============================================\n")
  cat("  VERDICT: REVIEW REQUIRED —", total_flagged, "flagged files\n")
  cat("  Check:", flagged_path, "\n")
  cat("  ============================================\n")
}

cat("\nValidation completed at", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
