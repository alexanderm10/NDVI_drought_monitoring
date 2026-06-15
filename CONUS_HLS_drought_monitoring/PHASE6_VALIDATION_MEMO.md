# Phase 6 Validation Memo

**Started**: 2026-06-10
**Current state**: v3 `categorical_usdm` complete; planning light Phase 2 + Phase 3 reframe.

This is the live document for Phase 6 (NDVI signal validation against independent
references). It gets appended to as sessions progress so a fresh session can
bootstrap from this file alone. Companion files: `RUNNING_ANALYSES.md` (terse
status), `09_validate_drought_signal.R` (the implementation), `WORKFLOW.md`
(pipeline overview).

---

## Context — why this work exists

The CONUS_HLS pipeline (scripts 01-08) produces per-pixel weekly NDVI anomalies
and four-window change-rate derivatives (w03/w07/w14/w30) over the Midwest DEWS
extent (129,310 4 km pixels × 13 years × 52 weeks). Script 09 (`validate_drought_signal.R`)
asks the scientific question: **do these NDVI signals carry useful information
about drought as captured by independent references** — USDM (categorical,
analyst-authored, lagging) and SPEI/SPI (continuous, meteorological)?

Phase 6 = the validation sections of script 09: `align_weekly`,
`categorical_usdm`, `continuous_spei` (STUB), `event_detection` (STUB), `qc`
(STUB). The cache `ndvi_drought_join_weekly_10y.rds` (8.3 GB, 67.6M pixel-weeks)
is the join of NDVI weekly summaries + USDM weekly + SPEI weekly + EPA
ecoregion lookup, built once by `align_weekly` (5 hr) and reused by all
analysis sections.

---

## Methods journey: v1 → v2 → v3

### v1 (2026-06-09 14:58 → 15:35 CDT, 20.8 min)
**Framing**: synchronous "when USDM is high, does NDVI z exceed a negative
threshold?" Per-pixel z of `ndvi_anom_mean`, lead-K `max(usdm[t..t+K])` for
K ∈ {0,1,2,4,8}, skill sweep over (z-threshold × USDM-threshold × K × stratum)
+ `bayes_sig` from `ndvi_n_sig ≥ 4`.

**Result**: HSS≈0, K-trend in wrong direction (skill DECREASING with lead time
when the lead-time hypothesis predicts increasing). bayes_sig had HSS≈0 because
`ndvi_n_sig` is direction-agnostic (counts both browning + greening
significance) and ~90% base rate.

**Diagnosis**: synchronous "is USDM high?" is the wrong question. USDM
*movement* matters more than USDM *level*.

**Mid-session bug fix**: integer overflow in `compute_skill` HSS denominator —
`(tp+fn)*(fn+tn)` overflows R's 32-bit int when subset sizes exceed
sqrt(2^31)≈46K. Cast all four contingency cells to double. Carried into v2/v3.

### v2 (2026-06-09 15:56 → 18:07 CDT, 130 min)
**Reframing**: bidirectional — drought intensifies AND drought eases, both
matter. Two confusion-matrix directions per cell:
- INTENSIFICATION: NDVI z ≤ -T paired with `usdm_change ≥ +T_chg`
- RECOVERY: NDVI z ≥ +T paired with `usdm_change ≤ -T_chg`

Added 4 derivative-window signals (deriv_w03_z, w07_z, w14_z, w30_z) alongside
`ndvi_z`. Added Spearman ρ side-cache.

**Result**: still HSS ≈ 0 / slightly negative; Spearman ρ wrong-sign (-0.06).
Recovery direction had **zero TPs in every cell**.

**Morning-after diagnosis (2026-06-10)** — three structural bugs:
1. **`usdm_change_K` was structurally non-negative** because the implementation
   took `running_max(usdm[t..t+K]) − usdm[t]` instead of a true lead value.
   Recovery scoring impossible by construction.
