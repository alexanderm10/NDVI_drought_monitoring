# CONUS HLS NDVI Drought Monitoring Workflow

**Purpose**: Pixel-by-pixel GAM-based drought monitoring for CONUS using HLS NDVI data

**Spatial Coverage**: Midwest DEWS region (extensible to full CONUS)
**Temporal Coverage**: 2013-2024
**Resolution**: 4km aggregated from 30m HLS
**Analysis Method**: Generalized Additive Models (GAMs) with derivative-based phenology detection

---

## Workflow Overview

This analysis follows Juliana's approach but scales from site-level to pixel-level analysis:

### Phase 0: Data Acquisition
- **Script**: `00_download_hls_data.R`
- **Output**: Raw HLS NDVI GeoTIFFs (30m resolution) organized by year
- **Status**: Currently downloading (21,307 files acquired as of 2025-10-21)

### Phase 1: Spatial Aggregation
- **Script**: `01_aggregate_to_4km.R`
- **Input**: 30m NDVI GeoTIFFs from Phase 0
- **Output**: `conus_4km_ndvi_timeseries.csv`
  - Columns: pixel_id, x, y, sensor, date, year, yday, NDVI
  - Aggregation: Median of 30m pixels → 4km grid cells
  - CRS: Albers Equal Area (EPSG:5070) for multi-UTM-zone consistency
  - Deduplication: Handles tile overlaps
- **Runtime**: ~2-4 hours
- **Features**: Checkpoint/resume capability

### Phase 2: Long-term Baseline (Climatology)
- **Script**: `02_fit_longterm_baseline.R`
- **Input**: Timeseries from Phase 1
- **Processing**: Fit pixel-by-pixel GAMs pooling 2013-2024 data
  - Model: `NDVI ~ s(yday, k=12, bs="cc")` (cyclic cubic spline)
  - Min observations: 20 per pixel
- **Output**: `conus_4km_baseline.csv`
  - Columns: pixel_id, yday (1-365), norm_mean, norm_se
  - Represents "expected" NDVI for each pixel on each day of year
- **Runtime**: ~30-60 minutes (sequential), faster with parallel
- **Features**: Checkpoint/resume, parallel processing

### Phase 3: Baseline Derivatives ⭐ NEW
- **Script**: `03_derivatives_baseline.R`
- **Input**: Timeseries from Phase 1 (refits GAMs for derivatives)
- **Processing**: Calculate derivatives of baseline climatology
  - Uses `calc.derivs()` function with 1000 posterior simulations
  - Detects significant rates of change (green-up, senescence)
- **Output**: `conus_4km_baseline_derivatives.csv`
  - Columns: pixel_id, yday, deriv_mean, deriv_lwr, deriv_upr, sig
  - sig = "*" where derivative significantly different from zero
- **Interpretation**:
  - **Positive derivatives** = green-up (increasing NDVI)
  - **Negative derivatives** = senescence (decreasing NDVI)
  - **Timing of peaks** = expected phenological transitions
- **Runtime**: ~60-90 minutes
- **Purpose**: Baseline for comparing individual year phenology

### Phase 4: Year-Specific GAMs
- **Script**: `04_fit_year_gams.R`
- **Input**: Timeseries from Phase 1
- **Processing**: Fit pixel-by-pixel GAMs for each year separately
  - Edge padding: 31 days from previous Dec & next Jan
  - Model: `NDVI ~ s(yday, k=12, bs="tp")` (thin plate spline for padded data)
  - Min observations: 15 per pixel-year
- **Output**: `conus_4km_year_splines.csv`
  - Columns: pixel_id, year, yday (1-365), year_mean, year_se
  - Represents actual NDVI for each pixel-year on each day
- **Runtime**: ~6-8 hours (highly parallelizable)
- **Features**: Checkpoint/resume, parallel processing

