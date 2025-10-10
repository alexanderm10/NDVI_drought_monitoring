# CONUS HLS-NDVI Drought Monitoring GAM Methodology

## Overview
Pixel-by-pixel Generalized Additive Model (GAM) analysis for vegetation stress detection using Harmonized Landsat Sentinel-2 (HLS) NDVI data at 4km resolution across the Contiguous United States (CONUS).

**Spatial Coverage:** CONUS
**Spatial Resolution:** 4km (aggregated from 30m HLS)
**Temporal Coverage:** 2013-present
**Update Frequency:** Biweekly incremental updates
**Baseline Window:** Rolling complete-years-only (currently 2013-2024)

---

## Data Sources

### NASA HLS v2.0
- **Products:** HLSL30 (Landsat 8/9) and HLSS30 (Sentinel-2A/2B)
- **Harmonization:** NASA pre-processing includes:
  - BRDF normalization
  - Spectral bandpass adjustment
  - Surface reflectance atmospheric correction
- **Native Resolution:** 30m
- **Bands Used:** Red (B04), NIR (B05/B8A), Fmask (quality)

### Quality Filtering (Fmask)
Scenes excluded if Fmask flags indicate:
- Bit 1: Cloud (2)
- Bit 2: Adjacent to cloud (4)
- Bit 3: Cloud shadow (8)
- Bit 4: Snow/ice (16)
- Bit 5: Water (32)

**Implementation:**
```r
quality_mask <- (
  (fmask %% 4) < 2 &    # Bit 1 not set (cloud)
  (fmask %% 8) < 4 &    # Bit 2 not set (adjacent)
  (fmask %% 16) < 8 &   # Bit 3 not set (shadow)
  (fmask %% 32) < 16 &  # Bit 4 not set (snow/ice)
  (fmask %% 64) < 32    # Bit 5 not set (water)
)
```

---

## Analytical Workflow

### Phase 1: Spatial Aggregation (30m → 4km)

**Purpose:** Reduce computational burden while retaining spatial patterns

**Method:**
1. Create 4km grid covering CONUS extent
2. For each 4km cell, extract all 30m HLS pixels
3. Calculate **MEDIAN** NDVI (robust to outliers and residual cloud contamination)
4. Retain metadata: pixel_id, x, y, sensor, date, year, yday (day-of-year)

**Rationale for MEDIAN:**
- More robust than mean to remaining outliers after Fmask filtering
- Aligns with Juliana's Chicago spatial analysis methodology
- Reduces sensitivity to edge pixels in heterogeneous landscapes

**Output Structure:**
```
pixel_id, x, y, sensor, date, year, yday, NDVI
```

**Temporal Resolution:** Individual image dates retained (no daily aggregation)

---

### Phase 2: Climatological Norms (Complete Years Only)

**Purpose:** Establish baseline "normal" phenological patterns for anomaly detection

**Baseline Window Rules:**
- **Definition:** Rolling window of complete calendar years
- **Current (2025):** 2013-2024 (12 years)
- **Update Trigger:** When full year of data available (e.g., 2025-12-31 complete → update to 2013-2025)
- **Rationale:** Prevents seasonal bias from partial years; maintains stable reference during year

**GAM Specification:**
```r
# For each pixel_id:
gam_norm <- gam(NDVI ~ s(yday, k=12, bs="cc"), data=all_years_pooled)
```

**Parameters:**
- `s(yday, k=12)`: Cyclic cubic spline with 12 knots
- `bs="cc"`: Cyclic cubic basis (yday 1 and 365 constrained to match)
- **No edge padding** (multi-year pooling smooths year boundaries)

**Output:**
```
pixel_id, yday, norm_mean, norm_se
```
Where:
- `norm_mean`: Predicted climatological NDVI for each day-of-year
- `norm_se`: Standard error of prediction

---

### Phase 3: Year-Specific Splines with Edge Padding

**Purpose:** Characterize annual phenology for each year independently

**Edge Padding (31-day extensions):**
To prevent boundary artifacts where GAM has no information beyond year edges:

```r
# Add 31 days from previous December
prev_dec <- data %>%
  filter(year == target_year - 1, yday > 334) %>%
  mutate(year = target_year, yday = yday - 366)  # Negative DOY: -30 to 0

# Add 31 days from next January
next_jan <- data %>%
  filter(year == target_year + 1, yday <= 31) %>%
  mutate(year = target_year, yday = yday + 365)  # Extended DOY: 366-396

# Combine with target year data
year_data_padded <- bind_rows(target_year_data, prev_dec, next_jan)
```

**GAM Specification:**
```r
# For each pixel_id × year combination:
gam_year <- gam(NDVI ~ s(yday, k=12), data=year_data_padded)
```

**Prediction:**
- Fit GAM on padded data (yday range: ~-30 to ~396)
- Predict only for yday 1-365 (discard padding in output)

**Output:**
```
pixel_id, year, yday, year_mean, year_se
```

---

### Phase 4: Anomaly Calculation with Uncertainty Propagation

**Anomaly Definition:**
```
anomaly = year_mean - norm_mean
```

**Uncertainty Propagation:**
Assuming independent errors:
```
anomaly_se = sqrt(year_se^2 + norm_se^2)
```

