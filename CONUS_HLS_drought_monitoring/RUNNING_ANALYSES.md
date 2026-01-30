# Currently Running Analyses

**Updated**: 2026-01-29 15:00 CST

## Status: RUNNING (download in progress)

### Redownload Progress
- **Current position**: 2016 September (in progress)
- **2013**: COMPLETE - 25,107 NDVI files
- **2014**: COMPLETE - 34,487 NDVI files
- **2015**: COMPLETE - 33,796 NDVI files
- **2016**: IN PROGRESS - 26,152 files (Sep in progress, ~3 months remaining)
- **2017-2024**: Pending

### File counts at shutdown:
```
2013: 25,039 files
2014: 11,678 files (partial)
2015: 4,679 files (old data)
2016: 5,955 files (old data)
```

---

## To Resume Next Session

### 1. Start the container
```bash
docker start conus-hls-drought-monitor
```

### 2. Resume the redownload
```bash
docker exec -d conus-hls-drought-monitor bash -c "cd /workspace && Rscript redownload_all_years_cloud100.R >> /data/redownload_cloud100.log 2>&1"
```

### 3. Monitor progress
```bash
docker exec conus-hls-drought-monitor tail -f /data/redownload_cloud100.log

# Check file counts:
for yr in 2013 2014 2015 2016 2017; do echo -n "$yr: "; ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$yr/ 2>/dev/null | wc -l; done
```

The script has **resume capability** - it checks if each NDVI file exists before downloading, so it will skip already-completed scenes and continue from where it left off.

---

## Completed This Session (Jan 29, 2026)

### 1. Comprehensive Methodology Documentation - COMPLETE
- **METHODOLOGY.md**: 400+ line complete end-to-end pipeline documentation
  - Data acquisition with cloud_cover_max=100% strategy
  - Spatial aggregation (30m → 4km)
  - Statistical modeling (GAMs with k=50)
  - Operational workflows (monthly updates + annual baseline)
- **OPERATIONAL_WORKFLOW.md**: User guide for monthly automation
- **Updated GAM_METHODOLOGY.md**: Cross-referenced with main methodology
- One-paragraph summary for presentations/proposals

### 2. Monthly Update Automation - COMPLETE
- **00_monthly_update.R**: Automated monthly data processing script
  - Downloads new month's HLS scenes
  - Aggregates to 4km
  - Refits current year GAMs
  - Recalculates anomalies
  - Runtime: ~4-6 hours per month
- **monthly_update.sh**: Bash wrapper for cron automation
- Ready to deploy once historical data complete

### 3. Log File Cleanup - COMPLETE
- Removed all test logs (21 files, ~204MB freed)
- Cleaned up repo for production readiness

### 4. k=50 Spatial Basis Test - COMPLETE (from previous session)
- **Result**: k=50 is stable (0.11% negative predictions)
- Test years: 2017, 2020, 2022, 2024
- Model stats: R²=0.698, RMSE=0.089, NormCoef=0.995
- **Decision**: Updated production script `03_doy_looped_year_predictions.R` to use k=50

### 2. 2013 Aggregation - COMPLETE
- **Output**: `/data/gam_models/aggregated_years/ndvi_4km_2013.rds` (6.5MB)
- 1,270,784 final observations
- Mean: 8.9 obs/pixel (Landsat-only year, no Sentinel-2)
- Note: "Failed" count (19K) was tiles outside Midwest bbox, not actual failures

### 3. Aggregation Script Improvements
- Updated `01_aggregate_to_4km_parallel.R`:
  - RDS batch checkpointing (15x smaller than CSV)
  - Command-line year selection: `Rscript 01_aggregate_to_4km_parallel.R 2014`
  - `--workers=N` flag for parallelism control
  - Automatic skip of completed years
  - Year-specific temp directories
  - Resume capability

### 4. Removed obsolete files
- Deleted `aggregate_2013_only.R` (functionality merged into main script)
- Removed k=50 test container

---

## Pipeline Status

| Step | Script | Status |
|------|--------|--------|
| Download | `redownload_all_years_cloud100.R` | PAUSED at March 2014 |
| Aggregation | `01_aggregate_to_4km_parallel.R` | 2013 COMPLETE, 2014+ pending |
| Norms | `02_doy_looped_norms.R` | Needs re-run after all years aggregated |
| Year Predictions | `03_doy_looped_year_predictions.R` | Updated to k=50, ready to run |

---

## Next Steps (when resuming)

1. **Resume redownload** - Continue from March 2014 through 2024
2. **Aggregate each year** as download completes:
   ```bash
   docker exec -d conus-hls-drought-monitor bash -c "cd /workspace && Rscript 01_aggregate_to_4km_parallel.R 2014 > /data/aggregate_2014.log 2>&1"
   ```
3. **After all years aggregated**: Combine into single timeseries, run Script 02 (norms), then Script 03 (predictions)

---

## Key Configuration

- **Spatial basis**: k=50 (validated)
- **Cloud cover filter**: 100% at scene level (Fmask handles pixel-level QA)
- **Aggregation**: 4km resolution, median, min 5 pixels per cell
- **Study area**: Midwest bbox (-104.5, 37.0, -82.0, 47.5)
