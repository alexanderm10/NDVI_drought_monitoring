# NDVI Drought Monitoring Workflow

## Overview
This pipeline processes HLS (Harmonized Landsat Sentinel-2) satellite data to monitor drought conditions across the Midwest DEWS domain using GAM-based vegetation anomaly detection with posterior uncertainty propagation.

## Current Workflow (DOY-Looped Approach)

The workflow uses a **day-of-year (DOY) looped** approach that processes each DOY separately in parallel, enabling:
- Memory-efficient processing of large spatial datasets
- Full posterior distribution capture for uncertainty quantification
- Incremental saving to prevent memory buildup

### Core Scripts

```
00_setup_paths.R                       - Cross-platform path configuration
00_posterior_functions.R               - Posterior simulation utilities
00_reproject_nlcd.R                    - Land cover reprojection for filtering

01_aggregate_to_4km.R                  - Aggregate 30m HLS → 4km timeseries
02_doy_looped_norms.R                  - Fit baseline GAMs by DOY (2013-2024)
03_doy_looped_year_predictions.R       - Fit year-specific GAMs by DOY
04_calculate_anomalies.R               - Calculate NDVI anomalies
05_visualize_anomalies.R               - Create time series plots and animations
06_calculate_change_derivatives.R      - Calculate rate-of-change anomalies
```

## Running the Workflow

### Prerequisites
- Docker container: `docker compose up -d`
- NASA Earthdata credentials in `.netrc`
- HLS data downloaded (scripts 00_download_*.R)
- NLCD land cover data reprojected

### Step-by-Step Execution

#### **Script 01: Aggregate HLS Data** (~3-4 hours)
```bash
docker exec conus-hls-drought-monitor Rscript 01_aggregate_to_4km.R
```
- Input: Raw 30m HLS NDVI files
- Output: 4km aggregated timeseries with cloud masking
- Output file: `conus_4km_ndvi_timeseries.rds`

#### **Script 02: Baseline Norms** (~6-8 hours, 4 cores)
```bash
docker exec conus-hls-drought-monitor Rscript 02_doy_looped_norms.R
```
- **Approach**: Processes each DOY (1-365) in parallel
- **Models**: GAMs with mission correction and temporal smoothing
- **Output**:
  - Summary statistics: `doy_looped_norms.rds` (1.1 GB)
  - Posteriors: `baseline_posteriors/doy_*.rds` (26 GB, 365 files)
  - Valid pixels: `valid_pixels_landcover_filtered.rds` (land cover mask)
- **Features**:
  - Incremental posterior saving (avoids memory buildup)
  - Land cover filtering (excludes water bodies)
  - 100 posterior simulations per pixel-DOY

#### **Script 03: Year Predictions** (~1.5-2 days, 3 cores)
```bash
docker exec conus-hls-drought-monitor Rscript 03_doy_looped_year_predictions.R
```
- **Approach**: Year-by-year, DOY-by-DOY processing
- **Models**: Spatial GAMs with 16-day trailing window
- **Output**:
  - Summary statistics: `modeled_ndvi/modeled_ndvi_YYYY.rds` (12 files, 6.7 GB)
  - Posteriors: `year_predictions_posteriors/YYYY/doy_*.rds` (171 GB)
- **Features**:
  - 3 cores (conservative for memory safety)
  - Incremental posterior saving
  - Same land cover mask as script 02

#### **Script 04: Calculate Anomalies** (~45 minutes)
```bash
docker exec conus-hls-drought-monitor Rscript 04_calculate_anomalies.R
```
- **Calculation**: anomaly = year_prediction - baseline_norm
- **Output**: `modeled_ndvi_anomalies/anomalies_YYYY.rds` (12 files, 6.7 GB)
- **Features**:
  - Land cover verification (confirms 125,798 valid pixels)
  - Uncertainty propagation (mean ± 95% CI)

#### **Script 05: Visualize Anomalies** (~15-30 minutes)
```bash
docker exec conus-hls-drought-monitor Rscript 05_visualize_anomalies.R
```
- **Outputs**:
  - Time series plots (domain-wide averages)
  - Faceted time series by year
  - Weekly anomaly maps (sample)
  - Animated GIF (full time series)
- **Location**: `/data/figures/MIDWEST/`

#### **Script 06: Change Derivatives** (~1.5-2 days, 3 cores)
```bash
docker exec conus-hls-drought-monitor Rscript 06_calculate_change_derivatives.R
```
- **Approach**: Point-to-point change using posteriors
- **Windows**: 3, 7, 14, 30-day intervals
- **Calculation**:
  ```
  baseline_change = baseline[day] - baseline[day-k]
  year_change = year[day] - year[day-k]
  change_anomaly = year_change - baseline_change
  ```
