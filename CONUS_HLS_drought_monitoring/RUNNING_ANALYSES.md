# Currently Running Analyses

**Updated**: 2026-04-28 11:30 MDT (end of pipeline-audit + downstream-fix session)

## Status: RUNNING — 4km Aggregation 2019-2025 (year 1 of 7, ~46% through 2019)

### Pipeline 1: 4km Aggregation (Script 01)
- **Status**: RUNNING — 2013-2018 complete, 2019 in progress
- **Active script**: `01_aggregate_to_4km_parallel.R 2019 2025 --workers=8 --tiles=bulk_downloads/midwest_tiles_overlapping.txt`
- **Log**: `/mnt/malexander/datasets/ndvi_monitor/gam_models/aggregation_2019_2025.log`
- **Started**: 2026-04-28 07:28 MDT (replaced unfiltered run from 2026-04-24)
- **As of 11:30 MDT**: 8/8 workers alive, ~46% through 2019 (212 RDS batches written + 8 worker_processed files), per-worker range 22-30 batches. Worker 04 slowest at 37%. Expected year 2019 completion: ~15:00 MDT today. Expected full 2019-2025 run: ~2026-05-04 to 05-05.

#### Year completion timing (original unfiltered run, 2013-2018)
| Year | Status | Runtime |
|------|--------|---------|
| 2013 | Complete | 305 min |
| 2014 | Complete | 431 min |
| 2015 | Complete | 429 min |
| 2016 | Complete | 736 min |
| 2017 | Complete | 1062 min |
| 2018 | Complete | 1862 min (~31 hrs) |

#### Tile filter swap (2026-04-28)
The original `midwest_tiles_noprefix.txt` contained all 1209 CONUS tiles, ~75% of which fell outside the Midwest 4km grid bbox. After 2018 completed, swapped to the geographically-filtered list:

- **Old filter**: 1209 tiles → ~24,000 files/worker for 2019, ~23% success rate
- **New filter**: 308 tiles → ~5,800 files/worker for 2019, ~100% success rate
- **Confirmed working**: 46,612 / 191,555 files kept (24.3%) for 2019, matches the predicted overlap

#### Swap procedure executed
1. ✓ 2018 completion verified: `ndvi_4km_2018.rds` (72MB, written Apr 27 18:05)
2. ✓ Killed bash wrapper (1285300), parent Rscript (1285305), and 8 orphaned workers
3. ✓ Preserved 2019 partial work in `aggregation_temp/2019/` (~80 batch files from overnight; will be deduplicated at combine time)
4. ✓ Restarted with: `Rscript 01_aggregate_to_4km_parallel.R 2019 2025 --workers=8 --tiles=bulk_downloads/midwest_tiles_overlapping.txt`
5. ✓ Verified healthy: 8 workers active, 610% CPU, 25 GB memory

**Expected completion**: ~7 days for 2019-2025 (was ~5 weeks unfiltered)

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

## Session Summary (Apr 28, 2026 — pipeline-audit + downstream-fix session)

Full pipeline review while aggregation runs. Two new agents added (pipeline-audit, r-reviewer), 23 deprecated scripts archived, 62 GB reclaimed, all four downstream scripts (02, 03, 04, 06) audited and patched. **5 commits pushed to origin/main.**

### Work Completed
1. **Agents** (`.claude/agents/`):
   - `pipeline_audit.md`: rewrote from corrupted-import markdown, retargeted from wildfire to NDVI HLS pipeline, scoped to `CONUS_HLS_drought_monitoring/` only
   - `r-reviewer.md`: added NDVI-specific framework checks (future worker recycling, posterior incremental saving, NLCD 125,798-pixel verification, Docker path duality, sensor handling, year-range hardcoding)
