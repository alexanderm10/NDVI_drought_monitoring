#!/bin/bash
# ==============================================================================
# Check aggregation progress
# ==============================================================================

echo "=== AGGREGATION PROGRESS CHECK ==="
echo "Timestamp: $(date)"
echo ""

# Check if process is running
if docker exec conus-hls-drought-monitor ps aux | grep -q "[R]script run_aggregation.R"; then
    echo "✅ Aggregation is RUNNING"
else
    echo "⚠ Aggregation process NOT found"
fi

echo ""
echo "--- Last 30 lines of log ---"
docker exec conus-hls-drought-monitor tail -30 /tmp/aggregation.log

echo ""
echo "--- Checkpoint file status ---"
if docker exec conus-hls-drought-monitor test -f /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.csv; then
    SIZE=$(docker exec conus-hls-drought-monitor stat -f%z /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.csv 2>/dev/null || docker exec conus-hls-drought-monitor stat -c%s /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.csv 2>/dev/null)
    LINES=$(docker exec conus-hls-drought-monitor wc -l /data/gam_models/conus_4km_ndvi_timeseries_checkpoint.csv 2>/dev/null | awk '{print $1}')
    echo "  Checkpoint exists: $LINES lines, $(( SIZE / 1024 / 1024 )) MB"
else
    echo "  No checkpoint file yet"
fi

echo ""
echo "--- Output file status ---"
if docker exec conus-hls-drought-monitor test -f /data/gam_models/conus_4km_ndvi_timeseries.csv; then
    SIZE=$(docker exec conus-hls-drought-monitor stat -f%z /data/gam_models/conus_4km_ndvi_timeseries.csv 2>/dev/null || docker exec conus-hls-drought-monitor stat -c%s /data/gam_models/conus_4km_ndvi_timeseries.csv 2>/dev/null)
    LINES=$(docker exec conus-hls-drought-monitor wc -l /data/gam_models/conus_4km_ndvi_timeseries.csv 2>/dev/null | awk '{print $1}')
    echo "  ✅ Final output exists: $LINES lines, $(( SIZE / 1024 / 1024 )) MB"
else
    echo "  Not completed yet"
fi

echo ""
echo "=== END PROGRESS CHECK ==="
