# Session Summary - February 3, 2026

**Duration**: ~3 hours
**Focus**: Data download status check, aggregation verification, bulk download system implementation

---

## 1. Morning Status Check ✓

### Download Progress Assessment
- **Docker container**: Running 10 days continuously
- **Progress**: Advanced from Sept 2016 to April 2017
- **Completions since last session**:
  - 2014: +22,812 files (11,678 → 34,490) ✓ COMPLETE
  - 2015: +30,107 files (4,679 → 34,786) ✓ COMPLETE
  - 2016: +10,494 files (26,152 → 36,646) ✓ COMPLETE
- **Current status**: 2017 April, 15,632 files downloaded

### Key Findings
- 2018 appears complete: 36,402 files
- 2019-2024 have 5K-6K files each (partial downloads)
- System has good resume capability

---

## 2. Aggregation Verification ✓

**Purpose**: Verify 2013-2016 aggregated data completeness and quality

### Results - ALL YEARS VERIFIED COMPLETE

| Year | Observations | Pixels | Obs/Pixel | Days | Coverage | Sensors | Status |
|------|-------------|--------|-----------|------|----------|---------|--------|
| 2013 | 1,270,784 | 142,099 | 8.9 | 222 | 85.1% | L30 only | ✓ |
| 2014 | 1,583,381 | 141,769 | 11.2 | 320 | 87.7% | L30 only | ✓ |
| 2015 | 1,616,606 | 142,466 | 11.3 | 305 | 83.8% | L30 97%, S30 3% | ✓ |
| 2016 | 2,139,261 | 142,111 | 15.1 | 291 | 80.6% | L30 57%, S30 43% | ✓ |

### Quality Checks
- ✓ Zero missing values across all years
- ✓ NDVI ranges reasonable: -1 to 1
- ✓ Consistent ~142K pixel coverage (4km grid)
- ✓ Increasing obs/pixel (8.9→15.1) as Sentinel-2 comes online

### "Missing" Dates Investigation
- 11-18% of source file dates have no aggregated data
- **Verified cause**: Tiles outside Midwest bbox (-104.5, 37.0, -82.0, 47.5)
  - California tiles (~-121° longitude)
  - North Carolina/Florida tiles (east of -82°)
- **Conclusion**: Aggregation working correctly, filtering as designed

---

## 3. Bulk Download System Implementation ✓

**Problem Identified**: Current R script searches full CONUS bbox, downloads many tiles that get filtered out during aggregation. Inefficient for Midwest-only analysis.

**Solution**: Modified NASA getHLS.sh script + processing pipeline

### System Components

#### A. Modified Download Script ([getHLS_bands.sh](CONUS_HLS_drought_monitoring/bulk_downloads/getHLS_bands.sh))
- **Source**: NASA LP DAAC HLS-Data-Resources
- **Modification**: Line 237 - filter to only B04, B05, B8A, Fmask
- **Data reduction**: 60-70% less download size vs full granules
- **Performance**: 10 parallel workers (configurable)
- **Resume capability**: Skips existing files

#### B. Tile List Generation
- **Derived from**: 2016 complete NDVI data (most comprehensive year)
- **Count**: 1,209 MGRS tiles covering Midwest bbox
- **Files**:
  - `midwest_tiles.txt` (with T prefix)
  - `midwest_tiles_noprefix.txt` (for getHLS.sh)

#### C. NDVI Processing Script ([process_bulk_ndvi.R](CONUS_HLS_drought_monitoring/bulk_downloads/scripts/process_bulk_ndvi.R))
- **Input**: Raw bands from getHLS.sh download
- **Process**: Calculate NDVI, apply Fmask quality filtering
- **Output**: NDVI files in `/mnt/.../processed_ndvi/daily/YYYY/`
- **Integration**: Same location as current script → auto-skip logic works
- **Performance**: Parallel processing (8 workers default)

#### D. Directory Structure
```
bulk_downloads/
├── getHLS_bands.sh              # Band-specific download
├── bulk_download_all_years.sh   # Sequential year processor
├── monitor_progress.sh          # Status checking
├── scripts/
│   └── process_bulk_ndvi.R     # Band → NDVI conversion
├── raw/                         # Download destination (gitignored)
├── logs/                        # Process logs (gitignored)
├── QUICKSTART.md               # Fast start guide
├── README.md                   # Complete workflow
└── getHLS_bands_README.md      # Script details
```

### Performance Comparison

**Current R Script**:
- Searches: 40 CONUS bbox tiles (8×5 grid)
- Downloads: All tiles overlapping bboxes
- Workers: 4 parallel
- Speed: Baseline

**Bulk Download System**:
- Searches: 1,209 specific MGRS tiles (Midwest only)
- Downloads: Only needed tiles, only 3-4 bands each
- Workers: 10 parallel
- **Expected speedup**: 5-10x faster

---

## 4. Parallel Bulk Download Launch ✓

**Started**: 09:32 CST
**Process IDs**: 979119 (master), 979123 (getHLS worker)
**Target**: Years 2019-2024 (6 years total)

### Current Status
- **Phase**: Querying NASA CMR for 2019 granules (1,209 tiles)
- **Expected query duration**: 5-15 minutes
- **Then**: Actual downloads will begin

### Integration with Current Download
Both systems running in parallel:
1. **Docker container**: Continues 2017-2018 downloads
2. **Bulk download**: Handles 2019-2024 Midwest tiles
3. **No duplication**: Both check for existing NDVI files and skip

