#!/bin/bash
# cleanup_stale_outputs.sh
# Remove stale pipeline outputs before running 2013-2025 aggregation.
# Run INSIDE the Docker container (paths are /data/...).
#
# Usage:
#   docker exec conus-hls-drought-monitor bash /workspace/cleanup_stale_outputs.sh --dry-run
#   docker exec conus-hls-drought-monitor bash /workspace/cleanup_stale_outputs.sh

set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "=== DRY RUN — no files will be deleted ==="
fi

BASE="/data/gam_models"
TOTAL_BYTES=0

count_and_remove() {
  local label="$1"
  local path="$2"

  if [[ ! -e "$path" ]]; then
    echo "  [SKIP] $label — does not exist"
    return
  fi

  if [[ -d "$path" ]]; then
    local size
    size=$(du -sb "$path" 2>/dev/null | cut -f1)
    local count
    count=$(find "$path" -type f | wc -l)
    TOTAL_BYTES=$((TOTAL_BYTES + size))
    echo "  [DEL]  $label — $count files, $(numfmt --to=iec $size)"
    if [[ "$DRY_RUN" == "false" ]]; then
      rm -rf "$path"
    fi
  else
    local size
    size=$(stat -c%s "$path" 2>/dev/null || echo 0)
    TOTAL_BYTES=$((TOTAL_BYTES + size))
    echo "  [DEL]  $label — $(numfmt --to=iec $size)"
    if [[ "$DRY_RUN" == "false" ]]; then
      rm -f "$path"
    fi
  fi
}

echo ""
echo "============================================"
echo "  STALE OUTPUT CLEANUP"
echo "============================================"
echo ""

# ── Step 1: Aggregated year files (old sparse data) ──
echo "── Step 1: Aggregated year files ──"
for yr in 2013 2014 2015 2016; do
  count_and_remove "ndvi_4km_${yr}.rds" "$BASE/aggregated_years/ndvi_4km_${yr}.rds"
done
echo ""

# ── Step 2: Combined timeseries ──
echo "── Step 2: Combined timeseries ──"
count_and_remove "conus_4km_ndvi_timeseries.rds" "$BASE/conus_4km_ndvi_timeseries.rds"
count_and_remove "conus_4km_ndvi_timeseries.csv" "$BASE/conus_4km_ndvi_timeseries.csv"
count_and_remove "timeseries backup (csv)" "$BASE/conus_4km_ndvi_timeseries_backup.csv"
count_and_remove "timeseries old incomplete (csv)" "$BASE/conus_4km_ndvi_timeseries_old_incomplete.csv"
echo ""

# ── Step 3: Baseline norms ──
echo "── Step 3: Baseline norms + posteriors ──"
count_and_remove "doy_looped_norms.rds" "$BASE/doy_looped_norms.rds"
count_and_remove "baseline_posteriors/" "$BASE/baseline_posteriors"
count_and_remove "norms backup (no posteriors)" "$BASE/doy_looped_norms_backup_no_posteriors.rds"
count_and_remove "norms FAILED artifact" "$BASE/doy_looped_norms_FAILED_20251202.rds"
echo ""

# ── Step 4: Year predictions ──
echo "── Step 4: Year predictions + posteriors ──"
count_and_remove "modeled_ndvi/" "$BASE/modeled_ndvi"
count_and_remove "year_predictions_posteriors/" "$BASE/year_predictions_posteriors"
count_and_remove "modeled_ndvi_stats.rds" "$BASE/modeled_ndvi_stats.rds"
echo ""

# ── Step 5: Anomalies ──
echo "── Step 5: Anomalies ──"
count_and_remove "modeled_ndvi_anomalies/" "$BASE/modeled_ndvi_anomalies"
count_and_remove "modeled_ndvi_anomalies_stats.rds" "$BASE/modeled_ndvi_anomalies_stats.rds"
echo ""

# ── Step 6: Change derivatives ──
echo "── Step 6: Change derivatives + posteriors ──"
count_and_remove "change_derivatives/" "$BASE/change_derivatives"
count_and_remove "change_derivatives_posteriors/" "$BASE/change_derivatives_posteriors"
count_and_remove "change_derivatives_stats.rds" "$BASE/change_derivatives_stats.rds"
echo ""

# ── Step 7: Old baselines and checkpoints ──
echo "── Step 7: Test/checkpoint/backup files ──"
count_and_remove "conus_4km_baseline_derivatives.csv" "$BASE/conus_4km_baseline_derivatives.csv"
count_and_remove "conus_4km_baseline.csv" "$BASE/conus_4km_baseline.csv"
count_and_remove "baseline derivatives checkpoint backup" "$BASE/conus_4km_baseline_derivatives_checkpoint_BACKUP_20251119.rds"
count_and_remove "year splines checkpoint" "$BASE/conus_4km_year_splines_checkpoint.rds"
count_and_remove "test_2018_parallel_timeseries.csv" "$BASE/test_2018_parallel_timeseries.csv"
count_and_remove "test_2018_cloud100 checkpoint" "$BASE/test_2018_cloud100_min5_timeseries_checkpoint.rds"
count_and_remove "test_2024_min_pixels_5.rds" "$BASE/test_2024_min_pixels_5.rds"
count_and_remove "modeled_ndvi_k50_test/" "$BASE/modeled_ndvi_k50_test"
count_and_remove "backups/" "$BASE/backups"
count_and_remove "aggregation_temp/" "$BASE/aggregation_temp"
echo ""

# ── Summary ──
echo "============================================"
echo "  TOTAL: $(numfmt --to=iec $TOTAL_BYTES)"
if [[ "$DRY_RUN" == "true" ]]; then
  echo "  (DRY RUN — nothing deleted)"
else
  echo "  (deleted)"
fi
echo "============================================"
