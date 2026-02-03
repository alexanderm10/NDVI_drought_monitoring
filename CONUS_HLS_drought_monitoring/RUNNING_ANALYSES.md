# Currently Running Analyses

**Updated**: 2026-02-03 09:35 CST

## Status: RUNNING (parallel download in progress)

### Redownload Progress
- **Current position**: 2017 April (in progress)
- **2013**: COMPLETE - 25,107 NDVI files
- **2014**: COMPLETE - 34,490 NDVI files
- **2015**: COMPLETE - 34,786 NDVI files
- **2016**: COMPLETE - 36,646 NDVI files
- **2017**: IN PROGRESS - 15,632 files (April in progress)
- **2018**: 36,402 files (appears complete)
- **2019**: 5,323 files (partial)
- **2020**: 6,292 files (partial)
- **2021-2024**: Pending

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

## Completed This Session (Feb 3, 2026)

### 1. Morning Status Check & Aggregation Verification - COMPLETE
- **Download Progress**: Container running 10 days, advanced from Sept 2016 to April 2017
  - 2014-2016 completed since last session (+~70K files)
  - 2018 appears complete (36,402 files)
  - 2019-2020 partially downloaded
- **Aggregation Completeness Check**: Verified 2013-2016 are fully aggregated and correct
  - Confirmed all source tiles properly processed
  - Verified "missing" dates are tiles outside Midwest bbox (California, Carolinas, Florida)
  - All 4 years have consistent ~142K pixel coverage
  - Zero missing values across all years
  - Data quality metrics all within expected ranges
- **Decision**: Wait for full year downloads before aggregating 2017+ (aggregation is faster than download)

### 2. Bulk Download System Setup - COMPLETE
- **Created**: `bulk_downloads/` directory with organized structure
- **Modified getHLS.sh** to download only B04, B05, B8A, Fmask (60-70% data reduction)
- **NDVI processing script**: Converts raw bands → NDVI format expected by current workflow
- **Tile list**: 1,209 Midwest MGRS tiles (from 2016 complete data)
- **Integration**: Saves to same location → current Docker script automatically skips
- **Documentation**: QUICKSTART.md, README.md, getHLS_bands_README.md

### 3. Parallel Bulk Download - LAUNCHED (Started 09:32 CST)
- **Status**: RUNNING - querying NASA CMR for 2019 granules
- **Years**: 2019-2024 (all 6 years, sequential processing)
- **Method**: Direct MGRS tile targeting, 10 parallel download workers
- **Expected speed**: 5-10x faster than CONUS-wide bbox search
- **Logs**: `bulk_downloads/logs/{download,process}_YYYY.log`
- **Master log**: `bulk_downloads/logs/all_years_master.log`

**Monitor**:
```bash
# Overall progress
tail -f bulk_downloads/logs/all_years_master.log

# Current year detail
tail -f bulk_downloads/logs/download_2019.log

# File counts
for yr in 2019 2020 2021 2022 2023 2024; do
  echo -n "$yr: "
  ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$yr/ 2>/dev/null | wc -l
done
```

---

## Completed Previous Session (Jan 29, 2026)

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

## Aggregation Status (2013-2016)

**Completeness Check (Feb 3, 2026): ALL YEARS VERIFIED COMPLETE ✓**

| Year | Observations | Pixels | Obs/Pixel | Days | Coverage | Sensors | File Size |
|------|-------------|--------|-----------|------|----------|---------|-----------|
| 2013 | 1,270,784 | 142,099 | 8.9 | 222 | 85.1% | L30 only | 6.5 MB |
| 2014 | 1,583,381 | 141,769 | 11.2 | 320 | 87.7% | L30 only | 8.3 MB |
| 2015 | 1,616,606 | 142,466 | 11.3 | 305 | 83.8% | L30 97%, S30 3% | 8.5 MB |
| 2016 | 2,139,261 | 142,111 | 15.1 | 291 | 80.6% | L30 57%, S30 43% | 12 MB |

**Notes:**
- All source files properly aggregated (11-18% of dates with no aggregated data are tiles outside Midwest bbox - verified correct)
- Zero missing values in all years
- NDVI ranges reasonable: -1 to 1
- Increasing obs/pixel (8.9→15.1) as Sentinel-2 comes online in 2015-2016
- Ready to aggregate 2017+ once downloads complete

---

## Pipeline Status

| Step | Script | Status |
|------|--------|--------|
| Download | `redownload_all_years_cloud100.R` | RUNNING - April 2017 |
| Aggregation | `01_aggregate_to_4km_parallel.R` | 2013-2016 COMPLETE & VERIFIED, 2017+ pending download |
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
