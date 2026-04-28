# ==============================================================================
# 01b_combine_year_files.R
#
# Purpose: Combine per-year aggregated NDVI files into the single timeseries
#          file consumed by scripts 02-06.
#
# Inputs:  aggregated_years/ndvi_4km_YYYY.rds  (one per year, written by 01)
# Output:  conus_4km_ndvi_timeseries.rds
#
# Usage:
#   Rscript 01b_combine_year_files.R                     # 2013-2025
#   Rscript 01b_combine_year_files.R 2013 2025           # explicit year range
#   Rscript 01b_combine_year_files.R --force             # overwrite existing
#
# Validation performed:
#   - All expected year files exist
#   - All year files share the same column schema
#   - Cross-year duplicates are reported (broken down by sensor) and trigger
#     an error; should be zero since `year` is derived from date and
#     partitions the data exactly, and within-year tile overlaps are already
#     median-collapsed by script 01
#   - Post-combine summary: rows, unique pixels, year coverage, sensor mix,
#     NDVI range, output file size
#
# Replaces the 6-line inline snippet that previously lived in WORKFLOW.md.
# ==============================================================================

library(dplyr)

source("00_setup_paths.R")
hls_paths <- get_hls_paths()

# ==============================================================================
# CLI
# ==============================================================================

args <- commandArgs(trailingOnly = TRUE)
force <- "--force" %in% args
numeric_args <- as.integer(args[grepl("^[0-9]+$", args)])

if (length(numeric_args) == 0) {
  expected_years <- 2013:2025
} else if (length(numeric_args) == 1) {
  expected_years <- numeric_args[1]
} else if (length(numeric_args) == 2) {
  expected_years <- numeric_args[1]:numeric_args[2]
} else {
  expected_years <- numeric_args
}

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  input_dir   = file.path(hls_paths$gam_models, "aggregated_years"),
  output_file = file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.rds"),
  expected_columns = c("pixel_id", "x", "y", "sensor", "date",
                       "year", "yday", "NDVI")
)

cat("=== COMBINE YEAR FILES ===\n")
cat("Started:        ", as.character(Sys.time()), "\n")
cat("Input dir:      ", config$input_dir, "\n")
cat("Output file:    ", config$output_file, "\n")
cat("Expected years: ", paste(range(expected_years), collapse = "-"),
    sprintf(" (%d years)\n", length(expected_years)))
cat("Force overwrite:", force, "\n\n")

# ==============================================================================
# SKIP-IF-EXISTS
# ==============================================================================

if (file.exists(config$output_file) && !force) {
  out_mtime  <- file.info(config$output_file)$mtime
  in_files   <- list.files(config$input_dir, pattern = "ndvi_4km_\\d{4}\\.rds$",
                           full.names = TRUE)
  in_mtimes  <- file.info(in_files)$mtime
  newest_in  <- if (length(in_mtimes)) max(in_mtimes) else as.POSIXct(NA)

  cat("Output already exists:\n")
  cat("  ", config$output_file, "\n")
  cat("  Modified:        ", as.character(out_mtime), "\n")
  cat("  Newest input:    ", as.character(newest_in), "\n")

  if (!is.na(newest_in) && newest_in > out_mtime) {
    stop("Output is older than at least one input year file. ",
         "Re-run with --force to rebuild.")
  } else {
    cat("\nOutput is up-to-date. Use --force to rebuild anyway.\n")
    quit(save = "no", status = 0)
  }
}

# ==============================================================================
# PRE-FLIGHT
# ==============================================================================

cat("--- Pre-flight checks ---\n")

if (!dir.exists(config$input_dir)) {
  stop("Input directory does not exist: ", config$input_dir)
}

available_files <- list.files(config$input_dir,
                              pattern = "^ndvi_4km_\\d{4}\\.rds$",
                              full.names = TRUE)
available_years <- as.integer(sub(".*ndvi_4km_(\\d{4})\\.rds$", "\\1",
                                  basename(available_files)))

missing_years <- setdiff(expected_years, available_years)
if (length(missing_years) > 0) {
  stop("Missing year files for: ", paste(missing_years, collapse = ", "),
       "\n  Looked in: ", config$input_dir)
}

extra_years <- setdiff(available_years, expected_years)
if (length(extra_years) > 0) {
  cat("  Note: extra year files present (not combined): ",
      paste(extra_years, collapse = ", "), "\n")
}

year_files <- available_files[available_years %in% expected_years]
year_files <- year_files[order(as.integer(sub(".*ndvi_4km_(\\d{4})\\.rds$",
                                              "\\1", basename(year_files))))]

cat("  Year files to combine:", length(year_files), "\n")
for (f in year_files) {
  size_mb <- file.info(f)$size / 1024^2
  cat(sprintf("    %s  (%.1f MB)\n", basename(f), size_mb))
}
cat("\n")

# ==============================================================================
# READ + SCHEMA CHECK
# ==============================================================================

cat("--- Reading year files ---\n")

year_dfs <- vector("list", length(year_files))
per_year_stats <- data.frame(
  year       = integer(),
  rows       = integer(),
  pixels     = integer(),
  l30_obs    = integer(),
  s30_obs    = integer(),
  ndvi_min   = numeric(),
  ndvi_max   = numeric(),
  stringsAsFactors = FALSE
)

