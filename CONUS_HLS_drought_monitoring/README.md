# CONUS HLS Drought Monitoring Pipeline

Monitors vegetation stress across the Continental United States using NDVI data from NASA's Harmonized Landsat Sentinel-2 (HLS) mission. Processes 30m HLS imagery through spatial aggregation, GAM-based modeling, and anomaly detection to identify drought conditions at 4km resolution.

**Coverage:** CONUS | **Resolution:** 4km | **Baseline:** 2013–present | **Update:** Monthly

---

## Documentation

| Document | Purpose |
|----------|---------|
| [WORKFLOW.md](WORKFLOW.md) | Step-by-step pipeline execution, runtime estimates, troubleshooting |
| [GAM_METHODOLOGY.md](GAM_METHODOLOGY.md) | Statistical approach, model specifications, posterior simulation |
| [RUNNING_ANALYSES.md](RUNNING_ANALYSES.md) | Current pipeline status and data inventory |
| [DOCKER_SETUP.md](DOCKER_SETUP.md) | Container configuration and setup |

---

## Pipeline Overview

```
HLS scenes (30m)
    ↓  01_aggregate_to_4km_parallel.R
4km NDVI timeseries
    ↓  02_doy_looped_norms.R
Baseline climatology (2013–present, pooled)
    ↓  03_doy_looped_year_predictions.R
Year-specific predictions
    ↓  04_calculate_anomalies.R
NDVI anomalies
    ↓  06_calculate_change_derivatives.R
Rate-of-change anomalies
```

See [WORKFLOW.md](WORKFLOW.md) for full execution instructions.

---

## Quick Start

```bash
# Start container
docker compose up -d

# Run full pipeline (scripts must execute in order)
docker exec conus-hls-drought-monitor Rscript 01_aggregate_to_4km_parallel.R \
  --workers=8 --tiles=bulk_downloads/midwest_tiles_overlapping.txt
docker exec conus-hls-drought-monitor Rscript 01b_combine_year_files.R
docker exec conus-hls-drought-monitor Rscript 02_doy_looped_norms.R
docker exec conus-hls-drought-monitor Rscript 03_doy_looped_year_predictions.R
docker exec conus-hls-drought-monitor Rscript 04_calculate_anomalies.R
docker exec conus-hls-drought-monitor Rscript 05a_timeseries_quick.R
docker exec conus-hls-drought-monitor Rscript 05b_animation_maps.R
docker exec conus-hls-drought-monitor Rscript 05c_create_yearly_gifs.R
docker exec conus-hls-drought-monitor Rscript 06_calculate_change_derivatives.R
docker exec conus-hls-drought-monitor Rscript 07_visualize_derivatives.R
```

## Data

- **Raw HLS:** `/mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/YYYY/`
- **GAM outputs:** `/mnt/malexander/datasets/ndvi_monitor/gam_models/`
- **Figures:** `/mnt/malexander/datasets/ndvi_monitor/figures/`
