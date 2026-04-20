# Currently Running Analyses

**Updated**: 2026-04-20 MDT

## Status: RUNNING — 2018 NDVI processing (final year of 2013-2018 re-pass)

### Pipeline 1: 2013-2018 HLS Re-Download + NDVI Processing
- **Status**: RUNNING — processing 2018 (year 6 of 6); 2013-2017 all complete
- **Script**: `bulk_download_docker.sh` (loops 2013→2018)
- **Log**: `bulk_downloads/logs/bulk_2013_2018.log` (per-year: `download_YYYY_docker.log`, `process_YYYY_docker.log`)
- **Reason**: Original 2013-2018 download used `max_items=100` (now `page_size=2000`); files were ~5x sparser than expected
- **2018 progress**: Chunk 8/39 (~20%), 67,807 NDVI files so far (target ~150-200K), 0 zombies, 0 errors
- **Workers**: 8 R workers

### Pipeline 2: 2025 Second Pass — COMPLETE
- **Result**: 285,621 NDVI files (finished Apr 9, 2026)
- **Improvement**: +2,074 late-arriving NASA granules caught vs pass 1 (283,547)
- **Errors**: ~20 corrupt reads (tiles T11TPH/T12TUT/T11TLJ/T12RVV — expected corrupt NASA source)

---

## Data Inventory

### Processed NDVI (daily) — Updated Apr 20, 2026
| Year | Files | Status |
|------|-------|--------|
| 2013 | ~40-50K (est.) | Re-processing complete |
| 2014 | ~40-50K (est.) | Re-processing complete |
| 2015 | ~120-150K (est.) | Re-processing complete |
| 2016 | ~120-150K (est.) | Re-processing complete |
| 2017 | 119,080 | **Re-processing complete** (Apr 16) |
| 2018 | 67,807+ | **RUNNING** — chunk 8/39 (~20%) |
| 2019 | 191,555 | **Complete** |
| 2020 | 188,190 | **Complete** |
| 2021 | 208,915 | **Complete** |
| 2022 | 258,101 | **Complete** |
| 2023 | 251,237 | **Complete** |
| 2024 | 254,497 | **Complete** (finished Mar 29) |
| 2025 | 285,621 | **Complete** (pass 2 finished Apr 9) |

---

## Monitoring

### Custom Agent
A `download-monitor` agent at `.claude/agents/download-monitor.md`. In Claude Code, ask "check on my downloads" to trigger it.

### Manual Monitoring
```bash
# Processing log
tail -f CONUS_HLS_drought_monitoring/bulk_downloads/logs/process_2025_docker_restart.log

# Docker container health
docker exec conus-hls-drought-monitor ps aux | grep -E "[R]script|[w]get"

# Check for zombies (should stay at 0)
docker exec conus-hls-drought-monitor ps aux | grep -c defunct

# File counts
for yr in 2019 2020 2021 2022 2023 2024 2025; do
  echo -n "$yr: "
  ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$yr/ 2>/dev/null | wc -l
done
```

---

## Session Summary (Mar 30, 2026)

### Work Completed
1. **Diagnosed competing processes**: Two `process_bulk_ndvi_docker.R 2025` instances (PID 54544 with 4 workers, PID 455930 with 8 workers) were racing on same data — ~28% error rate from write collisions
2. **Verified 2024 complete**: 254,497 NDVI files, 32 errors (all corrupt NASA source), 0 truncated files
3. **Fixed zombie root cause**: Added `init: true` to `docker-compose.yml` — PID 1 is now `docker-init` (tini) which properly reaps zombies. Cleared 1,009 accumulated zombies
4. **Updated safe_shutdown.sh**: Truncated file check now covers both 2024 and 2025 directories
5. **Clean restart**: Rebuilt container (`docker compose down/up`), restored `.netrc`, launched single `process_bulk_ndvi_docker.R 2025 --workers=8`
6. **Verified clean operation**: 0 zombies, 0.06% error rate (down from 28%), 8 workers active

