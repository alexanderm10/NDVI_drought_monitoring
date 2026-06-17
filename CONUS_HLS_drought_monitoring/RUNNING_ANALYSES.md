# Currently Running Analyses

**Updated**: 2026-06-17 EOD — **Two new figures built today**: (1) **Fig 9 (flash drought scatter)** — 3 color-encoding variants (LC / eco / dual), per-pixel IQR cross-bars with collapsed-IQR overlay (cross-in-circle), gate-consistent baseline for the 9.4 grass highlight, per-subset PIXEL_N_MIN gate (5 for All+D1, 3 for D2 strict), and figure-reviewer pass with all must-fixes applied. (2) **Fig 10 a/b/c (firing climatology)** — weekly stacked-fraction bars of NDVI/SPEI firing categories (both/NDVI only/SPEI only/neither) across the year. Three companion figures: domain-wide with sparkline volume context (10a), per-LC facet_grid (10b), per-eco facet_grid with month labels under every panel (10c). Palette synced to Fig 1/1b complementarity convention (NDVI=blue, SPEI=orange, both=green, neither=grey).

**New finding from Fig 10**: Seasonally asymmetric complementarity — **SPEI leads onset year-round; NDVI leads recovery in growing season** (esp. natural LCs). "Both" firings are rare (~5-8%) across the year. "Neither" is the modal category in every week (real coverage gap). User observation: NDVI's unique operational value lands particularly on **early-growing-season recovery transitions (MAR-JUN green-up)** — this sharpens the operational claim into "NDVI is a slow/recovery monitor with peak value on early-growing-season vegetation rebound."

Fig 9 + Fig 10 findings written to memory ([[firing-climatology-findings]] joins [[flash-drought-findings]]).

## Active run

(none)

## Toward methods/results memo (1-2 more sessions)

The user wants to write a brief methods/results memo for colleagues after ~1-2 more sessions. The substantive findings now in hand:

1. **Section A** (`continuous_spei_nlcd`) — four-mechanism eco × LC story (WORKS / SILENT / REVERSES-crop / REVERSES-grass + 9.3 grass-only WORKS)
2. **Section A++** (`categorical_usdm_nlcd`) — USDM ρ shows different pattern than SPEI β (8.4 Ozark USDM-WORKS-but-SPEI-SILENT; 9.2 urban density split absent on USDM side)
3. **Section B** (`event_detection_nlcd`) — spei_4w dominates onset; NDVI⊥SPEI complementarity ~19% NDVI-only across both directions; 8.3 Southeastern USA Plains is the operational dark horse for onset detection
4. **Section B+flash subset** (this session) — NDVI is a slow-drought monitor not flash; 9.4 grass exception on flash recovery
5. **Headline figures**: Fig 0 (domain), Fig 1+1b (complementarity), Fig 2 (8.3 deep-dive), Fig 3 (A vs B scatter), Fig 4 (complementarity atlas), Fig 5 (op-point heatmap), Fig 6/7/8 (case-year time series)

**What still needs to land before the memo writeup:**

### A. High-priority for memo (do next session)
- ✅ **Fig 9 — flash drought comparison figure** (DONE 2026-06-17). 3 color variants shipped (lc/eco/dual). Per-pixel IQR cross-bars + collapsed-IQR cross-in-circle markers + gate-consistent baselines + figure-reviewer pass.
- ✅ **Fig 10 a/b/c — firing climatology** (DONE 2026-06-17). Weekly composition by direction × {domain, LC, eco}. Surfaces seasonally asymmetric complementarity directly.
- ✅ **Productionize `section_flash_drought` in script 09** (DONE 2026-06-17). Wraps the trajectory + tagging + skill logic cleanly. Includes both per-event hit rate (POD-equivalent) AND temporal-block HSS (POD/FAR/HSS/ETS) per (eco × LC × subset × signal × direction). Output `flash_drought_10y.rds` (164 MB, 11.8 min runtime). Domain-wide hit rates reproduce exploration script exactly. `tmp_flash_drought_exploration.R` removed.
- **Verify canonical L2_name in Fig 3, Fig 4 captions/legends** per `feedback_verify_epa_l2_names.md`. Sample check.

### B. Strengthen the story (do next session if time)
- **8.4 Ozark "USDM-WORKS-but-SPEI-SILENT" deep dive** — reconcile categorical_usdm vs continuous_spei discrepancy. What signal are USDM analysts using in 8.4 that the meteorological SPEI series doesn't carry?
- **NDVI + SPEI ensemble signal test** — logical-OR at headline op vs each alone. Given the 19% complementarity rate, OR ensemble should beat either by ~5-10 percentage points on hit rate. Cheap reuse of pixel_event_map.

### C. Cleanup before memo finalization
- **8.1 + 5.2 grass-worst DJF-excluded diagnostic** (snow-contamination hypothesis) — only worth doing if the memo needs to address why the REVERSES-grass mechanism exists. Could defer.
- **Empirical growing-season redux** (00c) — only matters if Fig 6/7/8 go in the memo and we want stratum-appropriate growing-season bands rather than the Mar 1–Sep 30 calendar default. Can defer.
- **05_*.R refactor decision** — orthogonal to memo. Can defer.

### D. Suggested first-session-focus when resuming
**Build Fig 9** (the flash comparison) + **write the flash subset section of the memo proper** (clean writeup, less notebook-style than the PHASE6_VALIDATION_MEMO entry). Then **productionize section_flash_drought** so the analysis is reproducible. That should be ~one focused session and lands the headline analytical result of the memo.

**Second session-focus**: 8.4 Ozark deep-dive + ensemble test + L2_name verify pass + assemble memo outline.

## Recent session summaries (full detail below)
- 2026-06-17 (this session): Fig 9 + Fig 10 a/b/c built (above); `section_flash_drought` productionized in script 09 (`flash_drought_10y.rds` 164 MB / 11.8 min; both per-event hit rate AND temporal-block HSS; tmp exploration script retired).
- 2026-06-16: Fig 3+4+5 built; Fig 4 pivoted to complementarity atlas; flash drought exploration.
- 2026-06-15: Section B `event_detection_nlcd` built + run (180 MB output, 4 hr 19 min wall).
- 2026-06-12: USDM 5-LC + SPEI 5-LC rerun; 8.4 USDM-WORKS-but-SPEI-SILENT discrepancy surfaced.
- 2026-06-11: Phase 6 reframe; Section A `continuous_spei` complete; Section C `within_week_diagnostic` complete.
- 2026-06-10: `categorical_usdm` v3 built; Phase 6 reframe.
- (earlier): align_weekly cache + derivatives rebuild + weekly SPI/SPEI.

## Session Summary (2026-06-17) — Fig 9, Fig 10 a/b/c, productionize section_flash_drought

### Productionize `section_flash_drought` (afternoon, ~30 min code + 12 min full run)
- Wraps `tmp_flash_drought_exploration.R` (2026-06-16) into a proper section in `09_validate_drought_signal.R` (~310 lines added). CLI: `--section=flash_drought --scope=10y [--smoke]`.
- **Inputs**: `event_detection_nlcd_10y.rds` (events + pixel_event_map) + `align_weekly` cache (for fire re-detection) + USDM weekly + NLCD lookup.
- **Pipeline** (8 steps):
  1. Load Section B output (events_pixel + pixel_event_map)
  2. Load USDM, compute per-pixel rolling-max trajectory (`frollmax`, n=5, align=left/right)
  3. Tag events with `is_flash_d1` (max USDM ≥ D1 in ±4wk) and `is_flash_d2` (≥ D2)
  4. Join NLCD juliana (with urban 2-tier collapse) + ecoregion
  5. Per-event hit rates from pixel_event_map at headline op (matches exploration)
  6. Re-detect fires from align cache (`detect_fires_global` for ndvi_z + spei_13w @ z=1.5 K=2)
  7. Temporal-block contingency per (stratum × subset × signal × direction) via `compute_temporal_block_contingency` (block_weeks=4); skill via `compute_skill_metrics`
  8. Save `flash_drought_10y.rds` (164 MB xz)
- **Output structure**: `events_pixel_flash`, `hit_rate_flash_lc` (per-event metrics), `skill_flash_lc` (POD/FAR/HSS/ETS), `domain_summary`, `meta`. Output integrity verified with `xz -t`.
- **Verification**: domain-wide hit rates from full run match exploration exactly — `[all] onset NDVI=24.6% SPEI=27.0%`, `[flash_d2] onset NDVI=17.1% SPEI=60.8%`. HSS values populated and sensible (low POD, high FAR per the complementarity-dominates finding from Fig 10).
- **Headline HSS findings (new from proper contingency)**:
  - Best onset HSS in flash-D2 (n=65K events): **5.2 grass spei_13w HSS=+0.115** (Mixed Wood Shield grass — high signal-to-noise on rare severe events in this ecoregion).
  - Best recovery HSS in flash-D1 (n=374K events): **9.4 urban_dense ndvi_z HSS=+0.143** (small-N but defensible POD 0.282/FAR 0.882).
  - 9.4 grass + 9.4 crop recovery HSS ~0.08-0.09 on flash-D1 (SPEI side dominates the volume — consistent with Fig 10 recovery panel showing 9.4 grass blue dominance).
- **Retired**: `tmp_flash_drought_exploration.R` deleted (productionized; git history preserves).
- **WORKFLOW.md** updated with `flash_drought` section entry.

### Fig 9 — Flash drought scatter (3 variants, all polished)

### Fig 9 — Flash drought scatter (3 variants, all polished)
- 2×3 grid (rows = onset/recovery, cols = all / flash-D1 / flash-D2 strict) of (SPEI hit, NDVI hit) scatter per (eco × LC) stratum.
- **3 color-encoding variants** rendered side-by-side for comparison: `_color_lc` (NLCD fill — cleanest), `_color_eco` (ecoregion fill — categorical ECO_PAL after reviewer feedback), `_color_dual` (LC fill + eco border ring). User declined to pick a single winner ("still exploring"); all three kept.
- **Per-pixel IQR cross-bars** (Option A in design discussion) — point sits at the mean of per-pixel hit rates, cross-bars span 25th-75th percentile. Required two semantic fixes:
  - Initial cross-bars used per-event mean (point) and per-pixel IQR (bars) — point sat OUTSIDE the IQR for strata with heterogeneous event counts. Switched both to per-pixel statistics for internal consistency.
  - PIXEL_N_MIN gate tuned per-subset (5 for All+D1 plentiful, 3 for D2-strict sparse — preserves the 9.4 grass + crop recovery cells that would otherwise drop).
- **Collapsed-IQR overlay** (Option C) — cross-in-circle (shape 13) marker on points where per-pixel rates concentrate in a single quantization bin (no meaningful IQR to show). Universally applied (not just dual variant) for visual consistency.
- **Gate-consistent highlight baseline** — 9.4 grass recovery "NDVI lift over all-recovery" computed using the same per-pixel gate as the comparison cell, so D1 highlight (+24 pt) and D2 highlight (+8 pt) are apples-to-apples within their regime.
- **Figure-reviewer pass** (3 agents in parallel) caught: caption truncation/density, highlight arrow disconnection, Unicode rendering risk, dual-variant ring-on-ring conflict, ECO bivariate palette muddling. All must-fixes applied: ASCII-ified subtitle/caption, tightened nudge, bumped label sizes to project's 2.8 minimum, switched overlay to shape 13 universally, swapped ECO_PAL_BIVAR → ECO_PAL.
- Files: `10_phase6_figures.R::make_fig9_flash_drought()` (~250 lines), outputs `phase6_fig9_flash_drought_color_{lc,eco,dual}.png`.

### Fig 10 a/b/c — Firing climatology
- **User-proposed design** (chat-driven): X = ISO week of year (1-52), Y = stacked-fraction bars of firing categories at headline op (both / NDVI only / SPEI only / neither). Direct view of when each signal fires across the year.
- **Compromise presentation**: stacked fractions in main panel + sparkline of total event count per week (volume context). User: "we'll see more NDVI fires in growing season — is that picked up?" Yes, sparkline shows when events cluster (peak ~60K/week in JJA) so reader can decompose "rate" from "volume."
- **Three companion figures**:
  - **10a domain-wide** — patchwork stack of main + sparkline per direction; legend collected at bottom of combined figure.
  - **10b per-LC** — `facet_grid(direction ~ LC)`, 2×5 panels, month labels under each row via `axes = "all_x"`.
  - **10c per-eco** — `facet_grid(direction ~ eco)`, 2×9 panels, full EPA L2 names along top, month labels under every panel per user request.
