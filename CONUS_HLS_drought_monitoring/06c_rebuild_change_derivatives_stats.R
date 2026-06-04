# ==============================================================================
# 06c_rebuild_change_derivatives_stats.R
#
# Purpose: (Re)compute per-year summary rows in change_derivatives_stats.rds
#          from derivatives_YYYY.rds files on disk, without re-running 06/06b.
#
# Why: 06 only writes stats_df at the end of a fresh run, listing only the
#      years processed in that run. After 06b backfills additional years
#      (e.g., 2013/2014/2015/2016 from v1+backfill), their stats rows are
#      missing from change_derivatives_stats.rds. This script reads each
#      derivatives_YYYY.rds and appends/replaces its stats row, preserving
#      rows for years not requested.
#
# Stats schema (matches 06_calculate_change_derivatives.R lines 659-666):
#   year, n_results, n_significant, pct_significant, mean_anomaly, elapsed_mins
#
# CLI:
#   Rscript 06c_rebuild_change_derivatives_stats.R              # missing + stale
#   Rscript 06c_rebuild_change_derivatives_stats.R 2013 2015    # specific years
#   Rscript 06c_rebuild_change_derivatives_stats.R --all        # all years
#
# Default mode (no args):
#   target_years = (years with no stats row) ∪ (years whose derivatives file
#   mtime is newer than the stats file mtime).  This catches the 2026-06-02
#   case where 06b backfill rewrote derivatives_2018/2023.rds but 06c said
#   "nothing to do" because both years already had stats rows — checking only
#   year-level presence missed the row-count mismatch.
#
# Notes:
#   - elapsed_mins is set to NA for years computed here (not a timed 06 run).
#   - Reads via readRDS_retry for CIFS resilience.
#   - Writes via saveRDS_validated (post-rename readback gated to >=500 MB;
#     stats file is tiny, so the readback layer is a no-op — kept for symmetry).
# ==============================================================================

library(dplyr)
library(data.table)

source("00_setup_paths.R")
hls_paths <- setup_hls_paths()
source("00_posterior_functions.R")

config <- list(
  derivatives_dir = file.path(hls_paths$gam_models, "change_derivatives"),
  stats_file      = file.path(hls_paths$gam_models, "change_derivatives_stats.rds")
)

# -----------------------------------------------------------------------------
# CLI parsing
# -----------------------------------------------------------------------------
.cli_args <- commandArgs(trailingOnly = TRUE)
.want_all <- "--all" %in% .cli_args
.cli_years <- suppressWarnings(as.integer(setdiff(.cli_args, "--all")))
.cli_years <- .cli_years[!is.na(.cli_years)]

# -----------------------------------------------------------------------------
# Discover year files on disk
# -----------------------------------------------------------------------------
all_files <- list.files(config$derivatives_dir,
                        pattern = "^derivatives_[0-9]{4}\\.rds$",
                        full.names = FALSE)
all_years <- sort(as.integer(sub("^derivatives_([0-9]{4})\\.rds$", "\\1", all_files)))

cat("=== 06c rebuild change_derivatives_stats ===\n")
cat("Derivative files found:", length(all_years), "->",
    paste(range(all_years), collapse = "-"), "\n")

# -----------------------------------------------------------------------------
# Load existing stats (if any)
# -----------------------------------------------------------------------------
existing <- if (file.exists(config$stats_file)) {
  readRDS_retry(config$stats_file)
} else {
  data.frame(year = integer(0), n_results = integer(0), n_significant = integer(0),
             pct_significant = numeric(0), mean_anomaly = numeric(0),
             elapsed_mins = numeric(0))
}
cat("Existing stats rows:", nrow(existing),
    if (nrow(existing) > 0) paste0(" (", paste(range(existing$year), collapse = "-"), ")") else "",
    "\n")

# -----------------------------------------------------------------------------
# Decide which years to (re)compute
# -----------------------------------------------------------------------------
if (.want_all) {
  target_years <- all_years
} else if (length(.cli_years) > 0) {
  target_years <- intersect(.cli_years, all_years)
  missing_from_disk <- setdiff(.cli_years, all_years)
  if (length(missing_from_disk) > 0) {
    cat("WARNING: requested years have no derivatives file on disk:",
        paste(missing_from_disk, collapse = ", "), "\n")
  }
} else {
  # Default: missing rows + rows whose underlying year file is newer than the
  # stats file (i.e., the year was rewritten after stats were last computed).
  missing_years <- setdiff(all_years, existing$year)
  stale_years   <- integer(0)
  if (file.exists(config$stats_file)) {
    stats_mtime <- file.info(config$stats_file)$mtime
    file_mtimes <- file.info(file.path(config$derivatives_dir,
                                       sprintf("derivatives_%d.rds", all_years)))$mtime
    stale_years <- all_years[file_mtimes > stats_mtime]
    stale_years <- intersect(stale_years, existing$year)  # missing-only handled above
    if (length(stale_years) > 0) {
      cat("Stale years (file mtime newer than stats mtime):",
          paste(stale_years, collapse = ", "), "\n")
    }
  }
  target_years <- sort(union(missing_years, stale_years))
}

if (length(target_years) == 0) {
  cat("No years to recompute. Existing stats already cover all on-disk year files.\n")
  quit(status = 0)
}
cat("Years to (re)compute:", paste(target_years, collapse = ", "), "\n\n")

# -----------------------------------------------------------------------------
# Recompute stats for each target year
# -----------------------------------------------------------------------------
start_total <- Sys.time()
new_rows <- vector("list", length(target_years))
names(new_rows) <- as.character(target_years)

for (yr in target_years) {
  fn <- file.path(config$derivatives_dir, sprintf("derivatives_%d.rds", yr))
  cat(sprintf("Reading %s ...\n", basename(fn)))
  t0 <- Sys.time()
  df <- readRDS_retry(fn)
  dt_read <- as.numeric(difftime(Sys.time(), t0, units = "secs"))

  n_results       <- nrow(df)
  n_significant   <- sum(df$significant, na.rm = TRUE)
  pct_significant <- 100 * n_significant / n_results
  mean_anomaly    <- mean(df$anomaly_change_mean, na.rm = TRUE)

  cat(sprintf("  %d rows, %d significant (%.2f%%), mean_anomaly=%.6f, read=%.0fs\n",
              n_results, n_significant, pct_significant, mean_anomaly, dt_read))

  new_rows[[as.character(yr)]] <- data.frame(
    year            = yr,
    n_results       = as.integer(n_results),
    n_significant   = as.integer(n_significant),
    pct_significant = pct_significant,
    mean_anomaly    = mean_anomaly,
    elapsed_mins    = NA_real_   # not a timed run; preserve schema
  )

  rm(df); gc(verbose = FALSE)
}

# -----------------------------------------------------------------------------
# Merge with existing rows (replace by year), sort
# -----------------------------------------------------------------------------
new_df <- do.call(rbind, new_rows)
rownames(new_df) <- NULL

merged <- rbind(existing[!(existing$year %in% new_df$year), , drop = FALSE], new_df)
merged <- merged[order(merged$year), , drop = FALSE]
rownames(merged) <- NULL

cat("\n--- Final stats_df ---\n")
print(merged)

# -----------------------------------------------------------------------------
# Save (atomic via saveRDS_validated)
# -----------------------------------------------------------------------------
saveRDS_validated(merged, config$stats_file)
cat(sprintf("\nSaved %d rows to %s\n", nrow(merged), config$stats_file))
cat(sprintf("Total elapsed: %.1f min\n",
            as.numeric(difftime(Sys.time(), start_total, units = "mins"))))

print(warnings())
