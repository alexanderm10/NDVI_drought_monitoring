#!/bin/bash
# ==============================================================================
# BULK DOWNLOAD 2013-2018 RE-PASS (DOCKER VERSION)
# ==============================================================================
# Re-downloads HLS data for 2013-2018 to fill in granules missed by the
# original download (which used max_items=100, now fixed to page_size=2000).
# 2019-2025 already complete — not included here.
#
# Expected gains vs original:
#   2013-2014: L30 only (Landsat 8), expect ~40-50K files (up from 25-34K)
#   2015-2016: L30 + S30, expect ~120-150K files (up from 34-36K)
#   2017-2018: L30 + S30A + S30B, expect ~150-200K files (up from 36K)
#
# Resumable: getHLS_bands.sh skips existing files, process_bulk_ndvi.R skips
# already-processed scenes. Safe to restart at any point.
#
# Usage (from host):
#   docker exec -d conus-hls-drought-monitor bash -c \
#     "cd /workspace/bulk_downloads && nohup ./bulk_download_docker.sh \
#      > /workspace/bulk_downloads/logs/bulk_2013_2018.log 2>&1"
# ==============================================================================

cd /workspace/bulk_downloads

# Docker-internal paths (mapped from host /mnt/malexander/datasets/ndvi_monitor)
RAW_DIR="/data/bulk_downloads_raw"
NDVI_DIR="/data/processed_ndvi/daily"

echo "=== BULK DOWNLOAD (DOCKER): 2013-2018 RE-PASS ==="
echo "Start time: $(date)"
echo "Tiles: 1,209 Midwest MGRS tiles"
echo "Years: 2013-2018"
echo "Raw data: $RAW_DIR"
echo "NDVI output: $NDVI_DIR"
echo "Running inside Docker container: $(hostname)"
echo ""

# Helper: count NDVI files without glob overflow (find handles any file count)
count_ndvi() {
  find "$NDVI_DIR/$1" -name "*_NDVI.tif" 2>/dev/null | wc -l
}

# No NDVI_COMPLETE_THRESHOLD skip for 2013-2018 — all years need re-downloading.
# 2013-2014 will have fewer files than later years (L30 only), so any threshold
# would be wrong. We rely entirely on getHLS_bands.sh + process_bulk_ndvi skip-if-exists.

# Download + process for each year 2013-2018
for year in 2013 2014 2015 2016 2017 2018; do
  echo "=== YEAR $year ==="
  echo "Started: $(date)"

  existing_ndvi=$(count_ndvi $year)
  echo "Existing NDVI files: $existing_ndvi"

  # Check if download already completed by counting raw granule directories
  l30_count=$(find $RAW_DIR/L30/$year -mindepth 5 -maxdepth 5 -type d 2>/dev/null | wc -l)
  s30_count=$(find $RAW_DIR/S30/$year -mindepth 5 -maxdepth 5 -type d 2>/dev/null | wc -l)
  total_raw=$((l30_count + s30_count))

  if [ "$total_raw" -gt 1000 ]; then
    echo "⏭ Skipping download for $year — $total_raw granule dirs already exist (L30: $l30_count, S30: $s30_count)"
  else
    # Download raw bands
    ./getHLS_bands.sh \
      midwest_tiles_noprefix.txt \
      ${year}-01-01 \
      ${year}-12-31 \
      $RAW_DIR \
      > logs/download_${year}_docker.log 2>&1

    if [ $? -eq 0 ]; then
      echo "✓ Download complete for $year"
    else
      echo "✗ Download FAILED for $year - check logs/download_${year}_docker.log"
      echo "Completed $year: $(date)"
      echo ""
      continue
    fi
  fi

  # Process to NDVI (terra available in Docker)
  echo "Processing NDVI ($existing_ndvi files exist, processing remaining)..."
  Rscript scripts/process_bulk_ndvi_docker.R $year --workers=8 \
    > logs/process_${year}_docker.log 2>&1

  if [ $? -eq 0 ]; then
    count=$(count_ndvi $year)
    echo "✓ Processing complete: $count NDVI files for $year"
  else
    echo "✗ Processing FAILED for $year - check logs/process_${year}_docker.log"
  fi

  echo "Completed $year: $(date)"
  echo ""
done

echo "=== ALL YEARS COMPLETE ==="
echo "End time: $(date)"
echo ""
echo "Summary (2013-2018 re-pass):"
for year in 2013 2014 2015 2016 2017 2018; do
  count=$(count_ndvi $year)
  echo "  $year: $count NDVI files"
done
