#!/bin/bash
# ==============================================================================
# PREFETCH DOWNLOADS FOR 2023-2025
# ==============================================================================
# Runs alongside the main bulk_download_docker.sh to download future years
# while the current year's NDVI is being processed.
# The main script's skip logic (>1000 granule dirs) means it will skip the
# download step for any year we've already fetched here.
# ==============================================================================

cd /workspace/bulk_downloads

RAW_DIR="/data/bulk_downloads_raw"

for year in 2023 2024 2025; do
  # Check if already downloaded
  l30_count=$(find $RAW_DIR/L30/$year -mindepth 5 -maxdepth 5 -type d 2>/dev/null | wc -l)
  s30_count=$(find $RAW_DIR/S30/$year -mindepth 5 -maxdepth 5 -type d 2>/dev/null | wc -l)
  total=$((l30_count + s30_count))

  if [ "$total" -gt 1000 ]; then
    echo "[prefetch] ⏭ $year already has $total granule dirs, skipping"
    continue
  fi

  echo "[prefetch] === Downloading $year === ($(date))"
  ./getHLS_bands.sh \
    midwest_tiles_noprefix.txt \
    ${year}-01-01 \
    ${year}-12-31 \
    $RAW_DIR \
    > logs/prefetch_${year}.log 2>&1

  if [ $? -eq 0 ]; then
    new_total=$(find $RAW_DIR/L30/$year $RAW_DIR/S30/$year -mindepth 5 -maxdepth 5 -type d 2>/dev/null | wc -l)
    echo "[prefetch] ✓ $year download complete: $new_total granule dirs ($(date))"
  else
    echo "[prefetch] ✗ $year download FAILED — check logs/prefetch_${year}.log ($(date))"
  fi
done

echo "[prefetch] === All prefetch downloads complete === ($(date))"