2. **Pipeline audit** (read-only): identified 23 archive candidates + 6 ambiguous scripts requiring investigation. Cleaned up:
   - Group 1: 7 test/cloud100 experiment scripts (Jan 2026)
   - Group 2: 4 sequential predecessors of `_parallel` variants
   - Group 3: 4 stale orchestration/monitor scripts
   - Group 4: 4 pre-Docker bulk download artifacts
   - Group 5: 3 historical state files
   - Investigation finding: `00_gam_utility_functions.R` (superseded by `00_posterior_functions.R`)
   - All moved to `.archive/`. **Reclaimed 62 GB** by deleting `year_predictions_posteriors_k50_test/` (k=50 test posteriors no longer needed).
3. **Promoted combine snippet to script**: `01b_combine_year_files.R` (272 lines) replaces the unversioned R snippet that was living in `WORKFLOW.md`. Adds schema validation, sensor-broken-down duplicate detection, skip-if-up-to-date logic, per-year + combined sanity reports.
4. **Script 02 patches** (norms): added per-DOY seed (`1034 + day`) so 100 sims across DOYs are independent; resume mode now also verifies posterior file presence (was summary-only); DOY 366 dropping is now logged; new posterior format (see #7); documented sensor-pooling decision (HLS L30/S30 NASA-harmonized, no sensor term needed).
5. **Script 03 patches** (year predictions): pixel-id ordering fix (was using pixel_coords order with pred_grid-ordered values — silent misalignment risk); per-(year, DOY) seed (`year * 1000 + day`); resume mode now verifies posterior completeness per fitted DOY; 125,798-pixel guard; write-integrity check; **`mclapply` → `future_lapply` with the recycling pattern from MEMORY.md**, plus per-year pre-filter of timeseries to cut multisession worker memory from 15 GB to 250-400 MB.
6. **Script 04 full rewrite**: replaced naive interval arithmetic on summary CIs with **proper posterior subtraction**. Statistically correct anomaly CIs, internally consistent with script 06. Optional `--save-posteriors` flag. Per-DOY parallelization via future-recycling pattern. Pixel guard + write check.
7. **POSTERIOR FORMAT CHANGE** (scripts 02 + 03): write `list(pixel_id, sims_matrix)` instead of raw `df.sim`. Fixes a hidden ~3% bias in script 06's `calculate_stats` (X/x/y columns from `post.distns()`'s data-frame format were being averaged alongside the 100 sim columns by `rowMeans`/`quantile`, contaminating means and CIs and producing systematically false-negative significance flags). Pixel_id stored alongside also defends against future ordering drift between scripts.
8. **Script 06 update**: new `load_posteriors()` reads the list format → bias eliminated; `mclapply` → `future_lapply` with recycling; pre-flight inventory of baseline + year posteriors before launching workers (aborts fast if baseline >5% incomplete); resume mode verifies all per-DOY-window posteriors present; pixel guard; write-integrity check.
9. **`safe_shutdown.sh` patched**: removed `prefetch_downloads.sh` handling (script archived).
10. **Renamed `01_HLS_data_acquisition_FINAL.R` → `01_hls_acquisition_core.R`**: still load-bearing (sourced by `01a_midwest_data_acquisition_parallel.R` from 3 sites, all updated). The `_FINAL` suffix was misleading.
11. **WORKFLOW.md fully refreshed**: Core Scripts list updated with `01b`, `00_validate_ndvi_data`, `07_visualize_derivatives`, `07_classify_drought` (placeholder); 05 vs 05a/b/c clarified as alternative paths; replaced inline combine snippet with pointer to `01b_combine_year_files.R`; corrected script 02 description (no mission term, no temporal smoother — was wrong); added Script 07_visualize_derivatives section; added Planned Future Step section for `07_classify_drought`; updated Data Flow caption to 2013-2025 with leap-day note.
12. **DOCKER_SETUP.md cleaned up**: removed pre-DOY-looped pseudocode that referenced archived script names; replaced with pointer to WORKFLOW.md as single source of truth.
13. **Compressed 16 download/prefetch logs** in `bulk_downloads/logs/`: 568 MB → 24 MB (544 MB freed). Logs still readable via `zcat`/`zless`.

