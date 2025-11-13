#!/bin/bash
# Monitor Phase 2 baseline GAM fitting progress

echo "=== PHASE 2 BASELINE GAM FITTING PROGRESS ==="
echo ""
echo "Timestamp: $(date)"
echo ""

docker exec conus-hls-drought-monitor bash -c '
# Check if process is running
if pgrep -f "02_fit_longterm" > /dev/null; then
  echo "✓ Phase 2 process RUNNING"
  ps aux | grep "02_fit_longterm" | grep -v grep | awk "{print \"  CPU:\", \$3\"%\", \"  MEM:\", \$4\"%\"}"
else
  echo "✗ Phase 2 process NOT running"
fi

echo ""
echo "Latest Progress:"
# Find the most recent log file and show last 10 progress updates
latest_log=$(ls -t /workspace/phase2_*.log 2>/dev/null | head -1)
if [ -n "$latest_log" ]; then
  echo "  Log: $(basename $latest_log)"
  tail -100 "$latest_log" 2>/dev/null | grep -E "Progress:|pixels remaining|COMPLETE|Total time|pixels/min" | tail -10
else
  echo "  No log files found"
fi

echo ""
echo "Output File Status:"
if [ -f /data/gam_models/conus_4km_baseline.csv ]; then
  size=$(ls -lh /data/gam_models/conus_4km_baseline.csv | awk "{print \$5}")
  lines=$(wc -l < /data/gam_models/conus_4km_baseline.csv)
  echo "  File exists: $size ($lines records)"
else
  echo "  File not yet created (check checkpoint file)"
fi

echo ""
echo "Checkpoint Status:"
# Check for RDS checkpoint
if [ -f /data/gam_models/conus_4km_baseline_checkpoint.rds ]; then
  cp_size=$(ls -lh /data/gam_models/conus_4km_baseline_checkpoint.rds | awk "{print \$5}")
  cp_time=$(stat -c "%y" /data/gam_models/conus_4km_baseline_checkpoint.rds | cut -d. -f1)
  echo "  RDS checkpoint: $cp_size (last updated: $cp_time)"
  # Get record count from RDS file
  records=$(Rscript -e "df <- readRDS(\"/data/gam_models/conus_4km_baseline_checkpoint.rds\"); cat(nrow(df))" 2>/dev/null)
  if [ -n "$records" ]; then
    echo "  Records in checkpoint: $records"
  fi
else
  echo "  No checkpoint file found yet"
fi
'
