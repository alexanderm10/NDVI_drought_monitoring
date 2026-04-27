# Currently Running Analyses

**Updated**: 2026-04-27 MDT

## Status: RUNNING — 4km Aggregation (year 6 of 13, swap pending)

### Pipeline 1: 4km Aggregation (Script 01)
- **Status**: RUNNING — 2013-2017 complete, 2018 in progress (~18% as of 2026-04-27)
- **Script**: `01_aggregate_to_4km_parallel.R 2013 2025 --workers=8 --tiles=bulk_downloads/midwest_tiles_noprefix.txt`
- **Log**: `/mnt/malexander/datasets/ndvi_monitor/gam_models/aggregation_2013_2025.log`
- **Started**: 2026-04-24 08:40 MDT

#### Year completion timing
| Year | Status | Runtime |
|------|--------|---------|
| 2013 | Complete | 305 min |
| 2014 | Complete | 431 min |
| 2015 | Complete | 429 min |
| 2016 | Complete | 736 min |
| 2017 | Complete | 1062 min |
| 2018 | RUNNING (~18% after 22 hrs) | est. 5 days |

#### ⚠️ Tile filter inefficiency (discovered 2026-04-27)
The `midwest_tiles_noprefix.txt` filter contains all 1209 CONUS tiles, not just Midwest.
~75% of compute is wasted reading rasters from tiles outside the 4km grid bbox.
Confirmed by ~23% success rate across all completed years.

**Fix in place** (committed 2026-04-27):
- New filter: `bulk_downloads/midwest_tiles_overlapping.txt` (308 tiles, only zones 13-17)
- Generator: `bulk_downloads/generate_midwest_tile_filter.R`
- Resume bug fixed: `scene_id` now includes tile (was sensor+date only)

**Pending swap** when 2018 completes (~3 days):
1. Verify: `ls /mnt/malexander/datasets/ndvi_monitor/gam_models/aggregated_years/ndvi_4km_2018.rds`
2. Stop current job: kill the parent Rscript (PID ~1285305) inside container
3. Restart for 2019-2025 with the new filter:
   ```bash
   docker exec -d conus-hls-drought-monitor bash -c \
     "cd /workspace && Rscript 01_aggregate_to_4km_parallel.R 2019 2025 --workers=8 \
      --tiles=bulk_downloads/midwest_tiles_overlapping.txt \
      > /data/gam_models/aggregation_2019_2025.log 2>&1"
   ```
- **Expected savings**: ~5 weeks → ~7-10 days for 2019-2025

### Pipeline 2: 2013-2018 HLS Re-Download + NDVI Processing — COMPLETE
- **Status**: COMPLETE (finished Apr 22)
- **Script**: `bulk_download_docker.sh` (loops 2013→2018)
- **Log**: `bulk_downloads/logs/bulk_2013_2018.log`
- **Reason**: Original 2013-2018 download used `max_items=100` (now `page_size=2000`); files were ~5x sparser than expected
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

## Session Summary (Apr 24, 2026)

### Work Completed
1. **Confirmed 2013-2018 re-download complete**: All 6 years finished Apr 22 (40K-193K files per year)
2. **Preflight checks**: Verified all 13 year directories readable, grid consistency (150,480 cells, 125,798 valid pixels), 76 TB free disk
3. **Added `--tiles` filter to aggregation script**: New `--tiles=<file>` CLI parameter filters input files to specified MGRS tiles. Handles T-prefix mismatch between filenames (`T09UYP`) and tile list (`09UYP`). Prevents wasted CIFS I/O when processing CONUS data against Midwest grid.
4. **Discovered 2025 has same 1,209 Midwest tiles**: Despite being downloaded as full CONUS, all tiles in 2025 data are already Midwest-only. Tile filter still useful as safeguard.
5. **Launched full 2013-2025 aggregation**: 8 workers, tile-filtered, all 13 years queued. 2013 completed in 304.8 min (12 MB output). 2014 in progress.

### Files Modified
- `01_aggregate_to_4km_parallel.R`: Added `--tiles=<file>` CLI argument and tile filtering logic

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
| NDVI Processing (2013-2018) | `bulk_download_docker.sh` | **COMPLETE** (re-pass, finished Apr 22) |
| NDVI Processing (2019-2025) | `bulk_download_docker.sh` | **COMPLETE** |
| Aggregation (2013-2025) | `01_aggregate_to_4km_parallel.R` | **RUNNING** — 2013 done, 2014 in progress |
| Combine timeseries | R snippet (see WORKFLOW.md) | Pending aggregation |
| Norms (2013-2025) | `02_doy_looped_norms.R` | Pending combine |
| Year Predictions | `03_doy_looped_year_predictions.R` | Pending norms |
| Anomalies | `04_calculate_anomalies.R` | Pending year predictions |
| Derivatives | `06_calculate_change_derivatives.R` | Pending anomalies |

---

## Next Steps (After Aggregation Completes, ~Apr 26-27)

### 1. Combine all year files into timeseries
See the combine snippet in [WORKFLOW.md](WORKFLOW.md) — produces `conus_4km_ndvi_timeseries.rds`.

### 2. Check pixel coverage before fitting norms
After combining, check DOY coverage distribution for 2013-2018 to evaluate whether the 33% pixel threshold still needs adjustment (see `TIMESERIES_GAPS_ANALYSIS.md` in repo root).

### 3. Refit baseline norms (2013-2025)
```bash
docker exec conus-hls-drought-monitor Rscript 02_doy_looped_norms.R
```

### 4. Refit year predictions and downstream
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
