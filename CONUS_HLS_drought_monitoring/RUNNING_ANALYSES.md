# Currently Running Analyses

**Updated**: 2026-01-21 16:30 CST

## Active Processes

### 1. Full Dataset Redownload (cloud_cover_max=100%)
- **Script**: redownload_all_years_cloud100.R
- **Container**: conus-hls-drought-monitor
- **Started**: 2026-01-21 07:24
- **Log**: `/data/redownload_cloud100.log`
- **Workers**: 4 parallel workers @ 47-66% CPU
- **Progress**: 2013 data - 8,107 NDVI files so far
- **Expected**: Days to weeks (processing 2013-2024)
- **Monitor**:
  ```bash
  docker exec conus-hls-drought-monitor tail -f /data/redownload_cloud100.log
  # Check file counts:
  for yr in 2013 2014 2015; do echo -n "$yr: "; ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$yr/ 2>/dev/null | wc -l; done
  ```

### 2. k=50 Spatial Basis Test
- **Script**: 03_test_k50_year_predictions.R
- **Container**: conus-hls-k50-test
- **Started**: 2026-01-21 14:30
- **Log**: `/data/test_k50.log`
- **Workers**: 3 parallel workers @ 117-119% CPU, ~16-19GB RAM each
- **Progress**: Processing Year 2017 (first of 4 test years)
- **Test years**: 2017, 2020, 2022, 2024
- **Expected**: 2-3 days for all 4 years
- **Monitor**:
  ```bash
  docker exec conus-hls-k50-test tail -f /data/test_k50.log
  docker exec conus-hls-k50-test ps aux | grep "R --no-save"
  ```

## Completed This Session

1. **2018 parallel aggregation test** - COMPLETE
   - Result: 13.9 obs/pixel (vs 11.3 baseline) = 23% improvement
   - 36,402 scenes processed, 1.95M final observations
   - Output: `/data/gam_models/test_2018_parallel_timeseries.csv`

2. **Created production aggregation script** with disk checkpointing
   - File: `01_aggregate_to_4km_parallel.R`
   - Writes incrementally to disk instead of holding all in RAM

## Session Context

Testing data density improvements:
- Removed cloud_cover_max=40% pre-filter → 7x more scenes available
- After Fmask pixel-level filtering: 23% more obs/pixel (13.9 vs 11.3)
- Testing k=50 spatial basis (between k=30 stable and k=80 overfitting)

## When k=50 Test Completes

1. Check for negative predictions:
   ```r
   results <- readRDS("/data/gam_models/modeled_ndvi_k50_test/modeled_ndvi_2017.rds")
   sum(results$mean < 0, na.rm=TRUE)
   ```
2. If stable (few negatives), k=50 is viable
3. If overfitting, fall back to k=30

## Quick Commands for Next Session

```bash
# Check container status
docker ps --filter "name=conus"

# Check k=50 test progress
docker exec conus-hls-k50-test tail -50 /data/test_k50.log
docker exec conus-hls-k50-test ps aux | grep "R --no-save"

# Check redownload progress
docker exec conus-hls-drought-monitor tail -20 /data/redownload_cloud100.log
for yr in 2013 2014 2015 2016; do echo -n "$yr: "; ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$yr/ 2>/dev/null | wc -l; done

# If processes died, check logs for errors
docker logs conus-hls-k50-test 2>&1 | tail -50
docker logs conus-hls-drought-monitor 2>&1 | tail -50
```
