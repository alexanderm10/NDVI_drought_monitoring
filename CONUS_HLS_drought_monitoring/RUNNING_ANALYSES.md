# Currently Running Analyses

**Updated**: 2026-05-06 EOD (script 02 DOY 180 smoke test in flight)

## Active Background Process

- **Script**: `02_doy_looped_norms.R --doy=180` (single-DOY smoke test of the Apr 28 rewrite against the 167M-row 2013-2025 timeseries)
- **Container**: `conus-hls-drought-monitor`
- **Container PID**: 1309543 (host PID, R subprocess)
- **Started**: 2026-05-06 ~12:30 MDT
- **Log**: `/mnt/malexander/datasets/ndvi_monitor/gam_models/baseline_norms_test.log`
- **Status when session ended**: 6 min in, finished NLCD filter (147,880 → 129,310 pixels), 148.4M timeseries rows after filter, building prediction grid; GAM fit + 100 posterior sims still pending. Memory: 17.6 GB resident, 99.8% CPU.
- **Expected completion**: 15-30 min total wall-clock from launch
- **Outputs to expect on success**:
  - `gam_models/baseline_posteriors/doy_180.rds` (single-DOY posterior file, ~30-50 MB xz-compressed)
  - `gam_models/doy_looped_norms.rds` (summary stats — will be NA-filled for all DOYs except 180)
- **Monitor on next session**: `tail -50 /mnt/malexander/datasets/ndvi_monitor/gam_models/baseline_norms_test.log`

## Pipeline Status: 4km AGGREGATION + COMBINE COMPLETE; 02 PARALLELIZATION PENDING

### Pipeline 1: 4km Aggregation (Script 01) — COMPLETE
- **Status**: COMPLETE — 13 years (2013-2025) aggregated, all RDS files in `gam_models/aggregated_years/`
- **2025 finished**: 2026-05-05 15:40 MDT (488 min wall-clock with callr subprocess isolation; 0 subprocess crashes)
- **Per-round on 2025**: R1 8.6 min (resume-skip), R2 69 min (3,561 success / 295 fail), R3 226 min (19,561 / 439), R4 165 min (11,123 / 951). All "fail" counts are NULL-returns from quality filtering (no crashes — see Worker 4 investigation in May 6 session summary).
- **Combined timeseries**: `gam_models/conus_4km_ndvi_timeseries.rds` (808 MB, 167.1M rows, 147,880 pixels, 2013-04-12 to 2025-12-31, 38% L30 / 62% S30, written 2026-05-06 10:49 MDT)
- **Watcher**: `watch_then_combine.sh` was running but hit the host-vs-container path bug → 01b never launched on May 5 (fixed in commit `8ede66e`; combine ran manually on May 6).

#### Year completion timing (with tile filter)
| Year | Status | Runtime |
|------|--------|---------|
| 2019 | Complete | ~600 min |
| 2020 | Complete | ~580 min |
| 2021 | Complete | ~590 min |
| 2022 | Complete | ~750 min |
| 2023 | Complete | ~720 min |
| 2024 | Complete | 777 min |
| 2025 | RUNNING | (resume; ~6-8 hr remaining) |

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

## Session Summary (May 6, 2026 — 2025 confirmed clean, combined timeseries written, 2 fixes)

Returned to find the May 5 callr-protected 2025 aggregation had finished cleanly overnight, but the watcher launched 01b silently fail. Today: investigated the 2025 results, fixed two bugs, ran 01b manually.

### 2025 aggregation result (May 5 overnight)
- Finished 2026-05-05 15:40 MDT, 488 min wall-clock
- All 4 rounds completed (R1 8.6 min skip-pass, R2 69 min, R3 226 min, R4 165 min)
- **0 callr subprocess crashes** — the May 4 SIGSEGV did NOT recur. Either the May 4 corrupt-scene theory was wrong (it was actually a state-dependent allocation issue resolved by the cleaner subprocess workflow) or there's no truly corrupt scene to find.
- `aggregation_temp/2025/` was nuked by the year-end cleanup (script flaw — fixed today, see below).

### Worker 4 failure investigation
Worker 4 has shown 2-4× the failure rate of siblings every year (W4 ~430 fails vs ~130 siblings in 2019, 668 vs ~217 in 2024, 526 vs ~80 in 2025). Investigated and confirmed: **this is by-design quality filtering, not a bug**. Worker 4's round-robin tile assignment (39 tiles incl. T13TDF, T13SED) gets more edge-of-grid tiles. Sample of T13TDF (349 source files): 7/20 scenes returned NULL because they fell below the `min_pixels_per_cell = 5` threshold. Successful scenes only contribute 27-70 of 161,600 cells (thin-overlap edge tile). The script is correctly filtering scenes with insufficient signal.

