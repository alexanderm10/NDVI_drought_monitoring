# HLS Drought Monitoring Workflow

## Overview
This pipeline processes HLS (Harmonized Landsat Sentinel-2) satellite data to monitor drought conditions across the Midwest DEWS domain using GAM-based vegetation anomaly detection.

## Clean Workflow Structure

The workflow consists of sequentially numbered R scripts that can be run directly:

```
00_setup_paths.R          - Cross-platform path configuration
00_download_hls_data.R    - Phase 0: Download HLS satellite data
01_aggregate_to_4km.R     - Phase 1: Aggregate 30m → 4km with deduplication
02_fit_longterm_baseline.R - Phase 2: Fit baseline GAMs (2013-2024)
03_fit_year_gams.R        - Phase 3: Fit year-specific models
04_calculate_anomalies.R  - Phase 4: Calculate NDVI anomalies
05_classify_drought.R     - Phase 5: Classify drought severity
```

## Running the Workflow

### Prerequisites
- Docker container running: `docker compose up -d`
- NASA Earthdata credentials in `.netrc` file

### Execute Each Phase

**Phase 0: Download Data** (~12-24 hours for full acquisition)
```r
run_phase0 <- TRUE
source("00_download_hls_data.R")
```

**Phase 1: Aggregate to 4km** (~3-4 hours)
```r
run_phase1 <- TRUE
source("01_aggregate_to_4km.R")
```

**Phase 2: Fit Baseline** (~30-60 minutes with 10 cores)
```r
run_phase2 <- TRUE
source("02_fit_longterm_baseline.R")
```

**Phase 3: Fit Year Models** (~6 hours)
```r
run_phase3 <- TRUE
source("03_fit_year_gams.R")
```

**Phase 4: Calculate Anomalies** (~5 minutes)
```r
run_phase4 <- TRUE
source("04_calculate_anomalies.R")
```

**Phase 5: Classify Drought** (~5 minutes)
```r
run_phase5 <- TRUE
source("05_classify_drought.R")
```

## Data Flow

```
NASA STAC API
    ↓
Raw HLS bands (Red, NIR, Fmask)
    ↓
Processed NDVI (30m, cloud-masked)
    ↓
Aggregated 4km timeseries (deduplicated)
    ↓
Baseline GAM curves (2013-2024 pooled)
    ↓
Year-specific GAM curves
    ↓
NDVI anomalies (deviation from baseline)
    ↓
Drought classifications (D0-D4)
```

## Key Features

### Phase 0 Improvements
- **Deduplication**: Handles overlapping HLS tiles using median aggregation
- **Resumable**: Skips already-processed scenes
- **Full year coverage**: Downloads Jan-Dec (not just test months)

### Phase 1 Improvements
- **Tile overlap handling**: Median-aggregates duplicate pixel observations
- **Multi-UTM support**: Uses Albers Equal Area for consistent coordinates
- **Checkpointing**: Saves progress every 100 scenes

### Phase 2 Improvements
- **Quality control**: Minimum 20 observations per pixel required
- **Convergence checking**: Only saves successfully fitted models
- **Parallel processing**: Configurable cores (capped at 10 for shared servers)

## Important Notes

- **Scripts are workflow-style**: Set `run_phaseX <- TRUE` then source the script
- **Data requirements**: ~150GB for full HLS archive (2013-2024)
- **Processing time**: ~24-36 hours total for complete workflow
- **Docker required**: All scripts run inside Docker container

## Troubleshooting

**Download issues**: Check `.netrc` credentials and NASA Earthdata account

**Memory errors in Phase 2**: Reduce `n_cores` in config

**Missing data**: Run Phase 0 for specific years: modify `config$start_year` and `config$end_year`

## Reference Documentation

- `GAM_METHODOLOGY.md` - Statistical approach and model specifications
- `DOCKER_SETUP.md` - Container configuration details
- `README.md` - Project overview and background
