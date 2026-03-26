# Currently Running Analyses

**Updated**: 2026-03-26 16:45 MDT

## Status: STOPPED — Graceful shutdown for machine maintenance

### Pipeline: Bulk Download (2019-2025) — Docker
- **Status**: STOPPED — container shut down for machine update
- **Script**: `bulk_download_docker.sh` → `process_bulk_ndvi_docker.R`
- **Log**: `bulk_downloads/logs/process_2024_docker.log`, `bulk_downloads/logs/bulk_docker.log`
- **Container**: `conus-hls-drought-monitor` (stopped Mar 26, was up 14 days since Mar 12)
- **NDVI status**: 2019-2023 complete; 2024 stopped at chunk 29/51 (~55%); 2025 pending
- **Last completed chunk**: 28 (granules 135,001-140,000) — chunk 29 was interrupted
- **Error rate**: 0.03% across 28 completed chunks
- **Shutdown state**: `shutdown_state_20260326_164513.txt`

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

### Processed NDVI (daily) — Updated Mar 24, 2026
| Year | Files | Status |
|------|-------|--------|
| 2013 | 25,107 | Complete (pre-HLS) |
| 2014 | 34,490 | Complete (pre-HLS) |
| 2015 | 34,786 | Complete (pre-HLS) |
| 2016 | 36,646 | Complete (pre-HLS) |
| 2017 | 36,425 | Complete (pre-HLS) |
| 2018 | 36,483 | Complete (pre-HLS) |
| 2019 | 191,555 | **Complete** |
| 2020 | 188,190 | **Complete** |
| 2021 | 208,915 | **Complete** |
| 2022 | 258,101 | **Complete** (finished Mar 18) |
| 2023 | 251,237 | **Complete** (finished Mar 23) |
| 2024 | ~140,000 | **Stopped** — chunk 28/51 complete (~55%), shutdown for maintenance |
| 2025 | — | Pending — raw data prefetch was active (S30 tile T16UEU) |

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

## Session Summary (Mar 26, 2026)

### Work Completed
1. **Status check**: 2024 NDVI processing at chunk 29/51 (~55%), up from 17/51 on Mar 24
2. **Created safe_shutdown.sh**: Graceful shutdown script for pipeline — signals orchestrators, waits for R workers, validates files, saves state
3. **Graceful shutdown**: Stopped pipeline for machine maintenance (force-stopped mid chunk 29)
4. **Stopped containers**: `conus-hls-drought-monitor` and `gdo-wildfire-risk-monitor`

### Restart Procedure
```bash
docker start conus-hls-drought-monitor
docker exec -d conus-hls-drought-monitor bash -c 'cd /workspace/bulk_downloads && nohup ./bulk_download_docker.sh >> logs/bulk_docker.log 2>&1 &'
docker exec -d conus-hls-drought-monitor bash -c 'cd /workspace/bulk_downloads && nohup ./prefetch_downloads.sh >> logs/prefetch.log 2>&1 &'
```

### Post-restart cleanup
Chunk 29 was interrupted — up to 8 truncated NDVI files may exist. Run:
```bash
find /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/2024/ -name "*_NDVI.tif" -size -50k -delete
```
Then re-copy `.netrc` if container was rebuilt: `docker cp ~/.netrc conus-hls-drought-monitor:/.netrc`

---

## Session Summary (Mar 24, 2026)

### Work Completed
1. **Status check**: Confirmed 2023 NDVI processing completed (251,237 files) — 6 of 7 years done (2019-2023)
2. **2024 processing healthy**: Chunk 8/51, 0.04% error rate, ~1,940 granules/hour throughput
3. **Throughput analysis**: Compared 2023 vs 2024 processing rates — identical (~1,940/hr), no session degradation
4. **2025 prefetch active**: wget workers downloading S30 tile T12UVU (Oct 2025 data)
5. **Updated RUNNING_ANALYSES.md**: Refreshed all status tables

### Key Milestone
- **2023 NDVI processing complete** — 5 of 7 years (2019-2023) now fully processed
- Pipeline is 71% through the 2019-2025 NDVI processing queue
- 2024 ETA: ~March 29

---

## Session Summary (Mar 18, 2026)

