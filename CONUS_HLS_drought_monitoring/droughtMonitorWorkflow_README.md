# CONUS HLS Drought Monitoring Workflow

## Overview
This pipeline processes HLS (Harmonized Landsat Sentinel-2) satellite data to monitor drought conditions across the Midwest DEWS domain using GAM-based vegetation anomaly detection.

## Pipeline Phases

### Phase 0: Data Acquisition ✅ COMPLETE
**Scripts:**
- `01_HLS_data_acquisition_FINAL.R` - CONUS-scale data download
- `01a_midwest_data_acquisition.R` - Midwest DEWS regional download

**Output:** Raw HLS scenes in `/data/processed_ndvi/daily/`

---

### Phase 1: Spatial Aggregation ✅ COMPLETE
**Script:** `01b_aggregate_to_4km.R`

**What it does:**
- Aggregates 30m HLS NDVI → 4km resolution using median
- Handles multi-UTM zone data via Albers Equal Area projection
- Creates timeseries for 134,666 4km pixels (2013-2024)

**Run:**
```bash
docker exec conus-hls-drought-monitor Rscript /workspace/01b_aggregate_to_4km.R
# OR with logging:
docker exec conus-hls-drought-monitor /workspace/run_phase1.sh
```

**Output:** `conus_4km_ndvi_timeseries.csv` (110 MB, 1.37M observations)

**Time:** ~3.5 hours

---

### Phase 2: Long-Term Baseline Fitting ← YOU ARE HERE
**Script:** `02_fit_longterm_baseline.R`

**What it does:**
- Fits pixel-by-pixel GAMs pooling 2013-2024 data
- Model: `NDVI ~ s(yday, k=12, bs="cc")` (cyclic cubic splines)
- Generates baseline curves for all 365 days per pixel
- Parallel processing (max 10 cores for shared server)

**Run:**
```bash
docker exec conus-hls-drought-monitor Rscript /workspace/02_fit_longterm_baseline.R
# OR with logging:
docker exec conus-hls-drought-monitor /workspace/run_phase2.sh
```

**Output:** `conus_4km_baseline.csv` (~2-3 GB, ~49M rows)

**Time:** ~30-60 minutes (with 10 cores)

---

### Phase 3: Year-Specific Models
**Script:** `03_fit_year_gams.R`

**What it does:**
- Fits GAMs for each pixel-year combination
- Uses extended DOY (adds Dec/Jan from adjacent years) to avoid edge effects
- Generates annual curves to detect year-specific patterns

**Run:**
```bash
docker exec conus-hls-drought-monitor /workspace/run_phase3.sh
```

**Output:** `conus_4km_year_splines.csv`

**Time:** ~6 hours (with 10 cores)

---

### Phase 4: Anomaly Calculation
**Script:** `04_calculate_anomalies.R`

**What it does:**
- Joins baseline and year-specific splines
- Calculates NDVI deviations from long-term normal
- Identifies vegetation stress patterns

**Run:**
```bash
docker exec conus-hls-drought-monitor /workspace/run_phase4.sh
```

**Output:** `conus_4km_anomalies.csv`

**Time:** ~5 minutes

---

### Phase 5: Drought Classification
**Script:** `05_classify_drought.R`

**What it does:**
- Applies thresholds to anomalies
- Classifies drought severity (D0-D4 categories)
- ⚠️ Currently uses placeholder thresholds (exploratory only)

**Run:**
```bash
docker exec conus-hls-drought-monitor /workspace/run_phase5.sh
```

**Output:** `conus_4km_drought_classified.csv`

**Time:** ~5 minutes

---

## Monitoring Progress

All launcher scripts (`run_phase*.sh`) create timestamped log files:
```bash
# View real-time progress
tail -f /home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring/phase*_*.log
```

---

## Key Design Decisions

### Resource Management
- **CPU Limit:** 10 cores max (shared server - leaves capacity for others)
- **Checkpointing:** All phases save progress periodically (resumable)
- **Logging:** All output captured to timestamped log files in CONUS directory

### Methodology
- **Baseline:** Pooled 2013-2024 data with cyclic splines (matches Juliana's approach)
- **Year Models:** Extended DOY ±31 days to avoid boundary artifacts
- **Terminology:** "Baseline" not "climatology" (vegetation patterns, not climate data)

### Workflow Style
- Self-contained scripts: Can be sourced (functions only) or executed (auto-run)
- Sequential numbering: 01, 02, 03... shows order of execution
- Simple launchers: Optional `run_phase*.sh` scripts for easy execution with logging

---

## Docker Configuration

Container runs as your user (308911:100) with:
- 10 CPU core limit
- 64GB memory limit
- Data mount: `/mnt/malexander/datasets/ndvi_monitor` → `/data`
- Working directory: `/workspace` (maps to this CONUS folder)

---

## Next Steps After Phase 2

1. Run Phase 2 to generate baseline curves
2. Verify baseline output quality
3. Proceed to Phase 3 for year-specific models
4. Calculate anomalies in Phase 4
5. Review drought classifications in Phase 5