### Monitoring
```bash
# Overall progress
tail -f bulk_downloads/logs/all_years_master.log

# Quick status
cd bulk_downloads && ./monitor_progress.sh

# File counts
for yr in 2019 2020 2021 2022 2023 2024; do
  echo -n "$yr: "
  ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$yr/ | wc -l
done
```

---

## 5. Files Created/Modified

### New Files Committed
- `bulk_downloads/` (entire directory)
  - 3 documentation files (README, QUICKSTART, getHLS_bands_README)
  - 3 scripts (getHLS_bands.sh, bulk_download_all_years.sh, monitor_progress.sh)
  - 1 R script (process_bulk_ndvi.R)
  - 2 tile lists
  - .gitignore (excludes raw/ and logs/)
- `midwest_tiles.txt` (1,209 tiles)

### Modified Files
- `RUNNING_ANALYSES.md`
  - Updated download progress (Sept 2016 → April 2017)
  - Added aggregation verification results
  - Documented bulk download system
  - Added monitoring commands

### Git Commit
- **Commit**: d8533e0
- **Tag**: [data][ops]
- **Message**: "Add bulk download system for accelerated HLS data acquisition"
- **Pushed**: ✓ origin/main

---

## 6. Running Processes (DO NOT STOP)

### Process 1: Docker Download (Original)
- **Container**: conus-hls-drought-monitor
- **Script**: redownload_all_years_cloud100.R
- **Current**: April 2017
- **Started**: January 23, 2026 (10 days ago)
- **Monitor**: `docker exec conus-hls-drought-monitor tail -f /data/redownload_cloud100.log`

### Process 2: Bulk Download (NEW)
- **PIDs**: 979119 (master), 979123 (worker)
- **Script**: bulk_download_all_years.sh
- **Current**: 2019 (CMR query phase)
- **Started**: February 3, 2026 09:32 CST
- **Logs**:
  - Master: `bulk_downloads/logs/all_years_master.log`
  - Current: `bulk_downloads/logs/download_2019.log`
- **Monitor**: `cd bulk_downloads && ./monitor_progress.sh`

**Both processes have resume capability - safe to leave running**

---

## 7. Data Status

### Download Completion
| Year | Files | Status | Method |
|------|-------|--------|--------|
| 2013 | 25,107 | COMPLETE ✓ | Docker |
| 2014 | 34,490 | COMPLETE ✓ | Docker |
| 2015 | 34,786 | COMPLETE ✓ | Docker |
| 2016 | 36,646 | COMPLETE ✓ | Docker |
| 2017 | 15,632 | IN PROGRESS | Docker |
| 2018 | 36,402 | Appears complete | Docker |
| 2019 | 5,323 | IN PROGRESS | Both (parallel) |
| 2020 | 6,292 | IN PROGRESS | Both (parallel) |
| 2021 | 6,301 | Partial | Docker |
| 2022 | 5,919 | Partial | Docker |
| 2023 | 5,793 | Partial | Docker |
| 2024 | 5,962 | Partial | Docker |

### Aggregation Status
- **Complete**: 2013-2016 (verified this session)
- **Pending**: 2017+ (wait for downloads to complete)
- **Ready**: Scripts updated to k=50, ready to aggregate when data available

---

## 8. Next Session Tasks

### Immediate (Within 24 hours)
1. Check bulk download progress: `cd bulk_downloads && ./monitor_progress.sh`
2. Verify 2019 download started (should see granules downloading)
3. Monitor disk space: `df -h /mnt/malexander/datasets/`

### Short-term (1-3 days)
1. Monitor both download processes to completion
2. Verify 2017-2018 complete via Docker script
3. Verify 2019-2024 Midwest tiles via bulk download
4. Check for any failed downloads in logs

### When Downloads Complete
1. Aggregate 2017 (first complete year after 2016)
2. Verify aggregation quality for 2017
3. Continue sequential aggregation through 2024
4. Re-run Script 02 (norms) with full 2013-2024 dataset
5. Run Script 03 (predictions) for all years

---

## 9. Storage Estimates

### Current Usage
- 2013-2016 NDVI: ~150 GB
- 2017-2024 partial: ~200 GB
- Total processed NDVI: ~350 GB

### After Bulk Download Completes
- Raw bands (temporary): ~300-400 GB
- Final NDVI 2019-2024: ~100-150 GB
- **Can delete raw bands after processing**

### Aggregated Data (4km)
- Each year: 6-12 MB
- All years 2013-2024: <150 MB total (tiny!)

---

## 10. Lessons Learned

1. **Bulk download is essential** for large-scale HLS data acquisition
2. **Tile-specific targeting** much more efficient than bbox searching
3. **Resume capability** critical for multi-day downloads
4. **Parallel workflows** can complement each other when properly integrated
5. **Aggregation verification** important - revealed tiles outside bbox being filtered correctly

---

## Quick Commands for Next Session

```bash
# Check bulk download
cd ~/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring/bulk_downloads
./monitor_progress.sh

# Check Docker download
docker exec conus-hls-drought-monitor tail -100 /data/redownload_cloud100.log | grep "Processing"

# File counts
for yr in 2013 2014 2015 2016 2017 2018 2019 2020 2021 2022 2023 2024; do
  echo -n "$yr: "
  ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$yr/ 2>/dev/null | wc -l
done

# Aggregated years
ls -lh /mnt/malexander/datasets/ndvi_monitor/gam_models/aggregated_years/

# Storage check
df -h /mnt/malexander/datasets/
```

---

**Session End Time**: ~09:40 CST
**Container Status**: Running (leave as-is)
**Background Processes**: 2 running (Docker + Bulk)
**Next Check**: Monitor bulk download progress in 1-2 hours
