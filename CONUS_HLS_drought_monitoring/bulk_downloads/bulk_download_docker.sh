#!/bin/bash
# ==============================================================================
# BULK DOWNLOAD ALL YEARS 2019-2025 (DOCKER VERSION)
# ==============================================================================
# Runs inside Docker container where terra is available for NDVI processing.
# Uses Docker-internal paths (/data/ instead of /mnt/malexander/...).
# Resumable: getHLS_bands.sh skips existing files, process_bulk_ndvi.R skips
# already-processed scenes.
#
# Usage (from host):
#   docker exec -d conus-hls-drought-monitor bash -c \
#     "cd /workspace/bulk_downloads && nohup ./bulk_download_docker.sh \
#      > /workspace/bulk_downloads/logs/bulk_docker.log 2>&1"
# ==============================================================================

cd /workspace/bulk_downloads

# Docker-internal paths (mapped from host /mnt/malexander/datasets/ndvi_monitor)
RAW_DIR="/data/bulk_downloads_raw"
NDVI_DIR="/data/processed_ndvi/daily"

echo "=== BULK DOWNLOAD (DOCKER): 2019-2025 MIDWEST TILES ==="
echo "Start time: $(date)"
echo "Tiles: 1,209 Midwest MGRS tiles"
echo "Years: 2019-2025"
echo "Raw data: $RAW_DIR"
echo "NDVI output: $NDVI_DIR"
echo "Running inside Docker container: $(hostname)"
echo ""

# Helper: count NDVI files without glob overflow (find handles any file count)
count_ndvi() {
  find "$NDVI_DIR/$1" -name "*_NDVI.tif" 2>/dev/null | wc -l
}

# Minimum NDVI file threshold to consider a year "complete"
# Most years have 190-260k files; 180k skips complete years but catches partial ones like 2024
NDVI_COMPLETE_THRESHOLD=180000

# Download + process for each year
# 2019-2023 confirmed complete (Mar 2026) — start from 2024 to avoid slow CIFS scans
for year in 2024 2025; do
  echo "=== YEAR $year ==="
  echo "Started: $(date)"

  # Skip years that already have enough NDVI files
  existing_ndvi=$(count_ndvi $year)
  if [ "$existing_ndvi" -ge "$NDVI_COMPLETE_THRESHOLD" ]; then
    echo "⏭ Skipping $year — already has $existing_ndvi NDVI files (threshold: $NDVI_COMPLETE_THRESHOLD)"
    echo "Completed $year: $(date)"
    echo ""
    continue
  fi

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
echo "Summary:"
for year in 2019 2020 2021 2022 2023 2024 2025; do
  count=$(count_ndvi $year)
  echo "  $year: $count NDVI files"
done
