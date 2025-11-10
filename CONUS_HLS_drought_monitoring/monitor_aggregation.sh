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
# Find the most recent log file and show last 5 progress updates
latest_log=$(ls -t /workspace/phase1_*.log 2>/dev/null | head -1)
if [ -n "$latest_log" ]; then
  echo "  Log: $(basename $latest_log)"
  tail -100 "$latest_log" 2>/dev/null | grep -E "Progress:|scenes remaining|COMPLETE|Total time" | tail -5
else
  echo "  No log files found"
fi

echo ""
echo "Output File Status:"
if [ -f /data/gam_models/conus_4km_ndvi_timeseries.csv ]; then
  size=$(ls -lh /data/gam_models/conus_4km_ndvi_timeseries.csv | awk "{print \$5}")
  lines=$(wc -l < /data/gam_models/conus_4km_ndvi_timeseries.csv)
  echo "  File exists: $size ($lines observations)"
else
  echo "  File not yet created (check checkpoint file)"
fi

echo ""
echo "Checkpoint Status:"
# Check for RDS checkpoint (new format)
if [ -f /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.rds ]; then
  cp_size=$(ls -lh /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.rds | awk "{print \$5}")
  cp_time=$(stat -c "%y" /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.rds | cut -d. -f1)
  echo "  RDS checkpoint: $cp_size (last updated: $cp_time)"
  # Get observation count from RDS file
  obs_count=$(Rscript -e "df <- readRDS(\"/data/gam_models/conus_4km_ndvi_timeseries_checkpoint.rds\"); cat(nrow(df))" 2>/dev/null)
  if [ -n "$obs_count" ]; then
    echo "  Observations: $obs_count"
  fi
# Fall back to CSV checkpoint (old format)
elif [ -f /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.csv ]; then
  cp_size=$(ls -lh /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.csv | awk "{print \$5}")
  cp_lines=$(wc -l < /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.csv)
  echo "  CSV checkpoint: $cp_size ($cp_lines observations)"
else
  echo "  No checkpoint file found"
fi
'