### Phase 5: Year-Specific Derivatives ⭐ NEW
- **Script**: `05_derivatives_individual_years.R`
- **Input**: Timeseries from Phase 1 (refits year GAMs with edge padding)
- **Processing**: Calculate derivatives for each pixel-year
  - Uses same edge padding as Phase 4
  - 1000 posterior simulations per pixel-year
- **Output**: `conus_4km_year_derivatives.csv`
  - Columns: pixel_id, year, yday, deriv_mean, deriv_lwr, deriv_upr, sig
- **Interpretation**:
  - **Compare to Phase 3 baseline** to detect timing anomalies
  - **Early senescence** (neg. derivative earlier than baseline) = drought stress
  - **Delayed green-up** (pos. derivative later than baseline) = drought impact
  - **Reduced peak rate** = weakened vegetation response
- **Runtime**: ~8-12 hours
- **Purpose**: Detect phenological timing shifts (drought indicator)

### Phase 6: Magnitude Anomalies
- **Script**: `06_calculate_anomalies.R`
- **Input**: Baseline (Phase 2) + Year splines (Phase 4)
- **Processing**: Calculate NDVI anomalies
  - Anomaly = year_mean - norm_mean
  - Uncertainty propagation: anomaly_se = sqrt(year_se² + norm_se²)
  - Z-score and significance testing
- **Output**: `conus_4km_anomalies.csv`
  - Columns: pixel_id, year, yday, anomaly, anomaly_se, z_score, p_value, is_significant
  - Also includes year_mean, year_se, norm_mean, norm_se for context
- **Runtime**: ~5 minutes (fast join operation)
- **Purpose**: Quantify magnitude of NDVI departure from normal

### Phase 7: Classification (PLACEHOLDER - NOT RECOMMENDED)
- **Script**: `07_classify_drought.R`
- **Status**: Placeholder only - threshold classification is fraught
- **Recommendation**: **Do not use** - provide anomalies and derivatives, let users interpret

---

## Utility Functions

### `00_setup_paths.R`
- Cross-platform path configuration (Windows/Linux/Docker)
- Auto-detects OS and sets appropriate data paths
- Creates directory structure

### `00_gam_utility_functions.R` ⭐ NEW
Adapted from Juliana's workflow:

1. **`post.distns()`**: Posterior distribution calculations
   - Bayesian posterior simulations for robust uncertainty
   - Uses covariance matrix to generate coefficient distributions
   - Returns mean + credible intervals
   - *Note*: Current workflow uses standard GAM predict() SE, not full posteriors
   - Available for enhanced uncertainty quantification if needed

2. **`calc.derivs()`**: Derivative calculations with significance testing
   - Finite difference approximation of first derivatives
   - Posterior simulations for derivative uncertainty
   - Significance: if lwr × upr > 0 → excludes zero → significant change
   - **Key innovation** from Juliana's work for phenology detection

---

## Output Products

### Primary Outputs (for analysis/visualization)

1. **Baseline Climatology** (`conus_4km_baseline.csv`)
   - Expected NDVI by pixel and day of year
   - Use for: anomaly calculation, comparison to individual years

2. **Baseline Derivatives** (`conus_4km_baseline_derivatives.csv`) ⭐
   - Expected phenology timing (green-up, senescence)
   - Use for: detecting timing anomalies in individual years

3. **Year-Specific Splines** (`conus_4km_year_splines.csv`)
   - Actual NDVI by pixel, year, day of year
   - Use for: anomaly calculation, visualizing actual conditions

4. **Year Derivatives** (`conus_4km_year_derivatives.csv`) ⭐
   - Actual phenology timing by year
   - Use for: **comparing to baseline derivatives to detect drought stress timing**

5. **Magnitude Anomalies** (`conus_4km_anomalies.csv`)
   - NDVI deviations from normal with uncertainty
   - Use for: quantifying drought severity, mapping anomalies

### Intermediate Products

- **Timeseries** (`conus_4km_ndvi_timeseries.csv`): Raw aggregated data
- **Checkpoints**: Auto-saved during long-running phases for crash recovery

---

## Key Differences from Original Workflow