- **Palette synced** to Fig 1 / Fig 1b convention after user flagged inconsistency: NDVI = blue (#1565C0), SPEI = orange (#EF6C00), both = green (#2E7D32), neither = grey (#E0E0E0).
- **Polish pass**: collected guides (10a), facet_grid layouts (10b/c), repeated x-axis labels per facet (10b/c), in-panel italic n_events label per cell.

### Substantive findings from Fig 10
- **Onset is SPEI-led year-round** — orange dominates in every (eco × LC) cell, intensifying in growing season.
- **Recovery is NDVI-led in growing season** — blue dominates for natural LCs (grass, forest), most strikingly in MAM-JJA-SON.
- **Concurrent ("both") firings are rare** (~5-8%) — complementarity is the dominant mode, not redundancy.
- **"Neither" is the modal category in every week** — real coverage gap; ~50-70% of events have no signal fire.
- **9.2 Corn Belt onset**: SPEI dominant, NDVI conspicuously LOW — REVERSES-crop mechanism from [[continuous-spei-nlcd-findings]] visible in temporal-climatology form.
- **9.4 South Central Semiarid Prairies recovery**: NDVI MASSIVE (50-60% blue in MAM-SON) — the WORKS-on-recovery exception from [[flash-drought-findings]] dominates the all-events recovery climatology too.
- **NEW user observation**: NDVI picks up early-growing-season recoveries (MAR-JUN) particularly well. Combined with the flash finding, the operational claim sharpens: **NDVI is a slow/recovery monitor whose unique value is on early-growing-season vegetation rebound.**

### Files modified
- `10_phase6_figures.R`: +250 lines `make_fig9_flash_drought` + ~220 lines `make_fig10*` helpers/functions, FIRE_PAL constant, WEEK_BREAKS/LABELS, lubridate import, dispatch entries for fig=9, 10a, 10b, 10c.
- `RUNNING_ANALYSES.md`: this section.
- New memory: `project_firing_climatology_findings.md`; updated `MEMORY.md` index.
- Outputs: `phase6_fig9_flash_drought_color_{lc,eco,dual}.png` (~0.85 MB each), `phase6_fig10{a,b,c}_firing_climatology_{domain,lc,eco}.png` (0.30–0.46 MB each).

### Next session candidates
- **Polish/DRY**: lift FIRE_PAL to module-level (Fig 1, 1b, and 10 now have local copies of the same palette).
- **Productionize `section_flash_drought` in script 09** — wrap the exploratory pipeline with proper HSS computation, save `flash_drought_10y.rds`.
- **8.4 Ozark USDM-WORKS-but-SPEI-SILENT deep dive** — reconcile categorical_usdm vs continuous_spei.
- **NDVI + SPEI ensemble OR test** — 4-5% concurrent firing suggests OR ensemble lifts hit rate by ~10-15 pts.
- **Memo outline + draft** — substantive findings are all in hand; figures cover the story.

## Session Summary (2026-06-15) — Section B event_detection_nlcd built + run

### Implementation (morning, ~3 hr)
- New section `section_event_detection_nlcd` in `09_validate_drought_signal.R` (~830 lines added). Mirrors NLCD pattern from `section_continuous_spei_nlcd`/`section_categorical_usdm_nlcd`: 5 LC classes (collapse_urban_to_2tier) × 11 ecoregions × 2 dom tracks ≈ 100 stratum groups.
- 5 new helpers: `extract_spei_trajectory_per_event` (chunked non-equi join, bounded memory), `compute_temporal_block_contingency` (proper 2×2 via 4-week blocks → correct_negatives countable for HSS), `compute_skill_metrics` (POD/FAR/HSS/ETS/Bias), `match_fires_to_events_vec` + `count_false_alarms_vec` (~5-10× faster than scalar predecessors).
- **Caught a latent bug in legacy scalar matchers** (`match_fires_to_events`, `count_false_alarms`): `by = pixel_id` reduction + positional assignment back into events_out scrambled within-pixel row alignment. Hand-verified on synthetic pixel-1 case: scalar said 1 hit / 4 events, vec said 3 hits / 4 events; vec exactly matched manual computation. Added docstring warnings flagging the legacy functions as not-trusted. Original `section_event_detection` (paused 2026-06-11) used the buggy scalar — so its per-event lead/lag numbers in `PHASE6_VALIDATION_MEMO.md` line 412 are quantitatively unreliable.
- Bug fix: `EVENT_HEADLINE` → `EVENT_HEADLINES` typo in legacy section meta-list (would have errored on completion).
- CLI: `--section=event_detection_nlcd` + `--smoke` flag (2 ecos × 2 signals × 1 op for fast validation).

### Smoke test (~18 min wall, 2026-06-15 ~09:00 CDT)
- 39 MB output. SPEI sanity passed (onset mean spei13_post = −0.56, recovery = +0.32 — direction correct).
- Per-event hit_rate at headline op matches the 2026-06-11 predecessor smoke closely (8.4 grass onset 37.9% vs old 33.4%; 9.4 grass 22.4% vs old 23.1%) — within expected variance.
- Vec matcher hand-verified bit-correct.
- Smoke schema bug caught: `pixel_event_map` was missing `week_start`/`iso_year`/`iso_week` keys, so dcast collided on (pixel × type × signal). Fixed before full launch.

### Full run (4 hr 19 min wall, 2026-06-15 ~13:23 CDT completion)
- Cache load + NLCD + z-stand + strata: ~10 min
- SPEI trajectory extraction (1.5M onset + 1.5M recovery events × ±8wk window): **48.8 min** (26 chunks of ≤5K pixels)
- Fire detection (144 op-cells × 67M-row data): **172.0 min** — 196.5M total fire rows
- Skill loop (288 op×dom cells × {contingency + 2 lead matches}): **31.5 min** → 12,240 skill rows + 24,192 lead-dist rows
- pixel_event_map at 2 headline ops (ndvi_z + spei_13w) × 2 dirs: ~6M rows
- Save: ~7 min → `event_detection_nlcd_10y.rds` 180 MB xz-compressed

### Headline findings (full writeup → PHASE6_VALIDATION_MEMO.md)

**1. Real operational skill in 8.3 Southeastern USA Plains.** Best onset HSS = +0.473 (8.3 grass dom × spei_4w × z=1.5/K=1, n=6480 events, POD=0.526/FAR=0.473). 12 of top 20 onset cells are 8.3 strata. 8.3 = **Southeastern USA Plains** (Arkansas / Missouri Ozark foothills / East Texas / Louisiana / parts of MS+TN) — humid subtropical, mixed grass/crop/forest, episodic summer storms. (Earlier in this session 8.3 was misnamed "S Central Semi-Arid Prairies" — that's actually 9.4.)

**2. spei_4w dominates.** Of 35 strata with ≥5000 events, spei_4w wins 33 onset cells and 30 recovery cells (out of 35 each direction). Derivatives win 3 onset / 5 recovery cells. spei_13w/spei_26w almost never win at the single-op-point level. The short meteorological window catches more USDM transitions than longer windows OR than the NDVI signals at any single op-point.

**3. NDVI vs SPEI fires are LARGELY INDEPENDENT.** At the headline op (z=1.5, K=2, lead=8wk), per-event firing breakdown:
| Direction | Both | NDVI only | SPEI only | Neither |
|---|---|---|---|---|
| Onset | 5% | 19% | 22% | 53% |
| Recovery | 4% | 19% | 14% | 63% |

Only 4-5% concurrent firing. This means the NDVI monitor provides **complementary** information to SPEI, not redundant — it catches events SPEI misses, and vice versa. Major argument for using NDVI alongside (not instead of) the meteorological reference.

**4. Recovery > onset detectability.** 50% of strata have positive recovery HSS vs 40% for onset. Best recovery HSS = +0.223 (8.3 grass dom × deriv_w07_z) and +0.215 (6.2 grass × spei_26w). Greening events are easier to detect than stressed-onset events.

**5. SPEI trajectory matches USDM severity dose-response.** Onset events show mean SPEI13_post = −0.53 with 65% crossing −1 (D0+); the rare D1+ onset subset (n=485 vs 348K D0 events) shows mean SPEI = −1.02 with 92% crossing −1. Meteorological signal scales with USDM severity at event time.

**6. 8.3 Southeastern USA Plains is the new dark horse.** Section A (`continuous_spei_nlcd`) had 8.3 in the SILENT tier (small-negative ρ). Section B shows 8.3 grass+forest+crop with the BEST event-detection skill in the whole table. The two analyses measure different things: A measures concurrent state agreement, B measures event-timing alignment. 8.3 has poor concurrent agreement but excellent transition alignment.

**7. 9.2 corn belt is hard.** No 9.2 cell appears in the top-20 onset table. 9.2 crop spei_4w recovery HSS = +0.125 (n=229K) — modest. Consistent with Section A's REVERSES-CROP mechanism (irrigation/management buffers concurrent state, but transitions are still partially detectable).

### Files modified
- `09_validate_drought_signal.R`: +828 lines, -7 (new section + 5 helpers + bug-flagged scalar docstrings + CLI smoke flag + EVENT_HEADLINE typo fix + event_detection_nlcd config paths)
- `RUNNING_ANALYSES.md`: this section
- `PHASE6_VALIDATION_MEMO.md`: "Phase 6 Update: Section B" section (to be added)
- Commit: `111cadb` (pre-full-run)

### Lessons captured
- Cache-load is the single longest fixed cost (~5 min for the 8.9 GB join). Sub-section iteration is cheap once it's in memory.
- Block-based 2×2 contingency gives a properly defined HSS even when per-event match with tolerance is what users intuit. Both are reported in the output (HSS = block, hit_rate = per-event).
- The legacy `match_fires_to_events` bug existed since 2026-06-11; predecessor smoke results (PHASE6_VALIDATION_MEMO line 412) were within-pixel-scrambled. Aggregate hit rates per stratum happened to be roughly preserved despite the misalignment, which is why nobody noticed.
- `pixel_event_map` schema needed week_start key for dcast-style NDVI-vs-SPEI agreement analysis. Caught in smoke before full run.
- spei_4w as the operationally-best single signal is somewhat surprising; future work should test whether ensembles of (spei_4w + ndvi_z) beat spei_4w alone (the 4-5% concurrent firing rate suggests they would).

### Next session
- Visualize (the figure backlog from 2026-06-12 carryover plus new Section B figures: 8.3 hit-map, NDVI⊥SPEI complementarity panel, four-mechanism map now informed by Section B too)
- 8.1 + 5.2 grass-worst diagnostic (still on the carryover list)
- Decide whether to add ensembles of (NDVI + SPEI) as a derived signal
- Phase 6 → memo paper draft


## Session Summary (2026-06-12 afternoon) — 5-LC chain complete

### Pivot: urban_dense + urban_diffuse added mid-session
- Initial design (morning): `LC_STRATA_LEVELS = c("crop","forest","grassland")` with rationale "not the operational question for an ag monitor"
- User caught this mid-launch ("we should make sure we're capturing the different urbanicities") — project is "Urban Ecological Drought", so dropping urban was wrong
- Scoping: 4 NLCD urban classes collapse to 2 tiers along the 50%-impervious break: `urban_dense` = urban_high + urban_med (737 px Midwest); `urban_diffuse` = urban_low + urban_open (1,833 px). Per-class statistically infeasible (urban_high has only 28 px Midwest-wide); single "urban" loses the operationally-relevant impervious-cover gradient.
- Implementation: one-line `collapse_urban_to_2tier()` helper called right after the NLCD join in each section. Updated `LC_STRATA_LEVELS` constant + comment block. Killed in-flight 3-LC categorical_usdm_nlcd run and relaunched both sections sequentially with 5-LC schema.

### Helper refactor
- `run_two_track_sweep` + `run_two_track_correlation` (v3 helpers) gained `key_col` + `include_aggregate` args, defaulting to `"L2_code"` + `TRUE` for backward compatibility with existing v3 `categorical_usdm`. New LC sections pass fused stratum_key columns + `include_aggregate=FALSE`.
- `run_two_track_correlation` also gained `progress_every` + `label` args (added post-run after the 59-min silent step [7] caught us by surprise — Spearman ranking on 11M-row strata is expensive).
- New section function: `section_categorical_usdm_nlcd`. ~390 lines added. Mirror of `section_continuous_spei_nlcd` structure. Skips LC-interaction Wald test (no clean single-equation analog for skill metrics) and permutation null (first-pass default `null_reps=0`). Output: `usdm_confusion_nlcd_<scope>.rds` with `skill_binary_lc`, `skill_ordinal_lc`, `correlation_binary_lc`, `correlation_ordinal_lc`, `meta`.

### SPEI 5-LC (66.2 min, 2026-06-12 16:19)
- Per-stratum grid: 2,550 fits in 25.4 min (50 strata × 3 spei × 5 signals × 2 models, doubled for all+dom variants)
- LC-interaction grid: 1,230 slope + 660 wald rows in 33.1 min
- **Four-mechanism story holds + new urban findings**:
  - **9.2 corn belt — urban_dense joins crop reversal** (dense β=−0.072***, n=91; diffuse β=−0.008 ns, n=214; crop β=−0.100***; grass β=−0.007). High-impervious surfaces behave like managed cropland; low-impervious like natural vegetation. ONLY ecoregion where dense/diffuse meaningfully diverge.
  - **9.4 (WORKS) urban tracks the eco** (dense +0.169***, diffuse +0.195***, consistent with crop/grass/forest all +0.16-0.20)
  - **8.2/8.3 (SILENT) urban small-negative like everything else**
  - **8.1/5.2 (REVERSES-GRASS) urban mildly negative, not as bad as grass** (grass still worst)

### USDM 5-LC (95.0 min, 2026-06-12 17:54)
- Skill sweep: 17K binary + 50K ordinal rows in 27.2 min
- Correlation sweep: 1.7K binary + 1.7K ordinal rows in 59.1 min (silent — progress logging added afterward)
- **Headline: SPEI-vs-USDM discrepancy is itself the finding**
  - **9.4 WORKS replicates**: all-LC positive ρ (+0.014 to +0.054), but 3-4× smaller magnitude than SPEI β. Expected signature of USDM being a lagging analyst-curated product.
  - **9.2 REVERSES replicates direction**: all LCs negative ρ. BUT the SPEI-side density split is ABSENT on USDM (both urban tiers ~−0.045, not differentiated). USDM's coarse categorical can't see the surface-management gradient SPEI picks up.
  - **8.4 Ozark — SPEI SILENT, USDM WORKS**: USDM ρ all positive, best urban_dense +0.148 (small N), grass +0.042 (n=184K, solid). USDM analysts see something in 8.4 the meteorological signal doesn't.
  - **8.2 Plains grass — SPEI mild −0.030, USDM strong −0.171** (n=16K within-drought weeks). Mystery — opposite direction of agreement than expected.
  - **8.2 urban_dense intensification HSS = +0.020 at n=223K** — the most statistically-solid urban skill cell in the table. Small but real.

### Lessons captured for next session
- Urban two-tier (dense/diffuse) schema worked cleanly; both sections share `collapse_urban_to_2tier()` so any future urban-schema refinement applies atomically
- `run_two_track_correlation` silent for 59 min was a real annoyance — fixed (progress_every added)
- The four-mechanism SPEI typology and the USDM categorical signature give different answers in 8.4 and 8.2 — those discrepancies are the next round of mechanism questions
- Back-burner: 2-stage 4km→finer-res workflow ([[two-stage-resolution-idea]]) — the 9.2 SPEI-vs-USDM urban-density disagreement is exactly the kind of subpixel-mixing story that motivates Stage 2

### Files modified
- `09_validate_drought_signal.R`: +~440 lines (new section + helper refactor + collapse_urban_to_2tier + progress_every)
- `PHASE6_VALIDATION_MEMO.md`: +~330 lines ("Phase 6 Update: LC Stratification" section)
- `RUNNING_ANALYSES.md`: this section
- Memory: `two-stage-resolution-idea` (new), pending: `continuous-spei-nlcd-findings` update + `usdm-confusion-nlcd-findings` (new)

### Next session pickup
- Headline figures: four-mechanism map, SPEI-vs-USDM agreement scatter, corn-belt decomposition, 8.4 Ozark deep dive
- 8.1+5.2 grass-worst DJF-excluded diagnostic
- 8.4 Ozark "USDM-WORKS-but-SPEI-SILENT" investigation (what are analysts using?)
- 8.2 grass mystery (small-N check at K=1, K=2)
- Section B `event_detection` revival under skill framing with (eco × LC) stratification
- Stage-2 finer-res candidate: 9.2 urban-density mechanism



## Session Summary (2026-06-12 afternoon) — section_continuous_spei_nlcd built + run twice

### Built the new section (parallel to Section A)
- Added `section_continuous_spei_nlcd(scope, null_reps=0L)` to `09_validate_drought_signal.R` (~506 lines added).
- Reuses `fit_fe_spei_one_cell` and `run_fe_regression_grid` unchanged. One small additive change to the grid runner: `key_col` and `include_aggregate` args (defaults preserve Section A behavior).
- New helpers: `fit_lc_interaction_one_cell` + `run_lc_interaction_grid`. Fits `feols(signal ~ spei + i(nlcd_juliana, spei, ref="crop") [| iso_week])` per (eco × dom × spei × signal × model). Per-LC absolute slopes derived as reference + offset; Wald-tests whether offsets are jointly zero.
- Fixest API smoke-test settled on `feols(y ~ x + i(g, x, ref="a"))` + `fixest::wald(fit, keep=c("g::b:x", "g::c:x"))` for the "slopes differ" hypothesis. `hypotheses()` not in this fixest version; `wald(..., "g::")` defaults to "any slope nonzero" not "slopes differ" — caught and worked around.
- CLI: `--section=continuous_spei_nlcd`. Skips null model by default (`null_reps=0`); can rerun later with null if needed.

### Targeted-grid run (10 cells, ~44 min wall, 2026-06-12 11:45)
- 10 hypothesis-driven (L2 × LC) cells: 9.2 × {crop, forest, grassland}, 9.4 × grassland, 8.4 × {forest, crop}, 9.3 × grassland, 8.1 × {forest, crop, grassland}. Both dom variants (modal_frac ≥ 0.60 + all) = 20 strata.
- 5 ecoregions for interaction: 9.2, 9.4, 8.4, 9.3, 8.1.
- Per-stratum grid: 600 fits in 9.1 min. Interaction grid: 300 fits in 27 min.
- **Sanity check WARN fired** — spec error in my range, not a real divergence. I picked spei_13w as headline, but Section A's 9.4 was spei_26w (β=+0.184). For spei_26w the grass-only β=+0.195 — actually STRONGER than the full-eco baseline. Caught and acknowledged before reporting.
- **Headline confirmed**: 9.2 crop β=-0.142 (-0.152 with dom filter), 9.2 grass β=-0.048. Wald χ²=2685, p≈0. Corn-belt-is-crops hypothesis supported.

### Full-grid run (all 11 eco × 3 LC, ~57 min wall, 2026-06-12 13:17)
- Replaced `TARGETED_LC_STRATA` constant with dynamic full-grid derivation inside the section. `LC_STRATA_LEVELS = c("crop", "forest", "grassland")` (dropped urban_* + other — small N in rural Midwest; not the operational question for an ag monitor).
- 33 cells in cross; 30 with rows (3 eco × LC cells are empty in our domain).
- Per-stratum grid: 1,770 fits in 19.7 min. Interaction grid: 660 fits across 11 ecoregions in 30.5 min.
- Sanity check passed cleanly with the spei_26w-targeted range.
- Output `/data/validation/continuous_spei_nlcd_10y.rds` (95 KB) — overwrote the targeted-run version (superset).

### Headline findings (full grid, spei_26w × ndvi_z × pooled, dom=all)

Four operational signatures, NOT three:

| Group | Ecoregions | LC pattern | Mechanism |
|---|---|---|---|
| **WORKS** | 9.4, 6.2, 9.3-grass | All LCs positive (9.4: crop +0.16, forest +0.19, grass +0.20) | Pure semiarid rangeland response |
| **SILENT** | 8.2, 8.3, 8.4 (Plains + Ozark) | Uniformly small-negative (-0.02 to -0.05) | Water-buffered |
| **REVERSES — crop** | 9.2 (corn belt) | crop -0.100, grass -0.007 (clean LC contrast) | Irrigation + planting/harvest masking |
| **REVERSES — grass** | 5.2, 8.1 (Mixed Wood) | All negative, **grass is WORST** (5.2: crop -0.060, forest -0.070, grass -0.100) | Different mechanism — possibly snow contamination of dormant grass NDVI |

### Specific resolutions
- **9.3 mystery**: Section A's Tier-1 9.3 was entirely grass (β=+0.063); crop and forest are ~0. 9.3 IS Tier-1, but only for grasslands.
- **9.4 robustness**: LC restriction slightly STRENGTHENS the signal (grass-only +0.195 > full-eco +0.182). Section A baseline holds.
- **8.4 Ozark silence**: decomposes to mild forest negativity (-0.047, n=5,969) + tiny crop sample (n=94 NS).
- **Statistical robustness**: every ecoregion with ≥2 LCs at the 500-pixel floor shows Wald-significant LC modulation (p << 0.001).

### Open scientific question (raised by this run)
**8.1 + 5.2 "grass-worst reversal" mechanism**. Different from 9.2 corn-belt. Both are northern boreal-influenced Mixed Wood ecoregions. Hypothesis: dormant-season snow contamination differentially affects northern grass NDVI. Could test via seasonal subsetting (DJF excluded) or by stratifying within DOY ranges. Flagged for follow-up.

### Memory updated
- New: [[continuous-spei-nlcd-findings]]
- Updated: [[section-a-findings]] (notes the LC-stratified follow-up supersedes the ecoregion-only interpretation)
- Updated: [[phase6-validation-status]] (continuous_spei_nlcd now in the "complete" list; next-work list updated)
- Updated: MEMORY.md index

### Next session pickup
- **categorical_usdm LC rerun** — currently ecoregion-only; would surface whether v3 ecoregion heterogeneity is LC-mediated too. Same shape of analysis on USDM side as continuous_spei_nlcd did for SPEI side.
- **section_event_detection** — paused 2026-06-11 for framing redesign; resume under [[phase6-question-is-skill]] framing. Should stratify by (ecoregion × LC) from the start given the four-mechanism story.
- **8.1 + 5.2 grass-worst mechanism** — seasonal-subset diagnostic to test the snow-contamination hypothesis.

## Session Summary (2026-06-12 morning) — Phase 6 framing sharpened + NLCD 2019 extraction (00b)

### Phase 6 framing — third pass (lock this one in)
- The question is **skill of NDVI monitor against typical drought measures (USDM, SPEI)**. Full stop.
- *Not* "does NDVI lead USDM?" (Claude's 2026-06-10/11 framing — biased the op-point design toward maximizing lead).
- *Not* "USDM is lagging so optimize for tightest correspondence given its lag" (2026-06-11 fallback — still organized around USDM's temporal properties, not skill).
- Lead/lag observations are *diagnostic byproducts* of skill measurement, never optimization targets.
- Memory updated: [[phase6-question-is-skill]] (formerly [[usdm-lagging-not-ndvi-leading]] — superseded).
- Consequence for Section B: keep the helpers (build_events, detect_fires, match, count) as-is; drop the max-lead op-point sweep; headline POD/FAR/HSS/ETS per ecoregion; report median_lead as a diagnostic column.

### NLCD 2019 16-class extraction (00b_extract_nlcd_2019.R) — COMPLETE in 22 min
- **Why**: legacy `nlcd_code` is a 9-class US Labeled Ecosystems collapse (Forest=4, Herbaceous=8 lumping crop + grass + pasture) sourced from the GDO wildfire project. It cannot distinguish crop from grassland — so the leading hypothesis for the 9.2 Temperate Prairies SPEI reversal ("it's a cropland effect: irrigation + planting/harvest masking") is untestable on the legacy schema.
- **What**: pulled standard NLCD 2019 16-class (1.32 GB, 30m CONUS, EPSG:5070; via ScienceBase captcha 2026-06-12 morning, into `/data/input_data/nlcd/`). Resampled to 4km HLS grid via `terra::segregate + aggregate(fun="mean")` (segregate splits to per-class 0/1 layers; aggregate→mean of 0/1 gives the class fraction at 4km; which.max + max give modal class + dominance fraction in one pass).
- **Output**: `/data/gam_models/valid_pixels_nlcd2019.rds` (544 KB) — same 129,310 pixels as legacy, adds columns `nlcd_code_2019` (raw 16-class int), `nlcd_juliana` (collapsed string ∈ {crop, forest, grassland, urban_high/med/low/open, other}), `modal_frac` (0..1), `nlcd_dominant` (logical, ≥0.60). Legacy `valid_pixels_landcover_filtered.rds` is **untouched** — mtime confirmed unchanged. Pipeline invariant safe.
- **Companion rasters**: `/data/processed_ndvi/land_cover/nlcd_2019_4km_modal.tif` (27 KB, INT1U) + `nlcd_2019_4km_modal_frac.tif` (642 KB, FLT4S), both cropped to Midwest sub-template (320 × 517 cells).
- **Midwest LC distribution** (n=129,310): crop 47.4% (61,241), grassland 28.4% (36,758), forest 20.0% (25,900), other 2.2%, urban_* 1.95%. Plenty of sample for the corn-belt test.
- **Dominance**: ~64% of crop, 67% of grassland, 30% of forest cells have `modal_frac ≥ 0.60`. Forests have lower dominance because Midwest forest is in mixed crop/forest mosaic at 4km.
- **Spot-checks pass**: Iowa corn belt → crop (90% dominance). Mark Twain NF MO → forest 41 (93% dominance). Park Falls WI → forest (NLCD 90 Woody Wetlands per [[forest-wet-collapses-to-forest]]). Madison/Champaign/Des Moines → urban_low. Springfield MO Plateau → grassland/pasture (correct — open ag, not deep Ozark forest).
- **Legacy vs new disagreement is high**: legacy "8 Herbaceous" splits 53/42 crop/grassland under NLCD 2019. Legacy "4 Forest" splits 47/40 forest / (crop + grassland) — i.e. half of "legacy forest" is now classified as ag at 4km modal. Two different upstream rasters; treat as complementary, not interchangeable.

### Bug fixed mid-session (one-character)
- Initial run wrote `segregate(other = NA)` and produced all-1.0 dominance fractions with ~77% of pixels mis-classified as NLCD 11 (Open Water). Cause: with `other=NA`, each per-class layer is "1 where this class, NA elsewhere" — `aggregate(fun="mean", na.rm=TRUE)` then averages to exactly 1.0 wherever the class is present, and `which.max` ties on the first listed class (`11L` Open Water). Fix: `other = 0L` — one char. Memory: [[segregate-other-zero-not-na]].

### NLCD download path (for future reference)
- MRLC and ScienceBase both gate the S3-hosted files behind a captcha; no scriptable URL. The ScienceBase manager URL returns HTML (4 KB), the s3DownloadRequestPageUri is captcha-walled. The legacy NLCD 2019 product bucket (`s3-us-west-2.amazonaws.com/mrlc/`) requires signed requests for any object. Manual browser download at the ScienceBase catalog item page is the path. User downloaded `Annual_NLCD_LndCov_2019_CU_C1V0.zip` from `https://www.sciencebase.gov/catalog/item/664e0d2bd34e702fe8744536` and unzipped to `/data/input_data/nlcd/`.

### Memory additions this session
- [[phase6-question-is-skill]] (feedback — supersedes [[usdm-lagging-not-ndvi-leading]] file; question is skill, not lead/lag)
- [[forest-wet-collapses-to-forest]] (feedback — NLCD 90 Woody Wetlands lumps into `forest` per Juliana's empirical test)
- [[segregate-other-zero-not-na]] (feedback — terra gotcha, one-char bug fix)
- [[nlcd-2019-extraction]] (project — pointer to `valid_pixels_nlcd2019.rds` + Juliana collapse spec)

### Next session pickup
- Extend `09_validate_drought_signal.R section_continuous_spei()` to join `nlcd_juliana` from the new file and add it as a stratification dim. Two options on the table:
  - (a) **Parallel-strata**: add a separate LC-only strata loop alongside the existing L2_code loop → ~5 cells per signal-config (~165 fits, ~1 hr).
  - (b) **Cross**: `(L2_code × nlcd_juliana)` → ~55 cells per signal-config (~1,650 fits, ~12 hr). Direct answer to "is 9.2 reversal a crop effect?".
- Recommended: start with (b), or scope down to just the cells where the corn-belt hypothesis is directly testable (9.2 × crop, 9.2 × forest, 8.4 × forest, 8.4 × crop, 9.4 × grassland) — ~5 targeted cells vs the full cross. Discuss before launching.

## Session Summary (2026-06-11) — Phase 6 reframe + Section C + A; Section B paused

### Phase 6 strategic reframe
Validation goal pivoted from "does NDVI correlate with USDM severity bins?" (v3 `categorical_usdm` framing) to:
1. **Continuous reference**: does NDVI anomaly track continuous SPEI? (Section A, complete)
2. **Event-block correspondence**: when USDM declares events, when does NDVI signal fire? (Section B, partial)

USDM treated as event-block identifier + lagging consensus product; SPEI is the primary independent meteorological reference.

### Infrastructure
- **Dockerfile**: added `fixest` to Batch 8 (continuous_spei needs it). Container rebuilt 2026-06-11 ~09:55 CDT. Verified `requireNamespace("fixest")` returns TRUE.
- **No matrixStats drift this rebuild** (unlike 2026-06-08).

### Section C (`within_week_diagnostic`) — COMPLETE in 25 min
- Output: `/data/validation/within_week_sd_10y.rds` (447 MB)
- **Gate decision**: WEEKLY grain for Section B. All 11 ecoregions have median ratio(within_week_sd / across_week_sd) between 0.22 and 0.36; no pixels with ratio > 1. Weekly aggregation preserves the signal — daily-resolution event_detection NOT justified.
- **Sentinel-2 density effect** found in per-year breakdown: ratio dropped 0.375 (2016) → 0.23 (2023-25) as S2-B + L9 missions accumulated. Documented in [[sentinel2-density-drift]].
- **2016 wk 50 snow contamination hotspot** found: 5,026 pixels in upper Midwest with within-week SD > 0.2 in Dec 12-18 2016. Fmask snow flag didn't catch all snow. Documented in [[dormant-season-qualitative]] (don't mask dormant period, report qualitatively).

### Section A (`continuous_spei`) — COMPLETE in 80 min
- Output: `/data/validation/continuous_spei_10y.rds` (41 MB)
- Headline midwest_aggregate β = -0.038 is **misleading**; ecoregion stratification reveals 3-tier pattern:
  - **Tier 1 — works as expected** (positive β): 9.4 S-C Semiarid Prairies × spei_26w × ndvi_z β = +0.184 r² = 3.7% (best cell); 9.3, 6.2 also positive
  - **Tier 2 — silent** (β ≈ -0.04 to -0.05): 8.4 Ozark, 8.3 SE Plains, 8.2 Central Plains
  - **Tier 3 — REVERSED** (β = -0.07 to -0.12, NEGATIVE sign): 9.2 Temperate Prairies (corn belt heartland), 5.2 Mixed Wood Shield, 8.1 Mixed Wood Plains. Most plausible mechanism: irrigation buffering + heat-mediated confound + management intensity.
- All |β| > 0.01 cells have null permutation z-scores > 100. Effects are tiny in r² but statistically rock-solid.
- Pooled vs iso_week-FE estimates differ by < 0.01 for 95% of cells — seasonality not the main driver.
- Derivatives uniformly weaker than magnitude (max β = +0.049 for 9.4 × spei_4w × deriv_w03_z).
- **Implementation**: two file-scope models per cell (pooled + iso_week-FE), reuses v3 z-standardization helper (lifted to file scope), permutation null with SPEI shuffled within (pixel × season). One bug found mid-run: `residuals(fit)` row-mismatch fixed by manual `intercept + slope*x` (now uses `is.finite()` everywhere — see [[spei-cache-inf-quirk]]).
- Memory: [[section-a-findings]].

### Section B (`event_detection`) — DRAFTED, PAUSED before launch
- All helpers implemented and smoke-tested on 9.4 + 8.4 (30K pixels): build_pixel_events, build_ecoregion_events (with MAJORITY_DELTA=0.10 instead of impossible-at-4km ≥50%), detect_signal_fires_weekly, match_fires_to_events, match_fires_to_eco_events, count_false_alarms, summarize_lead_skill, process_signal_cell, run_event_grid, run_event_permutation_null.
- Smoke test produced interpretable numbers (8.4 onset hit_rate 33%, median_lead -1 wk; 9.4 onset hit_rate 23%, median_lead -1 wk).
- **PAUSED reason**: Claude framed op-point question as "does NDVI provide lead time?" and proposed sweep optimizing for "max lead time." User caught the conflation: the project framing is "USDM is a lagging indicator" NOT "NDVI is a leading indicator." Median lead = -1/0 weeks doesn't mean failure under correct framing. See [[usdm-lagging-not-ndvi-leading]] for full distinction.
- **Runtime concern**: naive scaling estimates ~30+ hr for full op-point sweep at unoptimized helpers. Optimization path (vectorize match + FAR via outer product + max.col) exists but not yet executed.
- **Tomorrow's pickup**: re-think Section B op-point design under USDM-as-lagging frame; decide which metrics matter (hit_rate, pct_lead_pos, temporal correspondence, NOT max-lead); reconsider whether sweep is needed vs focused-grid; then optimize helpers + launch.

### Methodology decisions made this session
- **Phase 6 reframe** (USDM-severity → SPEI-continuous + USDM-event-block). Driven by the observation that USDM is subjective/lagged/analyst-driven and inappropriate as severity truth.
- **iso_week-FE not iso_year×iso_week FE** for Section A: aggressive FE absorbs regional drought events (the signal). User caught this and we settled on pooled + iso_week-FE.
- **Test all three SPEI windows** (4w, 13w, 26w): empirically determine which timescale our NDVI signals track best.
- **MAJORITY_DELTA = 0.10** for ecoregion-aggregate events (instead of impossible ≥50% threshold).
- **Headline op-point for Section B = ndvi_z + deriv_w14_z** (both pixel maps kept).
- **Proper FAR**: fires NOT within ±lead of any event, not the approximate `n_fires - n_hits`.

### Memory additions this session
- [[sentinel2-density-drift]] (project)
- [[dormant-season-qualitative]] (feedback)
- [[spei-cache-inf-quirk]] (reference)
- [[phase6-extension-candidates]] (project — NLCD stratification, drought-week conditioning, VPD, SPEI lag, etc.)
- [[section-a-findings]] (project)
- [[usdm-lagging-not-ndvi-leading]] (feedback — the framing fix that paused Section B)

## Session Summary (2026-06-10) — `categorical_usdm` v3 + Phase 6 reframe

## Session Summary (2026-06-10) — `categorical_usdm` v3 + Phase 6 reframe

### Bug fixes confirmed in production (v3)

| Bug | v2 state | v3 state |
|---|---|---|
| Lead-K | `usdm_change ∈ [+0, +5]` (running-max, non-negative) | `usdm_change ∈ [-5, +5]` (true self-join, bidirectional) |
| Recovery TPs | All zero | 80.6M binary + 145.8M ordinal |
| USDM scale | -1, 0..4 (arithmetic on -1 sentinel) | 0..5 ordinal |
| L2_code labels | 5 integers (collapsed from "8.1","8.2"...) | 11 distinct character codes |

### Scientific findings (v3)

- **Recovery beats intensification**: 9/10 top-z binary cells + all 10 top-z ordinal cells are recovery. Ecologically plausible (greening response sharper than browning during drought onset).
- **Ecoregion heterogeneity**: 3 of 11 ecoregions show positive within-drought Spearman ρ for ndvi_z (Ozark/Ouachita 8.4 +0.023; South Central Semiarid Prairies 9.4 +0.014; Western Cordillera 6.2 +0.005). 8 show negative ρ; aggregate cancels to -0.024. The "no signal" headline is actually "heterogeneous signal averaging to zero."
- **Short-window derivatives dominate**: `deriv_w03_z`, `deriv_w07_z` are the modal argmax signal across cells. Magnitude (`ndvi_z`) rarely wins.
- **Effect sizes operationally modest**: best HSS = 0.0548 (8.4 recovery K=1 deriv_w03_z z≥2.0 dT=-1). Statistically detectable (z=821 vs null_sd≈1e-4) but small.

### v3 implementation (replaces v2 in `09_validate_drought_signal.R`)
- `section_categorical_usdm(scope, null_reps = 5L)` — new helpers `build_lead_K`, `sweep_z`, `run_two_track_sweep`, `run_two_track_correlation`, `month_to_season`, `safe_argmax` all file-scope above the section
- CLI: `--null-reps=N` (default 5; pass 0 to skip null model)
- Output `/data/validation/usdm_confusion_10y.rds` (0.84 MB, 11 components: skill_binary/ordinal, correlation_binary/ordinal, contingency_binary/ordinal, null_summary_binary/ordinal, null_max_across_windows_binary/ordinal, meta)
- v2 archived to `usdm_confusion_10y.v2.rds`
- Verification: r-reviewer pass (1 BLOCKER + 3 CONCERN + 4 NIT all addressed) + synthetic smoke test before launch

### Methodology decisions made this session
- **USDM recode site**: in-analysis (cache stays valid); source-side fix to 08 deferred as separate task
- **USDM encoding**: 2-track — BINARY (any drought y/n) for None↔D0 boundary + ORDINAL (D0..D4) within-drought
- **Null model**: 5 reps, block-permute usdm_ord within (pixel × season ∈ DJF/MAM/JJA/SON)
- **Multi-window correction**: max-across-windows null distribution (no windows dropped; handles correlated-test inflation exactly)

### Plan forward — combo route (light Phase 2 + Phase 3)

**Light Phase 2 (~1 day)**: NLCD land cover stratification (Juliana's lead — better recovery in Chicago area at LC aggregate) + condition skill on current USDM state (D0/D1/D2+ subsets).

**Phase 3 (~2-3 days)**: implement `section_continuous_spei` (pooled FE regression NDVI_anom ~ SPEI | year_week + (ecoregion or land cover)) + `section_event_detection` (USDM-event-anchored lead-time, not week-by-week). USDM becomes operational secondary; SPEI primary scientific reference.

**Deferred**: source-side USDM sentinel fix in 08 + cache rebuild (5 hr). Not blocking.

See `PHASE6_VALIDATION_MEMO.md` for full details.

## Session Summary (2026-06-09 afternoon) — `categorical_usdm` v1 + v2

### Script renumber + placeholder delete
- `git mv 07_validate_drought_signal.R 09_validate_drought_signal.R` — slots after `08_validation_data_setup.R` in workflow order.
- Deleted `07_classify_drought_PLACEHOLDER.R` (unused; read `conus_4km_anomalies.csv` no longer in pipeline output).
- Updated `run_phase6_align_weekly.sh:67` and `WORKFLOW.md` (script list + new Phase 6 section pointing to 08/09).
- `07_visualize_derivatives.R` kept at 07 — actively in use, slots after script 06.

### `categorical_usdm` v1 (2026-06-09 14:58 → 15:35 CDT, 20.8 min wall)
Initial implementation: per-pixel z of `ndvi_anom_mean`, lead-K USDM = max(usdm[t..t+K]) for K ∈ {0,1,2,4,8}, skill sweep over (z-threshold × USDM-threshold × K × stratum), plus a `bayes_sig` comparator from `ndvi_n_sig ≥ 4`.

**Bug fixed mid-session**: integer overflow in `compute_skill` HSS denominator — `(tp+fn)*(fn+tn)` overflows R's 32-bit int when subset sizes exceed sqrt(2^31) ≈ 46K; per-ecoregion subsets are tens of millions. Cast all four contingency cells to numeric upfront. Verified at overflow scale (30M/5M/2M/30M test case yields POD=0.94, HSS=0.79).

**Headline (Midwest aggregate, USDM ≥ D1)** — saved to `usdm_confusion_10y.v1.rds`:

| K | bayes_sig | z ≤ −1.5σ |
|--:|---|---|
| 0 | POD=0.997 FAR=0.78 CSI=0.22 **HSS≈0** | POD=0.08 FAR=0.73 CSI=0.07 HSS=0.025 |
| 4 | POD=0.997 FAR=0.73 CSI=0.27 **HSS≈0** | POD=0.07 FAR=0.71 CSI=0.06 HSS=0.007 |
| 8 | POD=0.997 FAR=0.68 CSI=0.32 **HSS≈−0.001** | POD=0.07 FAR=0.68 CSI=0.06 HSS=0.001 |

Three problems with the framing:
1. `bayes_sig` fires across the population — `ndvi_n_sig ≥ 4` predicate is direction-agnostic and base rate of significance is ~90%, so HSS≈0 (high recall, no precision).
2. z-bin skill barely above chance.
3. K-trend is the **wrong direction** for HSS — lead-time hypothesis would predict skill *increasing* with K; instead 0.025 → 0.001.

Root cause: synchronous "is USDM high?" framing is the wrong question. USDM movement matters more than USDM level.

### `categorical_usdm` v2 (in flight — launched 2026-06-09 15:56 CDT)

Reframed per session discussion: directionality matters in **both directions** (drought worsening AND drought receding); both **magnitude** (anomaly z) and **derivative** (rate of change) are NDVI signals; USDM target is signed change over [t, t+K] rather than static class.

**Five NDVI signals**, all per-pixel z-standardized:
- `ndvi_z` (magnitude — anomaly z)
- `deriv_w03_z`, `deriv_w07_z`, `deriv_w14_z`, `deriv_w30_z` (rate, 4 windows)

**USDM target**: `usdm_change_K = usdm_lead_K − usdm[t]` (signed).

**Two confusion-matrix directions** per (stratum × K × signal):
- INTENSIFICATION: pred = signal ≤ −threshold paired with usdm_change ≥ +T
- RECOVERY:        pred = signal ≥ +threshold paired with usdm_change ≤ −T

**Z thresholds**: signed {−2.5, −2, −1.5, −1, −0.5, +0.5, +1, +1.5, +2, +2.5}σ.
**USDM-change thresholds**: ±{1, 2, 3} class transitions.
**K values**: {1, 2, 4, 8} (K=0 dropped — change is always 0 there).

**Side cache**: Spearman ρ between (−signal) and `usdm_change` per (stratum × K × signal); negated so positive ρ = good skill (NDVI moves opposite to USDM). 200 rows total.

**Skill table size**: 12 strata × 4 K × 5 signals × 2 directions × 3 USDM-change × 5 z = **7,200 rows** (vs v1's 1,440).

**`bayes_sig` comparator dropped** in v2 — `ndvi_n_sig` on the cached file is direction-agnostic, can't honor the bidirectional framing without re-running align_weekly (5 hr) to add `ndvi_n_sig_neg/pos`. Flagged in code comments as the re-enable path.

### Next session priorities

1. **Validate v2 results in the morning** — `usdm_confusion_10y.rds` should be ~80-100 KB (vs v1's 72 KB given the expanded skill table). Check:
   - Spearman ρ — sign and magnitude per signal/K/ecoregion. Should be positive (NDVI moves opposite to USDM); larger derivative-window signals (w14, w30) may correlate better than w03 if the lead-time hypothesis holds.
   - Direction asymmetry — intensification HSS likely beats recovery HSS (NDVI lag during recovery is longer than during onset).
   - Per-ecoregion variation — Great Plains (cropland minimal) likely shows stronger NDVI-USDM coupling than Eastern Temperate Forests (heavily managed cropland).
2. **If v2 results are interpretable**: design `event_detection` and `continuous_spei` to follow the same bidirectional + magnitude+derivative pattern.
3. **If v2 also shows weak skill**: investigate whether the per-pixel z-standardization is the right baseline (vs ecoregion-week pooled), or whether the issue is the cached anomaly representation itself.
4. **Deferred**: align_weekly extension for directional `ndvi_n_sig_neg/pos` (would let us re-add the bayes_sig comparator).

## Session Summary (2026-06-09) — Phase 6 align_weekly COMPLETE (10y)

### Run outcome — `run_phase6_align_weekly.sh`

Launched 2026-06-09 09:26:47 CDT, `SEQUENCE_COMPLETE` at 2026-06-09 14:26 CDT. Total wall: **5.0 hr (300.0 min)** for 10y scope.

| Stage | Detail |
|---|---|
| Per-year loop (2016-2025) | 10 × ~24.0 min (range 23.7-24.6 min, remarkably uniform). Each year: anomalies 47.2M rows → 6.85M pixel-weeks; derivatives 188.8M rows → 6.85M pixel-weeks. |
| Year 2021 — rebuild validation | Read cleanly with the matching 6,853,430-row count → 2026-06-08 CIFS-corruption rebuild is end-to-end validated. |
| rbindlist + cross-year-boundary dedup | 68,534,300 → 67,629,130 rows |
| Join USDM + SPEI weekly + ecoregion | 67,629,130 rows, USDM 99.62% non-NA, SPEI-4w 99.62% non-NA, ecoregion 100% |
| Save | `ndvi_drought_join_weekly_10y.rds` 8.3 GB (8,901.8 MB), pixel coverage 129,310/129,310 (drift 0) |

### Docstring ETA correction

`run_phase6_align_weekly.sh` advertised ~60-90 min for 10y scope — actual is ~5 hr (the per-year loop alone is ~4 hr at uniform ~24 min/year, plus ~1 hr for rbindlist + dedup + joins + save). Updated this commit. Revised estimates:
- 10y scope: ~5 hr ± 10 min
- 13y scope: ~6.3 hr ± 15 min

### Open thread (deferred, not blocking)

R-side `readRDS()` silently hangs on two baseline files (`baseline_posteriors/doy_200.rds`, `doy_269.rds`) from both docker and host context, even when CIFS is idle. `xz -t` on the same files passes per-block CRC32 in 7-8 sec. This was flagged 2026-06-09 during rebuild verification (these two files triggered "Host is down" warnings during the rebuild) but is NOT blocking because the rebuild + downstream align_weekly both completed successfully and `xz -t` is the more authoritative integrity check. Some R↔CIFS interaction worth investigating later.

## Session Summary (2026-06-08 / 2026-06-09) — derivatives_2021 rebuild COMPLETE

### Run outcome — `run_2021_rebuild.sh`

Launched 2026-06-08 13:18 CDT, `SEQUENCE_COMPLETE` at 2026-06-09 09:18 CDT. Total wall: **20.0 hr** (16.4 hr Step 1 + 3.6 hr Step 2).

| Step | Wall | Output |
|---|---:|---|
| `rebuild_06` | 16.4 hr (762.4 min compute) | `derivatives_2021.rds` 11 GB, 188,533,980 rows, 92.6% significant, mean anomaly -0.000359 |
| `restore_stats_06c` | 3.6 hr | `change_derivatives_stats.rds` 548 B, 13 rows (2013-2025); 2021 has `elapsed_mins=762.4`, others NA (mtime-rebuild from on-disk year files) |

### Trigger — CIFS post-rename corruption of derivatives_2021.rds

Phase 6 `align_weekly` (launched 2026-06-06) failed at year 2021 with `lzma decoder corrupt data` reading derivatives_2021.rds (11.4 GB). Same failure class as derivatives_2016.rds on 2026-05-27 (CIFS server lost buffered bytes during a backup window post-rename). 2026-06-08 morning audit confirmed:
- 9 other year-summary files (2016-2020, 2022-2025) all read cleanly (188,792,600 rows each)
- `baseline_posteriors/` (365), `year_predictions_posteriors/2021/` (365) all read cleanly
- `valid_pixels_landcover_filtered.rds` (129,310) and the stale 13-row `change_derivatives_stats.rds` clean
- First 400/1460 `change_derivatives_posteriors/2021/doy_*_window_*.rds` files read cleanly before audit was killed (no longer load-bearing — Option B overwrites them)

Decision: canonical 06 re-run rather than algebraic-identity resurrection. Resurrection would shave ~12 hr but introduces novel code for a one-off recovery. 06 already has CIFS defenses baked in (`saveRDS_validated` post-rename readback added 2026-05-27).

### Verification (2026-06-09 ~09:30)

- `derivatives_2021.rds`: 11 GB, 188,533,980 rows, 92.6% significant ✓. Pre-rebuild stale-stats row reported 174,802,540 sig / mean -3.78e-04; new values are 174,553,320 sig / mean -3.59e-04 — within sim-level drift from BLAS-thread non-determinism (per memory note on `project_script02_parallelization`).
- `change_derivatives_stats.rds`: 13 rows, years 2013-2025 ✓.
- `baseline_posteriors/doy_200.rds` + `doy_269.rds`: XZ-integrity ✓ via `xz -t` (7.5 / 7.6 s full per-block CRC32 verify). These were the two baseline reads that triggered "Host is down" warnings during the rebuild; mtimes (May 7-8) prove they weren't mutated, xz CRC32 confirms bytes are intact.

### Operational notes

- 9 transient "Host is down" warnings in `rebuild_06.log` across the 762-min run (5 on per-window `.tmp` files mid-write, 2 on baseline reads, 2 generic `lzma decoding result 10`). All recovered by retry layer; final result was 365/365 valid DOYs (100% coverage). Warnings were noise from the retry layer, NOT the dangerous post-rename byte-loss class.
- Side issue from 13:16 launch attempt: matrixStats missing from container (re-installed via `docker exec -u root`). Verify after any future `docker compose up --build` per [project_container_matrixstats_drift](../../malexander/.claude/projects/-home-malexander-r-projects-github-NDVI-drought-monitoring/memory/project_container_matrixstats_drift.md). The 13:18 relaunch succeeded.
- Pre-step (manual): renamed corrupt year file to `derivatives_2021.rds.corrupt-2026-06-08.bak` (parallel to 2016 evidence file). Wrapper's pre-flight guard refuses to launch if original path is still occupied.
- **R↔CIFS readRDS hang on the two flagged baseline files (worth investigating later)**: post-rebuild verification attempts via `readRDS()` from R (host or docker) silently hung on doy_200.rds + doy_269.rds even after CIFS was free. `xz -t` worked cleanly in seconds. Some R/CIFS interaction worth investigating, but `xz -t` is the more authoritative integrity check anyway.

## Session Summary (2026-06-05 / 2026-06-06) — weekly SPI/SPEI COMPLETE

### Run outcome — `run_weekly_climatology.sh`

Launched 2026-06-04 17:21 CDT, marker `SEQUENCE_COMPLETE` at 2026-06-05 11:32 CDT. Total wall: **18.2 hr**.

| Section | Wall | Output | Rows | Pixels × periods |
|---|---:|---|---:|---|
| gridmet_weekly | 120.6 min | `gridmet_4km_weekly_1984_2025.rds` (3.4 GB) | 283,318,210 | 129,310 × 2,191 weeks |
| spei_weekly    | 959.7 min | `spei_4km_weekly_2013_2025.rds` (5.5 GB)   | 87,672,180  | 129,310 × 678 weeks  |
| qc             | 7.5 min   | `qc_report.rds` updated                     | —           | 6/6 files ✓          |

`qc_report.rds` now covers 6 files (was 4 pre-weekly): ecoregion lookup, USDM weekly, GridMET daily, SPEI monthly, **GridMET weekly, SPEI weekly**. Zero missing/extra pixels across all six.

### Performance footgun — `section_spei_weekly` parallel fell back to sequential (NOT a correctness issue)

`spei_weekly.log` shows **all 4 super-chunks fell back to sequential `lapply`**:

```
future_lapply ERROR: The total size of the 4 globals exported for future expression (‘FUN()’)
  is 27.45 GiB. ... The three largest globals are ‘fit_pixel’ (13.72 GiB of class ‘function’),
  ‘FUN’ (13.72 GiB of class ‘function’) and ‘WIN_SPI’ (43 bytes of class ‘numeric’)
  -- falling back to sequential
```

Closure size grew per super-chunk (27 → 47 → 67 → 86 GiB) because `fit_pixel` captured the enclosing `weekly_dt` data.table by reference, and `weekly_dt` itself grew as chunks accumulated results in the same frame.

**Why it's only a perf issue**: per-pixel SPEI fits are deterministic (no parallel RNG), and the fallback was uniform across all super-chunks, so output is bit-equivalent to a hypothetical successful-parallel run. The 16-hr wall is roughly 4× the ~4 hr it should have been at true 4-way parallel.

**Fix pattern** (for next touch of `08_validation_data_setup.R`):
- Hoist `fit_pixel` to top-level (or `local()`-isolate it) so it doesn't close over `section_spei_weekly`'s frame.
- Pass the chunk's row-subset explicitly as a `fit_pixel` argument (vs implicit capture of the full table).
- Inside the worker, dispatch via `data.table[pixel_id %in% chunk_pixels]` slice, not by indexing the captured frame.

**Decision**: defer the fix. Output is correct; no rerun planned unless we extend the climatology record (e.g., add 2026 once GridMET catches up). Patch lands when we next touch the file. Noted here so the fix isn't forgotten.

### Phase 6 input data inventory (final — all in `/mnt/malexander/datasets/ndvi_monitor/validation/`)

| File | Size | Rows | Span / shape |
|---|---:|---:|---|
| `midwest_extent.rds` | 1.8 KB | spatial bounds | static |
| `pixel_to_ecoregion_l2.rds` | 71 KB | 129,310 | per-pixel L2 ID |
| `ecoregions_midwest_l2.rds` | 2.7 MB | 9 polygons | EPA L2 |
| `usdm_4km_weekly_2013_2025.rds` | 1.9 MB | 87,672,180 | 678 weeks × 129,310 px (D0-D4 categorical) |
| `gridmet_4km_daily_2013_2025.rds` | 4.0 GB | 613,963,880 | 4,748 days × 129,310 px (pr+pet) |
| `gridmet_4km_weekly_1984_2025.rds` | 3.4 GB | 283,318,210 | 2,191 weeks × 129,310 px (pr+pet, climatology) |
| `spei_4km_monthly_2013_2025.rds` | 1.2 GB | 20,172,360  | 156 months × 129,310 px (SPI/SPEI 1m/3m/6m) |
| **`spei_4km_weekly_2013_2025.rds`** | **5.5 GB** | **87,672,180** | **678 weeks × 129,310 px (SPI/SPEI 4w/13w/26w)** |
| `qc_report.rds` | 300 B | per-file ✓ | completeness audit |

ISO-week join key (`year_week`) is consistent across USDM, SPEI weekly, GridMET weekly. The weekly SPEI is the primary climatic reference for Phase 6; monthly SPEI is kept for cross-check against published USDM scoring frameworks (which historically operate at monthly resolution).

### Next session priorities
1. **Phase 6 script 07 design sign-off** — see [Phase 6 design sketch](#phase-6-design-sketch-2026-06-06) below; decide modules + scope before coding.
2. **Temporal scope decision** — full 13-yr (2013 launch-lag + 2014/2015 pre-S2 winter gaps) vs uniform 2016-2025 (full S30+L30 era). Per memory `feedback_systematic_over_tailored`, default leans toward "accept the gaps, run uniform method"; the call depends on whether the validation grain forces uniformity (USDM-confusion tables are robust to missing weeks; per-pixel time-series correlation against weekly SPEI is more sensitive).
3. **Deferrable cleanup**: spei_weekly closure-capture fix; no rerun planned but the fix should land before any climatology extension.

## Phase 6 design sketch (2026-06-06)

**Goal**: Validate the NDVI-derived drought signal (anomalies + derivatives) against an independent ground truth (USDM categorical, SPEI continuous), at a grain that respects the pixel-week structure of the data.

**Sketch is provisional — pending user review/approval before any code lands.**

### Inputs to script 07

| Source | Layer | Frequency | Field(s) |
|---|---|---|---|
| NDVI signal | `modeled_ndvi_anomalies/anomalies_YYYY.rds` × 13 | per-DOY | `ndvi_anom`, `ndvi_anom_lwr/upr`, `is_significant` |
| NDVI signal | `change_derivatives_posteriors/YYYY/doy_DDD_window_WW.rds` × 17,704 | per (DOY, 3/7/14/30-day window) | `change_anom`, `change_anom_lwr/upr`, `is_significant` |
| USDM (ground truth, categorical) | `usdm_4km_weekly_2013_2025.rds` | weekly | `usdm_cat` ∈ {none, D0, D1, D2, D3, D4} |
| SPEI (continuous reference) | `spei_4km_weekly_2013_2025.rds` | weekly | `spi_4w/13w/26w`, `spei_4w/13w/26w` |
| Ecoregion grouping | `pixel_to_ecoregion_l2.rds` | static | `l2_id` (9 substantive L2s) |

### Decisions needed (user input)

| # | Question | Default if no preference |
|---|---|---|
| 1 | Validation grain — pixel-week, ecoregion-week, or both? | both (pixel-week is the test; ecoregion-week is the reporting summary) |
| 2 | Temporal scope — 13-yr (2013-2025) or uniform 10-yr (2016-2025)? | uniform 10-yr; cross-reference figures for 2013-2015 as supplementary |
| 3 | SPEI window of record — match 4w to weekly NDVI; 13w to derivative 14-30 window; or scan all? | match by timescale (4w↔3/7-day, 13w↔14/30-day) + report 26w as longer-context baseline |
| 4 | Primary skill metric — categorical (USDM-class confusion) or continuous (correlation/regression vs SPEI)? | both, in separate sub-modules |
| 5 | Pixel resampling — leave full 129,310 or stratify-sample for figure-friendly summaries? | full for stats; stratified random N=2000 for diagnostics + figures |
| 6 | NDVI signal collapse — anomaly mean only, derivative significance flag only, or joint? | joint: NDVI anomaly continuous + derivative-significance categorical |

### Proposed script 07 architecture (mirrors 08's section-CLI pattern)

```
07_validate_against_drought.R --section=<name> [--scope=10y|13y]

Sections (sequential, each cached to disk so reruns are cheap):
  align_weekly       — collapse per-DOY NDVI anomalies to ISO-week summaries
                       (mean ndvi_anom, max |ndvi_anom|, fraction-DOYs-significant)
                       joined to USDM week + SPEI 4w/13w/26w
                       Output: ndvi_drought_join_weekly_<scope>.rds (~6-8 GB est.)
  
  categorical_usdm   — USDM-class confusion matrices:
                       NDVI-anomaly z-score binned vs USDM D0-D4
                       Per ecoregion + CONUS-Midwest aggregate
                       Output: usdm_confusion_<scope>.rds + figures
  
  continuous_spei    — Per-pixel + per-ecoregion-week regression:
                       ndvi_anom ~ spei_<W> + factor(year_week)
                       Lag analysis (NDVI vs SPEI t / t-1 / t-2 weeks)
                       Output: spei_regression_<scope>.rds + figures
  
  event_detection    — Drought event = run of weeks where USDM ≥ D1
                       NDVI-signal hit/miss/false-alarm classification
                       (was NDVI z-anom ≤ -threshold for any week in event?)
                       Output: events_<scope>.rds + figures
  
  qc                 — pixel + week alignment audit across all outputs
```

### Why this shape

- **`section`-CLI matches 08's pattern** — same dispatcher, same logging convention, same cache-on-disk reruns. Familiar shape for next session.
- **`align_weekly` runs once** then the four analysis sections (categorical, continuous, event, qc) all read from its cached output — keeps the ~88M-row per-pixel join from being rebuilt 4×.
- **Two scope flags** (`--scope=10y|13y`) without parallel script copies — one codepath, controlled by filter at `align_weekly`.
- **Ecoregion + Midwest aggregate** in every output so stats are interpretable at both granularities; user can pick whichever grain answers a given question.

### Open architectural questions

- **Per-pixel regression at 129,310 × 678 ≈ 88M rows** — fits in memory as a tall data.table but downstream `lm()` / fixed-effects would need a `fixest` / per-group `data.table[, lm(...)]` pattern to scale. Decide before coding: `fixest` (fast, memory-friendly) vs per-ecoregion split + serial OLS.
- **Anomaly significance threshold for event-detection** — `is_significant` (Bayesian CI excludes 0, already on disk) is the natural call. But USDM thresholds are calibrated against various ad-hoc continuous indicators; need to pick z-score bins for the confusion matrix that don't trivialize the comparison. Suggest: report 3 binnings (1σ / 1.5σ / 2σ) and let the reader judge.
- **Spatial autocorrelation in pixel-level stats** — 4km pixels in the same ecoregion week are NOT independent. For headline numbers, ecoregion-week aggregate is the honest summary; pixel-level numbers are diagnostic-only. Should we mention this in the doc upfront?

### What's NOT in scope for script 07

- Drought classification system (was `07_classify_drought_PLACEHOLDER.R` — separate script, separate decision later)
- New satellite-data pulls (out of phase)
- Re-fit of any GAM (this is downstream-only)

## Session Summary (2026-06-03) — Phase 6 prep COMPLETE

### What ran (two-stage)

**(1) Evening sequence (2026-06-02 15:52 → 18:33 CDT)** — partial:
- `audit_backfill` ✓ — 06b 2018+2023 confirmed clean (188,792,600 rows each)
- `06c_rebuild` ✓ but **skipped 2018/2023** because both already had stats rows (stale-detection gap — see patches)
- `usdm_process` ✓ → `usdm_4km_weekly_2013_2025.rds` (1.9 MB, 87,672,180 rows)
- `gridmet` ✗ — OOM during a single 614M-row `merge(pr_long, pet_long)` (full-record materialization before merge)
- `spei`, `qc` skipped

**(2) Remaining sequence (2026-06-03 09:40 → 13:05 CDT)** after gridmet rewrite — all green:

| Section | Wall time | Output |
|---|---:|---|
| gridmet | 51 min | 4.0 GB, 613,963,880 rows (129,310 px × 4,748 days) |
| spei    | 149 min | 1.2 GB, 20,172,360 rows (129,310 px × 156 months) |
| qc      | 4 min | 4/4 files ✓ ok, 0 missing/extra pixels each |

**(3) 06c stale-row rebuild (2026-06-03 13:06 → 13:44 CDT)** auto-launched by `then_run_06c.sh`:
- New mtime-based stale detection correctly flagged 2018+2023
- 2018 stats: 188,663,290 → **188,792,600** rows (mean_anomaly 8.29e-04 → 7.94e-04)
- 2023 stats: 188,663,290 → **188,792,600** rows (mean_anomaly 3.40e-03 → 3.39e-03)
- 13-year stats now internally consistent

### Patches landed

1. **`section_gridmet` rewrite (`08_validation_data_setup.R`)** — per-year extract + per-year `merge(pr, pet)` + `data.table::rbindlist` at the end. Peak memory bounded to one year's table (~47M rows) instead of two full 614M-row long tables. Final write uses `compress = "gzip"` rather than the default xz: xz on the merged table ran at ~32 MB/min (~60+ min for 4 GB); gzip finishes in ~5 min. This RDS is consumed only by `section_spei` and not archived long-term, so the size trade (~4 GB gzip vs ~2 GB xz) is acceptable.
2. **`06c_rebuild_change_derivatives_stats.R` default-mode upgrade** — also re-computes rows whose `derivatives_<year>.rds` mtime is newer than `change_derivatives_stats.rds` mtime, not just missing-year rows. Catches the 2026-06-02 case where 06b backfill rewrote derivatives files but 06c said "nothing to do" because stats rows already existed.

### Tooling (untracked → now committed)
- `run_remaining_sequence.sh` — gridmet → spei → qc with per-step logs + `SEQUENCE_COMPLETE`/`SEQUENCE_FAILED` markers
- `then_run_06c.sh` — polls the sequence marker, runs 06c rebuild on success

### Final stats — `change_derivatives_stats.rds` (13 rows, 2013-2025)

| year | n_results   | n_significant | pct_significant | mean_anomaly  |
|------|-------------|---------------|-----------------|---------------|
| 2013 | 123,878,980 | 111,308,480   | 89.85%          | -2.219e-03    |
| 2014 | 185,689,160 | 169,021,072   | 91.02%          |  1.703e-03    |
| 2015 | 185,689,160 | 168,272,004   | 90.62%          | -2.417e-03    |
| 2016 | 188,792,600 | 172,332,219   | 91.28%          | -6.800e-05    |
| 2017 | 188,792,600 | 173,703,576   | 92.01%          |  1.666e-04    |
| 2018 | 188,792,600 | 175,567,396   | 92.99%          |  7.941e-04    |
| 2019 | 188,792,600 | 175,341,602   | 92.88%          | -2.051e-03    |
| 2020 | 188,792,600 | 174,560,761   | 92.46%          |  1.908e-03    |
| 2021 | 188,792,600 | 174,802,540   | 92.59%          | -3.781e-04    |
| 2022 | 188,792,600 | 176,065,576   | 93.26%          | -2.862e-03    |
| 2023 | 188,792,600 | 175,771,354   | 93.10%          |  3.395e-03    |
| 2024 | 188,792,600 | 175,777,785   | 93.11%          | -1.368e-03    |
| 2025 | 188,792,600 | 176,637,530   | 93.56%          | -1.057e-03    |

### Phase 6 input data inventory (`validation/`)

| File | Size | Rows |
|---|---:|---:|
| `midwest_extent.rds` | 1.8 KB | spatial bounds |
| `pixel_to_ecoregion_l2.rds` | 71 KB | 129,310 pixels → EPA L2 |
| `ecoregions_midwest_l2.rds` | 2.7 MB | 9 substantive L2 polygons |
| `usdm_4km_weekly_2013_2025.rds` | 1.9 MB | 87,672,180 |
| `gridmet_4km_daily_2013_2025.rds` | 4.0 GB | 613,963,880 |
| `spei_4km_monthly_2013_2025.rds` | 1.2 GB | 20,172,360 |
| `qc_report.rds` | 272 B | per-file completeness audit (all ✓) |

### Next session priorities
1. Phase 6 analysis design — script 07+ scaffolding for event-detection (NDVI anomaly vs USDM categorical + SPEI continuous)
2. Decide temporal scope: full 13-year (with 2013-2015 partial coverage) vs uniform 2016-2025

## Session Summary (2026-06-02) — full 13-year audit + root-cause for 2014/2015 gaps

### Full inventory audit (13 years)
Ran fresh on-disk enumeration of `change_derivatives_posteriors/<year>/doy_DDD_window_WW.rds` files vs `year_predictions_posteriors/<year>/` upstream DOYs. All 17,704 window files are 78.2–84.9 MB (well above 50 MB resume guard; zero sub-threshold files; no corruption).

| Year | Status | Notes |
|------|--------|-------|
| 2013 | 30 partial/zero DOYs — **structural Landsat-8-launch lag** | First upstream DOY = 113; DOYs 113-142 progressively gain windows as 16/14/7/3-day lags become available. NOT a loss. |
| 2014 | 12 partial DOYs | Upstream gap DOYs 45/46/47 |
| 2015 | 12 partial DOYs | Upstream gap DOYs 15/16/17 |
| 2016, 2017 | clean (1460/1460) | |
| **2018** | **1 partial DOY 229 win_30** — newly-found compute loss | Backfill in flight |
| 2019-2022 | clean (1460/1460) | |
| **2023** | **1 partial DOY 138 win_30** — newly-found compute loss | Backfill in flight |
| 2024-2025 | clean (1460/1460) | |

The 2018 and 2023 single-window misses leaked past 06 v2's cascade-bug fix — they were visible in `change_derivatives_stats.rds` as `n_results = 188,663,290` (vs 188,792,600 full = exactly −129,310 = one window's worth) but the v2 log surface-summary said "365/365 valid" because at DOY granularity each had ≥1 window. Both have upstream lag DOYs present and healthy (2018 doy_199 = 79.8 MB; 2023 doy_108 = 81.3 MB), confirming compute loss not upstream gap. Likely one of the 29 lost warnings in the v2 run.

### Backfill (in flight)
`Rscript 06b_backfill_change_derivatives.R 2018 2023` launched 08:26 CDT. Diff phase correctly detected 1 missing DOY per year. 2018 backup `.v1-pre-backfill.bak` written (11 GB). After merge completes for both years, will run integrity verification.

### 2014/2015 upstream gap — ROOT-CAUSE CONFIRMED (data density limit, not bug)

Investigated whether the 6 missing upstream DOYs (2014: 45/46/47 = Feb 14-16; 2015: 15/16/17 = Jan 15-17) were due to (a) cloud/mask filtering, (b) never-downloaded HLS files, or (c) data-density limit.

**Step 1 — HLS files downloaded? YES, at normal density.**

| Date | HLS NDVI files | Nearby healthy DOYs |
|---|---:|---|
| 2014-02-14 (DOY 45) | 164 | range 128–184 |
| 2014-02-15 (DOY 46) | 148 | |
| 2014-02-16 (DOY 47) | 153 | |
| 2015-01-15 (DOY 15) | 107 | |
| 2015-01-16 (DOY 16) | 188 | |
| 2015-01-17 (DOY 17) | 153 | |

**Step 2 — Aggregated into 4km timeseries? YES, with low yield.** 2014 yday 30-47 has 50,987 obs — all **L30 (Landsat 8) only**; no S30 contributes in 2014 (Sentinel-2A launched mid-2015, S2B in 2017; HLS S30 doesn't meaningfully contribute until ~2016).

**Step 3 — Script 03 fit threshold (≥33% = ≥42,672 unique pixels in 16-day trailing window with non-NA NDVI AND non-NA baseline norm, line 389 of `03_doy_looped_year_predictions.R`):**

| Window | Unique pixels | Threshold | Short by |
|---|---:|---:|---:|
| 2014 DOY 45 (Jan 30–Feb 14) | **40,466** | 42,672 | 2,206 |
| 2014 DOY 46 (Jan 31–Feb 15) | **35,444** | 42,672 | 7,228 |
| 2014 DOY 47 (Feb 1–Feb 16)  | **35,201** | 42,672 | 7,471 |
| 2015 DOY 15 (Dec 31–Jan 15) | **36,717** | 42,672 | 5,955 |
| 2015 DOY 16 (Jan 1–Jan 16)  | **36,211** | 42,672 | 6,461 |
| 2015 DOY 17 (Jan 2–Jan 17)  | **40,029** | 42,672 | 2,643 |

Reference: same-season healthy windows hit 56,402–125,557 unique pixels.

**Structural cause**: L30's 16-day revisit means a perfect 16-day window has only ~1 obs per pixel. Winter clouds/snow reject ~50% of valid scenes. Pre-S2 era can't compensate. Unique-pixel coverage falls just below the 0.33 quality threshold for 6 specific DOYs across 2014/2015.

### Decision (user, 2026-06-02)

**Accept the 6-DOY gap.** Preference is for a systematic, robust method applied uniformly across the whole record over tailoring parameters to a known-limited period. Recovery options considered but rejected:

| Option | Cost | Quality impact |
|---|---|---|
| Lower threshold 0.33 → 0.27 | Refit 03 for affected years; ~5 hr/year | Recovers only DOY 45 + DOY 17 (near-misses); fits would have ~30% pixel coverage |
| Widen trailing window 16 → 24 or 32 days | Refit 03 for **all** years; non-trivial | Recovers all 6 but smooths temporal signal everywhere |
| **Accept the gap** | Free | 6 mid-winter DOYs missing in 2014/2015 derivative coverage |

If Phase 6 analysis quality requires uniformly-complete coverage, may trim record to **2016-2025** (full S30+L30 era). Keep 13-year dataset available for cross-reference. See [[project-pre-s2-winter-gap]] in memory for the structural-data-density explanation.

### Final tier classification (13 years)

| Tier | Years | Count |
|---|---|---|
| **Fully clean** (1460/1460 windows) | 2016, 2017, **2018 (pending backfill)**, 2019-2022, **2023 (pending backfill)**, 2024-2025 | 11 of 13 |
| **Upstream gap** (12 partial DOYs each — pre-S2 winter density) | 2014, 2015 | 2 |
| **Launch lag** (~30 partial/zero DOYs — structural Landsat 8 launch) | 2013 | 1 |

### Carryover state for next session
- After backfill: run `06c_rebuild_change_derivatives_stats.R` to refresh 2018/2023 rows in stats file.
- Phase 6 starts: visualization / drought classification (script 07+, not yet written).
- When editing 02/03/04/06: add the queued one-liner `if (length(warnings()) > 0) print(warnings())` (see [[feedback-print-warnings-at-end]]).

## Session Summary (2026-05-28) — 2014 audit

### 2014 DOY audit result — CLEAN (no v1 cascade losses)

Ran 06b diff logic against 2014 (enumeration only, no compute). Result:

- **362 expected DOYs** (from year_predictions_posteriors/2014/)
- **350 complete DOYs** (all 4 windows ≥ 50 MB)
- **12 partial DOYs** (3/4 windows each): DOYs 48-50, 52-54, 59-61, 75-77
- **0 DOYs with zero windows** — confirms no v1 cascade-loss pattern

**Root cause**: `year_predictions_posteriors/2014/` is missing DOYs **45, 46, 47** (Feb 14-16, 2014). These 3 missing lag posteriors cascade to 12 partial window-files via the lag dependency:
- Window 3 lag DOYs 45/46/47 → DOYs 48/49/50 missing window-3
- Window 7 lag DOYs 45/46/47 → DOYs 52/53/54 missing window-7
- Window 14 lag DOYs 45/46/47 → DOYs 59/60/61 missing window-14
- Window 30 lag DOYs 45/46/47 → DOYs 75/76/77 missing window-30

**Conclusion**: Same upstream-gap class as 2013/2015 residuals. Script 06 behaved correctly — it returned NULL when the upstream data wasn't there; no silent losses, no cascade bug. The stats row for 2014 (185,689,160 rows) is correct: 350 × 4 × 129,310 + 12 × 3 × 129,310 = 185,689,160 ✓.

**Decision**: Accept the gap. No backfill — upstream data (script 03 DOYs 45-47 for 2014) doesn't exist. Phase 6 should treat DOYs 48-50, 52-54, 59-61, 75-77 as partial in 2014 (same handling as 2013/2015 residual DOYs).

### Next session priorities
1. Start Phase 6 (visualization / drought classification — script 07+, not yet written)
2. When editing any of 02/03/04/06: add the `print(warnings())` line

---

## Session Summary (2026-05-27) — 06b first pass + 2016 recovery + stats rebuild

### What ran
- **First 06b pass** completed Wed 2026-05-27 ~02:30 CDT, all three years (2013/2015/2016) targeted. Per-DOY compute worked end-to-end; the script's drop-partial-rows merge patch resolved 39 overlap-halt cases without surprise.
- **derivatives_2016.rds corruption** discovered during post-run integrity audit: file readable up to ~95% then `cannot open compressed file ... probable reason 'Host is down'`. saveRDS_validated's pre-rename readback had passed during the run, so the corruption happened AFTER `file.rename` returned success — server-side CIFS write completion lost buffered bytes during the next backup window. **Recovery**: quarantined corrupt file as `.post-rename-corruption-evidence-2026-05-27`, restored from `.v1-pre-backfill.bak` (md5-confirmed bit-identical), deleted the 8 affected window files for DOYs 102/345 so the diff would re-flag them.
- **06b 2016-only re-run** (`Rscript 06b_backfill_change_derivatives.R 2016`): launched 08:52 CDT, completed 12:13 CDT in **200.9 min**. 2 DOYs (102, 345) recomputed, merged into restored .bak summary → 188,792,600 rows (= 365 DOYs × 4 windows × 129,310 pixels — full coverage). **Layer 1c post-rename readback passed silently** (the corruption mode would now have surfaced as a loud error). **Integrity audit PASSED** (365/365 DOYs in summary match window file inventory).
- **06c stats rebuild** via NEW script [06c_rebuild_change_derivatives_stats.R](06c_rebuild_change_derivatives_stats.R): recomputed rows for 2013/2014/2015/2016 from on-disk derivatives_YYYY.rds (4 sequential reads, no parallel — load + sum is single-pass). 67.0 min wall time. Merged with existing 2017-2025 rows → 13-year stats_df, saved via saveRDS_validated.

### Patches landed today (commit `e3c8af1`)
1. **`saveRDS_validated` Layer 1c post-rename readback** (00_posterior_functions.R) — size-gated at 500 MB by default so year-summary writes are verified but per-window (~80 MB) writes don't pay xz-decompression overhead. On failure, leaves the corrupt file in place and retries the full save via a new .tmp + rename cycle. If all attempts fail, errors loudly with "post-rename readback failed after rename succeeded" so the source of corruption is unambiguous.
2. **06b CLI year-override** (06b_backfill_change_derivatives.R) — `Rscript 06b... 2016` now restricts target_years to just 2016, letting single-year recovery avoid the ~3 hr full tri-year merge I/O.

### Final stats — `change_derivatives_stats.rds` (13 rows, 2013-2025)

| year | n_results   | n_significant | pct_significant | mean_anomaly  | elapsed_mins |
|------|-------------|---------------|-----------------|---------------|--------------|
| 2013 | 123,878,980 | 111,308,480   | 89.85%          | -2.219e-03    | NA (06b)     |
| 2014 | 185,689,160 | 169,021,072   | 91.02%          |  1.703e-03    | NA (v1)      |
| 2015 | 185,689,160 | 168,272,004   | 90.62%          | -2.417e-03    | NA (06b)     |
| 2016 | 188,792,600 | 172,332,219   | 91.28%          | -6.800e-05    | NA (06b)     |
| 2017 | 188,792,600 | 173,703,576   | 92.01%          |  1.666e-04    | 762.7        |
| 2018 | 188,663,290 | 175,442,770   | 92.99%          |  8.286e-04    | 749.8        |
| 2019 | 188,792,600 | 175,341,602   | 92.88%          | -2.051e-03    | 764.1        |
| 2020 | 188,792,600 | 174,560,761   | 92.46%          |  1.908e-03    | 765.1        |
| 2021 | 188,792,600 | 174,802,540   | 92.59%          | -3.781e-04    | 832.2        |
| 2022 | 188,792,600 | 176,065,576   | 93.26%          | -2.862e-03    | 761.1        |
| 2023 | 188,663,290 | 175,647,234   | 93.10%          |  3.397e-03    | 758.6        |
| 2024 | 188,792,600 | 175,777,785   | 93.11%          | -1.368e-03    | 762.0        |
| 2025 | 188,792,600 | 176,637,530   | 93.56%          | -1.057e-03    | 763.0        |

- **Mean significant across 13 years: 92.21%** (v2-only mean was 92.93%; 2013-2016 sit in the 89.9–91.3% range, pulling the overall mean down by ~0.7 pp).
- `elapsed_mins` is NA for the four years rebuilt via 06c (no single timed run — composite of v1 + 06b). The 2017-2025 elapsed values come from the 06 v2 run.

### Carryover state — partial DOYs in 2013/2014/2015 NOT re-attempted
All three years' gaps are confirmed upstream year-prediction posterior gaps (not 06 compute bugs). Same root cause, same decision for all three:

- **2013**: Year posteriors missing many DOYs. Summary row count → 239.4 DOY-equivalents. Root cause: upstream 03 gaps.
- **2014**: Year posteriors missing DOYs 45/46/47 → 12 partial window-DOYs. **Audited 2026-05-28** — no v1 cascade losses. Root cause: upstream 03 gaps. Summary row count → 358.9 DOY-equivalents ✓.
- **2015**: Year posteriors missing lag DOYs. 12 still-partial window-DOYs. Root cause: upstream 03 gaps. Summary row count → 358.9 DOY-equivalents.
- **2016**: 0 missing DOYs. Summary row count → 365.0 DOY-equivalents (clean).

Decision: NOT re-process. Root cause is upstream data (script 03), not 06's compute. Phase 6 should treat partial DOYs as missing in visualizations.

### Open question for Phase 6
Partial-window DOYs in 2013/2014/2015 affect derived stats on those specific DOYs only. Phase 6 should either (a) treat those DOYs as missing in visualizations, or (b) backfill via a script 03/04 re-run for the specific lag DOYs. (b) is much heavier; defer the call until Phase 6 starts.

## Session Summary (2026-05-26)

### 06 v2 outcome
- **Completed**: Sat 2026-05-23 05:02 CDT
- **Total wall time**: 6919.8 min = 115.3 hr = 4.8 days (beat the ~36–60 hr launch estimate by ~2x — actual per-year was ~12.5 hr, not 4–7 hr; original estimate didn't account for matrixStats compute still dominating at 5 workers)
- **Years processed**: 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024, 2025
- **DOY completeness**: every year 365/365 valid. v1 cascade pattern (1 visible error → 20-35 silent losses) did NOT recur. The two `511797b` fixes (wrap-the-save retry + `cat()`-not-`warning()`) held end-to-end across ~75,920 readRDS and ~19,000 saveRDS calls.
- **Mean significant results**: 92.9% (range 92.0–93.6 across the 9 years; very stable)
- **Pace per year** (min): 762.7, 749.8, 764.1, 765.1, **832.2** (2021 outlier, +9%, not investigated), 761.1, 758.6, 762.0, 763.0
- **Worker pattern**: 5 future workers, RSS 2.0 → 5.8 GB within a year (expected growth), reset cleanly at every year-boundary recycle. Zero `FutureInterruptError` events.

### Warnings audit gap
The log ends with `There were 29 warnings (use warnings() to see them)` but the warnings themselves are lost — the script exits without calling `print(warnings())` to flush them. Clean DOY counts suggest they were benign, but unverifiable. **One-line fix queued**: add `if (length(warnings()) > 0) print(warnings())` at the end of script 06 (and 02/03/04) next time any of them is edited. See [[feedback-print-warnings-at-end]] in memory.

### Carryover state for next session
- **2013/2015/2016 are still v1 outputs** (mtimes May 16-18, smaller files): 4.5 GB / 8.4 GB / 11 GB vs ~10.8 GB for the v2 years. The 159 missing DOYs (88+69+2) need 06b backfill before Phase 6 work is valid for the full 13-year span.
- **`change_derivatives_stats.rds`** only covers 2017-2025. 06b will need to rebuild this for all 13 years.
- **06b draft** already had a 1-round r-reviewer pass (CRITICAL + 2 HIGH applied: atomic backup before heavy load, (yday,window)-grain overlap check, tmp+rename + size validation on restart). Slated for launch this week.

### Next session priorities
1. Read `06b_backfill_change_derivatives.R`, sanity-check, dry-run DOY-diff phase
2. Launch 06b (~2-3 hr expected for 159 DOYs at v2's rate)
3. Verify 3 target years' window-file inventories match year summaries
4. Rebuild `change_derivatives_stats.rds` for full 13 years
5. Start Phase 6 (visualization / drought classification — script 07+, not yet written)
6. When editing any of 02/03/04/06: add the `print(warnings())` line

## Prior Active Process (now complete) — 06 v2 launch context

### Why v2 — two cascade-loss bugs found in v1

The Monday morning audit traced an unexpectedly bad v1 pattern: 1 visible `fwrite error` or `cannot open the connection` was always followed by 20–35 silent DOY losses in the same year. Two bugs combined:

1. **`saveRDS_validated`'s write was outside the retry loop.** The retry only wrapped the readback validation; an actual write-side CIFS hiccup propagated straight past the retry, no backoff applied. **Fix**: wrap `saveRDS()` in tryCatch inside the for-loop, treat write errors the same as validation errors (cleanup .tmp, sleep, retry).
2. **Phase 1 (calculate_change_anomaly) errors were emitted as `warning()` instead of `cat()`.** Multisession workers' warnings collect into a condition list that does NOT get ferried to the parent stdout that the log captures; `cat()` does get ferried. So when the same CIFS hiccup that broke a write also broke the next 20-30 workers' reads (via `load_posteriors` → `readRDS_retry` exhausted), those losses produced warnings that vanished, then `process_year_doy` returned NULL without error, and the script's outer cat()/ERROR path never fired. **Fix**: replace `warning()` with `cat()` so phase-1 errors land in the log.

Also bumped `n_cores` 3 → 5: empirical worker residency in v1 was 3.3–4.1 GB (not the 800 MB initial estimate). 5 × ~5 GB + ~42 GB parent peak = ~67 GB of the 128 GiB cap. Held to 5 (not 6+) to limit simultaneous CIFS write contention during midnight windows.

### v1 outcomes (carryover state)

| Year | DOYs avail | Valid | Posteriors | Year .rds | Status |
|------|-----------|-------|------------|-----------|--------|
| 2013 | 253 | 163 (–88) | 616 | 4.5 GB | Resume scan sees as complete (needs backfill) |
| 2014 | 362 | 362 ✓ | 1436 | 11 GB | CLEAN |
| 2015 | 362 | 293 (–69) | 1151 | 8.4 GB | Resume scan sees as complete (needs backfill) |
| 2016 | 365 | 363 (–2) | 1456 | 11 GB | Resume scan sees as complete (needs backfill) |
| 2017 | 365 | ~350 partial | 349 partials | none | Will be reprocessed from scratch by v2 |

### Patches landed pre-launch (commit `b1d5e57`)

Audit + r-reviewer pass before kicking off the multi-day run:

1. **Shared helpers in `00_posterior_functions.R`**: moved `readRDS_retry` here from inline-in-04 so 04 + 06 share one definition. `saveRDS_validated` (added in `8b67463`) is also here.
2. **`library(matrixStats)` + `rowQuantiles` in `calculate_stats`**: bit-equivalent to `apply(quantile)`, ~1.8x faster. Saves ~40 hr from the multi-day run since calculate_stats is the dominant compute cost (6 quantile calls per DOY-window × 4 windows × 365 × 13 years).
3. **`load_posteriors` uses `readRDS_retry`**: defends against ~75,920 readRDS calls during the run hitting transient CIFS hiccups.
4. **`process_year_doy` refactored to two-phase**: Phase 1 computes all 4 windows for a DOY into in-memory buffer; Phase 2 saves them via `saveRDS_validated`. Eliminates orphan-posterior risk.
5. **Per-window writes use `saveRDS_validated`**: atomic .tmp+rename + read-back validation. Defends against silent midnight CIFS corruption (the failure mode that wrote 3 lzma-corrupt files in 03 v2/v3).
6. **Year-summary writes also use `saveRDS_validated`** (r-reviewer CRITICAL — was the one remaining bare saveRDS).
7. **Resume guards bumped**: per-window `0` → `50e6` (catches the 48 MB corruption class from 03 v2; empirical baseline min is 77 MB so 50 MB has 35% margin); year-summary `1e5` → `5e8` (500 MB; expected ~5-10 GB compressed).
8. **Drop unnecessary `as.data.frame()` conversion** (r-reviewer HIGH 2): was creating a 3rd 21 GB copy of year_df during rbindlist; data.table inherits from data.frame. Cuts parent peak from ~63 GB to ~42 GB.

### r-reviewer findings

- 1 CRITICAL (year-summary bare saveRDS) — fixed
- 2 HIGH (PER_WINDOW_MIN_BYTES too low; as.data.frame() peak) — fixed
- 2 MEDIUM (validation cost commentary; resume scan size-only check) — accepted
- 2 LOW (bare readRDS on small startup files; bare saveRDS on tiny stats_file) — left as inconsistencies

### Why this run is the highest-stakes so far

06 will make:
- ~75,920 readRDS calls (16 reads per DOY × 365 DOYs × 13 years)
- ~19,000 saveRDS calls (4 windows × 365 DOYs × 13 years)
- Cross ~3 midnight CIFS backup windows

Without `readRDS_retry` and `saveRDS_validated`, a single midnight event could lose hundreds to thousands of DOY-windows (the 04 v2 cascade pattern that wiped 281 of 365 DOYs in year 2025). Both helpers have now survived their first real midnight crossings (03 v5 yesterday).

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