### Two bugs fixed
1. **Corrupt-log preservation** (`01_aggregate_to_4km_parallel.R`): The year-end `unlink(temp_dir, recursive=TRUE)` was wiping any `worker_NN_corrupt.txt` audit logs before they could be inspected. Now: before the unlink, copy the contents to `<output_dir>/ndvi_4km_<year>_corrupt_scenes.txt` and print a confirmation line. If no crashes happened, print "no subprocess crashes" so absence is explicit.
2. **Watcher path bug** (`watch_then_combine.sh`): The May 5 watcher launched `01b` via `docker exec -d ... bash -c "...> /mnt/malexander/.../combine.log 2>&1"` — but `/mnt/malexander/...` doesn't exist inside the container. The redirect failed → the entire `bash -c` errored out → Rscript never started. Fixed by using container path `/data/gam_models/combine_2013_2025.log` for the redirect, keeping host path `/mnt/...` for the user-facing "Tail X to follow" message.
3. Both fixes in commit `8ede66e`.

### 01b run
Launched manually at 10:08 MDT, finished 10:49 MDT (41 min). Result:
- 167,122,092 rows combined (sum of all 13 year files)
- 147,880 unique pixels (full grid, every year)
- DOY 1-366 (leap day), 2013-04-12 to 2025-12-31
- 38.1% L30 / 61.9% S30 (S30 has higher revisit rate)
- 0 duplicates, 0 NA NDVIs, range -1 to 1
- Output: 808 MB at `gam_models/conus_4km_ndvi_timeseries.rds`

### Next steps
Downstream pipeline now fully unblocked:
1. `02_doy_looped_norms.R` — baseline norms across all years
2. `03_doy_looped_year_predictions.R` — per-year per-DOY GAM fits
3. `04_calculate_anomalies.R` — anomaly calculation (posterior subtraction)
4. `06_calculate_change_derivatives.R` — derivative-based stress detection

All four were rewritten in the Apr 28 session with the new posterior list format and recycling pattern. None have run since the rewrite.

### Files Modified
- `CONUS_HLS_drought_monitoring/01_aggregate_to_4km_parallel.R` (commit `8ede66e`) — preserve corrupt-scene logs
- `CONUS_HLS_drought_monitoring/watch_then_combine.sh` (commit `8ede66e`) — fix container-path redirect
- `CONUS_HLS_drought_monitoring/RUNNING_ANALYSES.md` — this file

---

## Session Summary (May 5, 2026 — callr subprocess isolation + 2025 resume)

After May 4's terra::resample SIGSEGV killed the parent R, today's work added the subprocess boundary needed to survive C-level signals. R's `tryCatch` cannot catch SIGSEGV; only an OS process boundary can.

### Diagnosis attempt
Tried to identify the corrupt scene from worker 2's queue: tracker's last successful entry was `S30_T15SYC_2025-08-15`, so the next scene would be `HLS.S30.T15SYC.2025229T163921.v2.0_NDVI.tif`. Reproduced the exact pipeline call (Albers grid → reproject to UTM → resample to 30m) on this file in a fresh R session — **no crash**. Either the segfault is state-dependent (accumulated terra C++ allocations across thousands of scenes) or my position estimate was off; can't pinpoint without instrumentation. Decided to deploy callr instead: it identifies AND survives the bad scene without needing to know which one in advance.

### Script change — `01_aggregate_to_4km_parallel.R`
1. Added `library(callr)`
2. In `process_file_chunk_disk`: each worker spawns a persistent `callr::r_session` subprocess at startup. Grid + agg function sent once via `terra::wrap()`/`unwrap()` for fast IPC thereafter.
3. Each scene's `aggregate_scene_to_4km` call replaced with `rs$run(...)` (~5-10s per call vs ~5s direct — IPC overhead is small relative to the inherent terra cost on 13M-pixel rasters)
4. On `tryCatch` error from `rs$run()`: log `<file>\t<error>` to `worker_NN_corrupt.txt`, kill the dead session, respawn, continue. Counts as a normal `n_failed`.
5. Subprocess closed at end of `process_file_chunk_disk` (clean per-round teardown via existing `plan(sequential)` recycling)

Validated end-to-end: 3 real scenes + 1 fake "corrupt" scene → 3 success, 1 failed, corrupt log created with the underlying error message. Worker continued through the failure.

### Resume launched
- 2026-05-05 07:32 MDT, command unchanged: `Rscript 01_aggregate_to_4km_parallel.R 2019 2025 --workers=8 --tiles=bulk_downloads/midwest_tiles_overlapping.txt`
- 2019-2024 auto-skipped at start; 2025 resumes with all 8 trackers preserved (4,100-4,901 scenes each) and 353 RDS batches
- Watcher (`watch_then_combine.sh`, host PID 3629505) still running; will auto-launch `01b_combine_year_files.R 2013 2025` when 2025 finishes
- Expected: ~12-15 hr wall-clock for the remaining ~50% of 2025