- **Output**:
  - Summary statistics: `change_derivatives/derivatives_YYYY.rds`
  - Posteriors: `change_derivatives_posteriors/YYYY/doy_XXX_window_YY.rds`
- **Features**:
  - Independent window calculation (handles missing data gracefully)
  - Statistical significance testing (95% CI exclusion)
  - Posterior probability scores

## Data Flow

```
HLS L30 (30m)
    ↓
4km NDVI timeseries (cloud-masked, deduplicated)
    ↓
Baseline GAMs (DOY-looped, 2013-2024 pooled)
    ├─ Summary stats (mean, CI)
    └─ Posteriors (100 sims × 125k pixels × 365 DOYs)
    ↓
Year-specific GAMs (DOY-looped, each year)
    ├─ Summary stats
    └─ Posteriors (100 sims × 125k pixels × ~195 DOYs × 12 years)
    ↓
NDVI Anomalies (year - baseline)
    ↓
Change Derivatives (rate of change anomalies)
    └─ 4 time windows (3, 7, 14, 30 days)
```

## Key Features

### Land Cover Filtering
- **Applied in**: Scripts 02, 03, 04, 05, 06
- **Excludes**: Water bodies (NLCD code 1)
- **Valid pixels**: 125,798 (from 145,686 total 4km pixels)
- **File**: `valid_pixels_landcover_filtered.rds`

### Posterior Distributions
- **Purpose**: Proper uncertainty propagation through all calculations
- **Simulations**: 100 per pixel-DOY
- **Storage**: xz compression, incremental saving
- **Total size**: ~200 GB (26 GB baseline + 171 GB years + derivatives)

### Memory Management
- **Strategy**: Incremental saving of posteriors, return only summaries
- **Parallelization**: Conservative core counts (3-4) to stay within 96 GB limit
- **Processing**: DOY-by-DOY (not all DOYs at once)

### Edge Case Handling
- **Year boundaries**: DOY wrapping for change derivatives
- **Missing data**: Graceful NULL returns for unavailable DOYs
- **Mission correction**: Cross-calibration for Landsat 5/7/8/9

## Storage Requirements

| Component | Size | Location |
|-----------|------|----------|
| Raw HLS data | ~150 GB | `/data/raw_hls_data/` |
| 4km timeseries | 99 MB | `/data/gam_models/` |
| Baseline posteriors | 26 GB | `/data/gam_models/baseline_posteriors/` |
| Year posteriors | 171 GB | `/data/gam_models/year_predictions_posteriors/` |
| Model outputs | 6.7 GB | `/data/gam_models/modeled_ndvi/` |
| Anomalies | 6.7 GB | `/data/gam_models/modeled_ndvi_anomalies/` |
| Derivatives | ~TBD | `/data/gam_models/change_derivatives/` |
| **Total** | **~370 GB** | |

## Runtime Estimates

| Script | Runtime | Cores | Memory |
|--------|---------|-------|--------|
| 01 | 3-4 hours | 1 | ~8 GB |
| 02 | 6-8 hours | 4 | ~64 GB peak |
| 03 | 1.5-2 days | 3 | ~70 GB peak |
| 04 | 45 minutes | 1 | ~8 GB |
| 05 | 15-30 minutes | 1 | ~12 GB |
| 06 | 1.5-2 days | 3 | ~70 GB peak |
| **Total** | **3-4 days** | | |

## Important Notes

- **Docker required**: All scripts run inside Docker container with R environment
- **Sequential execution**: Scripts must run in order (dependencies)
- **Resumable**: Scripts 02, 03, 06 can resume from checkpoints
- **Land cover consistency**: Same valid pixels used across all scripts
- **Posterior storage**: Keep posteriors for derivatives (don't delete)

## Troubleshooting

**Memory errors**:
- Reduce `n_cores` in script config
- Check Docker memory limit (should be 96 GB)

**Missing posteriors**:
- Re-run script 02 or 03 with posterior saving enabled
- Check for disk space (need ~200 GB free)

**Pixel count mismatches**:
- Verify `valid_pixels_landcover_filtered.rds` exists
- Check land cover reprojection (script 00_reproject_nlcd.R)

**Slow performance**:
- Scripts 03 and 06 are CPU-intensive (expected 1.5-2 days each)
- Monitor with `docker stats` for memory/CPU usage

## Reference Documentation

- **`GAM_METHODOLOGY.md`** - Statistical approach and model specifications
- **`DOCKER_SETUP.md`** - Container setup and configuration
- **`README.md`** - Project overview and background
- **`CLAUDE.md`** - AI assistant guidance for code modifications
- **`.archive/`** - Historical documentation (optimization logs, change logs)

## Citation

If using this workflow, please cite:
- HLS data: NASA's Harmonized Landsat Sentinel-2 project
- GAM methodology: `mgcv` package (Wood 2017)
- Posterior simulation approach: Based on Gavin Simpson's derivative functions
