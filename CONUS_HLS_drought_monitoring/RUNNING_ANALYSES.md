# Currently Running Analyses

**Updated**: 2026-02-18 16:15 CST

## Status: RUNNING — Two pipelines converging toward 2022

### Pipeline 1: Bulk Forwards (2019→2024) — Docker
- **Status**: RUNNING — 2021 NDVI processing, Chunk 12/42 (~29%)
- **Script**: `bulk_download_docker.sh` → `getHLS_bands.sh` + `process_bulk_ndvi_docker.R`
- **Log**: `bulk_downloads/logs/process_2021_docker.log`
- **Workers**: 8 parallel R (NDVI calc), chunked in 5,000-granule batches
- **NDVI output**: 2021: 60,734 files; 2022-2024: queued after 2021 finishes
- **Note**: 2019/2020 NDVI output dirs are empty — need standalone re-run after 2021

### Pipeline 2: Backwards Queue (2025→2022) — Docker
- **Status**: RUNNING — `download_queue_backwards.sh` (started Feb 16)
- **Script**: `download_queue_backwards.sh` → `01a_midwest_data_acquisition_parallel.R`
- **Queue**: 2025 ✓ COMPLETE → **2024 in progress** (Feb 2024) → 2023 → 2022
- **Log**: `/data/download_queue.log`, per-year: `/data/download_YYYY_conus.log`
- **Workers**: 4 parallel R workers, 40 CONUS tiles, `cloud_cover_max=100`
- **NDVI output**: 2025: 35,230 files (complete); 2024: 11,057 files (in progress)
- **Meet-in-middle target**: Both pipelines converge at 2022

### Previous Issues (Resolved)
- **Feb 12**: Migrated from host to Docker (host lacked `terra` for NDVI processing)
- **Feb 13**: 2025 download crashed with `FutureInterruptError` during November processing
- **Feb 16**: Root cause identified and fixed — see "Session Summary (Feb 16)" below

---

## Monitoring

### Custom Agent (New)
A `download-monitor` agent was created at `.claude/agents/download-monitor.md`. In Claude Code, ask "check on my downloads" to trigger it.

### Manual Monitoring
```bash
# Bulk download (2019-2024)
tail -f CONUS_HLS_drought_monitoring/bulk_downloads/logs/bulk_docker.log

# 2025 download
tail -f /mnt/malexander/datasets/ndvi_monitor/download_2025_restart.log

# Docker container health
docker exec conus-hls-drought-monitor ps aux | grep -E "[R]script|[w]get"

# Check for zombies
docker exec conus-hls-drought-monitor ps aux | grep " Z "

# File counts
for yr in 2019 2020 2021 2022 2023 2024 2025; do
  echo -n "$yr: "
  ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$yr/ 2>/dev/null | wc -l
done
```

---

## Session Summary (Feb 12, 2026)

### Work Completed
1. **Killed host processes**: Bulk download process group + 3 zombie `curl` processes
2. **Restarted Docker**: Cleared 4 zombie R workers from crashed 2025 download
3. **Moved bulk download into Docker**: Created `bulk_download_docker.sh` and `process_bulk_ndvi_docker.R` with Docker-internal paths (`/data/` instead of `/mnt/malexander/...`). `terra` now available for NDVI processing.
4. **Copied .netrc**: Earthdata credentials placed at `/.netrc` in container (matching `$HOME=/`)
5. **Restarted 2025 download**: `acquire_conus_data(start_year=2025)` — skipped Jan-Feb, now on March 2025
6. **Created download-monitor agent**: `.claude/agents/download-monitor.md` — custom Claude Code agent for automated status checks

### Files Created
- `.claude/agents/download-monitor.md`
- `bulk_downloads/bulk_download_docker.sh`
- `bulk_downloads/scripts/process_bulk_ndvi_docker.R`

### Commits
- `d3993a5` — `[ops][docker] Move bulk download into Docker and add download-monitor agent`

---

## Session Summary (Feb 16, 2026)

### Problem: `FutureInterruptError` Crashes

Both the 2025 download (`01a_midwest_data_acquisition_parallel.R`) and the bulk NDVI processing (`process_bulk_ndvi.R` / `process_bulk_ndvi_docker.R`) were crashing with `FutureInterruptError` — R parallel workers were being interrupted mid-execution, leaving zombie processes and no NDVI output.

### Root Cause

