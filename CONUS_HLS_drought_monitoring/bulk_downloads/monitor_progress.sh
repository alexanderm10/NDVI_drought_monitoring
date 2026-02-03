#!/bin/bash
# Quick progress monitor for bulk download

cd /home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring/bulk_downloads

echo "=== BULK DOWNLOAD PROGRESS CHECK ==="
echo "Time: $(date)"
echo ""

# Check if process is running
if pgrep -f "bulk_download_all_years.sh" > /dev/null; then
  echo "✓ Bulk download process RUNNING"
else
  echo "⨯ Bulk download process NOT running"
fi

if pgrep -f "getHLS_bands.sh" > /dev/null; then
  echo "✓ Download worker ACTIVE"
else
  echo "⨯ Download worker inactive (may be between years or querying)"
fi
echo ""

# Check master log
echo "=== MASTER LOG (last 10 lines) ==="
if [ -f logs/all_years_master.log ]; then
  tail -10 logs/all_years_master.log
else
  echo "Not started yet"
fi
echo ""

# Check current year download
echo "=== CURRENT DOWNLOAD ACTIVITY ==="
for year in 2019 2020 2021 2022 2023 2024; do
  if [ -f logs/download_${year}.log ]; then
    lines=$(wc -l < logs/download_${year}.log)
    if [ $lines -gt 0 ]; then
      echo "Year $year: $lines log lines"
      granules=$(grep -c "granules to download" logs/download_${year}.log 2>/dev/null || echo "0")
      downloaded=$(grep -c "Finished downloading" logs/download_${year}.log 2>/dev/null || echo "0")
      if [ $granules -gt 0 ]; then
        echo "  └─ Found $granules granules, downloaded $downloaded so far"
      fi
    fi
  fi
done
echo ""

# Check NDVI file counts
echo "=== NDVI FILES CREATED ==="
for year in 2019 2020 2021 2022 2023 2024; do
  count=$(ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$year/ 2>/dev/null | wc -l)
  if [ $count -gt 0 ]; then
    echo "  $year: $count NDVI files ✓"
  else
    echo "  $year: 0 files (pending)"
  fi
done
echo ""

# Check raw band storage
echo "=== RAW BAND STORAGE ==="
for sensor in L30 S30; do
  if [ -d raw/$sensor ]; then
    size=$(du -sh raw/$sensor 2>/dev/null | cut -f1)
    count=$(find raw/$sensor -name "*.tif" 2>/dev/null | wc -l)
    echo "  $sensor: $count band files, $size"
  fi
done
echo ""

echo "=== MONITORING COMMANDS ==="
echo "Watch master log:      tail -f logs/all_years_master.log"
echo "Watch current year:    tail -f logs/download_2019.log"
echo "Watch processing:      tail -f logs/process_2019.log"
echo "Detailed check:        ./monitor_progress.sh"
