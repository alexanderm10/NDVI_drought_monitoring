#!/bin/bash
# ==============================================================================
# BULK DOWNLOAD ALL YEARS 2019-2024
# ==============================================================================
# Downloads HLS bands (B04, B05, B8A, Fmask) for all Midwest tiles
# Runs in parallel with current Docker download script
# Both scripts will skip files created by the other (no duplication)
# ==============================================================================

cd /home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring/bulk_downloads

# Raw data directory on server (maps to /data/bulk_downloads_raw in Docker)
RAW_DIR="/mnt/malexander/datasets/ndvi_monitor/bulk_downloads_raw"

echo "=== BULK DOWNLOAD: 2019-2024 MIDWEST TILES ==="
echo "Start time: $(date)"
echo "Tiles: 1,209 Midwest MGRS tiles"
echo "Years: 2019-2024"
echo "Raw data: $RAW_DIR"
echo ""

for year in 2019 2020 2021 2022 2023 2024; do
  echo "=== YEAR $year ==="
  echo "Started: $(date)"

  # Download raw bands to server location
  ./getHLS_bands.sh \
    midwest_tiles_noprefix.txt \
    ${year}-01-01 \
    ${year}-12-31 \
    $RAW_DIR \
    > logs/download_${year}.log 2>&1

  if [ $? -eq 0 ]; then
    echo "✓ Download complete for $year"

    # Process to NDVI
    echo "Processing to NDVI..."
    Rscript scripts/process_bulk_ndvi.R $year --workers=8 \
      > logs/process_${year}.log 2>&1

    if [ $? -eq 0 ]; then
      count=$(ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$year/ 2>/dev/null | wc -l)
      echo "✓ Processing complete: $count NDVI files created for $year"

      # Optional: cleanup raw bands to save space
      # Uncomment if disk space is limited
      # echo "Cleaning up raw bands..."
      # rm -rf raw/L30/$year raw/S30/$year
    else
      echo "✗ Processing FAILED for $year - check logs/process_${year}.log"
    fi
  else
    echo "✗ Download FAILED for $year - check logs/download_${year}.log"
  fi

  echo "Completed $year: $(date)"
  echo ""
done

echo "=== ALL YEARS COMPLETE ==="
echo "End time: $(date)"
echo ""
echo "Summary:"
for year in 2019 2020 2021 2022 2023 2024; do
  count=$(ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$year/ 2>/dev/null | wc -l)
  echo "  $year: $count NDVI files"
done
echo ""
echo "These files will be automatically skipped by the current Docker download script."