### Work Completed
1. **Status monitoring**: Tracked 2022 NDVI processing from 96% to completion (258,101 files from 259,322 granules, all 52 chunks clean)
2. **Pipeline transition confirmed**: Orchestrator automatically moved to 2023 at 11:35 MDT; currently scanning 252,480 granules
3. **Prefetch status**: 2023 raw data download complete (342k files); 2024 prefetch active (152k+ files, tiles T14TPK/T14TPL)
4. **Updated RUNNING_ANALYSES.md**: Refreshed all status tables and data inventory

### Key Milestone
- **2022 NDVI processing complete** — 4 of 7 years (2019-2022) now fully processed
- Pipeline is 57% through the 2019-2025 NDVI processing queue

### Commits
- See below

---

## Session Summary (Mar 16, 2026)

### Work Completed
1. **Status checks**: Confirmed 2022 NDVI processing healthy at 73% (189k/259k files); ~6,300 files/30min throughput
2. **download-monitor agent rewrite**: Updated `.claude/agents/download-monitor.md` to check NDVI file counts per year (real progress metric) and active worker memory. Old version checked wrong log paths inside container
3. **bulk_download_docker.sh fixes**:
   - Replaced `ls *_NDVI.tif | wc -l` with `find`-based `count_ndvi()` helper to avoid glob overflow on large dirs
   - Added `NDVI_COMPLETE_THRESHOLD=100000` skip logic — years already fully processed are skipped without re-processing
   - Removed redundant 2019/2020 pre-processing loop (merged into main loop)
4. **prefetch_downloads.sh**: New script to pre-download 2023-2025 raw data in parallel with ongoing NDVI processing. Currently pre-fetching 2023 data in background
5. **Commit**: `5cb0a84` — all changes pushed to main

### Key Finding: NDVI File Count Method
`ls /dir/*_NDVI.tif | wc -l` crashes with "Argument list too long" on dirs with 200k+ files.
Use `find /dir -name "*_NDVI.tif" | wc -l` instead — no argument limit.

### Commits
- `5cb0a84` — `[monitor][docker][data] Improve status monitoring and bulk download robustness`

---

## Session Summary (Mar 12, 2026)

### Work Completed
1. **Crash recovery**: Remote machine went down overnight, container exited (code 255)
2. **NFS remount**: CIFS mount to `ascend.egs.anl.gov` dropped during crash; confirmed it came back up, verified data integrity (38TB raw data intact)
3. **Container restart**: Restarted container, re-copied `.netrc`, verified NFS visible inside container at `/data/`
4. **Fixed re-download problem**: `wget -N` was re-downloading all existing files (timestamp mismatch after NFS remount). Added skip logic to `bulk_download_docker.sh` — counts existing granule directories and skips download if >1000 already exist for a year
5. **NDVI processing hardening**: Added `validate_tif()` to both `process_bulk_ndvi.R` and `process_bulk_ndvi_docker.R` — catches corrupt/truncated downloads before loading (prevents SIGFPE crashes). Safe NDVI calc via `lapp()` instead of C++ raster algebra. Corrupt file logging for later re-download

### Commits
- See below

### Key Finding: NFS Crash Recovery
- NFS mount (`//ascend.egs.anl.gov/home/malexander`) drops on machine crash but auto-remounts on reboot
- Docker bind mounts become stale — container must be restarted to pick up remounted filesystem
- `wget -N` timestamp comparison breaks after NFS remount, causing full re-downloads of existing data

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
| Download (2019-2025) | `bulk_download_docker.sh` | RUNNING — 2019-2024 downloaded, 2024 NDVI chunk 8/51, 2025 prefetching |
| Aggregation | `01_aggregate_to_4km_parallel.R` | 2013-2016 COMPLETE, 2017+ pending |
| Norms | `02_doy_looped_norms.R` | Pending aggregation |
| Year Predictions | `03_doy_looped_year_predictions.R` | Updated to k=50, ready |

---

## Key Notes for Next Session

- **`.netrc` is ephemeral**: Re-copy after container rebuild/restart: `docker cp ~/.netrc conus-hls-drought-monitor:/.netrc`
- **NFS mount may drop on crash**: Check with `df -h /mnt/malexander/datasets/ndvi_monitor/` — should show 316TB CIFS mount, not local `/dev/sda1`
- **Docker bind mounts go stale after NFS remount**: Must restart container (`docker restart conus-hls-drought-monitor`) to pick up remounted filesystem
- **Bulk download now has skip logic**: Counts granule dirs, skips download if >1000 exist. Won't re-download completed years
- **NDVI processing validates TIFs**: `validate_tif()` catches corrupt files before loading, logs them for later re-download