### Key Fix: Zombie Root Cause Resolution
The long-standing zombie problem was caused by Docker's PID 1 being `tail -f /dev/null`, which never calls `wait()`. Adding `init: true` to `docker-compose.yml` injects `tini` as PID 1, which properly reaps all child processes. This is a permanent fix — no more zombie accumulation regardless of how R workers exit.

### Files Modified
- `docker-compose.yml`: Added `init: true`
- `safe_shutdown.sh`: Extended truncated file check to include 2025

---

## Session Summary (Mar 27, 2026 — afternoon)

### Work Completed
1. **Status check**: 2024 at chunk 29/51 (~55%), 2025 download 92% complete (L30 done, S30 missing 182 tiles in zones 17-19)
2. **Restarted 2025 S30 prefetch**: Resumed `getHLS_bands.sh` to finish remaining ~24K S30 granules
3. **Launched parallel 2025 NDVI processing**: Started `process_bulk_ndvi_docker.R 2025 --workers=4` alongside ongoing 2024 (8 workers) — 12 total workers, plenty of headroom on 48-CPU/251GB system

---

## Session Summary (Mar 27, 2026 — morning)

### Work Completed
1. **Container restart**: Restarted `conus-hls-drought-monitor` after machine maintenance shutdown
2. **Re-copied `.netrc`**: Earthdata auth credentials restored inside container
3. **Fixed NDVI skip threshold**: Raised `NDVI_COMPLETE_THRESHOLD` from 100k to 180k — old threshold was incorrectly skipping 2024 (152k files, only ~55% complete)
4. **Narrowed year loop**: Changed `bulk_download_docker.sh` to iterate only 2024-2025 (2019-2023 confirmed complete) — avoids ~5 min of slow CIFS file counting per completed year
5. **Added download-monitor permissions**: Added Bash permissions for `echo`, `tail`, `grep`, `df`, `head`, `cat` to `settings.local.json` so the download-monitor agent can run its diagnostic commands

---

## Previous Session Summaries

### Mar 26 — Safe shutdown for maintenance
Created `safe_shutdown.sh`, gracefully stopped pipeline for machine maintenance at chunk 29.

### Mar 24 — 2023 complete, 2024 at 14%
Confirmed 2023 done (251,237 files). 2024 processing at chunk 8/51.

### Mar 18 — 2022 complete
2022 finished (258,101 files). Pipeline auto-transitioned to 2023.

### Mar 16 — Monitor agent rewrite
Fixed `download-monitor` agent, added `count_ndvi()` helper to bulk script, created `prefetch_downloads.sh`.

### Mar 12 — NFS crash recovery
Machine crashed, NFS remounted. Added `validate_tif()` to catch corrupt files. Fixed `wget -N` re-download bug.

### Feb 20 — Zombie diagnosis, shelved R-based 2025 download
Docker PID 1 zombie root cause identified. Extended bulk download to 2025. Shelved R-based CONUS download.

### Feb 16 — Parallel stability pattern
Fixed `FutureInterruptError` with worker recycling: fresh `plan()` per chunk, `tryCatch` + sequential fallback, `gc()` cleanup.

### Feb 12 — Docker migration
Moved bulk download into Docker container. Created `download-monitor` agent.

---

## Pipeline Status (Apr 20, 2026)

| Step | Script | Status |
|------|--------|--------|
| NDVI Processing (2013-2017) | `bulk_download_docker.sh` | **COMPLETE** (re-pass) |
| NDVI Processing (2018) | `bulk_download_docker.sh` | **RUNNING** — chunk 8/39 |
| NDVI Processing (2019-2025) | `bulk_download_docker.sh` | **COMPLETE** |
| Aggregation (2013-2025) | `01_aggregate_to_4km_parallel.R` | Pending — awaiting 2018 completion |
| Norms (2013-2025) | `02_doy_looped_norms.R` | Pending aggregation |
| Year Predictions | `03_doy_looped_year_predictions.R` | Pending norms |
| Anomalies | `04_calculate_anomalies.R` | Pending year predictions |
| Derivatives | `06_calculate_change_derivatives.R` | Pending anomalies |