### Files Created
- `01b_combine_year_files.R` — combine per-year aggregation outputs into `conus_4km_ndvi_timeseries.rds` (replaces the inline R snippet in WORKFLOW.md)
- `.claude/agents/pipeline_audit.md` — NDVI-pipeline-targeted audit agent
- `.claude/agents/r-reviewer.md` — R code reviewer with NDVI framework checks

### Files Modified (active pipeline)
- `02_doy_looped_norms.R`
- `03_doy_looped_year_predictions.R`
- `04_calculate_anomalies.R` (full rewrite)
- `06_calculate_change_derivatives.R`
- `00_posterior_functions.R` (added `seed` parameter)
- `01a_midwest_data_acquisition_parallel.R` (3 source() calls updated for rename)
- `safe_shutdown.sh` (removed prefetch handling)
- `WORKFLOW.md`, `DOCKER_SETUP.md`

### Files Renamed
- `01_HLS_data_acquisition_FINAL.R` → `01_hls_acquisition_core.R`
- 23 scripts → `.archive/` (see commit `382da23` for full list)

### Commits Pushed (origin/main)
1. `382da23` — `[cleanup][fix][agents]` Archive 23 deprecated scripts; add combine script; patch script 02
2. `6198bf5` — `[rename][docs]` Rename hls_acquisition_core; refresh WORKFLOW + DOCKER_SETUP
3. `e9725b9` — `[fix]` Complete rename — drop duplicate 01_HLS_data_acquisition_FINAL.R
4. `0fd9233` — `[fix][03]` Pixel-id ordering, per-(year,DOY) seed, complete-resume check, mclapply→future
5. `5c7b9b1` — `[fix][04][06]` Posterior-based anomalies + calculate_stats bias fix + future_lapply

### Bugs Caught (severity)
- **CRITICAL** silent pixel-id misalignment in script 03 (pixel_coords order vs pred_grid order)
- **CRITICAL** `calculate_stats` bias in script 06 (~3% mean shift, false-negative significance flags) caused by `rowMeans`/`quantile` sweeping the X/x/y columns of the saved `df.sim` data frame
- **CRITICAL** cross-(year, DOY) posterior correlation (deflated CIs in scripts 04 + 06) — same set.seed reused per call
- **HIGH** resume modes in scripts 02/03/06 only checked summary stats, not posterior file presence
- **HIGH** `mclapply` worker memory exhaustion risk on long jobs (per MEMORY.md prior incident)
- **HIGH** combine logic was an unversioned R snippet in markdown
- **METHODOLOGICAL** script 04 used naive interval arithmetic on summary CIs instead of posterior subtraction — wider intervals than statistically correct, inconsistent with script 06

### Next Steps (after aggregation completes ~2026-05-04 / 05-05)
1. Run `01b_combine_year_files.R` (~5 min) — produces `conus_4km_ndvi_timeseries.rds`
2. Run `02_doy_looped_norms.R` (~6-8 hr serial) — baseline norms + posteriors in NEW format
3. Run `03_doy_looped_year_predictions.R` (~1.5-2 days, 3 future workers per year) — year predictions + posteriors
4. Run `04_calculate_anomalies.R` (~4-6 hr with new posterior method) — proper posterior-based anomalies
5. Run `05_visualize_anomalies.R` OR `05a/05b/05c` (anomaly figures)
6. Run `06_calculate_change_derivatives.R` (~1.5-2 days) — change derivatives, bias fixed
7. Run `07_visualize_derivatives.R` (derivative figures)

`07_classify_drought.R` remains a placeholder for future work — needs threshold validation against USDM.

### Files NOT Committed (intentionally left in working tree)
- `.claude/settings.local.json` and `.vscode/settings.json` — both modified before this session started; left untouched for user to review/commit/discard separately.

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