for (i in seq_along(year_files)) {
  f  <- year_files[[i]]
  yr <- as.integer(sub(".*ndvi_4km_(\\d{4})\\.rds$", "\\1", basename(f)))
  df <- readRDS(f)

  # Schema check: all year files must have the same expected columns
  if (!all(config$expected_columns %in% names(df))) {
    missing_cols <- setdiff(config$expected_columns, names(df))
    stop("Year ", yr, " file missing expected columns: ",
         paste(missing_cols, collapse = ", "),
         "\n  Got: ", paste(names(df), collapse = ", "))
  }

  # Drop any extra columns to keep schema strict
  df <- df[, config$expected_columns]

  # Per-year summary for the report
  per_year_stats <- rbind(per_year_stats, data.frame(
    year     = yr,
    rows     = nrow(df),
    pixels   = length(unique(df$pixel_id)),
    l30_obs  = sum(df$sensor == "L30"),
    s30_obs  = sum(df$sensor == "S30"),
    ndvi_min = min(df$NDVI, na.rm = TRUE),
    ndvi_max = max(df$NDVI, na.rm = TRUE)
  ))

  year_dfs[[i]] <- df
  cat(sprintf("  %d: %s rows, %d pixels\n", yr,
              format(nrow(df), big.mark = ","), length(unique(df$pixel_id))))
}

cat("\n")

# ==============================================================================
# COMBINE + DUPLICATE CHECK
# ==============================================================================

cat("--- Combining ---\n")

combined <- bind_rows(year_dfs)
rm(year_dfs); gc(verbose = FALSE)

cat("  Combined rows:", format(nrow(combined), big.mark = ","), "\n")

# Duplicate detection: (pixel_id, sensor, date) should be unique. Year is
# derived from date, so cross-year duplicates are structurally impossible
# (a Dec 31 obs goes to year N, a Jan 1 obs to year N+1). Within-year dupes
# from MGRS tile overlap were already collapsed to median by script 01. So
# we expect zero dupes; if any are found that's a real upstream bug.
# Note: same-date L30 + S30 observations are NOT duplicates (different sensor).
dup_rows <- combined %>%
  group_by(pixel_id, sensor, date) %>%
  filter(n() > 1) %>%
  ungroup()

if (nrow(dup_rows) > 0) {
  dup_by_sensor <- dup_rows %>%
    group_by(sensor) %>%
    summarise(
      duplicate_rows = n(),
      affected_keys  = n_distinct(paste(pixel_id, date)),
      .groups = "drop"
    )

  cat("  ERROR: duplicates found by sensor:\n")
  print(dup_by_sensor, row.names = FALSE)

  example_keys <- dup_rows %>%
    distinct(pixel_id, sensor, date) %>%
    head(5)
  cat("\n  Example duplicate keys (up to 5):\n")
  print(example_keys, row.names = FALSE)

  stop("Found ", nrow(dup_rows), " duplicate rows across ",
       n_distinct(paste(dup_rows$pixel_id, dup_rows$sensor, dup_rows$date)),
       " unique (pixel_id, sensor, date) keys. ",
       "This indicates a script 01 dedup bug, schema mismatch between year ",
       "files, or year-file corruption. Investigate before proceeding.")
}
cat("  Duplicates:    0 (schema clean)\n\n")

# ==============================================================================
# POST-FLIGHT SUMMARY
# ==============================================================================

cat("--- Per-year summary ---\n")
print(per_year_stats, row.names = FALSE)
cat("\n")

cat("--- Combined summary ---\n")
cat("  Total rows:        ", format(nrow(combined), big.mark = ","), "\n")
cat("  Unique pixels:     ", format(length(unique(combined$pixel_id)),
                                    big.mark = ","), "\n")
cat("  Year range:        ", min(combined$year), "-", max(combined$year), "\n")
cat("  DOY range:         ", min(combined$yday), "-", max(combined$yday), "\n")
cat("  Date range:        ", as.character(min(combined$date)), "to",
                              as.character(max(combined$date)), "\n")
cat("  L30 observations:  ", format(sum(combined$sensor == "L30"),
                                    big.mark = ","),
    sprintf(" (%.1f%%)\n", 100 * mean(combined$sensor == "L30")))
cat("  S30 observations:  ", format(sum(combined$sensor == "S30"),
                                    big.mark = ","),
    sprintf(" (%.1f%%)\n", 100 * mean(combined$sensor == "S30")))
cat("  NDVI range:        ", round(min(combined$NDVI, na.rm = TRUE), 4),
                              "to", round(max(combined$NDVI, na.rm = TRUE), 4),
                              "\n")
cat("  NDVI mean:         ", round(mean(combined$NDVI, na.rm = TRUE), 4), "\n")
cat("  NA NDVI rows:      ", sum(is.na(combined$NDVI)), "\n\n")

# ==============================================================================
# SAVE
# ==============================================================================

cat("--- Saving ---\n")
cat("  Writing:", config$output_file, "\n")
saveRDS(combined, config$output_file, compress = "gzip")

out_size_mb <- file.info(config$output_file)$size / 1024^2
cat(sprintf("  Output size: %.1f MB\n", out_size_mb))
cat("\nDone:", as.character(Sys.time()), "\n")
