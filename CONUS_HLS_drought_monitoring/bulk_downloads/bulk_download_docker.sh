#!/bin/bash
# ==============================================================================
# BULK DOWNLOAD ALL YEARS 2019-2024 (DOCKER VERSION)
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

echo "=== BULK DOWNLOAD (DOCKER): 2019-2024 MIDWEST TILES ==="
echo "Start time: $(date)"
echo "Tiles: 1,209 Midwest MGRS tiles"
echo "Years: 2019-2024"
echo "Raw data: $RAW_DIR"
echo "NDVI output: $NDVI_DIR"
echo "Running inside Docker container: $(hostname)"
echo ""

# First, process NDVI for years that already downloaded but failed processing
# (2019 and 2020 raw data is complete, terra is now available in Docker)
for year in 2019 2020; do
  raw_count=$(find $RAW_DIR/L30/$year $RAW_DIR/S30/$year -name "*.tif" 2>/dev/null | head -1)
  ndvi_count=$(ls $NDVI_DIR/$year/*_NDVI.tif 2>/dev/null | wc -l)

  if [ -n "$raw_count" ] && [ "$ndvi_count" -eq 0 ]; then
    echo "=== PROCESSING NDVI for $year (raw data exists, NDVI missing) ==="
    echo "Started: $(date)"
    Rscript scripts/process_bulk_ndvi_docker.R $year --workers=8 \
      > logs/process_${year}_docker.log 2>&1

    if [ $? -eq 0 ]; then
      count=$(ls $NDVI_DIR/$year/*_NDVI.tif 2>/dev/null | wc -l)
      echo "✓ Processing complete: $count NDVI files created for $year"
    else
      echo "✗ Processing FAILED for $year - check logs/process_${year}_docker.log"
    fi
    echo ""
  fi
done

# Now continue with download + processing for remaining years
for year in 2019 2020 2021 2022 2023 2024; do
  echo "=== YEAR $year ==="
  echo "Started: $(date)"

  # Download raw bands
  ./getHLS_bands.sh \
    midwest_tiles_noprefix.txt \
    ${year}-01-01 \
    ${year}-12-31 \
    $RAW_DIR \
    > logs/download_${year}_docker.log 2>&1

  if [ $? -eq 0 ]; then
    echo "✓ Download complete for $year"

    # Process to NDVI (terra available in Docker)
    echo "Processing to NDVI..."
    Rscript scripts/process_bulk_ndvi_docker.R $year --workers=8 \
      > logs/process_${year}_docker.log 2>&1

    if [ $? -eq 0 ]; then
      count=$(ls $NDVI_DIR/$year/*_NDVI.tif 2>/dev/null | wc -l)
      echo "✓ Processing complete: $count NDVI files created for $year"
    else
      echo "✗ Processing FAILED for $year - check logs/process_${year}_docker.log"
    fi
  else
    echo "✗ Download FAILED for $year - check logs/download_${year}_docker.log"
  fi

  echo "Completed $year: $(date)"
  echo ""
done

echo "=== ALL YEARS COMPLETE ==="
echo "End time: $(date)"
echo ""
echo "Summary:"
for year in 2019 2020 2021 2022 2023 2024; do
  count=$(ls $NDVI_DIR/$year/*_NDVI.tif 2>/dev/null | wc -l)
  echo "  $year: $count NDVI files"
done