**Statistical Significance:**
```
z_score = anomaly / anomaly_se
p_value = 2 × pnorm(-|z_score|)  # Two-tailed test
```

**Output:**
```
pixel_id, year, yday, anomaly, anomaly_se, z_score, p_value
```

**Interpretation:**
- **Negative anomaly:** Below-normal NDVI (potential vegetation stress)
- **Positive anomaly:** Above-normal NDVI (favorable conditions)
- **p < 0.05:** Statistically significant departure from climatology

---

### Phase 5: Drought Classification (TBD)

**Status:** Method under development

**Considerations:**
- Distinguish vegetation stress signal from sensor/methodological noise
- Account for spatiotemporal autocorrelation
- Integrate uncertainty bounds into classification
- Validate against USDM or other drought indicators

**Placeholder Approaches:**
1. **Significance-based:** Classify based on anomaly magnitude and p-value thresholds
2. **Percentile-based:** Use empirical distribution of anomalies across space/time
3. **Hybrid:** Combine statistical significance with percentile rankings

---

## Operational Update Workflow

### Biweekly Incremental Updates

**Steps:**
1. Download new HLS scenes from NASA (scenes from last 14 days)
2. Apply Fmask quality filtering
3. Calculate NDVI for new scenes
4. Aggregate new scenes to 4km grid (append to timeseries)
5. Refit year-specific GAMs for current year only (using updated edge padding from next year if available)
6. Recalculate anomalies for current year against existing climatology
7. Update drought classifications for current year

**DO NOT recalculate climatology** (remains stable until next complete year)

### Annual Climatology Update

**Trigger:** January 1st following completion of previous year

**Example:** On 2026-01-01 (after 2025 data complete):

**Steps:**
1. Verify 2025 dataset completeness (sufficient temporal coverage)
2. Update baseline window: 2013-2024 → 2013-2025
3. Refit all pixel climatological GAMs (Phase 2)
4. Recalculate all year-specific anomalies (Phases 3-4) for consistency
5. Archive previous climatology version with metadata

**Rationale:**
- Growing baseline improves statistical power
- Captures long-term climate trends
- Annual update frequency balances stability vs. currency

---

## Quality Control

### Scene-Level Checks
- Verify Fmask availability (100% coverage required)
- Check for band file integrity (Red, NIR, Fmask)
- Log failed downloads/processing for recovery

### Pixel-Level Checks
- Minimum observation threshold (e.g., ≥20 observations per year)
- GAM convergence diagnostics (`gam.check()`)
- Flag pixels with excessive missing data

### Anomaly-Level Checks
- Inspect spatial coherence (isolated anomalies may indicate artifacts)
- Compare to ancillary drought indicators (USDM, SPI, EDDI)

---

## Key Decisions and Rationale

### Why 4km resolution?
- Mirrors common climate datasets (PRISM, gridMET)
- Reduces from ~3 billion pixels (30m CONUS) to ~2 million pixels (4km)
- Maintains sufficient spatial detail for regional drought patterns

### Why MEDIAN aggregation?
- Robust to outliers
- Less sensitive to residual cloud contamination post-Fmask
- Follows Juliana's validated Chicago methodology

### Why complete-years-only baseline?
- Prevents seasonal bias from partial years
- Maintains stable reference for within-year comparisons
- Simplifies operational updates (no mid-year baseline recalculation)

### Why 31-day edge padding?
- Prevents GAM boundary artifacts (poor fit at yday 1 and 365)
- Provides context for phenological transitions across year boundaries
- Empirically validated in Juliana's Chicago analysis

### Why k=12 knots?
- Captures seasonal phenology (spring green-up, summer peak, fall senescence)
- Sufficient flexibility without overfitting
- Standard choice for annual vegetation cycles

### Why trust NASA HLS harmonization?
- NASA applies rigorous BRDF normalization
- Spectral bandpass adjustments align L30/S30
- Surface reflectance corrections account for atmospheric effects
- Independent validation confirms <5% sensor differences after harmonization

---

## Software Dependencies

### R Packages
- `mgcv`: GAM model fitting
- `terra`: Raster data handling (30m HLS products)
- `dplyr`, `lubridate`: Data manipulation
- `ggplot2`: Visualization

### External Tools
- NASA Earthdata Login (required for HLS downloads)
- GDAL (raster processing backend)

---

## References

### Related Work
- Juliana's Chicago spatial analysis: `spatial_analysis/` directory
- HLS User Guide: https://lpdaac.usgs.gov/documents/1698/HLS_User_Guide_V2.pdf
- Wood, S.N. (2017). *Generalized Additive Models: An Introduction with R* (2nd ed.)

### Data Citations
- NASA HLS: https://lpdaac.usgs.gov/products/hlsl30v002/
- Fmask Algorithm: Zhu et al. (2015) Remote Sensing of Environment

---

## Version History

**v1.0 (2025-01-10):**
- Initial methodology documentation
- Baseline window: 2013-2024
- CONUS 4km resolution
- Biweekly operational updates planned

---

## Contact

For questions regarding this methodology:
- See project CLAUDE.md for architectural details
- See STATUS.md for current data processing status