### Files Modified
- `CONUS_HLS_drought_monitoring/01_aggregate_to_4km_parallel.R` (commit `6432c9c`) — callr::r_session subprocess isolation around `aggregate_scene_to_4km`
- `CONUS_HLS_drought_monitoring/RUNNING_ANALYSES.md` — this file

### After 2025 lands
1. Inspect `worker_NN_corrupt.txt` files to identify the actual corrupt scene(s)
2. If found: re-download from NASA HLS S3 (tile T15SYC + nearby), re-run script 01 for 2025 only (resume logic skips already-processed scenes, retries the failed ones)
3. Watcher auto-runs `01b_combine_year_files.R` → produces `conus_4km_ndvi_timeseries.rds`
4. Continue downstream: 02 → 03 → 04 → 06 (all rewritten in Apr 28 session — see below)

---

## Session Summary (May 4, 2026 — 2025 crash diagnosis + script rewrite + resume)

Returning to a stalled aggregation: 2025 crashed on May 1 03:53 with `FutureInterruptError` (worker OOM cascade) at ~50% through, after 2013-2024 had completed cleanly. Workers died simultaneously at 4,100-4,600/9,000 scenes — classic OS OOM kill pattern, not a bad scene.

### Root cause
The MEMORY.md "stable parallel R" pattern (5 elements) was only **partially** implemented in `01_aggregate_to_4km_parallel.R`:

| # | Pattern element | Pre-rewrite state |
|---|-----------------|-------------------|
| 1 | `options(future.globals.maxSize = 2 * 1024^3)` | ❌ Never set |
| 2 | Recycle workers between iterations | ⚠️ Only between *years*, not within (workers ate ~9.5K files in one shot) |
| 3 | `tryCatch` around `future_lapply` with sequential fallback | ❌ Missing |
| 4 | `rm()` + `gc()` for terra rasters inside workers | ❌ `aggregate_scene_to_4km` left `ndvi_30m`, `grid_4km_reproj`, `grid_30m`, large vectors uncleaned |
| 5 | Chunk large jobs (~5K granules per chunk) | ❌ Whole year per worker per call |

Why 2025 specifically: files-per-worker grew year-over-year (3.7K in 2017 → 7.9K in 2024 → 9.5K in 2025, +20% over previous max). 2024 was already at the unsafe ceiling; 2025 pushed past it.

### Script rewrite — `01_aggregate_to_4km_parallel.R`
1. `options(future.globals.maxSize = 2 * 1024^3)` set globally
2. `aggregate_scene_to_4km` drops terra rasters (`ndvi_30m`, `grid_4km_reproj`, `grid_30m`) and large vectors (`pixel_ids`, `ndvi_vals`, `df`) before the dplyr aggregation
3. `flush_buffer` does `rm(batch_df) + gc(verbose=FALSE)` after each 100-scene RDS write
4. **Sub-chunked dispatch**: each year is split into rounds of `<= chunk_size` files/worker (default 2500). `plan(multisession)` → `future_lapply` → `plan(sequential) + gc()` between every round. Workers' R subprocesses are torn down and respawned fresh, releasing accumulated terra C++ allocations.
5. `tryCatch` wraps `future_lapply` with sequential `lapply` fallback if a parallel round dies
6. New `--chunk-size=N` CLI arg (default 2500); for 2025 (max 9,482 files/worker) → 4 rounds with full recycling between

### Resume launched
- Container restart 2026-05-04 07:22:41 MDT, command unchanged: `Rscript 01_aggregate_to_4km_parallel.R 2019 2025 --workers=8 --tiles=bulk_downloads/midwest_tiles_overlapping.txt`
- Per-worker `worker_NN_processed.txt` trackers preserved → workers skip ~4,100-4,600 already-processed scenes each, continue with remaining ~4,500-5,000
- 357 RDS batches in `aggregation_temp/2025/` from May 1 partial run also preserved (combine-time dedup handles overlap)
- Watcher (`watch_then_combine.sh`, host PID 3629505, running since May 1) still armed → auto-launches `01b_combine_year_files.R 2013 2025` when `ndvi_4km_2025.rds` lands

### Files Modified
- `CONUS_HLS_drought_monitoring/01_aggregate_to_4km_parallel.R` — full rewrite of memory-management pattern (see above)
- `CONUS_HLS_drought_monitoring/RUNNING_ANALYSES.md` — this file
- `CONUS_HLS_drought_monitoring/watch_then_combine.sh` — added (host watcher, written May 1, not previously committed)

### Next Steps
Same as Apr 28 plan — once 2025 finishes (~14:00-16:00 MDT today) and `01b` auto-runs, proceed: 02 → 03 → 04 → 05 → 06 → 07.

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