---

## Next Steps (After 2018 Finishes, ~Apr 23-24)

### 1. Re-aggregate 2013-2018 to 4km
```bash
# Delete old per-year files so the script re-processes them
rm /mnt/malexander/datasets/ndvi_monitor/gam_models/aggregated_years/ndvi_4km_201{3,4,5,6,7,8}.rds

docker exec conus-hls-drought-monitor Rscript 01_aggregate_to_4km_parallel.R 2013 2018 --workers=8
```

### 2. Aggregate 2025 (new year)
```bash
docker exec conus-hls-drought-monitor Rscript 01_aggregate_to_4km_parallel.R 2025 --workers=8
```

### 3. Combine all year files into timeseries
See the combine snippet in [WORKFLOW.md](WORKFLOW.md) — produces `conus_4km_ndvi_timeseries.rds`.

### 4. Check pixel coverage before fitting norms
After combining, check DOY coverage distribution for 2013-2018 to evaluate whether the 33% pixel threshold still needs adjustment (see `TIMESERIES_GAPS_ANALYSIS.md` in repo root).

### 5. Refit baseline norms (2013-2025)
```bash
docker exec conus-hls-drought-monitor Rscript 02_doy_looped_norms.R
```

### 6. Refit year predictions and downstream
```bash
docker exec conus-hls-drought-monitor Rscript 03_doy_looped_year_predictions.R
docker exec conus-hls-drought-monitor Rscript 04_calculate_anomalies.R
docker exec conus-hls-drought-monitor Rscript 06_calculate_change_derivatives.R
```

---

## Geographic Coverage Discrepancy (Important for Analysis)

The download methods used different geographic extents across years. This matters when comparing file counts or interpreting coverage gaps.

| Years | Download Method | Geographic Extent |
|-------|----------------|-------------------|
| 2013-2018 (original) | `01a_midwest_data_acquisition.R` (CMR API, `max_items=100`) | Midwest bbox: -104.5 to -82.0 lon, 37.0 to 47.5 lat |
| 2013-2018 (re-download, Apr 2026) | `bulk_download_docker.sh` + `midwest_tiles_noprefix.txt` | 1,209 Midwest MGRS tiles |
| 2019-2024 | `bulk_download_docker.sh` + `midwest_tiles_noprefix.txt` | 1,209 Midwest MGRS tiles |
| 2025 | `01a_midwest_data_acquisition_parallel.R` | **Full CONUS**: -125 to -66 lon, 25 to 49 lat |

**Key implications:**
- **2013-2024 are internally consistent** after the re-download: all use the same 1,209 Midwest MGRS tile list
- **2025 covers more territory** (full CONUS) — its higher file counts (~283K vs ~188-254K for 2022-2024) partly reflect larger geographic coverage, not just more Sentinel passes
- The 1,209-tile list was derived from 2016 complete data (Feb 3 commit); MGRS tiles are a fixed grid so tile completeness should not be an issue
- **Do not directly compare 2025 file counts to 2013-2024** as a data quality metric — the domains differ

---

## Key Notes for Next Session

- **`.netrc` is ephemeral**: Re-copy after container rebuild/restart: `docker cp ~/.netrc conus-hls-drought-monitor:/.netrc`
- **Zombie fix is permanent**: `init: true` in docker-compose.yml — no manual cleanup needed
- **NFS mount may drop on crash**: Check with `df -h /mnt/malexander/datasets/ndvi_monitor/` — should show 316TB CIFS mount, not local `/dev/sda1`
- **Docker bind mounts go stale after NFS remount**: Must restart container to pick up remounted filesystem
- **2025 processing will auto-resume**: skip-if-exists logic means a restart just skips already-processed granules