### What We Kept from Juliana's Approach:
- ✅ GAM methodology (cyclic splines for baseline, edge-padded for years)
- ✅ Derivative analysis for phenology detection (**core innovation**)
- ✅ Posterior-based uncertainty quantification (available via `post.distns()`)
- ✅ Focus on timing anomalies, not severity thresholds

### What We Changed:
- **Scale**: Site-level → Pixel-level (thousands of pixels vs 8 sites)
- **Sensor**: Multiple Landsat missions → HLS (harmonized Landsat 8/9 + Sentinel-2)
- **Spatial**: Point extracts → 4km grid aggregation
- **Land Cover**: Separate models by LC type → Pixel-specific models
- **Derivatives**: Source baseline from Phase 2 GAMs, not separate fits

### What We Skipped:
- ❌ Drought severity classification (thresholds are problematic)
- ❌ USDM validation (Phase 5 placeholder can be developed if needed)
- ❌ Mission-specific reprojection (HLS already harmonized)

---

## Interpretation Guide

### Drought Signals to Look For:

1. **Magnitude Anomalies** (Phase 6)
   - Negative anomaly = below-normal NDVI
   - Large |z-score| + significant = statistically unusual
   - Sustained negative anomalies = drought impact

2. **Timing Anomalies** (Phase 5 vs Phase 3)
   - **Early senescence**: Year derivative turns negative earlier than baseline
   - **Delayed green-up**: Year derivative turns positive later than baseline
   - **Truncated growing season**: Earlier end + later start = drought stress
   - **Reduced peak rate**: Lower max derivative = weaker vegetation response

3. **Combined Analysis**
   - Negative magnitude anomaly + early senescence = strong drought signal
   - Normal magnitude but shifted timing = phenological stress without severe impact
   - Severe magnitude with normal timing = flash drought or sudden stress

### Example Drought Year Pattern:
```
Spring: Delayed green-up (pos. deriv starts late)
Summer: Negative NDVI anomaly (below normal greenness)
Fall: Early senescence (neg. deriv starts early)
Result: Shortened growing season + reduced productivity
```

---

## Next Steps After Data Download Completes

1. **Verify Phase 1 output** (timeseries complete and deduplicated)
2. **Run Phase 2** (baseline climatology)
3. **Run Phase 3** (baseline derivatives) - can run in parallel with Phase 4
4. **Run Phase 4** (year-specific GAMs) - can run in parallel with Phase 3
5. **Run Phase 5** (year derivatives) - requires Phase 4 complete
6. **Run Phase 6** (magnitude anomalies) - requires Phases 2 & 4

### Parallelization Strategy:
- Phases 3 & 4 can run simultaneously (both read Phase 1 output)
- Phase 5 depends on Phase 4
- Phase 6 depends on Phases 2 & 4

---

## Computational Considerations

### Memory Requirements:
- Phase 1: Moderate (one scene at a time, but many scenes)
- Phases 2-5: High (pixel-by-pixel GAM fitting)
- Phase 6: Low (simple join operation)

### Parallelization:
- Currently set to `n_cores = 1` for safety
- Can increase to `detectCores() - 1` for faster processing
- Docker container has resource limits - adjust accordingly

### Checkpointing:
- All long-running phases (1-5) have checkpoint/resume
- Safe to interrupt and restart
- Checkpoints auto-deleted on successful completion

---

## References

- **Original methodology**: Juliana's Midwest DEWS analysis (2001-2024)
- **GAM approach**: Wood (2006) Generalized Additive Models: An Introduction with R
- **Derivatives**: Gavin Simpson's blog posts on GAM derivatives
  - https://fromthebottomoftheheap.net/2016/12/15/simultaneous-interval-revisited/
  - https://github.com/gavinsimpson/random_code/blob/master/derivFun.R
- **Posterior simulations**: Simpson (2016) on simultaneous confidence intervals

---

## Contact

M. Ross Alexander
Created: 2025-10-21
Based on Juliana's Midwest DEWS drought monitoring workflow
