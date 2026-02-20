# Currently Running Analyses

**Updated**: 2026-02-20 13:00 CST

## Status: RUNNING — Bulk download processing 2019-2025

### Active Pipeline: Bulk Download (2019-2025) — Docker
- **Status**: RUNNING — 2019 NDVI processing (raw data exists on disk)
- **Script**: `bulk_download_docker.sh` → `getHLS_bands.sh` + `process_bulk_ndvi_docker.R`
- **Log**: `bulk_downloads/logs/bulk_docker.log`
- **Workers**: 8 parallel R (NDVI calc), chunked in 5,000-granule batches
- **Year range**: 2019-2025 (extended from 2019-2024 this session)
- **Container**: `conus-hls-drought-monitor`, clean restart (0 zombies)

### Shelved: R-based 2025 Download (CONUS parallel)
- **Reason**: Docker PID 1 (`tail -f /dev/null`) doesn't reap zombie processes. Every parallel R worker that exits becomes a permanent zombie until container restart. Tried `multisession` and `multicore` — both create zombies in this container.
- **Resolution**: 2025 added to bulk download script instead (wget-based, no zombies)
- **Existing data**: 35,230 NDVI files from previous runs remain intact

---

## Data Inventory (Feb 20, 2026)

### Raw L30 (Landsat) Files
| Year | Files | Size |
|------|-------|------|
| 2019 | 170,607 | 1.7 TB |
| 2020 | 170,571 | 1.7 TB |
| 2021 | 198,510 | 1.9 TB |
| 2022 | 349,276 | 3.4 TB |

### Raw S30 (Sentinel) Files
| Year | Files | Size |
|------|-------|------|
| 2019 | 535,584 | 7.0 TB |

### Processed NDVI (daily)
| Year | Files | Status |
|------|-------|--------|
| 2013 | 25,107 | Complete (pre-HLS) |
| 2014 | 34,490 | Complete (pre-HLS) |
| 2015 | 34,786 | Complete (pre-HLS) |
| 2016 | 36,646 | Complete (pre-HLS) |
| 2017 | 36,425 | Complete (pre-HLS) |
| 2018 | 36,483 | Complete (pre-HLS) |
| 2019 | 50,441 | Complete |
| 2020 | 13,305 | **Partial (~25%)** |
| 2021 | 61,194 | Complete |
| 2022 | 5,919 | **Partial (~10%)** |
| 2023 | 5,793 | **Partial (~10%)** |
| 2024 | 27,659 | **Partial (~50%)** |
| 2025 | 35,230 | In progress |

---

## Monitoring

### Custom Agent
A `download-monitor` agent at `.claude/agents/download-monitor.md`. In Claude Code, ask "check on my downloads" to trigger it.

### Manual Monitoring
```bash
# Bulk download
tail -f CONUS_HLS_drought_monitoring/bulk_downloads/logs/bulk_docker.log

# Docker container health
docker exec conus-hls-drought-monitor ps aux | grep -E "[R]script|[w]get"

# Check for zombies
docker exec conus-hls-drought-monitor ps aux | grep -c defunct

# File counts
for yr in 2019 2020 2021 2022 2023 2024 2025; do
  echo -n "$yr: "
  ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$yr/ 2>/dev/null | wc -l
done
```

---

## Session Summary (Feb 20, 2026)

### Work Completed
1. **Container restart**: Cleared 30 zombies + 14 D-state processes from stalled container
2. **Re-launched bulk download**: Resumed from 2019 NDVI processing
3. **Diagnosed 2025 download issues**: `acquire_conus_data()` was only defining functions, not executing; then parallel workers created permanent zombies due to Docker PID 1 issue
4. **Applied zombie fixes to `01a_midwest_data_acquisition_parallel.R`**:
   - Removed duplicate `plan(multisession)` before loop (created instant zombies)
   - Switched to `plan(multicore)` for fork-based reaping
   - Removed redundant `source("01a_midwest_data_acquisition_parallel.R")` in workers
5. **Extended bulk download to 2025**: Added 2025 to year loop in `bulk_download_docker.sh`
6. **Optimized download-monitor agent**: Reduced tool calls for faster status checks
7. **Shelved 2025 R-based download**: Docker container lacks proper init; bulk download covers it

### Key Finding: Docker Zombie Root Cause
Docker's PID 1 (`tail -f /dev/null`) never calls `wait()`, so any orphaned child process becomes a permanent zombie. This affects ALL parallel R strategies (`multisession` and `multicore`) when the parent is killed mid-run. The only workaround without rebuilding the container is to use sequential processing or the wget-based bulk download (which creates shell processes that don't become zombies).

### Commits
- `9ebbeeb` — `[ops][fix] Fix parallel zombie accumulation, extend bulk download to 2025`

---

## Previous Session Summaries

### Session Summary (Feb 16, 2026)

**Problem**: `FutureInterruptError` crashes in R parallel workers.
**Root cause**: Workers accumulated memory without recycling. `terra` rasters not freed, `future.globals.maxSize` too small.
**Fix**: Worker recycling pattern — fresh `plan()` per iteration, `tryCatch` + sequential fallback, `gc()` cleanup, 5,000-granule chunks.

### Session Summary (Feb 12, 2026)

**Work**: Migrated bulk download from host to Docker (host lacked `terra`). Created `download-monitor` agent. Copied `.netrc` into container.

---

## Pipeline Status

| Step | Script | Status |
|------|--------|--------|
| Download (2013-2018) | `redownload_all_years_cloud100.R` | COMPLETE |
| Download (2019-2025) | `bulk_download_docker.sh` | RUNNING — 2019 NDVI processing |
| Aggregation | `01_aggregate_to_4km_parallel.R` | 2013-2016 COMPLETE, 2017+ pending |
| Norms | `02_doy_looped_norms.R` | Pending aggregation |
| Year Predictions | `03_doy_looped_year_predictions.R` | Updated to k=50, ready |

---

## Key Notes for Next Session

- **`.netrc` is ephemeral**: Re-copy after container rebuild: `docker cp ~/.netrc conus-hls-drought-monitor:/.netrc`
- **Bulk download is resumable**: `getHLS_bands.sh` skips existing files, `process_bulk_ndvi_docker.R` skips processed scenes
- **Current run won't include 2025**: Bash read the script at launch; 2025 will be picked up on next restart
- **2020, 2022, 2023 are critical gaps**: Bulk download will fill these as it works through each year
