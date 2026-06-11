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
