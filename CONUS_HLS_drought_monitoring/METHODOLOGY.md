# CONUS HLS-NDVI Drought Monitoring Methodology

**Complete End-to-End Pipeline Documentation**

---

## Executive Summary

This system monitors vegetation stress across the Continental United States (CONUS) using satellite-derived NDVI data from NASA's Harmonized Landsat Sentinel-2 (HLS) mission. The pipeline processes 30m resolution imagery through spatial aggregation, statistical modeling with Generalized Additive Models (GAMs), and anomaly detection to identify drought conditions.

**Key Specifications:**
- **Spatial Coverage:** CONUS (Continental United States)
- **Spatial Resolution:** 4km (aggregated from 30m HLS)
- **Temporal Coverage:** 2013-present
- **Data Sources:** Landsat 8/9 (L30) and Sentinel-2 A/B (S30)
- **Update Frequency:** Monthly incremental updates
- **Baseline Period:** 2013-2024 (rolling)

---

## Table of Contents

1. [Data Acquisition Pipeline](#1-data-acquisition-pipeline)
2. [Spatial Aggregation](#2-spatial-aggregation)
3. [Statistical Modeling](#3-statistical-modeling)
4. [Anomaly Detection](#4-anomaly-detection)
5. [Operational Workflow](#5-operational-workflow)
6. [Quality Control](#6-quality-control)
7. [Storage & Computing](#7-storage--computing)

---

## 1. Data Acquisition Pipeline

### 1.1 Data Sources

**NASA HLS v2.0 (Harmonized Landsat Sentinel-2)**
- **Products:**
  - HLSL30: Landsat 8/9 (16-day revisit, launched 2013/2021)
  - HLSS30: Sentinel-2 A/B (5-day revisit, launched 2015/2017)
- **Native Resolution:** 30m
- **Harmonization:** NASA pre-processing includes:
  - BRDF (Bidirectional Reflectance Distribution Function) normalization
  - Spectral bandpass adjustment to align L30/S30
  - Atmospheric correction to surface reflectance
- **Bands Used:**
  - Red: B04 (Landsat/Sentinel)
  - NIR: B05 (Landsat) / B8A (Sentinel)
  - Fmask: Quality assessment layer

**Data Access:**
- Source: NASA LP DAAC (Land Processes Distributed Active Archive Center)
- API: CMR STAC (Common Metadata Repository SpatioTemporal Asset Catalog)
- Authentication: NASA Earthdata Login required

### 1.2 Cloud Cover Filtering Strategy

**Scene-Level Filter:**
```r
cloud_cover_max = 100%
```

**Rationale:**
- **Traditional approach** (cloud_cover_max=40%): Discards scenes with >40% cloud cover
- **Our approach** (cloud_cover_max=100%): Downloads all scenes, relies on pixel-level QA
- **Benefit:** 7x more scenes available, +23% valid observations after Fmask filtering
- **Test results (2018):** 13.9 obs/pixel (100% threshold) vs 11.3 (40% threshold)

**Pixel-Level Quality Filtering (Fmask):**

Fmask is a bitmask where each bit represents a quality flag:
- Bit 1 (value 2): Cloud
- Bit 2 (value 4): Adjacent to cloud
- Bit 3 (value 8): Cloud shadow
- Bit 4 (value 16): Snow/ice
- Bit 5 (value 32): Water

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

Only pixels passing ALL checks are retained for NDVI calculation.

### 1.3 NDVI Calculation

**Formula:**
```r
NDVI = (NIR - Red) / (NIR + Red)
```

**Implementation:**
```r
# After Fmask filtering
red_masked <- red * quality_mask
nir_masked <- nir * quality_mask

# Calculate NDVI only for valid pixels
ndvi <- (nir_masked - red_masked) / (nir_masked + red_masked)
```

**Value Range:** -1 to +1
- **Negative values:** Water, snow, or bare surfaces
- **0 to 0.2:** Sparse vegetation
- **0.2 to 0.5:** Moderate vegetation
- **0.5 to 1.0:** Dense, healthy vegetation

### 1.4 Download Scripts

**Primary Script:** `redownload_all_years_cloud100.R`
- Calls: `01a_midwest_data_acquisition_parallel.R`
- **Parallelization:** 4 workers
- **Resume capability:** Skips existing NDVI files
- **Years:** 2013-2024 (historical); add new years as launched

**Data Organization:**
```
/data/processed_ndvi/daily/
  ├── 2013/
  │   └── HLS.L30.T15TXK.2013001T163920.v2.0_NDVI.tif
  ├── 2014/
  ├── ...
  └── 2024/
```

**File Naming Convention:**
```
HLS.{L30|S30}.T{tile}.{YYYYDDD}T{HHMMSS}.v2.0_NDVI.tif
```
Where:
- L30/S30: Landsat or Sentinel
- T{tile}: MGRS tile ID (e.g., T15TXK)
- YYYYDDD: Year and day-of-year
- HHMMSS: Acquisition time

---

## 2. Spatial Aggregation

### 2.1 Purpose

Reduce computational burden while retaining spatial drought patterns:
- **Input:** ~3 billion 30m pixels (CONUS)
- **Output:** ~145,000 4km pixels
- **Reduction factor:** ~20,000x fewer pixels

### 2.2 Aggregation Method

**Script:** `01_aggregate_to_4km_parallel.R`

**Configuration:**
```r
config <- list(
  target_resolution = 4000,        # 4km grid cells (meters)
  aggregation_method = "median",   # Robust to outliers
  min_pixels_per_cell = 5,         # Minimum 30m pixels required
  n_workers = 4,                   # Parallel processing
  batch_size = 100,                # RDS checkpointing frequency
  midwest_bbox = c(-104.5, 37.0, -82.0, 47.5)  # Spatial extent
)
```

**Workflow:**
1. Create 4km reference grid over study area bbox
2. For each 4km cell:
   - Extract all 30m HLS pixels within cell
   - Calculate **MEDIAN** NDVI (if ≥5 pixels available)
   - Store: pixel_id, x, y, sensor, date, year, yday, NDVI
3. Checkpoint every 100 scenes per worker (RDS batch files)
4. Combine batches, remove duplicates (same pixel_id + date)
5. Save final year timeseries

**Rationale for MEDIAN:**
- More robust than mean to residual outliers after Fmask
- Reduces sensitivity to edge pixels in heterogeneous landscapes
- Consistent with validated Chicago spatial analysis methodology

**Parallelization:**
- 4 workers process scenes in parallel
- Each worker writes numbered RDS batches: `worker_01_batch_0001.rds`
- Tracker file prevents reprocessing: `worker_01_processed.txt`
- Resume capability: Detects completed years, skips them

**Command-Line Usage:**
```bash
# Single year
Rscript 01_aggregate_to_4km_parallel.R 2014

# Year range
Rscript 01_aggregate_to_4km_parallel.R 2014 2016

# All years (2013-2024)
Rscript 01_aggregate_to_4km_parallel.R

# Specify worker count
Rscript 01_aggregate_to_4km_parallel.R 2014 --workers=4
```

**Output Files:**
```
/data/gam_models/aggregated_years/
  ├── ndvi_4km_2013.rds  (6.5 MB, 1.27M obs)
  ├── ndvi_4km_2014.rds  (8.3 MB, 1.58M obs)
  ├── ndvi_4km_2015.rds  (8.5 MB, 1.62M obs)
  └── ...
```

### 2.3 Data Structure

**Aggregated Timeseries Format:**
```r
# Each RDS file contains:
tibble(
  pixel_id = 1:145686,           # Unique 4km pixel identifier
  x = numeric,                    # Longitude (center of cell)
  y = numeric,                    # Latitude (center of cell)
  sensor = character,             # "L30" or "S30"
  date = Date,                    # YYYY-MM-DD
  year = integer,                 # YYYY
  yday = integer,                 # Day-of-year (1-365/366)
  NDVI = numeric                  # Median NDVI value
)
```

**Observation Density:**
- **2013:** 8.9 obs/pixel (Landsat-only year)
- **2014:** 11.2 obs/pixel
- **2015:** 11.3 obs/pixel
- **2016+:** 11-18 obs/pixel (Landsat + Sentinel)

---

## 3. Statistical Modeling

### 3.1 Overview

GAM (Generalized Additive Model) approach with two phases:
1. **Baseline norms:** Long-term climatological phenology (2013-2024 pooled)
2. **Year-specific splines:** Individual year phenology for anomaly detection

See **GAM_METHODOLOGY.md** for full statistical details.

### 3.2 Baseline Climatology

**Script:** `02_doy_looped_norms.R`

**Model Specification:**
```r
# For each pixel_id (DOY-by-DOY processing):
gam(NDVI ~ s(yday, k=12, bs="cc"), data=all_years_pooled)
```

**Parameters:**
- `s(yday, k=12)`: Cyclic cubic spline with 12 knots
- `bs="cc"`: Cyclic cubic basis (yday 1 and 365 constrained to match)
- **Data:** All years pooled (2013-2024)

**Features:**
- DOY-by-DOY parallel processing (365 DOYs)
- Incremental posterior saving (100 simulations per pixel-DOY)
- Land cover filtering (excludes water bodies: NLCD code 1)

**Outputs:**
```
/data/gam_models/
  ├── doy_looped_norms.rds           # Summary statistics (1.1 GB)
  └── baseline_posteriors/
      ├── doy_001.rds
      ├── doy_002.rds
      └── ... (365 files, 26 GB total)
```

**Runtime:** ~6-8 hours (4 cores, 96GB RAM)

### 3.3 Year-Specific Phenology

**Script:** `03_doy_looped_year_predictions.R`

**Model Specification:**
```r
# For each pixel_id × year × DOY:
gam(NDVI ~ norm + s(x, y, k=50) - 1, data=trailing_16day_window)
```

**Key Parameters:**
- `norm`: Offset from baseline climatology (from Script 02)
- `s(x, y, k=50)`: Spatial smooth with 50 basis functions
  - **Updated from k=30** based on validation testing (Jan 2026)
  - k=50 validated: 0.11% negative predictions, R²=0.698
- **Trailing window:** 16 days of observations prior to target DOY

**Features:**
- Year-by-year processing (2013-2024)
- DOY-by-DOY processing within each year
- Incremental posterior saving
- 3 cores (conservative for 96GB RAM limit)

**Outputs:**
```
/data/gam_models/
  ├── modeled_ndvi/
  │   ├── modeled_ndvi_2013.rds
  │   └── ... (12 files, 6.7 GB)
  └── year_predictions_posteriors/
      ├── 2013/doy_*.rds
      └── ... (171 GB total)
```

**Runtime:** ~1.5-2 days (3 cores, 96GB RAM)

---

## 4. Anomaly Detection

### 4.1 Anomaly Calculation

**Script:** `04_calculate_anomalies.R`

**Formula:**
```r
anomaly = year_prediction - baseline_norm
```

**Uncertainty Propagation:**
```r
# Assuming independent errors:
anomaly_se = sqrt(year_se^2 + norm_se^2)

# Statistical significance:
z_score = anomaly / anomaly_se
p_value = 2 * pnorm(-abs(z_score))  # Two-tailed test
```

**Outputs:**
```
/data/gam_models/modeled_ndvi_anomalies/
  ├── anomalies_2013.rds
  └── ... (12 files, 6.7 GB)
```

**Data Structure:**
```r
tibble(
  pixel_id, x, y, year, yday, date,
  anomaly,      # Deviation from baseline
  anomaly_se,   # Standard error
  z_score,      # Standardized anomaly
  p_value       # Statistical significance
)
```

**Interpretation:**
- **Negative anomaly:** Below-normal NDVI (vegetation stress)
- **Positive anomaly:** Above-normal NDVI (favorable conditions)
- **p < 0.05:** Statistically significant departure

**Runtime:** ~45 minutes

### 4.2 Change Rate Anomalies (Derivatives)

**Script:** `06_calculate_change_derivatives.R`

**Purpose:** Detect rapid vegetation changes (browning/greening events)

**Method:**
```r
# For each time window (3, 7, 14, 30 days):
baseline_change = baseline[day] - baseline[day - k]
year_change = year[day] - year[day - k]
change_anomaly = year_change - baseline_change
```

**Features:**
- Independent window calculation
- Posterior-based uncertainty propagation
- Statistical significance testing

**Outputs:**
```
/data/gam_models/change_derivatives/
  ├── derivatives_2013.rds
  └── ... (12 files)
```

**Runtime:** ~1.5-2 days (3 cores)

---

## 5. Operational Workflow

### 5.1 Historical Data Pipeline (Initial Setup)

**Status (Jan 2026):** In progress

**Steps:**
1. **Download HLS data** (2013-2024)
   - Script: `redownload_all_years_cloud100.R`
   - 4 parallel workers
   - ~25,000-35,000 scenes per year
   - Runtime: ~2-3 weeks total

2. **Aggregate to 4km** (year-by-year)
   - Script: `01_aggregate_to_4km_parallel.R YYYY`
   - 4 parallel workers
   - ~7-8 hours per year
   - Docker: `conus-aggregate-YYYY`

3. **Combine years into single timeseries**
   - Merge all `ndvi_4km_YYYY.rds` files
   - Remove duplicates
   - Save: `conus_4km_ndvi_timeseries.rds`

4. **Fit baseline norms** (2013-2024 pooled)
   - Script: `02_doy_looped_norms.R`
   - ~6-8 hours

5. **Fit year-specific GAMs** (2013-2024)
   - Script: `03_doy_looped_year_predictions.R`
   - ~1.5-2 days

6. **Calculate anomalies** (2013-2024)
   - Script: `04_calculate_anomalies.R`
   - ~45 minutes

### 5.2 Monthly Incremental Updates (Operational)

**Trigger:** First week of each month (after previous month completes)

**Example:** On 2026-02-05 (after January 2026 complete):

**Steps:**

1. **Download new HLS scenes**
   ```r
   # Modify acquisition script for date range:
   acquire_conus_data(
     start_date = "2026-01-01",
     end_date = "2026-01-31",
     cloud_cover_max = 100
   )
   ```
   - Runtime: ~1-2 hours (depending on scene count)

2. **Aggregate new scenes to 4km**
   ```r
   # Process only the current year
   Rscript 01_aggregate_to_4km_parallel.R 2026 --workers=4
   ```
   - Runtime: ~30 minutes (incremental)
   - Output: Updates `ndvi_4km_2026.rds`

3. **Update current year timeseries**
   ```r
   # Append new data to existing timeseries
   existing <- readRDS("conus_4km_ndvi_timeseries.rds")
   new_data <- readRDS("aggregated_years/ndvi_4km_2026.rds")

   combined <- bind_rows(existing, new_data) %>%
     distinct(pixel_id, date, .keep_all = TRUE) %>%
     arrange(pixel_id, date)

   saveRDS(combined, "conus_4km_ndvi_timeseries.rds")
   ```

4. **Refit current year GAMs**
   ```r
   # Modify Script 03 to process only 2026:
   Rscript 03_doy_looped_year_predictions.R --year=2026
   ```
   - Runtime: ~2-3 hours (single year)
   - Output: Updates `modeled_ndvi/modeled_ndvi_2026.rds`

5. **Recalculate current year anomalies**
   ```r
   # Modify Script 04 to process only 2026:
   Rscript 04_calculate_anomalies.R --year=2026
   ```
   - Runtime: ~5 minutes (single year)

**DO NOT** recalculate baseline climatology (remains stable until January 1st)

### 5.3 Annual Climatology Update

**Trigger:** January 1st following completion of previous year

**Example:** On 2027-01-01 (after 2026 data complete):

**Steps:**

1. **Verify data completeness**
   - Check temporal coverage for 2026
   - Ensure sufficient observations per pixel

2. **Update baseline window**
   - Old: 2013-2024 (12 years)
   - New: 2013-2025 (13 years)
   - Eventually: Rolling 10-15 year window (TBD)

3. **Refit baseline climatology**
   ```r
   # Re-run with updated year range:
   Rscript 02_doy_looped_norms.R
   ```
   - Runtime: ~6-8 hours
   - Output: New baseline_posteriors/

4. **Recalculate ALL year-specific anomalies**
   ```r
   # Rerun for consistency with new baseline:
   Rscript 03_doy_looped_year_predictions.R
   Rscript 04_calculate_anomalies.R
   ```
   - Runtime: ~1.5-2 days
   - Ensures temporal consistency

5. **Archive previous version**
   - Save old baseline with metadata
   - Document baseline window change

**Rationale:**
- Growing baseline improves statistical power
- Captures long-term climate trends
- Annual update balances stability vs. currency

---

## 6. Quality Control

### 6.1 Scene-Level Checks

**During Download:**
- Verify Fmask file availability (100% required)
- Check band file integrity (Red, NIR, Fmask)
- Log failed downloads for recovery
- Skip existing NDVI files (resume capability)

### 6.2 Aggregation-Level Checks

**Pixel Filtering:**
- Minimum 5 pixels per 4km cell (configurable)
- Bbox filtering: Only Midwest tiles retained
- "Failed" tiles are often outside study area (not actual failures)

**Example (2014 aggregation):**
- Total scenes: 34,487
- Success: 7,744 (tiles overlapping Midwest)
- Failed: 26,743 (tiles outside Midwest bbox - expected)

### 6.3 Model-Level Checks

**Baseline Fitting (Script 02):**
- Minimum 20 observations per pixel over baseline period
- GAM convergence diagnostics (`gam.check()`)
- Expected exclusion: ~5-7% of pixels (low data density)

**Year Fitting (Script 03):**
- Check for negative NDVI predictions (model instability)
- Validation: k=50 produces 0.11% negative (acceptable)
- Spatial coherence checks

### 6.4 Anomaly-Level Checks

**Spatial Coherence:**
- Isolated extreme anomalies may indicate artifacts
- Regional patterns expected for true drought events

**Cross-Validation:**
- Compare to USDM (US Drought Monitor)
- Compare to SPI (Standardized Precipitation Index)
- Compare to EDDI (Evaporative Demand Drought Index)

---

## 7. Storage & Computing

### 7.1 Storage Requirements

| Component | Size | Location |
|-----------|------|----------|
| Raw HLS scenes (2013-2024) | ~600 GB | `/data/processed_ndvi/daily/` |
| Aggregated 4km timeseries | ~90 MB | `/data/gam_models/aggregated_years/` |
| Baseline norms | 1.1 GB | `/data/gam_models/` |
| Baseline posteriors | 26 GB | `/data/gam_models/baseline_posteriors/` |
| Year predictions | 6.7 GB | `/data/gam_models/modeled_ndvi/` |
| Year posteriors | 171 GB | `/data/gam_models/year_predictions_posteriors/` |
| Anomalies | 6.7 GB | `/data/gam_models/modeled_ndvi_anomalies/` |
| Derivatives | ~50 GB | `/data/gam_models/change_derivatives/` |
| **Total** | **~960 GB** | |

**Annual Growth (Operational):**
- New HLS scenes: ~30-40 GB/year
- Updated posteriors: ~15 GB/year
- **Expected:** ~50 GB/year incremental

### 7.2 Computing Requirements

**Docker Container:**
```yaml
resources:
  limits:
    cpus: '10.0'
    memory: 96G
  reservations:
    cpus: '4.0'
    memory: 16G
```

**Runtime Estimates:**

| Phase | Script | Runtime | Cores | RAM |
|-------|--------|---------|-------|-----|
| Download (2013-2024) | redownload_all_years_cloud100.R | 2-3 weeks | 4 | 8GB |
| Aggregation (per year) | 01_aggregate_to_4km_parallel.R | 7-8 hours | 4 | 16GB |
| Baseline norms | 02_doy_looped_norms.R | 6-8 hours | 4 | 64GB |
| Year predictions | 03_doy_looped_year_predictions.R | 1.5-2 days | 3 | 70GB |
| Anomalies | 04_calculate_anomalies.R | 45 min | 1 | 8GB |
| Derivatives | 06_calculate_change_derivatives.R | 1.5-2 days | 3 | 70GB |
| **Full pipeline** | | **3-4 days** | | |

**Monthly Update (Operational):**
- Download new scenes: ~1-2 hours
- Aggregate new data: ~30 minutes
- Refit current year: ~2-3 hours
- **Total:** ~4-6 hours/month

### 7.3 Software Dependencies

**R Packages:**
- `mgcv`: GAM model fitting
- `terra`: Raster processing (HLS scenes)
- `dplyr`, `lubridate`: Data manipulation
- `future`, `future.apply`: Parallel processing
- `ggplot2`: Visualization

**External Tools:**
- Docker (container management)
- GDAL (raster backend for terra)
- NASA Earthdata Login (HLS downloads)

**R Version:** 4.3.0+
**OS:** Linux (Ubuntu 22.04)

---

## 8. Key Methodological Decisions

### 8.1 Why 4km Resolution?

- Reduces from ~3 billion pixels (30m) to ~145,000 (4km)
- Matches common climate datasets (PRISM, gridMET)
- Maintains sufficient detail for regional drought patterns
- Computational tractability for GAM fitting

### 8.2 Why MEDIAN Aggregation?

- Robust to outliers
- Less sensitive to residual cloud contamination
- Reduces edge pixel effects in heterogeneous landscapes
- Validated in Chicago spatial analysis

### 8.3 Why cloud_cover_max=100%?

- 7x more scenes available vs traditional 40% threshold
- +23% valid observations after Fmask filtering
- Many heavily-clouded scenes contribute valid pixels
- Pixel-level QA (Fmask) handles cloud removal

### 8.4 Why k=50 for Spatial Smooth?

- Tested k=30, k=50, k=80, k=150
- k=50 validated: R²=0.698, only 0.11% negative predictions
- Balances spatial detail vs overfitting
- Updated from k=30 based on Jan 2026 testing

### 8.5 Why Rolling Baseline Window?

- Captures long-term climate trends
- Growing baseline improves statistical power
- Annual updates balance stability vs. currency
- Complete-years-only prevents seasonal bias

---

## 9. Validation & Testing

### 9.1 Cloud Cover Test (2018)

**Setup:** Compare 40% vs 100% cloud_cover_max threshold

**Results:**
- 40% threshold: 5,150 scenes, 11.3 obs/pixel
- 100% threshold: 36,402 scenes, 13.9 obs/pixel
- **Improvement:** 7x more scenes, +23% observations

**Conclusion:** Pixel-level Fmask filtering effectively handles cloud removal

### 9.2 Spatial Basis Test (Jan 2026)

**Setup:** Test k=30, 50, 80, 150 on years 2017, 2020, 2022, 2024

**Results (k=50):**
- R² = 0.698
- RMSE = 0.089
- Negative predictions: 0.11% (acceptable)
- Normalization coefficient: 0.995

**Conclusion:** k=50 provides stable, accurate spatial smoothing

### 9.3 Min Pixels Test (Jan 2026)

**Setup:** Test min_pixels_per_cell = 5 vs 10

**Results:**
- min=5: Slightly more coverage, negligible quality impact
- min=10: Excludes some marginal pixels

**Conclusion:** min=5 balances coverage and quality

---

## 10. Future Enhancements

### 10.1 Drought Classification (TBD)

**Current Status:** Anomalies calculated, classification pending

**Proposed Approaches:**
1. **Percentile-based:** Use empirical anomaly distribution
2. **Threshold-based:** Define drought intensity categories
3. **Hybrid:** Combine statistical significance + magnitude

**Validation:** Cross-reference with USDM

### 10.2 Real-Time Monitoring Dashboard

**Components:**
- Web-based visualization of current anomalies
- Time series plots by region
- Automated weekly/monthly reports
- Email alerts for significant drought events

### 10.3 Multi-Index Integration

**Additional Indicators:**
- SPI (Standardized Precipitation Index)
- EDDI (Evaporative Demand Drought Index)
- Soil moisture data
- Crop yield forecasts

**Composite Drought Index:** Weighted combination of NDVI + climate indices

---

## References

**Data Sources:**
- NASA HLS: https://lpdaac.usgs.gov/products/hlsl30v002/
- Fmask Algorithm: Zhu et al. (2015) *Remote Sensing of Environment*

**Statistical Methods:**
- Wood, S.N. (2017). *Generalized Additive Models: An Introduction with R* (2nd ed.)
- GAM derivatives: Gavin Simpson's blog and gratia package

**Related Documentation:**
- `GAM_METHODOLOGY.md`: Detailed statistical specifications
- `WORKFLOW.md`: Script execution guide
- `DOCKER_SETUP.md`: Container configuration
- `CLAUDE.md`: AI assistant guidance

---

## Version History

**v2.0 (2026-01-29):**
- Complete end-to-end pipeline documentation
- Updated cloud cover strategy (100% threshold)
- Updated spatial basis (k=50)
- RDS checkpointing for aggregation
- Monthly operational workflow

**v1.0 (2025-01-10):**
- Initial GAM methodology (Midwest only)

---

## Contact

For questions regarding this methodology:
- See `CLAUDE.md` for architectural details
- See `RUNNING_ANALYSES.md` for current processing status
- See `GAM_METHODOLOGY.md` for statistical details