R's `future` parallel framework was accumulating memory across long-running jobs. Workers were never recycled, so memory grew until the system killed them. Additionally, `terra` raster objects weren't being freed inside worker functions, and the default `future.globals.maxSize` was too small for the raster data being passed.

### Fixes Applied (3 scripts)

**1. `01a_midwest_data_acquisition_parallel.R` (2025 CONUS download)**
- Added `options(future.globals.maxSize = 2 * 1024^3)` (2 GB limit)
- Fresh worker pool each month: `plan(multisession)` at start, `plan(sequential)` + `gc()` after
- `tryCatch` around `future_lapply` with sequential fallback on failure
- `gc(verbose = FALSE)` inside each worker after processing
- Increased `max_items` from 100 to 1000 to avoid scene truncation

**2. `process_bulk_ndvi.R` (host NDVI processing)**
- Added `options(future.globals.maxSize = 2 * 1024^3)`
- Chunked processing: 5,000 granules per chunk instead of all-at-once
- Fresh worker pool per chunk with cleanup between chunks
- `tryCatch` with sequential fallback per chunk
- `rm()` + `gc()` for raster objects inside `calculate_ndvi_bulk()`

**3. `process_bulk_ndvi_docker.R` (Docker NDVI processing)**
- Same fixes as `process_bulk_ndvi.R` (Docker-path variant)

### Key Pattern: Stable R Parallel Processing

```r
# 1. Set generous global size limit
options(future.globals.maxSize = 2 * 1024^3)

# 2. Fresh workers each iteration
plan(multisession, workers = 4)

# 3. Wrap in tryCatch with sequential fallback
results <- tryCatch({
  future_lapply(..., future.seed = TRUE)
}, error = function(e) {
  lapply(...)  # sequential fallback
})

# 4. Clean up after each iteration
plan(sequential)
gc(verbose = FALSE)

# 5. Free rasters inside workers
rm(red, nir, ndvi); gc(verbose = FALSE)
```

### Result
- 2025 download: Running stable since restart, processing ~1 month/day
- Bulk NDVI: 2019 produced 50,441 files, 2020 produced 13,305 files (previously 0)
- No new zombie processes generated

---

## Key Notes for Next Session

- **`.netrc` is ephemeral**: It was copied into the running container. If the container is rebuilt (`docker compose build`), you need to re-copy it: `docker cp ~/.netrc conus-hls-drought-monitor:/.netrc`
- **Bulk download is resumable**: `getHLS_bands.sh` skips existing files, so restarts are safe
- **2025 download is resumable**: R script checks for existing NDVI files before downloading
- **NDVI processing for 2019/2020**: Will happen automatically after each year's download completes inside Docker

---

## Pipeline Status

| Step | Script | Status |
|------|--------|--------|
| Download (2013-2018) | `redownload_all_years_cloud100.R` | COMPLETE |
| Download (2019-2024) | `bulk_download_docker.sh` | RUNNING - 2021 NDVI chunk 12/42 |
| NDVI (2019/2020) | `process_bulk_ndvi_docker.R` | PENDING - dirs empty, re-run after 2021 |
| Download (2022-2025) | `download_queue_backwards.sh` | RUNNING - 2025 ✓, 2024 in progress |
| Aggregation | `01_aggregate_to_4km_parallel.R` | 2013-2016 COMPLETE, 2017+ pending |
| Norms | `02_doy_looped_norms.R` | Pending aggregation |
| Year Predictions | `03_doy_looped_year_predictions.R` | Updated to k=50, ready |

---

## Aggregation Status (2013-2016)

| Year | Observations | Pixels | Obs/Pixel | Days | Sensors | File Size |
|------|-------------|--------|-----------|------|---------|-----------|
| 2013 | 1,270,784 | 142,099 | 8.9 | 222 | L30 only | 6.5 MB |
| 2014 | 1,583,381 | 141,769 | 11.2 | 320 | L30 only | 8.3 MB |
| 2015 | 1,616,606 | 142,466 | 11.3 | 305 | L30 97%, S30 3% | 8.5 MB |
| 2016 | 2,139,261 | 142,111 | 15.1 | 291 | L30 57%, S30 43% | 12 MB |

## Key Configuration

- **Spatial basis**: k=50 (validated)
- **Cloud cover filter**: 100% at scene level (Fmask handles pixel-level QA)
- **Aggregation**: 4km resolution, median, min 5 pixels per cell
- **Study area**: Midwest bbox (-104.5, 37.0, -82.0, 47.5)
