# Currently Running Analyses

**Updated**: 2026-05-15 ~14:45 CDT (entire 13-year anomalies pipeline COMPLETE through 04 v4)

## No Active Background Process

Pipeline state on 2026-05-15: **02 (norms) + 03 (year predictions) + 04 (anomalies) all complete for all 13 years (2013-2025)**. Next step is script 06 (change derivatives).

## Final pipeline state — 13-year anomalies COMPLETE

- **modeled_ndvi/**: 13 × `modeled_ndvi_YYYY.rds`, ~14 GB total. 2013 = 755 MB (253 DOYs), 2014 = 1085 MB (362 DOYs), 2015 = 1.1 GB (362 DOYs after refit), 2016-2025 = 1.09 GB each (365 DOYs).
- **year_predictions_posteriors/**: 13 year-dirs of per-DOY posteriors, total 4,748 files. Min 75.2 MB, max 83.2 MB, all ≥ 50 MB threshold.
- **modeled_ndvi_anomalies/**: 13 × `anomalies_YYYY.rds`, ~15 GB total. 96.1-96.9% significant per year.
- **All 3 corrupt files refit + present**: 2015/doy_205, 2025/doy_086, 2025/doy_322.

### Cross-layer consistency

For every year, `nrow(anomalies_YYYY.rds) == nrow(modeled_ndvi_YYYY.rds) == n_doys × 129,310`. Posterior file counts match modeled_ndvi DOY counts. Pipeline is internally consistent across all 3 layers.

## Today's recovery (2026-05-14 → 2026-05-15)

The 04 v3 audit on 2026-05-14 morning surfaced 3 lzma-corrupt year posterior files:
- `2015/doy_205.rds` (76 MB, 03 v2 May 9 00:00)
- `2025/doy_086.rds` (48 MB, 03 v3 May 13 00:01)
- `2025/doy_322.rds` (4.2 MB, 03 v3 May 13 00:00)

All three written within 1 minute of midnight CDT. saveRDS itself returned success; corruption only surfaced when downstream readRDS attempted to deserialize the lzma stream days later. The //ascend.egs.anl.gov mount has a midnight backup window (or similar disruption) that silently truncates writes in flight.

### Patches landed

1. **`saveRDS_validated()` helper in `00_posterior_functions.R`** (commit `8b67463`) — two-layer defense:
   - Layer 1: write to `<file>.tmp`, validate, atomic `file.rename` (SMB2 SET_INFO is atomic). The final filename only ever contains a fully-written, validated payload.
   - Layer 2: read-back validation via `readRDS` of the `.tmp` before rename. Catches lzma corruption, truncation, etc. Caveat: may be served from page cache (cache=strict) — layer 1 carries the load there.
   - 3 retries with 5/30/90s backoff. `stopifnot` guard on `backoff_secs` length to prevent NA-poisoning Sys.sleep on misconfiguration.
2. **CRITICAL fix**: 02's `process_single_doy` had no outer `tryCatch`. A `saveRDS_validated stop()` would have killed parallel + sequential fallback + entire script. Wrapped to match script 03's pattern.
3. **Resume size guards bumped**: 02 line 379 + 03 lines 291, 476 from `> 0` to `>= 50e6` (50 MB). Catches the 4.2 MB and 48 MB legacy corrupt files automatically on resume. Verified legitimate posteriors are 75-83 MB so 50 MB is conservative (commit `9af53bf` covers the year-level scan that was missed in `8b67463`).
4. **Per-DOY worker writes** in 02 line 450 + 03 line 422 now use `saveRDS_validated`.

### r-reviewer pass

Round 1: 1 CRITICAL + 1 HIGH + 2 MEDIUM. All addressed in `8b67463`.

The HIGH (page-cache may fool readback) was structurally addressed by upgrading the helper to write-to-tmp + atomic rename (originally just validate-after-write). Even if the readback hits cache, the rename layer ensures the canonical filename never points to a partial file.

### Refit recovery

1. Deleted 3 corrupt year posteriors + 2 affected anomalies files
2. Launched **03 v4 refit** — exited immediately with "All years already processed" because the resume scan reads `fitted_doys` from `modeled_ndvi_YYYY.rds$mean[!is.na(mean)]`. The corrupt DOYs were already absent from the summary files (their workers had errored mid-write back in 03 v2/v3), so `setdiff(fitted_doys, valid_post_doys) == 0` even after the deletes. **Resume-logic gap discovered**: it can only catch DOYs that ARE in the summary but missing from posteriors; DOYs missing from BOTH are invisible.
3. Worked around by deleting `modeled_ndvi_2015.rds` + `modeled_ndvi_2025.rds` to force 03 to reprocess those years from scratch.
4. **03 v5 refit** completed in **267.4 min**: per-DOY skip identified 4 DOYs to fit in 2015 (3 insufficient-data 15/16/17 + 1 deleted 205) and 2 DOYs to fit in 2025 (86, 322). Reloaded 361 + 363 existing posteriors. Wrote new modeled_ndvi summaries. Mean R² = 0.309, RMSE = 0.151.
   - **All 3 refit posteriors landed at 77-78 MB** — back in normal range, deserialize cleanly.
   - **0 stray `.tmp` files** — saveRDS_validated happy path worked, no failed-validation cleanup needed.
   - The new write helper survived its first real run including a midnight crossing.
5. **04 v4** completed in **107.6 min** (started 11:54 CDT, finished 14:41 CDT): resume scan correctly skipped 11 complete years; processed 2015 (362 DOYs) and 2025 (365 DOYs). Mean % significant: 96.5% across all years.

### Triple-check audit of the 11 untouched years (2013, 2014, 2016-2024)

Done 2026-05-15 morning before launching 03 v5, to confirm those years didn't have other lurking corruption:
- **Layer 1 — modeled_ndvi summaries**: all present, 754-1095 MB, full DOY coverage (253/362/365×9), all 129,310 pixels, no NA holes inside fitted DOYs.
- **Layer 2 — per-DOY posteriors (4,015 files across 11 years)**: min 75.2 MB, max 83.2 MB, **0 below 50 MB**.
- **Layer 3 — anomaly outputs**: all present, 796-1150 MB, full DOY coverage matching modeled_ndvi, 96.1-96.9% significant.
- **Bonus**: 04 v2/v3 had already done the strongest possible validation by successfully `readRDS`'ing every per-DOY posterior in those 11 years to compute the anomalies — no lzma errors anywhere.

## Logs preserved

- `year_predictions_v4_resumebug.log` — the false "all complete" exit
- `year_predictions_v5_refit.log` — the actual refit (267 min)
- `anomalies_v1_falsethreshold.log` — 1 GB write-guard false-trip on year 2013
- `anomalies_v2_cifshiccup.log` — midnight CIFS hiccup wiped 281 of 365 DOYs in 2025
- `anomalies_v3.log` — refit 2015 + 2025 with readRDS_retry; surfaced the 3 lzma-corrupt files via "failed after 3 attempts"
- `anomalies_v4.log` — final clean run (107.6 min, 2 years)

## Next step

Script 06 (`06_calculate_change_derivatives.R`). Per project history (RUNNING_ANALYSES Apr 28 audit), 06 was rewritten to read year + baseline posteriors directly via `load_posteriors()` (which validates the `list(pixel_id, sims)` format). With the saveRDS_validated patch now in place upstream, 06 has the full benefit of validated writes.

## Script 04 v2 — CIFS hiccup at midnight (2026-05-13 23:50 → 2026-05-14 00:01)

- **Wall-clock**: 10.0 hr (started 13:29 CDT 2026-05-13, halted 00:01 CDT 2026-05-14)
- **Outcome**: 11 of 13 years saved cleanly. Year 2015 has 1 DOY hole (DOY 205); year 2025 lost 281 of 365 DOYs.
- **Symptom**: "cannot open the connection" / "error reading from connection" on readRDS, exact pattern that MEMORY.md flags for the //ascend.egs.anl.gov mount.
- **Diagnosis pattern (smoking gun)**:
  ```
  Worker 1 (DOYs 1-122):   succeeded 1-28,    failed 29-122
  Worker 2 (DOYs 123-244): succeeded 123-149, failed 150-243
  Worker 3 (DOYs 245-365): succeeded 244-272, failed 273-365
  ```
  All three workers succeeded for the first ~28 DOYs of 2025, then failed simultaneously in mid-chunk. Single wall-clock event, almost certainly a midnight CIFS backup window or transient mount drop.
- **Why r-reviewer's HIGH 2 (structured error sentinel) earned its keep**: without it, the worker `cat()` calls would have been silently dropped by future.apply; we'd have seen "84 of 365 succeeded" with NO indication of which DOYs failed or what the error was. With the sentinel, the diagnosis was 30 seconds of grep.
- **Per-year results from v2 (preserved on disk)**:

| Year | Status (after v2) | Size | Time |
|------|--------------|------|------|
| 2013 | ✅ from v1 | 797 MB | 100 min |
| 2014 | ✅ | 1.2 GB | 52 min |
| 2015 | 🗑 deleted (1 DOY hole) | — | — |
| 2016 | ✅ | 1.2 GB | 50 min |
| 2017 | ✅ | 1.2 GB | 49 min |
| 2018 | ✅ | 1.2 GB | 49 min |
| 2019 | ✅ | 1.2 GB | 49 min |
| 2020 | ✅ | 1.2 GB | 49 min |
| 2021 | ✅ | 1.2 GB | 50 min |
| 2022 | ✅ | 1.2 GB | 49 min |
| 2023 | ✅ | 1.2 GB | 49 min |
| 2024 | ✅ | 1.2 GB | 49 min |
| 2025 | 🗑 deleted (264 MB partial) | — | — |

- **Patch (commit `e54eaa2`)**: `readRDS_retry()` helper at script scope wraps both `readRDS` calls in `process_doy`. 3 attempts, 5s/15s/30s backoff, catches all readRDS errors. Survives a typical CIFS hiccup (10-60s) without slowing down the happy path. Worst-case extra wait per failed DOY: 50s. Defined at script scope so future.apply ships it as a global to workers.
- **v2 log preserved**: `/mnt/malexander/datasets/ndvi_monitor/gam_models/anomalies_v2_cifshiccup.log` — full forensic record incl. all 281 failed DOYs.

## Script 04 v1 — false-tripped write guard on year 2013 (2026-05-13 morning)

- **Outcome**: completed year 2013 cleanly (32.7M rows = 253 DOYs × 129,310 pixels, 0 NAs) but the new post-write integrity guard tripped because the file was 796 MB vs the 1 GB threshold I'd set during pre-launch audit. Misdiagnosed expected size as 2-3 GB; reality is 0.8-1.2 GB depending on DOY count.
- **Fix (commit `f68dbc9`)**: lowered `RESUME_MIN_BYTES` from 1 GB → 500 MB. Catches the known 03 v2 truncation pattern (300 MB) while allowing 2013's legitimate ~800 MB and full years' ~1.0-1.2 GB. Cross-checked against `modeled_ndvi/modeled_ndvi_YYYY.rds` sizes from 03.
- **No data loss**: 2013 file was complete and correct; just the guard threshold was too strict. v2 resume scan correctly skipped 2013 and picked up from 2014.
- **v1 log preserved**: `/mnt/malexander/datasets/ndvi_monitor/gam_models/anomalies_v1_falsethreshold.log`

## Script 03 v3 — COMPLETE

- **Wall-clock**: 2568.8 min (~42.8 hr; started 2026-05-11 07:55 CDT, exited 2026-05-13 ~02:50 CDT)
- **Outputs**: 13 × `modeled_ndvi/modeled_ndvi_YYYY.rds` (~1.09 GB each, 14 GB total) + 13 year-dirs of per-DOY posteriors + `modeled_ndvi_stats.rds`
- **DOY counts** (from per-year posterior dir): 2013 = 253 (Landsat 8 launched 2013-04-11; pre-DOY-113 has no data, expected), 2014/2015 = 362 (3 DOYs missing per year — insufficient data, per-DOY skip patch held), 2016-2025 = 365 ✓
- **Per-year timings**: 2019 = 111.2 min (reload-from-posteriors, no fitting), 2020-2024 = 376-415 min, 2025 = 439.6 min
- **Run-level stats**: Mean R² = 0.302, Mean NormCoef = 0.985, Mean RMSE = 0.1715
- **Patches that held**: 128 GiB cap not breached, per-DOY skip pre-scan worked, parent-side `rm()` + `gc()` between years kept memory flat (~55-81 GiB across 7 years, no climb to OOM)
- **Reload-DOYs limitation**: 2019's per-DOY model stats are NA in `modeled_ndvi_stats.rds` (reload-from-posteriors path can't reconstruct R²/NormCoef/SplineP/RMSE from the saved sims matrix). Affects diagnostics only, not downstream analysis.
- **Log**: `/mnt/malexander/datasets/ndvi_monitor/gam_models/year_predictions_v3.log` (preserved)

## 03 v2 → v3 (the May 9-10 OOM at midnight + per-DOY skip patch, 2026-05-11 AM)

**v2 outcome**: ran 2026-05-08 11:46 → 2026-05-10 00:00 (~60 hr). Years 2013-2018 saved cleanly. Year 2019 wrote all 365 posterior files but the parent OOM-killed mid-`saveRDS(year_grid, "modeled_ndvi_2019.rds")` at 00:00:00.612 — the summary file is 300 MB (vs ~1.1 GB expected) and `readRDS` errors on it. Years 2020-2025 not started.

**Diagnosis**: `cat /sys/fs/cgroup/memory.events` confirmed `oom_kill 2` and `memory.peak = 96 GiB` (the docker-compose cap). Container itself stayed up because R was a child of the long-running `tail -f` PID 1; only the R subtree died. Host had no reboot, no swap exhaustion. Cause: parent's working set (timeseries_with_norms ~10 GB + norms_df ~2.3 GB + year_data ~700 MB + accumulating year_results_list across 6 prior years + saveRDS gzip buffer) crossed the 96 GiB cap during 2019's saveRDS. 2018 didn't OOM because year_data is smaller for early years; 2019 was the first year with 13.7M-row year_data slice plus 6 years of accumulated leakage.

**Three patches applied 2026-05-11**:

1. **`docker-compose.yml` 96 GiB → 128 GiB** — host has 251 GiB; bumped cap with ~120 GiB headroom for system + other users. Verified via `cat /sys/fs/cgroup/memory.max` = exactly 128 GiB after `docker compose up -d`. Modern Docker compose v2 honors `deploy.resources.limits` in non-swarm mode (not always true historically — check before assuming).

2. **Per-DOY skip in `03_doy_looped_year_predictions.R`** — pre-scan posterior dir; classify DOYs as `to_fit` vs `to_reload`. Run workers only on `to_fit`. Reload `to_reload` in a separate parallel block: `apply(sims, 1, mean | quantile, na.rm=TRUE)` to reconstruct (mean, lwr, upr) — bit-equivalent to `post.distns()` lines 95-97. Trade-off: per-DOY model stats (R2, NormCoef, SplineP, RMSE) not reconstructable from posteriors → reloaded DOYs get NA stats in `modeled_ndvi_stats.rds` (only affects diagnostics, not downstream analysis). For 2019 specifically, all 365 stats will be NA — acceptable given 6-hour speedup. Combine loop changed from `for (i in seq_along(results_list))` (positional, 1:365) to `for (res in results_list)` (DOY-keyed via `res$yday`) since results_list is now `c(processed, reloaded)` in arbitrary order. Added `stopifnot(d ∈ 1:365)` guard.

3. **`rm()` + `gc(verbose=FALSE)` hygiene** — drop `results_list` before `bind_rows`, drop `year_results_list` after, drop `year_data + year_grid + year_stats` at end of each year iteration. Goal: keep parent footprint flat across 7 years instead of accumulating to OOM. Memory has indeed stayed at ~55 GiB through the 2019 reload phase — no climb.

**r-reviewer caught one real bug** during the patch review: my first reload draft used `rowMeans(sims)` (defaults `na.rm=FALSE`) instead of `apply(sims, 1, mean, na.rm=TRUE)`. Would have produced `NA` for any pixel with degenerate sims, diverging from the original ci values. Fixed before launch.

**Restart sequence (2026-05-11)**:
1. Diagnosed OOM via cgroup memory.events
2. Edited docker-compose.yml + 03 script (215 lines added/changed)
3. r-reviewer reviewed patches; fixed na.rm bug + added DOY-range guard
4. Parse-checked clean
5. `docker compose down && docker compose up -d` — verified 128 GiB cap live
6. Deleted corrupt `modeled_ndvi_2019.rds` (would crash resume scan at `readRDS`)
7. Launched v3 at 07:55 CDT
8. Verified resume scan correctly identified 2013-2018 as complete and 2019 as needing 365 reloads
9. Confirmed workers spawned for parallel reload (PIDs 213-215, ~315% combined CPU)

**Lesson worth keeping**: The OOM was preventable if we'd had per-year `gc()` and explicit `rm()` from the start. r-reviewer's earlier 03/04/06 audit (May 8) caught flush.console + future.seed + pixel-count invariant, but did not flag the absence of intermediate-object cleanup — worth adding to the "before-launch checklist for long parallel R jobs" alongside the future.globals.maxSize check.

## Script 02 v2 Backfill — COMPLETE

- **Wall-clock**: 1142.6 min (19.04 hr; started 2026-05-07 14:57 CDT, exited 2026-05-08 10:12:48 CDT)
- **Fitted**: 365/365 DOYs, 0 failed, 100% pixel-DOY coverage
- **Outputs**:
  - `gam_models/doy_looped_norms.rds` — 1.1 GB gzipped, 47,198,150 rows × 7 cols (pixel_id, yday, x, y, mean, lwr, upr); 0 NAs in mean/lwr/upr; mean range -0.026 to 0.810; CI width median 0.0015
  - `gam_models/baseline_posteriors/doy_NNN.rds` × 365 — 27.6 GB total, contiguous DOY 001-365
  - `gam_models/valid_pixels_landcover_filtered.rds` — 129,310 pixels (NLCD codes 2-9, water excluded)
- **Per-chunk timings** (4 workers × 30 DOYs/chunk):
  - Chunks 1-7: 54-80 min each (normal parallel)
  - **Chunk 8: 334 min ⚠️** — silent serial fallback (forensics below)
  - Chunks 9-13: 13-75 min each (returned to normal parallel)

### Chunk-8 forensics + the cross-pipeline buffering bug

Chunk 8 (DOYs 211-240) ran 334 min vs ~75 min/parallel-chunk because it silently fell back to sequential `lapply` inside the `tryCatch` error handler. File mtimes prove it: chunk 8's 30 DOYs landed in strict numerical order ~9.5 min apart (single-process pattern), while chunks 7, 9, 10 show 4-worker scrambled bursts. The `cat("WARNING: future_lapply failed...")` line never appeared in `baseline_norms_v2.log` because **R block-buffers stdout when redirected to a file** and the parent process was still alive. The serial fallback used identical `process_single_doy()` with deterministic per-DOY seed (`1034L + day`), so chunk 8's outputs are bit-equivalent to what 4 workers would have produced — no rerun needed. Same pattern was visible at end-of-run: the post-chunk-13 `cat("Processing complete!")`, `Saving final output...`, and the multi-minute `saveRDS(... compress="gzip")` all sat in the buffer until script exit (final flush dumped ~30 lines at once at 10:12:48).

### Downstream pipeline pre-patch (committed 30ed58e, 2026-05-08)

r-reviewer audit of 03, 04, 06 found the same `flush.console()` blind spot in all three. Fixed pre-emptively while 02 was still running (safe — none were in flight):
- `flush.console()` added in every `tryCatch` error handler before the long fallback, and after every `plan(sequential)`/major progress print
- `future.seed = TRUE` → `future.seed = NULL` (03's workers seed deterministically inside `post.distns()`; 04/06 workers do pure arithmetic with no RNG calls)
- Pixel-count invariant promoted from `cat("WARNING")` to `stop()` in 04/06; kept as soft-warn in 03 per existing design comment

### Script 02 patch + EXPECTED_VALID_PIXELS update (this commit)

After 02 exited cleanly, applied matching patches:
- **02 flush.console() patch**: 4 calls added — after each chunk-start print, in the tryCatch fallback before `lapply`, after each chunk-done print, after the post-loop summary print, and after the "Saving summary statistics..." print just before the multi-minute `saveRDS` gzip step
- **EXPECTED_VALID_PIXELS = 125798L → 129310L** in scripts 03/04/06: the stale 125,798 constant predated the current NLCD filter; 129,310 is what 02 actually wrote in the v2 backfill (verified via `nrow(valid_pixels_landcover_filtered.rds)` and `nrow(doy_looped_norms.rds) / 365`). Without this update, the just-hardened `stop()` checks in 04 and 06 would have blocked the entire 03→04→06 chain.

## 03 v1 → v2 (the future.globals.maxSize incident, 2026-05-08 PM)

After 02 finished at 10:12 CDT and the matching flush.console + EXPECTED_VALID_PIXELS patches landed (commit `c960a63`), launched `03_doy_looped_year_predictions.R` against the new norms at 10:27 CDT (`year_predictions_v1.log`).

**Within 25 minutes** the per-year watcher fired its first event:
```
WARNING: future_lapply failed for year 2013: The total size of the 11 globals
  exported for future expression is 2.42 GiB. This exceeds the maximum allowed
  size 2.00 GiB ... The three largest globals are 'norms_df' (2.29 GiB ...),
  'year_data' (134.27 MiB ...) and 'pixel_coords' (2.96 MiB ...)
Falling back to sequential lapply for this year (slower but safer)...
```

The script's tryCatch handler caught the failure cleanly and dropped to sequential `lapply` — but **without today's flush.console patch this would have been silent for hours, then days**. As it was, the WARNING surfaced in the log within seconds of the parent print, and we caught it before significant compute was wasted (5 hr/year sequential × 13 years ≈ 30+ days vs ~3-4 days parallel).

**Diagnosis**: the 2 GB cap dated from when norms_df was a different shape. The v2 backfill made norms_df ~2.3 GB on its own (47.2M pixel-DOY rows × 7 cols), already over the cap before any other globals were added.

**Fix** (commit `9021c3a`): bumped to `4 * 1024^3` with documenting comment block. Memory math at 4 GB: 3 workers × 2.42 GB shipped globals = ~7.3 GB worker overhead + 3 × ~3 GB base R + ~25 GB parent ≈ 42 GB total, well under 96 GB cap.

**Restart sequence**:
1. Killed v1 (parent + 3 idle workers via `pkill -f`)
2. Renamed v1 log → `year_predictions_v1_failed_globalsoom.log` (preserves the warning text as historical record)
3. Applied maxSize fix + parse-checked
4. Launched v2 at 11:46 CDT (clean restart; 21 partial-2013 DOY files left as-is — deterministic seed = bit-equivalent overwrite on re-run, no data integrity concern)
5. v2 verified parallel: 3 workers spawned at 12:12 CDT, ~174 DOYs of 2013 written by session-end
6. Re-armed the per-year watcher on `year_predictions_v2.log`

**Lesson worth keeping**: r-reviewer's earlier 04/06 review correctly assessed *worker active memory* (matrices loaded inside the worker function) but missed *globals serialization size* (data shipped TO the worker by future.apply). These are separate bottlenecks. Worth checking both before launching long parallel jobs against newly-resized data.

## Today's Session (2026-05-08): chunk-8 forensics + full pipeline patch + 02 completion + 03 launch

1. **Diagnosed chunk-8 hiccup** as a silent sequential fallback (see post-completion TODOs above). Mtimes are conclusive; root cause is missing `flush.console()` in the tryCatch error handler combined with R's default stdout block-buffering when redirected to a file.
2. **r-reviewer audited 03, 04, 06** and found the same `flush.console()` bug in *all three* downstream scripts (would have produced the same multi-hour silent fallback during the 02→03→04→06 chain).
3. **Patched 03, 04, 06 pre-emptively** — safe because none are running. Three changes per script:
   - `flush.console()` added in every `tryCatch` error handler and after each `plan(sequential)`/major progress print
   - `future.seed = TRUE` → `future.seed = NULL` (03's workers seed deterministically inside `post.distns()`; 04 and 06 workers do pure arithmetic with no RNG calls — `TRUE` was gratuitous CMRG-seed shipping)
   - Pixel-count invariant (125,798) promoted from `cat("WARNING")` to `stop()` in 04 and 06 (silent mismatch would misalign matrix rows downstream)
4. **Files changed**: `03_doy_looped_year_predictions.R`, `04_calculate_anomalies.R`, `06_calculate_change_derivatives.R`. Parse-checked clean. Diffs are net +52 / -14 lines, mostly comments explaining the rationale.
5. **Script 02 fix applied** at 10:13 CDT immediately after PID 1311950 exited cleanly (see `02 v2 Backfill — COMPLETE` section above for the four flush.console() insertion sites).
6. **Pixel-count constants updated** 125798L → 129310L across 03/04/06 to match the current NLCD filter (deferred-discovery: my hardening to `stop()` would have blocked 04/06 because the constants were stale from a previous filter version).
7. **Pixel-count invariant documented** in WORKFLOW.md (commit `22eb494`): new "Land Cover Filtering > Maintenance" subsection with 4-trigger checklist + R one-liner for re-checking; in-script comment pointers from 03/04/06; matching `feedback_pixel_count_invariant.md` saved to project memory.
8. **Script 03 v1 launched and silent-failed** with future.globals.maxSize=2GB (norms_df is 2.3 GB on its own; same root cause class as the chunk-8 incident, caught by the patches landed earlier today). Killed v1, bumped maxSize to 4 GB (commit `9021c3a`), relaunched as v2. v2 verified parallel: 3 workers running.
9. **All four scripts patched + 02 backfill + 03 launch** committed in 4 commits today: `30ed58e` (03/04/06 pre-patch), `c960a63` (02 patch + EXPECTED_VALID_PIXELS), `22eb494` (WORKFLOW.md docs), `9021c3a` (03 maxSize bump). All pushed to `origin/main`.

## Today's Session (2026-05-07): 02 parallelization + OOM fix

1. **DOY 180 smoke test (yesterday)**: completed cleanly in 9.8 min (single-core). Validated the Apr 28 rewrite works on the 148M-row filtered timeseries.
2. **02 parallelized** with 4-worker `future_lapply` over 30-DOY chunks. Mirrors script 03's pattern; per-chunk pre-filter ships ~250-340 MB chunk_data instead of broadcasting the full 8.7 GB timeseries. `--doy=N` flag extended to `--doys=A,B,C` for parallel smoke testing.
3. **Smoke tests** (DOYs 178/180/182): 10.0-10.9 min wall-clock; per-pixel posterior mean correlates at 0.9999997 with serial. Sim-level drift ~0.5% from BLAS thread scheduling — accepted (same as script 03).
4. **8-worker OOM** at 14:11 CDT: container hit exactly 96 GB; cgroup `memory.events: oom_kill 2`. Empirical per-worker peak (~11 GB) made 8 workers exceed budget. Reduced to 4 workers with 22 GB headroom.
5. **v2 backfill** launched 14:57 CDT, currently running (chunk 1 in flight at session end).
6. **Files preserved**: `gam_models/baseline_posteriors/doy_180.rds.serial_backup` (76 MB) — the original serial DOY 180 output, kept as historical comparison point.

## Pipeline Status: 4km AGGREGATION + COMBINE COMPLETE; 02 PARALLEL BACKFILL IN FLIGHT

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