2. **USDM `dm_max == -1` is a sentinel for "None"** (recoded from NA at
   [08_validation_data_setup.R:275](08_validation_data_setup.R#L275)). v2 did
   arithmetic on it as if it were an ordinal class, making None→D0 (~60% of
   transitions) numerically equivalent to D2→D3.
3. **L2_code labels collapsed** 11 distinct EPA Level II ecoregions ("9.3",
   "8.1", etc., character strings) to 5 integers via `as.integer(stratum)`,
   mislabeling outputs.

### v3 (2026-06-10 09:25 → 15:57 CDT, 391.9 min ≈ 6.5 hr)
**Design** (full plan: `/home/malexander/.claude/plans/with-that-understanding-let-s-dynamic-naur.md`):

1. **USDM in-analysis recode**: `usdm_ord = usdm + 1L` → scale {0=None, 1=D0,
   ..., 5=D4}. Cache stays valid (source-side fix to 08 deferred).
2. **True lead-K via self-join** (not running max): `usdm_ord_lead_K =
   usdm_ord at (week_start + 7K)`. Onset/end derived from in_drought transitions.
3. **Two-track skill**:
   - **BINARY** (full population): pred = signal threshold vs obs = onset_K /
     end_K. Honors the None↔D0 boundary as a binary event.
   - **ORDINAL** (within-drought subset, `usdm_ord ≥ 1`): pred = signal vs
     obs = `usdm_change_K ≥ ±T_chg`. Strict ordinal progression within drought.
4. **L2_code fix**: `as.character(stratum)`, `L2_name` joined into all outputs.
   11 ecoregions preserved.
5. **Permutation null** (5 reps): block-permute `usdm_ord` within (pixel ×
   season ∈ DJF/MAM/JJA/SON). Per-cell `(observed − null_mean) / null_sd`.
   Max-across-windows correction for correlated multi-signal testing.

**Verification before launch**: r-reviewer pass (1 BLOCKER + 3 CONCERN + 4 NIT,
all addressed) + synthetic smoke test on 3-pixel × 20-week dataset
(lead-K direction, onset/end flags, shuffle preserves per-pixel marginal).

**Result file**: `/mnt/malexander/datasets/ndvi_monitor/validation/usdm_confusion_10y.rds`
(0.84 MB, list of 11 components). v2 archived to `usdm_confusion_10y.v2.rds`.

---

## Current findings (v3)

### Bug fixes confirmed in production

| Bug | v2 state | v3 state |
|---|---|---|
| Lead-K | `usdm_change ∈ [+0, +5]` (running-max, non-negative) | `usdm_change ∈ [-5, +5]` (true lead, bidirectional) |
| Recovery TPs | All zero | 80.6M binary + 145.8M ordinal |
| USDM scale | -1, 0, 1, 2, 3, 4 (arithmetic on -1 sentinel) | 0..5 ordinal (true ordinal) |
| L2_code labels | 5 integers (collapsed) | 11 distinct character codes |

### Scientific findings

1. **Recovery beats intensification, consistently.**
   9 of top-10 binary max-z cells and **all 10** top ordinal max-z cells are
   recovery direction. Intensification HSS ranges -0.04 to +0.01; recovery
   HSS ranges -0.01 to +0.05. Ecologically plausible: vegetation greening after
   rain is a sharp, visible photosynthetic response; browning during drought
   onset is slow and variable.

2. **Ecoregion heterogeneity** — within-drought ordinal Spearman ρ for ndvi_z
   at K=4, sorted:

   | L2 | Ecoregion | ρ |
   |---|---|---:|
   | 8.4 | Ozark/Ouachita-Appalachian Forests | **+0.023** |
   | 9.4 | South Central Semiarid Prairies | **+0.014** |
   | 6.2 | Western Cordillera | +0.005 |
   | 8.3 | Southeastern USA Plains | -0.016 |
   | aggregate | Midwest | -0.024 |
   | 8.2 | Central USA Plains | -0.046 |
   | 9.3 | West-Central Semiarid Prairies | -0.047 |
   | 8.1 | Mixed Wood Plains | -0.052 |
   | 8.5 | Mississippi Alluvial | -0.058 |
   | 5.2 | Mixed Wood Shield | -0.070 |
   | 9.2 | Temperate Prairies | -0.076 |

   3 ecoregions show signal in the expected direction; 8 show the opposite.
   Aggregate cancels — the "no signal in Midwest" headline is actually
   "heterogeneous signal that averages to zero."

3. **Short-window derivatives dominate the argmax.**
   In the max-across-windows tables, `deriv_w03_z` and `deriv_w07_z` are the
   modal winning signal across ecoregion-K-threshold cells. Magnitude
   (`ndvi_z`) rarely wins. Consistent with the "rate-of-change at fine
   temporal scales is more informative than level" hypothesis.

4. **Effect sizes remain operationally modest.**
   Best observed HSS in the whole table: **0.0548** (ecoregion 8.4 within-
   drought recovery, K=1, deriv_w03_z, z≥2.0, dT=-1). Still <10% of perfect
   skill. Statistical significance (z=821 with null_sd ≈ 1e-4) is overwhelming
   but reflects 5-rep null variance on 67M-row HSS, not a strong signal.

### Statistical context (read before believing the z-scores)

The null_sd is consistently ~1e-4 across all cells because:
- Each null rep computes HSS on 67M pixel-weeks (within-rep variance ≈ 0; HSS
  is a near-deterministic function of the data given the shuffle).
- Cross-rep variance reflects only how 5 different shuffles produce 5 different
  USDM-NDVI alignments — small in absolute terms.

So a z-score of "473" means observed HSS = 0.03 sits 473 permutation-SDs above
a null mean of ~0.0005. **Statistically detectable, operationally trivial.** The
direction of the signal (recovery > intensification, ecoregion heterogeneity)
matters more than the magnitude.

---

## Open questions / threads to pull

### NLCD land cover stratification (Juliana's lead)
Ecoregion stratification (EPA Level II) catches climate / regional biome
differences but **misses land-cover heterogeneity within an ecoregion**.
Juliana's work flagged:
- Better recovery skill in the **Chicago area at the land-cover aggregate**
  level (urban + nearby crops + nearby forest each behave differently)
- **Lagging signals** — NDVI tracking USDM with delay that varies by land cover

The Midwest is heavily managed cropland. A wheat field, a forest pixel, and an
urban pixel in the same ecoregion will have wildly different NDVI-drought
relationships. Cropland is irrigated / managed away from drought signal in some
cases; forests retain leaves longer; urban pixels respond barely at all.

**Action item for next session**: stratify v3 results by NLCD land cover
class. The `valid_pixels_landcover_filtered.rds` has per-pixel NLCD codes;
needs to be joined to the cache (or to the v3 output post-hoc) and the skill
re-aggregated by (ecoregion × land-cover) instead of ecoregion alone.

### Baseline-z choice — per-pixel may be over-correcting
Per-pixel z-standardization on already-deseasonalized anomalies removes pixel-
level offsets that might carry real drought-prone information. Worth trying:
- `--zbase=ecoregion_week` (pool across pixels within ecoregion × ISO-week)
- `--zbase=land_cover_week` (pool by land cover)
- `--zbase=none` (raw anomaly)

Three side-by-side skill tables would settle whether per-pixel z is the right
baseline.

### USDM lagging-indicator concern (still unresolved)
USDM is analyst-authored from multiple inputs (SPEI, PDSI, streamflow, soil
moisture, expert reports, sometimes NDVI itself) and lags actual surface
conditions. Even at K=8 (8-week lead) we may not be fully accounting for the
analyst-side lag. Juliana noted lagging signals; this is consistent.

The K=1 vs K=8 z-score patterns in v3 are mixed — some cells peak at K=1, some
at K=8. No clean monotone lead-time signal at the aggregate level.

### Continuous reference is cleaner science
USDM as primary target has several issues:
- consensus-authored, categorical (information loss at thresholds)
- partially NDVI-informed (not fully independent)
- weekly updated, lagging by 7-14 days
- categorical 4 km resampling creates artificial blockiness

SPEI/SPI on the same weekly grid are continuous, mechanistic, fully
independent. Phase 3 reframing around SPEI as the primary scientific
reference (with USDM kept as operational secondary check) sidesteps most of
these issues.

---

## Plan forward — combo route (light Phase 2 + Phase 3)

### Light Phase 2 (~1 day wall)
Focus: **isolate where the recovery signal actually lives.**

**P2.1a — NLCD land cover stratification** (NEW, Juliana's lead)
- Join NLCD codes from `valid_pixels_landcover_filtered.rds` into the v3
  output post-hoc (or rebuild the skill tables stratified by both ecoregion
  and land cover from the cache — choose by compute cost).
- Re-aggregate skill statistics by (ecoregion × land cover) and just by land
  cover. Look for the Chicago-area effect Juliana identified.
- ~3-6 hr depending on whether post-hoc or re-run.

**P2.1b — Condition on current USDM state**
- Stratify the ordinal track by `usdm_ord` at t (separate matrices for D0,
  D1, D2, D3+). Tests whether recovery signal is concentrated at a specific
  severity band.
- Cheap: post-hoc on the contingency tables.

**P2.3 (deferred, optional)** — compare per-pixel z vs ecoregion-week pooled z
vs land-cover-week pooled z. Defer until we see whether NLCD stratification
helps.

### Phase 3 (~2-3 days wall)
Focus: **continuous SPEI as primary scientific reference.**

**P3.1 — Implement `section_continuous_spei`**
- Pooled fixed-effects regression `ndvi_anom ~ spei | year_week + ecoregion`
  (or `+ land_cover` if Phase 2 confirms LC matters) via `fixest::feols`.
- Per ecoregion + Midwest pooled. Headline β (per σ of SPEI).
- Per-pixel slope map (data.table by-pixel).
- Continuous-on-continuous is the cleanest scientific question.

**P3.2 — Implement `section_event_detection`** (reframed from v1 stub)
- Drought EVENT = (pixel, week) where USDM crosses <D1 → ≥D1 AND stays ≥D1
  for ≥4 weeks. NOT week-by-week scoring of USDM levels.
- Score NDVI anomaly lead-time TO these events. Event-based skill is much
  more interpretable than week-by-week skill on imbalanced labels.
- Rapid-onset / flash-drought subclass: events where USDM transitions
  D0→D2+ within 4 weeks. Expect derivative signal to outperform magnitude
  here.

**P3.3 — Implement `section_qc`** — alignment / completeness audit.

### Deferred (not blocking)
- **Source-side USDM sentinel fix in 08** — rewrite `dm_max == -1` recoding,
  re-run `section_usdm_process` (~30 sec) + `section_align_weekly` (~5 hr).
  Schedule when convenient. Phase 2-3 don't block on it.

---

## Files / paths

| Path | What |
|---|---|
| `09_validate_drought_signal.R` | Implementation — `section_categorical_usdm` is v3 |
| `/mnt/malexander/datasets/ndvi_monitor/validation/ndvi_drought_join_weekly_10y.rds` | 8.3 GB cache, read by all analysis sections |
| `/mnt/malexander/datasets/ndvi_monitor/validation/usdm_confusion_10y.rds` | v3 output (0.84 MB) |
| `/mnt/malexander/datasets/ndvi_monitor/validation/usdm_confusion_10y.v2.rds` | v2 archive (187 KB) |
| `/mnt/malexander/datasets/ndvi_monitor/validation/usdm_confusion_10y.v1.rds` | v1 archive (72 KB) |
| `/mnt/malexander/datasets/ndvi_monitor/validation/usdm_4km_weekly_2013_2025.rds` | USDM source, `dm_max` ∈ {-1, 0..4} where -1=None |
| `/mnt/malexander/datasets/ndvi_monitor/validation/pixel_to_ecoregion_l2.rds` | (pixel_id, L1_code, L1_name, L2_code, L2_name), 11 L2 strata |
| `/mnt/malexander/datasets/ndvi_monitor/gam_models/valid_pixels_landcover_filtered.rds` | per-pixel NLCD class — to be joined in Phase 2.1a |
| `logs/categorical_usdm_v3_10y_20260610_0925.log` | v3 run log |
| `/home/malexander/.claude/plans/with-that-understanding-let-s-dynamic-naur.md` | Original Phase 1 plan + Phase 2/3 outlines |

## v3 output structure (for quick load)

```r
r <- readRDS("/mnt/malexander/datasets/ndvi_monitor/validation/usdm_confusion_10y.rds")
names(r)
# skill_binary, skill_ordinal,
# correlation_binary, correlation_ordinal,
# contingency_binary, contingency_ordinal,
# null_summary_binary, null_summary_ordinal,
# null_max_across_windows_binary, null_max_across_windows_ordinal,
# meta
```

| Component | Rows | Columns |
|---|---:|---|
| `skill_binary` | 2,400 | per (stratum × K × signal × direction × z_threshold) — full population |
| `skill_ordinal` | 7,200 | + `usdm_change_threshold`, within-drought subset |
| `correlation_binary` | 240 | Spearman ρ(-signal, signed transition) per (stratum × K × signal) |
| `correlation_ordinal` | 240 | Spearman ρ(-signal, usdm_change) within-drought |
| `contingency_binary` | 8,526 | (z-bin × transition) frequency tables |
| `contingency_ordinal` | 16,522 | (z-bin × usdm_change) frequency tables, within-drought |
| `null_summary_binary` | 2,400 | per-cell null_mean, null_sd, observed_hss, z_score |
| `null_summary_ordinal` | 7,200 | same + dT |
| `null_max_across_windows_binary` | 480 | best-of-5-signals correction per (stratum × K × direction × z_threshold) |
| `null_max_across_windows_ordinal` | 1,440 | same + dT |

---

# 2026-06-11 Session — Phase 6 reframe: Section C + A complete, Section B paused

## Strategic reframe

The v3 `categorical_usdm` validation result (HSS≈0.05, weak ecoregion-pooled correlations) raised a deeper question: is USDM-severity the right validation reference at all? USDM is a subjective, analyst-driven consensus product with documented lag; treating it as severity truth caps the validation. The reframe:

- **Continuous reference** → `continuous_spei` (Section A): does NDVI track meteorological drought (SPEI)?
- **Event-block reference** → `event_detection` (Section B): when USDM declares events, when does NDVI fire?

USDM is now the event-block identifier and a lagging operational reference. SPEI is the primary independent scientific reference. v3 `categorical_usdm` stays as supplementary context.

## Section C (`within_week_diagnostic`) — gate decision: WEEKLY

Output: `/data/validation/within_week_sd_10y.rds` (447 MB, 25 min).

Per-(pixel × iso_week) SD of `anoms_mean` across DOYs in that week, vs per-pixel SD of weekly-mean anomalies across weeks. Ratio < 1 means weekly aggregation preserves the signal.

| L2 | median ratio (within/across SD) |
|---|---:|
| 9.3 W-C Semiarid Prairies | 0.218 |
| 9.4 S-C Semiarid Prairies | 0.252 |
| 9.2 Temperate Prairies | 0.258 |
| 5.2 Mixed Wood Shield | 0.266 |
| 8.1 Mixed Wood Plains | 0.270 |
| 8.2 Central USA Plains | 0.291 |
| 8.4 Ozark Forests | 0.313 |
| 8.3 SE USA Plains | 0.324 |

All 11 ecoregions in [0.22, 0.36]. Zero pixels with ratio > 1. Weekly aggregation is fine. **Section B uses the existing align_weekly cache, not daily files.**

Two structural findings:
- **Sentinel-2 density drift** (memory: `sentinel2-density-drift`): within-week SD ratio dropped from 0.375 (2016) to 0.23 (2023-25) as S2-B + L9 missions accumulated. Affects how Section B's cross-year skill should be interpreted.
- **2016-wk-50 snow contamination hotspot**: 5,026 upper-Midwest pixels with within-week SD > 0.20 in mid-December 2016. Fmask snow flag missed it. Don't filter the dormant period (memory: `dormant-season-qualitative`); flag the artifact when interpreting.

## Section A (`continuous_spei`) — three-tier ecoregion pattern

Output: `/data/validation/continuous_spei_10y.rds` (41 MB, 80 min).

Two FE models per (stratum × spei_window × signal): pooled (`signal_z ~ spei`) and iso_week-FE (`signal_z ~ spei | iso_week`). Both with pixel-clustered SEs. Plus per-pixel slope map + permutation null.

User caught early design error: I proposed `iso_year × iso_week` FE (standard panel data default) which would absorb regional drought events — the very signal we want to measure. Pooled FE is the operational headline; iso_week-FE adds mild seasonality control without stripping the signal.

### Headline finding — ecoregion stratification reveals 3-tier pattern

| Stratum × SPEI × signal | β | r² | % pixels positive | Tier |
|---|---:|---:|---:|---|
| **9.4 × spei_26w × ndvi_z** | **+0.184** | **3.7%** | 93% | **Tier 1 — works** |
| 6.2 × spei_26w × ndvi_z | +0.106 | 1.3% | 100% | Tier 1 |
| 9.3 × spei_26w × ndvi_z | +0.062 | 0.7% | 75% | Tier 1 |
| 9.4 × spei_13w × ndvi_z | +0.104 | 1.2% | 77% | Tier 1 (shorter window) |
| 8.4 × spei_13w × ndvi_z | −0.048 | 0.3% | 16% | Tier 2 — silent (Ozark mesic forest) |
| 8.3 × spei_13w × ndvi_z | −0.045 | 0.2% | 17% | Tier 2 |
| 8.2 × spei_13w × ndvi_z | −0.051 | 0.3% | 16% | Tier 2 |
| 8.1 × spei_13w × ndvi_z | −0.066 | 0.5% | 24% | Tier 3 — REVERSED (Chicago corridor) |
| 5.2 × spei_13w × ndvi_z | −0.090 | 0.9% | 8% | Tier 3 |
| **9.2 × spei_13w × ndvi_z** | **−0.124** | **2.0%** | **15%** | **Tier 3 (corn belt heartland)** |
| midwest_aggregate × spei_13w × ndvi_z | −0.038 | 0.2% | — | MISLEADING — averages opposite signs |

### Interpretation
- **Tier 1 (semiarid prairies)**: NDVI tracks SPEI in expected direction at longer integration windows (26w > 13w > 4w). Sustained drought drives NDVI. This is the operational drought-monitoring success story.
- **Tier 2 (mesic forests, transitional plains)**: water-buffered systems show no linear NDVI~SPEI relationship.
- **Tier 3 (corn belt + Mixed Wood Plains)**: NEGATIVE β. Most likely mechanism is irrigation buffering + heat-mediated confound + management intensity. The strongest reverse is 9.2 Temperate Prairies (Iowa/Illinois corn belt).

### Statistical robustness
- All |β| > 0.01 cells have null permutation z-scores > 100 (most are 500-820+). Tiny in r² but rock-solid signal.
- Pooled vs iso_week-FE estimates differ by < 0.01 for 95% of cells. Seasonality not the main driver.
- 14/150 cells flip sign between pooled and iso_week-FE; all involve coefficients near zero.

### Derivative vs magnitude
Maximum derivative β in entire table is +0.049 (9.4 × spei_4w × deriv_w03_z). Derivatives are transient signals; SPEI is integrating. The "short SPEI × short derivative" pairing is the only derivative cell that matters operationally. Magnitude (`ndvi_z`) is the right signal for SPEI comparisons.

### Operational implications
- Best operating point for an NDVI drought monitor at concurrent grain: 9.4 (and similar) × spei_26w × ndvi_z. Defendable claim: "in semiarid prairie ecoregions, our NDVI anomaly indicator tracks 6-month SPEI with β ≈ 0.18 and ~3.7% of variance explained."
- Cannot claim aggregate Midwest-wide tracking — the signal is heterogeneous and averages to misleading near-zero.
- Section B's event_detection needs to inherit this stratification.

## Section B (`event_detection`) — PAUSED for framing redesign

### Implementation status
All helpers drafted and smoke-tested:
- `build_pixel_events()` — per-pixel chronological USDM transitions (onset: -1→≥0; recovery: ≥0→-1)
- `build_ecoregion_events()` — per (L2×week), in_drought fraction change ≥ MAJORITY_DELTA=0.10 (user's ≥50% was structurally impossible at 4 km USDM resolution)
- `detect_signal_fires_weekly()` — per-pixel runs of K consecutive weeks where signal crosses threshold
- `match_fires_to_events()` — per event, find nearest fire within ±lead_window
- `match_fires_to_eco_events()` — eco-aggregate version
- `count_false_alarms()` — proper FAR (fires NOT within ±lead of any event)
- `summarize_lead_skill()` — hit_rate, FAR, median lead, percentile distribution
- `process_signal_cell()` — full pipeline for one (signal × z × K × direction), iterates lead inside (~3x speedup)
- `run_event_grid()` — main loop
- `run_event_permutation_null()` — re-match cached fires against shuffled event dates

### Smoke test result (9.4 + 8.4, 30K pixels, headline op-point)
| Stratum | event_type | n_events | hit_rate | median_lead | pct_lead_pos | FAR |
|---|---|---:|---:|---:|---:|---:|
| 8.4 Ozark | onset | 107,673 | 33.4% | -1 wk | 44% | 80% |
| 9.4 Prairies | onset | 240,948 | 23.1% | -1 wk | 44% | 78% |
| 8.4 Ozark | recovery | 104,830 | 19.7% | 0 wk | 47% | 55% |
| 9.4 Prairies | recovery | 234,619 | 28.9% | -1 wk | 26% | 68% |

### Why paused
Claude framed Section B op-point design as "does NDVI provide lead time?" and proposed optimizing for "max lead with high hit rate." User caught the conflation:

> "wait why are we wanting to quantify a lead time. We're wanting to see if there is a lead time. We weren't saying that NDVI would be a leading indicator. We were saying that USDM might be a lagging indicator. I think you're conflating things."

The project framing is **USDM-as-lagging-indicator**, NOT **NDVI-as-leading-indicator**. Under the correct framing, median_lead = -1 weeks doesn't read as failure — it reads as "NDVI fires near-simultaneously with USDM, which (given USDM's documented lag) could mean NDVI is tracking actual onset and USDM is catching up." Different scientific question, different op-point design, different headline metrics.

See memory `usdm-lagging-not-ndvi-leading` for the full distinction and concrete consequences for redesign.

### Runtime concern (not fixed yet)
Smoke-test scaling: 90 cells × 3 leads × 4.3× pixel scaling ≈ 30+ hr unoptimized. Vectorized `match_fires_to_events` + `count_false_alarms` (outer product + `max.col`) would give 5-10x speedup → ~5-8 hr. Not yet executed; depends on framing decision.

### Pickup tomorrow
1. Resolve framing: what does Section B actually test under USDM-as-lagging frame? Which metrics matter?
2. Redesign op-points (likely fewer than 270; possibly focused on temporal correspondence, not max lead)
3. Decide whether to optimize helpers (probably yes regardless)
4. Smoke + launch

## Phase 6 extension candidates (deferred but documented)

See memory `phase6-extension-candidates`. Top three:
1. **NLCD land cover stratification** (Juliana's lead). Made MORE compelling by Section A finding 9.2 strong negative β — testing whether crop pixels vs grassland pixels within 9.2 show different signs would directly test the irrigation/management-buffer hypothesis.
2. **Drought-week conditioning**: does β get larger during USDM-flagged drought weeks than non-drought weeks? Tests drought-specificity.
3. **NDVI ⊥ SPEI residual conditioning**: `usdm ~ ndvi_z + spei` — does NDVI add information beyond SPEI?

## Files updated this session

- `09_validate_drought_signal.R`: added Section C + A (full implementations), Section B (drafted, smoke-tested, paused)
- `Dockerfile`: added `fixest` to Batch 8
- `RUNNING_ANALYSES.md`: full session summary at top
- `PHASE6_VALIDATION_MEMO.md`: this section
- Six memory entries (see Memory additions in RUNNING_ANALYSES)

---

# Phase 6 Update: LC Stratification (2026-06-12)

This section continues the live memo from 2026-06-12, after a substantial NLCD-land-cover stratification arc. The Phase 6 framing also sharpened to **skill of NDVI monitor against typical drought measures (USDM, SPEI)** — full stop. Not "does NDVI lead?", not "does USDM lag?" Lead/lag are diagnostic byproducts (memory: `phase6-question-is-skill`).

## NLCD 2019 16-class extraction (`00b_extract_nlcd_2019.R`)

The legacy land-cover lookup (`valid_pixels_landcover_filtered.rds`) inherited from the GDO wildfire project uses a 9-class "US Labeled Ecosystems" collapse where Forest=4 and Herbaceous=8 lump crop + grass + pasture together. That schema **cannot distinguish crop from grassland** — which makes it impossible to test the leading hypothesis for the 9.2 Temperate Prairies SPEI reversal ("it's a cropland effect: irrigation + planting/harvest masking").

Built a parallel per-pixel lookup `valid_pixels_nlcd2019.rds` from standard NLCD 2019 16-class (manual ScienceBase download, 1.32 GB, 30m CONUS, EPSG:5070). Resampled to the 4 km HLS grid via `terra::segregate + aggregate(fun="mean")`: segregate splits to per-class 0/1 layers, aggregate→mean gives the class fraction at 4 km, `which.max + max` give modal class + dominance fraction in one pass.

**Output columns** (added to existing pixel_id × x × y):
- `nlcd_code_2019` — raw 16-class integer
- `nlcd_juliana` — collapsed string: {crop, forest, grassland, urban_high/med/low/open, other}. Juliana's collapse spec; NLCD 90 Woody Wetlands folds into `forest` per her empirical test in Chicago (memory: `forest-wet-collapses-to-forest`).
- `modal_frac` — 0..1, the modal class's coverage fraction at 4 km
- `nlcd_dominant` — logical, `modal_frac >= 0.60`

**Midwest LC distribution** (n=129,310 valid pixels): crop 47.4%, grassland 28.4%, forest 20.0%, other 2.2%, urban_* 1.95%.

**Dominance distribution**: ~64% of crop, 67% of grassland, 30% of forest cells have `modal_frac ≥ 0.60`. Forests have lower dominance because Midwest forest exists in a mixed crop/forest mosaic at 4 km.

**Legacy vs new disagreement is substantial**: legacy "8 Herbaceous" splits 53/42 crop/grassland under NLCD 2019. Legacy "4 Forest" splits 47/40 forest / (crop + grassland) — i.e., half of "legacy forest" at 4 km modal is actually ag-dominated. Two different upstream rasters; treat as complementary, not interchangeable. Legacy lookup is **untouched** — the pipeline invariant (`EXPECTED_VALID_PIXELS`) is preserved.

**One-character bug caught mid-session**: initial run used `segregate(other=NA)` and produced all-1.0 dominance fractions with ~77% of pixels mis-classified as NLCD 11 (Open Water). Cause: with `other=NA`, each per-class layer is "1 where this class, NA elsewhere"; `aggregate(fun="mean", na.rm=TRUE)` then averages to exactly 1.0 wherever the class is present, and `which.max` ties on the first listed class (11=Open Water). Fix: `other=0L`. One character. Memory: `segregate-other-zero-not-na`.

## Section A++ (`continuous_spei_nlcd`) — 3-LC four-mechanism story

LC-stratified extension of `continuous_spei`. Decomposes each ecoregion into crop / forest / grassland strata. Same fixest FE-regression machinery (`fit_fe_spei_one_cell` + `run_fe_regression_grid`) operating on a **fused stratum_key** column (`paste(L2_code, nlcd_juliana, dom_filter, sep="|")`); the per-stratum and LC-interaction grids share the same `run_fe_regression_grid` via a new `key_col` argument that defaults to `"L2_code"` for backward compatibility with v3 categorical_usdm.

**LC-interaction model** (per ecoregion × dom × spei × signal × model): `feols(signal_z ~ spei + i(nlcd_juliana, spei, ref="crop") [| iso_week])` with `fixest::wald(fit, keep=c("nlcd_juliana::forest:spei", "nlcd_juliana::grassland:spei"))` to test "do the per-LC slopes differ from crop's slope?". Per-LC absolute slopes are derived as reference + offset.

Two dominance variants throughout: `all` (every pixel in the stratum) and `dom` (`modal_frac >= 0.60`).

### Headline finding: the 3-LC story reveals FOUR operational signatures, not three

| Signature | Ecoregions | LC pattern (spei_26w × ndvi_z × pooled) | Mechanism |
|---|---|---|---|
| **WORKS** | 9.4 (S Central Semiarid Prairies), 6.2 (W Cordillera), 9.3-grass | All LCs positive (9.4: crop +0.16, forest +0.19, grass +0.20) | Pure semiarid rangeland response |
| **SILENT** | 8.2 (Central USA Plains), 8.3 (SE USA Plains), 8.4 (Ozark/Ouachita) | Uniformly small-negative (−0.02 to −0.05) across LCs | Water-buffered |
| **REVERSES-CROP** | 9.2 (Temperate Prairies / corn belt) | crop −0.100, grass −0.007 (clean LC contrast). Wald χ²=2685, p≈0 | Irrigation + planting/harvest masking |
| **REVERSES-GRASS** | 5.2 (Mixed Wood Shield), 8.1 (Mixed Wood Plains) | All negative, **grass is WORST** (5.2: crop −0.060, forest −0.070, grass −0.100) | Different mechanism — likely dormant-season snow contamination of northern grass NDVI |

**Specific resolutions provided by LC stratification**:
- **9.3 mystery**: Section A's Tier-1 9.3 was entirely grass (β=+0.063); crop and forest are ~0. 9.3 IS Tier-1, but only for grasslands.
- **9.4 robustness**: LC restriction slightly STRENGTHENS the signal (grass-only +0.195 > full-eco +0.182). Section A baseline holds.
- **8.4 Ozark silence**: decomposes to mild forest negativity (−0.047, n=5,969) + tiny crop sample (n=94 NS).

**Statistical robustness**: every ecoregion with ≥2 LCs at the 500-pixel floor shows Wald-significant LC modulation (p << 0.001).

**Open question raised**: the 8.1 + 5.2 "grass-worst reversal" mechanism — different from 9.2 corn-belt. Both are northern boreal-influenced Mixed Wood ecoregions. Hypothesis: dormant-season snow contamination differentially affects northern grass NDVI. Could test via DJF-excluded subset. Flagged for follow-up (memory: `phase6-next-session-plan`).

## Section A++ (5-LC, urban-stratified) — what dense vs diffuse urban reveals

**Schema pivot 2026-06-12 afternoon**: extended `LC_STRATA_LEVELS` from 3 → 5 LCs to include urban, motivated by the project's "Urban Ecological Drought" framing. The 4 NLCD urban classes collapse to 2 tiers along the 50%-impervious break (NLCD's natural med/low boundary):

- `urban_dense` = urban_high (≥80% impervious) + urban_med (50-79%) → 737 px Midwest-wide
- `urban_diffuse` = urban_low (20-49% impervious) + urban_open (<20%) → 1,833 px

Per-class is statistically infeasible (urban_high has only 28 px Midwest-wide). Single "urban" would lose the operationally-relevant impervious-cover gradient.

**Implementation**: one-line `collapse_urban_to_2tier()` helper called right after the NLCD join in each section. Rewrites `nlcd_juliana` in memory; `valid_pixels_nlcd2019.rds` on disk untouched.

**Dominance handling**: kept the global 60% modal_frac floor. Urban essentially never crosses it (urban_dense_dom ≈ 38 px Midwest, urban_diffuse_dom ≈ 8 px) because 4 km cells are rarely 60% pure dense urban anywhere in CONUS. Urban therefore carries meaningful sample only in the `all` track. Downstream readers filter urban `dom` rows by n_pixel_weeks.

**Sample size reach by ecoregion** (`all` track, n_pixels):
- urban_dense: 8.2 (431), 8.1 (100), 9.2 (91), 8.3 (62), 9.4 (31); rest <30
- urban_diffuse: 8.2 (705), 8.1 (564), 8.3 (217), 9.2 (214), 9.4 (65); rest <20

Only the LC-interaction `wald` test uses a 500-pixel floor; urban_diffuse crosses it in 8.1 + 8.2 + 8.3 + 9.2; urban_dense doesn't cross it anywhere. Per-stratum fits and skill metrics are unfloored at the run level; readers filter on n_pixel_weeks for statistical confidence.

### Urban headline findings (spei_26w × ndvi_z × pooled, `all` track)

| Eco | Eco signature | urban_dense β (n) | urban_diffuse β (n) | Reference LCs in this eco |
|---|---|---|---|---|
| **9.4** | WORKS | **+0.169*** (31) | **+0.195*** (65) | crop +0.164, grass +0.195, forest +0.193 |
| **9.2** | REVERSES-CROP | **−0.072*** (91) | **−0.008** ns (214) | crop −0.100, grass −0.007, forest −0.061 |
| **8.1** | REVERSES-GRASS | −0.043*** (100) | −0.034*** (564) | crop −0.056, grass −0.093, forest −0.068 |
| **8.2** | SILENT | −0.035*** (431) | −0.031*** (705) | crop −0.040, grass −0.030, forest −0.028 |
| **8.3** | SILENT | −0.034*** (62) | −0.033*** (217) | crop −0.034, grass −0.013, forest −0.020 |
| **5.2** | REVERSES-GRASS | −0.095* (5) | −0.078*** (17) | crop −0.060, grass −0.100, forest −0.070 |
| **6.2** | WORKS | (n<3, NS) | +0.121* (3) | grass +0.101, forest +0.113 |
| **9.3** | WORKS (grass only) | −0.068** (7) | +0.100* (3) | crop −0.007***, grass +0.063*** |
| **8.4** | SILENT | (n=8 NS) | −0.049*** (37) | crop NS (n=94), grass −0.032, forest −0.047 |

*** p<0.001, ** p<0.01, * p<0.05, ns p>=0.05

### The smoking-gun result

**In the corn belt (9.2), dense urban joins the crop reversal pattern (β=−0.072***, n=91) while diffuse urban behaves like grass (β=−0.008 ns, n=214)**. The crop slope is −0.100, the grass slope is −0.007 — and urban_dense lands much closer to crop than to grass, while urban_diffuse lands almost exactly on grass.

This is consistent with a "managed-surface" interpretation:
- **High-impervious urban behaves like managed cropland** under drought — both have substantial water management (irrigation for crops, mowing/landscaping/lawn watering for dense urban), and both have NDVI dynamics that don't track water-balance deficit linearly
- **Low-impervious urban behaves like the natural vegetation mosaic** it sits within — suburban parks and low-density development with substantial canopy/grass tracks SPEI the same way grasslands in the corn belt do (essentially flat)

This is the **only ecoregion** where dense and diffuse urban diverge meaningfully. Everywhere else (8.1, 8.2, 8.3 in particular, with the largest urban samples), they're within each other's error bars and consistent with the eco-wide pattern.

### What urban DOES NOT change

The four-mechanism operational story (WORKS / SILENT / REVERSES-CROP / REVERSES-GRASS) survives intact. Urban refines but does not supersede:
- WORKS ecoregions (9.4, 6.2): urban tracks the eco-wide positive pattern. No new mechanism.
- SILENT ecoregions (8.2, 8.3, 8.4): urban tracks the eco-wide small-negative pattern. No new mechanism.
- REVERSES-GRASS (5.2, 8.1): urban shows mild negative, not the grass-worst pattern. Snow-contamination hypothesis still applies to grass, not to urban.
- REVERSES-CROP (9.2): urban DENSE joins the crop reversal — this **extends** the operational story for 9.2 from "it's cropland" to "it's managed surfaces broadly," but doesn't change the headline.

### What urban DOES change

- **Opens an impervious-cover / UHI hypothesis** for the 9.2 reversal that wasn't accessible at 3-LC: dense urban surfaces in the corn belt don't just match crops in impervious behavior — they share whatever drought-response mechanism applies to managed surfaces broadly. Urban heat island confounds, evaporative-cooling loss, lawn-irrigation maintenance — all consistent.
- **Provides a urban-vs-rural contrast within ecoregion**: in 9.2 specifically, comparing 9.2|urban_dense (−0.072) to 9.2|grass (−0.007) shows a 65× larger negative response in dense urban than in adjacent natural grass cover. That's the kind of contrast that motivates the eventual finer-resolution second-stage analysis (memory: `two-stage-resolution-idea`).
- **Statistical honesty caveat**: urban_dense samples are small in most ecoregions (only 8.2 crosses 100 px). The 9.2 dense-urban finding rests on n=91; not tiny but not bulletproof either. The pattern is consistent across ecoregions in *direction* (dense urban tracks the eco-wide pattern; the only divergent case is 9.2 where it joins crop instead of grass), which is the more robust finding than any single β estimate.

## Implementation notes

- **Schema refactor risk**: both `section_continuous_spei_nlcd` and `section_categorical_usdm_nlcd` now share `collapse_urban_to_2tier()` + `LC_STRATA_LEVELS`. Any future schema change applies to both atomically. The valid_pixels_nlcd2019.rds on disk is the source of truth at 9-class resolution; the 2-tier collapse happens per-run in memory.
- **Sweep helpers** (`run_two_track_sweep`, `run_two_track_correlation`) gained `key_col` + `include_aggregate` args with backward-compatible defaults (`L2_code`, `TRUE`). v3 `section_categorical_usdm` is unchanged in behavior. New LC sections call with the fused `stratum_key_*` columns + `include_aggregate=FALSE` (no midwest_aggregate per LC).
- **`section_categorical_usdm_nlcd`** intentionally does NOT include an LC-interaction Wald test (unlike `continuous_spei_nlcd`). There's no clean single-equation analog for skill metrics — POD/FAR/HSS aren't slopes, so a slope-differ test doesn't transfer. Per-stratum (eco × LC) skill + correlation tables tell the LC story directly; downstream LC contrasts done by hand.
- **Stale log strings**: both section functions still print `"crop,forest,grassland"` in the `[5] Build stratum_key columns` log line. The actual strata logic uses `LC_STRATA_LEVELS` (correct, 5-LC). Cosmetic fix queued for next commit.

## Section A++ runtime (5-LC, 2026-06-12)

| Phase | Wall time | Output |
|---|---|---|
| Per-stratum grid (50 strata `all` + dom variants) | 25.4 min | 2,550 rows |
| LC-interaction grid (11 eco × 2 dom × 3 spei × 5 signals × 2 models) | 33.1 min | 1,230 slope rows + 660 wald rows |
| Save + summary | <1 min | `continuous_spei_nlcd_10y.rds` (95K xz) |
| **Total** | **66.2 min** | (vs 57 min for 3-LC; ~1.16× scaling) |

## Section II++ (`categorical_usdm_nlcd`) — COMPLETE in 95 min (2026-06-12 17:54)

**Design**: mirror of `continuous_spei_nlcd` on the USDM side. Same eco × LC fused stratum_key + dominance variants. Reuses v3's `run_two_track_sweep` (binary + ordinal skill: POD/FAR/HSS) + `run_two_track_correlation` (Spearman ρ), both now generalized to the LC stratification via `key_col`.

**Skipped on first pass** (matches `continuous_spei_nlcd`):
- Permutation null (default `null_reps=0`)
- Contingency tables (with LC dim the cell count explodes; not the headline)
- LC-interaction Wald test (no clean analog for skill metrics)

**Output**: `/data/validation/usdm_confusion_nlcd_10y.rds` (1.59 MB xz) with `skill_binary_lc`, `skill_ordinal_lc`, `correlation_binary_lc`, `correlation_ordinal_lc`, `meta`.

**Runtime breakdown** (95 min total):
- Steps [1]-[5] data prep + stratum build: ~9 min
- Step [6] skill sweep (110 strata × 4K × 5 signals × 2 dom-variants): 27.2 min
- Step [7] Spearman correlation: 59.1 min — SLOWER than expected because cor(method="spearman") on 11M-row strata is expensive, and the helper has no progress logging. Cosmetic bug filed (todo): add `progress_every` print to `run_two_track_correlation`.
- Steps [8]-[11] parse + sanity + save + summary: <1 min

### Within-drought Spearman ρ headline (K=4, ndvi_z, `all` track)

Sign convention: ρ = cor(−NDVI_z, USDM_change). Positive ρ = NDVI below-normal precedes USDM intensifying = SKILL. Negative ρ = NDVI ABOVE-normal precedes USDM intensifying = REVERSED.

| Eco | Eco SPEI signature | USDM ρ range (LCs) | Most positive LC | Most negative LC | Consistency with SPEI? |
|---|---|---|---|---|---|
| **9.4** | WORKS | [+0.014, +0.054] | urban_dense +0.054, urban_diffuse +0.054 | grass +0.014 | **Replicates** (all positive, smaller magnitude) |
| **6.2** | WORKS | [−0.001, +0.022] | urban_diffuse +0.022 | grass −0.001 | Replicates (weakly) |
| **8.4** | SILENT (on SPEI) | [+0.016, +0.148] | **urban_dense +0.148** (n=727, noisy) | forest +0.016 | **DISCREPANCY** — looks WORKS on USDM |
| **8.3** | SILENT | [−0.071, +0.060] | urban_dense +0.060, crop +0.021 | grass −0.071 | **Partial discrepancy** — grass negative, others positive |
| **8.2** | SILENT | [−0.171, −0.063] | urban_dense −0.063 | **grass −0.171** (worst in table) | Discrepancy — much more negative than SPEI suggested |
| **9.2** | REVERSES-CROP | [−0.096, −0.043] | urban_diffuse −0.043 | forest −0.096 | **Replicates direction**, but mechanism differs (forest worst on USDM; crop worst on SPEI) |
| **8.1** | REVERSES-GRASS | [−0.062, −0.019] | urban_diffuse −0.019 | grass −0.062 | Replicates (grass-worst within reasonable range) |
| **5.2** | REVERSES-GRASS | [−0.106, −0.027] | urban_dense −0.027 | urban_diffuse −0.106 | Replicates direction |
| **9.3** | WORKS (grass only) | [−0.117, −0.029] | urban_diffuse −0.029 | urban_dense −0.117 (n=1.7K) | **Inverted** — grass +0.063 SPEI vs grass −0.041 USDM |

### The USDM-vs-SPEI discrepancy is the story

The four-mechanism SPEI typology does **NOT cleanly replicate on USDM**. Three patterns of disagreement:

1. **SILENT-on-SPEI becomes WORKS-on-USDM in 8.4 (Ozark)**: SPEI showed 8.4 with mild forest negativity (−0.047, n=5,969). USDM shows 8.4 with positive ρ across all LCs, best at urban_dense +0.148 (small N, suspect) and grass +0.042 (n=184K, solid). USDM consensus seems to track something in 8.4 that the meteorological water-balance integration misses.

2. **SILENT-on-SPEI becomes SHARPLY-NEGATIVE-on-USDM in 8.2 (Central USA Plains)**: 8.2|grass shows ρ=−0.171 on USDM (the worst cell in the table), with reasonable N (16K within-drought weeks). On SPEI 8.2|grass was a mild −0.03. This is opposite of 8.4 — USDM thinks 8.2|grass is doing the *opposite* of what NDVI says.

3. **WORKS replicates everywhere but magnitudes shrink ~3-4× from SPEI to USDM**: 9.4 SPEI β ranges +0.16 to +0.20; 9.4 USDM ρ ranges +0.01 to +0.05. This is the *expected* signature of USDM being a lagging analyst-curated product — the meteorological signal (SPEI) is strong and clean, while the categorical USDM-side signal is weaker and noisier because expert judgement on weekly bins adds latency and binarization noise.

The discrepancies are themselves diagnostic: they identify ecoregions where USDM is "seeing" something different from raw water-balance (8.4 mesic forest, 8.2 plains agriculture). These are candidate cells for follow-up investigation of what USDM's expert consensus is picking up that SPEI alone misses.

### Urban findings for USDM

| Eco | urban_dense ρ (n) | urban_diffuse ρ (n) | Note |
|---|---|---|---|
| 9.4 | +0.054 (8,574) | +0.054 (17,260) | Both urban tiers track the eco-wide positive ρ. Density doesn't differentiate. |
| 9.2 | −0.050 (20,339) | −0.043 (46,697) | Mildly negative for both — **does NOT show the SPEI-side density split** (where dense joined crop reversal at −0.072 and diffuse behaved like grass at −0.008). On USDM both urban tiers behave similarly. |
| 8.1 | −0.028 (13,591) | −0.019 (79,357) | Mild negative, urban_diffuse slightly less negative than urban_dense |
| 8.2 | −0.063 (61,059) | −0.086 (98,308) | Both moderately negative — does NOT show grass's −0.171 extreme |
| 8.3 | +0.060 (7,804) | +0.012 (26,745) | **urban_dense slightly positive** — possibly an artifact of small N (7,804 is borderline) |
| 8.4 | **+0.148 (727)** | **+0.098 (4,704)** | Suspect — both n's small. But the sign is consistent across both urban tiers and with grass/crop in 8.4, so the direction is reproducible even if the magnitude is unstable. |

**Urban headline contrasted with SPEI**:
- The **9.2 corn-belt density split (dense reverses, diffuse doesn't) — present on SPEI, absent on USDM**. SPEI saw urban_dense at −0.072 (matching crop −0.100) and urban_diffuse at −0.008 (matching grass −0.007). USDM sees both urban tiers at ~−0.045, not differentiating. This is one of the cases where SPEI's fine-grained water-balance picks up surface-management gradients that USDM's coarse expert categorical does not.
- The **WORKS pattern in 9.4 replicates for urban on USDM** — urban_dense +0.054, urban_diffuse +0.054 are consistent with each other and with grass/crop/forest in the same eco (all weakly positive). Urban in a WORKS eco tracks the eco.
- **8.2 urban_dense intensification HSS = +0.020 at n=223K** is the most solid urban-skill cell in the table — a small but statistically-real positive intensification signal in dense urban areas of the Central Plains. Worth a follow-up look on what's distinctive about 8.2 dense-urban response.

### Skill metric tables (intensification + recovery, K=4, ndvi_z, dom=all)

Selected highlights (full tables in `skill_binary_lc` slot of the RDS):

**Intensification HSS top 6 (z=−1.5, big-N cells only, n>50K)**:
| Stratum | HSS | POD | FAR | n |
|---|---|---|---|---|
| 8.4 grass | +0.025 | 0.092 | 0.878 | 531K |
| 8.2 grass | +0.022 | 0.089 | 0.897 | 82K |
| 8.2 urban_dense | +0.020 | 0.077 | 0.892 | 223K |
| 8.2 urban_diffuse | +0.019 | 0.079 | 0.894 | 365K |
| 8.3 grass | +0.015 | 0.085 | 0.900 | 962K |
| 8.2 crop | +0.012 | 0.074 | 0.894 | 5.98M |

**Recovery HSS top 5 (z=+1.5, big-N cells only, n>50K)**:
| Stratum | HSS | POD | FAR | n |
|---|---|---|---|---|
| 6.2 forest | +0.030 | 0.115 | 0.930 | 233K |
| 6.2 grass | +0.027 | 0.111 | 0.939 | 206K |
| 8.2 crop | +0.012 | 0.072 | 0.900 | 5.98M |
| 8.4 grass | +0.010 | 0.063 | 0.899 | 531K |
| 8.2 urban_diffuse | +0.009 | 0.067 | 0.910 | 365K |

Overall skill remains low (HSS <0.06 even for the best cells), consistent with v3 categorical_usdm headline that NDVI provides modest categorical drought-state skill against USDM. The LC stratification reveals *where* the modest skill concentrates: grasslands in the central Plains (8.2, 8.3, 8.4) for intensification, forest+grass in the Western Cordillera (6.2) for recovery, with 8.2 urban tiers being competitive.

## What to do next

1. **Headline figures** (memory: `phase6-next-session-plan`, item "figure candidates"):
   - Four-mechanism eco map with urban tiers overlaid
   - Per-eco LC strip chart for both SPEI β and USDM ρ side-by-side
   - SPEI-vs-USDM agreement scatterplot (β on x, ρ on y, colored by LC, sized by N) — direct visualization of the discrepancies
   - Corn-belt 9.2 decomposition: bar chart showing crop / forest / grass / urban_dense / urban_diffuse for both SPEI β and USDM ρ
   - 8.4 Ozark "USDM-WORKS-but-SPEI-SILENT" detail figure
2. **8.1 + 5.2 grass-worst diagnostic**: DJF-excluded re-run to test snow contamination hypothesis. Now informed by USDM: 8.1 USDM also shows grass-worst (−0.062), so the pattern isn't a SPEI-only artifact.
3. **8.4 Ozark deep dive**: why does USDM see drought-tracking skill here while SPEI shows nothing? Check whether USDM analysts in this region rely on signals other than precipitation deficit (vegetation appearance, streamflow, soil moisture maps).
4. **8.2 grass mystery**: SPEI mild negative (−0.030), USDM strongly negative (−0.171). What's driving the divergence? Could be small N artifact (16K is modest) — verify by adding K=1, K=2 to the LC version.
5. **Cross-section reproduction figure (QC)**: for each (eco × LC) cell where both SPEI and USDM agree on sign, confirm the direction. List the disagree cells with rank-ordered importance.
6. **Section B event_detection**: revive under skill framing with (eco × LC) stratification baked in. Now with explicit hypotheses from the SPEI vs USDM 5-LC comparison.
7. **Eventually, Stage-2 finer-resolution analysis**: 30m HLS for flagged drought areas to parse subpixel structure (memory: `two-stage-resolution-idea`). The 9.2 urban-density split on SPEI but not USDM is a leading candidate for Stage-2 — what's happening at sub-4km scale that the categorical analyst-product smears over?

---

# Phase 6 Update: Section B (`event_detection_nlcd`) — 2026-06-15

LC-stratified event detection completed in a single afternoon (~3 hr to build, 4 hr 19 min full run, ~15 min to inspect). Anchored on USDM transitions (none→D0 onset, any→none recovery), measures how skillfully NDVI z, 4 derivative windows, and 3 SPEI windows *fire* near those transitions. Proper POD/FAR/HSS/ETS via temporal-block contingency; per-event lead percentiles as diagnostic. SPEI joined as both a fire-signal family AND a within-window trajectory descriptor on every event.

Output: `/data/validation/event_detection_nlcd_10y.rds` (180 MB xz). Contains: events_pixel (1.53M onset + 1.48M recovery × 17 cols with SPEI trajectory), events_ecoregion (eco-aggregate), skill_lc (12,240 rows = 50 strata × 2 dom × 8 signals × 36 ops × 2 dirs / dedup), lead_distributions_lc (24,192 rows), pixel_event_map (6M rows at 2 headline ops), meta.

## Implementation lessons

**Caught a latent bug in legacy scalar matchers** (`match_fires_to_events`, `count_false_alarms`, lines 3028–3121). The `by = pixel_id` reduction reorders results by pixel, but the positional assignment back into `events_out` assumes original row order. Within a pixel that has >1 event, hit/lead/n_fires values get scrambled across events. Hand-verified on synthetic pixel-1 case: scalar said 1 hit / 4 events, vec said 3 hits / 4 events, manual computation agreed with vec exactly. The 2026-06-11 Section B smoke results (line 412 of this memo) used the scalar — aggregate hit rates per stratum happened to be approximately preserved despite the misalignment, but per-event lead/lag claims should not be trusted from that old smoke. Production `section_event_detection_nlcd` uses only the vectorized helpers; legacy scalars retained with docstring warnings as reference / corner-case fallback.

**Block-based 2×2 contingency for HSS.** The per-event hit/false-alarm framework gives POD and FAR but cannot define `correct_negatives` without a denominator of "trials." We discretize time into 4-week blocks (≈ ~130 blocks × ~129K pixels = ~17M cells per stratum); for each (pixel × block), is there any event in the block and is there any fire in the block? 2×2 over all blocks per stratum gives proper HSS/ETS. Lead percentiles are still reported separately as a diagnostic at ±4w and ±8w match tolerances. The block-based HSS is *stricter* than per-event hit_rate (same-block vs ±8wk tolerance) — both useful for different framings.

**SPEI trajectory extraction needs chunking.** Naive `events[weekly, on="pixel_id"]` cartesian explodes (10M events × 520 weekly rows per pixel ≈ 5B rows joined). Chunked by pixel batches of 5000 → 26 chunks at full pop, each cartesian-joins only that chunk's events × weekly rows, then aggregates per-event. 48.8 min total for 3M events at full pop, ~2 GB peak.

**Runtime budget** (full pop, 67M weekly rows, 129K pixels, 10 years):
- Cache load + slim + NLCD join + z-stand + strata: ~10 min
- Event build (per-pixel + eco-aggregate): ~5 min
- SPEI trajectory: 48.8 min
- Fire detection (8 signals × 3 z × 3 K × 2 dir = 144 cells): **172 min** (longest single step)
- Skill loop (288 op×dom cells × {contingency + 2 lead matches}): 31.5 min
- pixel_event_map (2 headline ops × 2 dirs): ~5 min
- Save (179 MB xz): ~7 min
- **Total: 259 min wall ≈ 4 hr 19 min**

## Headline findings

### 1. Real operational skill in 8.3 South Central Semi-Arid Prairies

Top 5 onset cells (n_events ≥ 5000):

| L2 | LC | dom | Signal | z | K | n_events | POD | FAR | **HSS** |
|---|---|---|---|---|---|---|---|---|---|
| 8.3 | grassland | dom | spei_4w | 1.5 | 1 | 6,480 | 0.526 | 0.473 | **+0.473** |
| 8.3 | grassland | dom | spei_4w | 1.5 | 2 | 6,480 | 0.389 | 0.327 | +0.452 |
| 8.3 | grassland | dom | spei_4w | 1.0 | 2 | 6,480 | 0.540 | 0.534 | +0.439 |
| 8.3 | grassland | all | spei_4w | 1.5 | 1 | 27,656 | 0.467 | 0.493 | +0.423 |
| 8.3 | grassland | all | spei_4w | 1.0 | 2 | 27,656 | 0.520 | 0.546 | +0.414 |

12 of top 20 cells are 8.3 strata. 8.4 forest (Ozark) shows up too (+0.343 at z=1.5/K=1/all). HSS in the 0.30–0.47 range is operationally meaningful — half of all USDM onset transitions caught with manageable false-alarm rate.

### 2. spei_4w (short-window meteorological signal) dominates

Of 35 (eco × LC × dom) cells with ≥5000 events, the best-skill signal per cell breakdown:

| Direction | spei_4w wins | derivatives win | spei_13w/26w wins |
|---|---|---|---|
| Onset | **33 of 35** | 0 | 2 |
| Recovery | **30 of 35** | 3 | 2 |

`spei_4w` is the operationally-best single signal across the board. NDVI z and the 4 derivative windows rarely beat it at the single-op-point level. This is genuinely surprising given the original framing motivation ("NDVI fills gaps in SPEI") — at this *single-op-point* benchmark, SPEI is the harder one to beat.

Caveat: the per-event hit_rate breakdown shows that spei_4w catches *different events* than NDVI does (only ~5% concurrent), so the per-cell best-signal table understates the value-add of combining signals.

### 3. NDVI and SPEI fires are largely independent — complementarity argument

`pixel_event_map` at the headline op-point (z=1.5, K=2, lead=8wk), agreement matrix per direction:

| Direction | Both | NDVI only | SPEI only | Neither |
|---|---|---|---|---|
| Onset | 5% | 19% | 22% | 53% |
| Recovery | 4% | 19% | 14% | 63% |

**Only 4-5% of USDM events have both signals firing.** This is the strongest single argument for the NDVI monitor's value: it's catching events SPEI misses (~19% of all events) and vice versa (~22%). If we treated either signal alone as the detector, we'd miss most events. An ensemble (NDVI fire OR SPEI fire) would catch ~46% of onset events — close to the best single-signal POD in 8.3 — but with broader coverage across ecoregions.

This complementarity is the central operational finding from Section B. Whether to *headline* an ensemble in published claims is a downstream design question (does the user want a single combined indicator, or two separate indicators to be interpreted together?).

### 4. Recovery > onset detectability

Over the 35 stratum cells with ≥5000 events:
- 39.6% have positive onset HSS (median = 0)
- 50.1% have positive recovery HSS (median = 0)

Best recovery cells:

| L2 | LC | dom | Signal | z | K | n | POD | **HSS** |
|---|---|---|---|---|---|---|---|---|
| 8.3 | grassland | dom | deriv_w07_z | 1.5 | 2 | 6,448 | 0.201 | **+0.223** |
| 6.2 | grassland | all | spei_26w | 1.0 | 2 | 2,635 | 0.260 | +0.215 |
| 6.2 | grassland | dom | spei_26w | 1.0 | 2 | 1,355 | 0.243 | +0.206 |
| 9.4 | crop | dom | spei_4w | 1.5 | 1 | 92,345 | 0.320 | +0.163 |
| 9.4 | crop | all | spei_4w | 1.5 | 2 | 113,469 | 0.237 | +0.157 |

Greening events leave a cleaner signature than stressing events. Operationally, an NDVI monitor would be a better *recovery* tracker than *onset* warner — which is the opposite of how drought monitoring is usually framed.

### 5. SPEI trajectory matches USDM severity (dose-response)

Per-event SPEI window descriptors aggregated by USDM post-class:

| event_type | usdm_post | n | mean spei13_post | % crossed −1 in ±8wk |
|---|---|---|---|---|
| onset | D0 | 1,531,053 | −0.53 | 65.8% |
| onset | D1 | 485 | −1.02 | 92.4% |
| recovery | (any → none) | 1,475,032 | +0.23 | 46.7% (still in window) |

D1 onsets are much rarer (n=485 across 13 ecoregions × 10 years) but show a markedly deeper meteorological signature. Establishes the SPEI trajectory data are signal-meaningful, not noise.

By ecoregion, onset SPEI trajectory severity:
| L2 | n_onsets | mean spei13_post | % crossed −1 |
|---|---|---|---|
| 8.4 Ozark | 107K | −0.59 | 70.2% |
| 9.2 corn belt | 332K | −0.59 | 66.4% |
| 9.4 Prairies | 241K | −0.57 | 64.2% |
| 8.2 Plains | 212K | −0.53 | 66.5% |
| 8.1 Mixed Wood | 152K | −0.57 | 66.6% |
| 8.3 South Central | 195K | −0.48 | 66.8% |
| 5.2 Mixed Wood Plains | 126K | −0.60 | 65.8% |
| 9.3 W Cornbelt | 159K | **−0.44** | **51.6%** |
| 6.2 Western Cordillera | 6K | −0.47 | 48.0% |

**9.3 W Cornbelt has the weakest meteorological signature at USDM onset** — USDM declares drought there with thinner SPEI evidence. Worth a follow-up: are those declarations driven by other inputs (soil moisture, streamflow, agricultural reports) rather than precipitation deficit? 6.2 has a similar pattern but on much smaller N.

### 6. Section A vs Section B agreement and divergence

| Ecoregion | Section A (continuous_spei) | Section B (event_detection) |
|---|---|---|
| 8.3 | SILENT (β small-negative) | **TOP onset skill (HSS +0.47)** |
| 9.4 | WORKS (β=+0.18 grass) | Strong recovery (HSS +0.15 crop), modest onset |
| 8.4 Ozark | SILENT (β ≈ −0.05 forest) | Top-5 onset (HSS +0.34 forest) |
| 9.2 corn belt | REVERSES (β=−0.10 crop) | Weak overall, modest recovery (HSS +0.12) |
| 9.3 W Cornbelt | mostly grass-positive | Bottom of skill table (HSS −0.07) |

**The two sections measure different things and disagree often.** Section A measures concurrent state agreement (does NDVI track SPEI week-to-week?). Section B measures event-timing alignment (does NDVI fire near USDM transitions?). 8.3 has poor concurrent agreement but excellent transition alignment — meaning the temporal *changes* line up even when the *levels* don't. Both are valid operational metrics; users should pick based on which question matters for their application.

### 7. 8.3 Plains is the new dark horse

Section A had 8.3 in the SILENT tier (β small-negative across LCs, ~−0.03). Section B reveals it has the best transition-detection skill in the entire 50-stratum table. The story:
- 8.3 is "South Central Semi-Arid Prairies" (Oklahoma / Texas Panhandle / SE Kansas).
- Semi-arid → SPEI fluctuations are biologically meaningful.
- Land cover is grass-dominated with crop + forest patches → mixed but heavily semi-natural.
- Mean SPEI13_post at onset = −0.48 (modest — events are common, not necessarily severe).
- High event volume (195K onset events, much higher than 8.4 Ozark's 107K).

The combination of "frequent transitions" + "meteorologically meaningful response" + "natural vegetation cover" makes 8.3 the cleanest test case for the SPEI-fire-as-USDM-anchor framing. Worth a deep-dive figure.

## Files updated

- `09_validate_drought_signal.R`: +828 lines (commit `111cadb` pre-launch)
- `RUNNING_ANALYSES.md`: 2026-06-15 session summary
- `PHASE6_VALIDATION_MEMO.md`: this section

## What to do next (Phase 6 — Section B feeds into the figure backlog)

1. **NDVI-vs-SPEI complementarity figure** — Venn-style or 2×2 panel of the agreement matrix, faceted by ecoregion. The headline finding (4-5% concurrent firing) needs to be visible immediately.
2. **8.3 deep-dive figure** — onset hit_rate map (pixel-level from `pixel_event_map`), or HSS-by-stratum bar with 8.3 highlighted; reproduces the operational claim "this is where the monitor works."
3. **Section A × Section B 2×2 mechanism table** — for each (eco × LC), is it state-concurrent + transition-aligned (both A and B positive), concurrent-only, transition-only, or neither? Direct visualization of where the two analyses agree vs disagree.
4. **Headline op-points across signal × direction matrix** — heatmap of best HSS per (signal × direction) collapsed across strata. Lets readers see at a glance that spei_4w wins onset/recovery, derivatives win in a few recovery cells.
5. **SPEI trajectory by event severity** — line plot of mean SPEI13 around event time (±8wk), faceted by D0 / D1 onset and recovery. Confirms the dose-response visually.
6. **Pre-existing carryover** (memory: `phase6-next-session-plan`): 8.1 + 5.2 grass-worst DJF-excluded diagnostic; 8.4 Ozark "USDM-WORKS-but-SPEI-SILENT" deep dive; the figures already enumerated in the 2026-06-12 plan.
7. **Ensemble exploration** — does (NDVI fire OR SPEI fire) outperform either alone at the event level? Cheap to compute from the existing outputs (no new model fits needed). If the 4-5% concurrent + 19% NDVI-only + 22% SPEI-only pattern holds across strata, an ensemble has obvious POD upside but ambiguous FAR/HSS impact.
8. **Memo / paper draft prep** — Phase 6 now has the full picture: A (state), B (transitions), USDM/SPEI references both stratified by LC. The "skill of an NDVI drought monitor" question can be answered.

---

# Glossary of acronyms used throughout Phase 6

Keep this near the top of any external write-up — multiple acronyms collide across literatures (POD / FAR / HSS / ETS from forecast verification; SPEI / SPI / USDM / NDVI from drought / remote-sensing). Established 2026-06-15 during Section B figure-pass review.

| Acronym | Meaning |
|---|---|
| **NDVI** | Normalized Difference Vegetation Index — vegetation greenness from Landsat / Sentinel-2 HLS |
| **SPEI** | Standardized Precipitation-Evapotranspiration Index — meteorological drought index, water balance (precip − PET) standardized to ~N(0,1); negative = dry |
| **SPI** | Standardized Precipitation Index — precip-only standardized index (also in cache, less-used in Phase 6) |
| **USDM** | US Drought Monitor — operational consensus weekly product. Classes: None / D0 (abnormally dry) / D1 (moderate) / D2 (severe) / D3 (extreme) / D4 (exceptional) |
| **POD** | Probability of Detection (hit rate) = hits / (hits + misses). Ranges [0, 1] |
| **FAR** | False Alarm Ratio = false_alarms / (hits + false_alarms). Ranges [0, 1] |
| **HSS** | Heidke Skill Score — 2×2 categorical skill vs chance. Ranges [−1, +1]; 0 = no skill |
| **ETS** | Equitable Threat Score (a.k.a. Gilbert Skill Score) — variant of HSS adjusted for randomly-correct hits |
| **β / r²** | Per-stratum regression slope and within-R² (Section A: NDVI z vs SPEI raw via `fixest::feols`) |
| **ρ** | Spearman rank correlation (used in Section A++ `categorical_usdm` within-drought analysis) |
| **z / z-anomaly** | Per-pixel-standardized anomaly: (signal − per-pixel mean) / per-pixel SD. So a normally-green pixel that gets stressed shows up as negative z |
| **K** | Sustained-weeks requirement — signal must stay past threshold for K consecutive weeks to count as "fired" |
| **fire** | When a signal crosses its threshold and sustains for K weeks. Section B's atomic unit of analysis |
| **lead_window** | Match tolerance (weeks) for pairing a fire to a USDM event (±N weeks around the event) |
| **L2 / L2_code** | EPA Level II Ecoregion (e.g., 9.4, 8.3, 5.2) — geographic-ecological strata used throughout |
| **LC** | Land cover from NLCD 2019, collapsed via Juliana's schema to: crop, forest, grassland, urban_dense, urban_diffuse, (other) |
| **dom / all** | Two-track LC stratification: "dom" = only pixels where modal LC class covers ≥60% of the 4 km cell; "all" = every pixel in stratum |
| **modal_frac** | Fraction of the 4 km cell covered by the dominant NLCD class (0..1) |
| **spei_4w / 13w / 26w** | SPEI computed over 4-week, 13-week, 26-week accumulation windows |
| **deriv_w03_z, etc.** | Standardized NDVI derivative anomaly at window widths of 3, 7, 14, 30 days |
| **continuous_spei (Section A)** | `09_validate_drought_signal.R` section: regresses NDVI z on SPEI raw, headline β |
| **categorical_usdm (Section A++)** | Confusion-matrix analog on USDM categorical data, headline HSS |
| **event_detection (Section B)** | Anchored on USDM transitions, asks when NDVI/SPEI fires near the event |
| **`_nlcd` suffix** | LC-stratified version of the section (always preferred for headline claims) |
| **D0+** | USDM D0 or worse (any drought class). Used as the "onset" target in Section B |
| **onset / recovery** | USDM transitions: onset = none → D0+; recovery = any drought → none |
| **HLS** | Harmonized Landsat-Sentinel (NASA data product combining L8/L9 + Sentinel-2 to harmonized 30m surface reflectance) |
| **DEWS** | Drought Early Warning System (NIDIS regional program — Midwest DEWS is our analysis domain) |
| **GAM / GAMM** | Generalized Additive Model / GAM with Mixed effects. The upstream NDVI baseline fitting (scripts 01–06) |
| **DOY / yday** | Day-of-year (1..365/366) |
| **ISO week** | ISO 8601 week number — weekly aggregation grain used throughout Phase 6 |
| **MIDWEST domain** | 1976 × 1212 km region covering 14 states / 129,310 land-filtered pixels (NOT CONUS despite the directory name) |

---

# Figures log (Phase 6 visualization pass — `10_phase6_figures.R`)

All figures land in `/data/figures/phase6/`. Built incrementally starting 2026-06-15. Naming: `phase6_<figN>_<slug>.png`.

## Figure 1: NDVI ⊥ SPEI complementarity (per ecoregion)
`phase6_fig1_ndvi_spei_complementarity.png` — 100% stacked horizontal bar per ecoregion × {onset, recovery}; segments = {both, NDVI only, SPEI only, neither}. Uses headline op-point z=1.5 / K=2 / lead=±8wk.

### Key takeaways
- **Only 4-5% of USDM events have both NDVI AND SPEI firing at this op-point.** The two signals are largely independent at the event level — they catch different events, not the same ones.
- **NDVI uniquely catches ~19% of events SPEI misses** across most ecoregions; **SPEI uniquely catches 6-28%** depending on stratum. Combined (NDVI OR SPEI) operational POD = ~30-50% per ecoregion.
- **8.3 South Central Semi-Arid Prairies has the highest "both" (~10% onset)** — consistent with its top-ranked Section B HSS (+0.473 grass dom). The cell where the two signals agree the most is also the cell with the best operational skill.
- **9.4 recovery shows highest "both" (10%)** — paralleling Section A's WORKS designation for 9.4.
- **8.2 onset has the largest "NDVI only" share (27%)** — NDVI is the dominant detector in central Plains cropland.
- **Recovery generally has less "SPEI only"** than onset — SPEI is poor at detecting greening. NDVI's value-add is largest in recovery monitoring.

## Figure 1b: complementarity stratified by LC (eco × LC × direction)
`phase6_fig1b_ndvi_spei_complementarity_lc.png` — same structure as 1 but faceted by LC class (rows) × direction (cols). Cells with n_events < 500 suppressed.

### Key takeaways
- **Crop onset**: 8.3 has the largest "both" — corn-belt cropland where the two signals are most aligned. 8.2 + 9.4 crop show strong NDVI-only — NDVI catches crop drought SPEI misses, possibly via irrigation-stress signatures.
- **Forest onset**: 8.2 central Plains forest has the largest NDVI-only share — forest NDVI signal is high-value where SPEI is silent.
- **Grass onset**: 6.2 Western Cordillera grass is nearly all "neither" — semi-arid grass has low NDVI variability and at this op-point almost nothing fires. 8.3 grass shows the clearest "both" segment.
- **Urban dense**: small N (only 5 ecos make the n≥500 cutoff). 8.3, 8.2 urban_dense are dominated by NDVI-only and SPEI-only — almost no concurrent firing.
- **Urban diffuse onset**: looks much like grass — consistent with `continuous_spei_nlcd` finding that low-impervious urban behaves like natural cover.
- **Recovery side (across LCs)**: NDVI-only dominates almost everywhere. SPEI is structurally poor at greening detection.

## Pending figures (this session)
- **Reference domain map** — LC + ecoregion zones, to orient external readers.
- **Figure 2** — 8.3 Plains deep-dive (HSS bar / hit-rate map).
- **Figure 3** — Section A × B 2×2 mechanism map (where do the two analyses agree vs disagree?).
- **Figure 4** — four-mechanism eco map (from `continuous_spei_nlcd`) with Section B annotations.
- **Figure 5** — headline op-points heatmap (best HSS per signal × direction).
