#!/bin/bash
# Monitor Phase 1 aggregation progress

echo "=== PHASE 1 AGGREGATION PROGRESS ==="
echo ""
echo "Timestamp: $(date)"
echo ""

docker exec conus-hls-drought-monitor bash -c '
# Check if process is running
if pgrep -f "01_aggregate" > /dev/null; then
  echo "✓ Aggregation process RUNNING"
  ps aux | grep "01_aggregate" | grep -v grep | awk "{print \"  CPU:\", \$3\"%\", \"  MEM:\", \$4\"%\"}"
else
  echo "✗ Aggregation process NOT running"
fi

echo ""
echo "Latest Progress:"
tail -20 /workspace/phase1_fresh_run_*.log 2>/dev/null | grep -E "Progress:|scenes|COMPLETE|Total time" | tail -5

echo ""
echo "Output File Status:"
if [ -f /data/gam_models/conus_4km_ndvi_timeseries.csv ]; then
  size=$(ls -lh /data/gam_models/conus_4km_ndvi_timeseries.csv | awk "{print \$5}")
  lines=$(wc -l < /data/gam_models/conus_4km_ndvi_timeseries.csv)
  echo "  File exists: $size ($lines observations)"
else
  echo "  File not yet created (check checkpoint file)"
fi

# Check checkpoint file
if [ -f /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.csv ]; then
  cp_size=$(ls -lh /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.csv | awk "{print \$5}")
  cp_lines=$(wc -l < /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.csv)
  echo "  Checkpoint: $cp_size ($cp_lines observations)"
fi
'
