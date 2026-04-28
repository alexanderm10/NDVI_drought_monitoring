#!/bin/bash
# Quick progress monitor for HLS acquisition

echo "=== HLS ACQUISITION PROGRESS ==="
echo ""
echo "Timestamp: $(date)"
echo ""

docker exec conus-hls-drought-monitor bash -c '
# Check if process is running
if pgrep -f "00_download_hls_data" > /dev/null; then
  echo "✓ Acquisition process RUNNING"
  ps aux | grep "00_download" | grep -v grep | awk "{print \"  Runtime:\", \$10}"
else
  echo "✗ Acquisition process NOT running"
fi

echo ""
echo "Files by Year:"
for year in {2013..2024}; do
  count=$(find /data/processed_ndvi/daily/$year -name "*_NDVI.tif" 2>/dev/null | wc -l)
  recent=$(find /data/processed_ndvi/daily/$year -name "*_NDVI.tif" -mmin -15 2>/dev/null | wc -l)
  if [ $recent -gt 0 ]; then
    printf "  %d: %4d files (%d new in last 15 min) ✓\n" $year $count $recent
  else
    printf "  %d: %4d files\n" $year $count
  fi
done

echo ""
total=$(find /data/processed_ndvi/daily -name "*_NDVI.tif" 2>/dev/null | wc -l)
echo "Total: $total NDVI files"
'
