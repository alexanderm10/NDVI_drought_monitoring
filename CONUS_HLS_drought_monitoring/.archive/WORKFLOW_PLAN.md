# HLS Spatial Drought Monitoring Workflow Plan

## Current Status (as of session end)

### Completed:
✅ Downloaded HLS L30/S30 data for Midwest DEWS (2013-2024, 12 tiles)
✅ Calculated initial NDVI (without quality filtering)
✅ Ran sensor diagnostic - identified 25% L30/S30 difference due to clouds/snow
✅ Updated download code to include Fmask quality layers
✅ Created retroactive Fmask download script
✅ Created NDVI reprocessing script with quality filtering

### In Progress:
🔄 Running Fmask download for existing data (~2-5 GB, 30-60 min)

### Next Immediate Steps:
1. Complete Fmask download
2. Reprocess NDVI with quality masks (30-60 min)
3. Re-run sensor diagnostic (expect <5% difference after cleaning)

---

## Post-Fmask Implementation Workflow

### Phase 1: Data Validation & Sensor Decision
**Goal**: Determine if sensor correction is needed

**Step 1: Re-run diagnostic with clean NDVI**
```r
source("CONUS_HLS_drought_monitoring/diagnostic_hls_sensor_comparison.R")
results <- run_hls_sensor_diagnostic()
```

- Expected: L30/S30 difference drops from 25% to <5%
- **Decision point**:
  - If <5%: Skip sensor correction, combine L30+S30 directly ✅
  - If >5%: Implement pixel-by-pixel sensor GAMs ⚠️

---

### Phase 2: Spatial Aggregation to 4km
**Goal**: Reduce from 30m (~millions of pixels) to 4km (~3,000-5,000 pixels) for manageable GAM processing

**Step 2: Aggregate NDVI to 4km grid**
- Method: Median aggregation (133×133 pixels → 1 4km pixel)
- Why median: Robust to remaining cloud artifacts
- Output structure: Midwest ~3,000-5,000 4km pixels
- Integration-ready: Matches PRISM, Daymet, gridMET, USDM resolution

**Step 3: Create 4km pixel dataframe**
- Structure: `(pixel_id, x, y, date, ndvi, sensor, year, yday)`
- Similar to Juliana's spatial_analysis approach but at 4km instead of 30m
- Saves as CSV for GAM analysis

**Script to develop**: `CONUS_HLS_drought_monitoring/aggregate_to_4km.R`

---

### Phase 3: Temporal GAM Modeling
**Goal**: Calculate climatology and anomalies (following Juliana's spatial workflow)

**Step 4: Sensor harmonization (if needed)**
- Only if diagnostic shows >5% difference
- 4km pixel-level GAMs: `NDVI ~ s(yday, k=12, by=sensor) + sensor`
- Reproject S30 to L30 reference
- Save reprojected NDVI

**Step 5: Calculate 4km climatological norms (2013-2024)**
- Per-pixel GAM: `NDVIReprojected ~ s(yday, k=12, bs="cc")`
- Cyclic cubic spline for smooth annual cycle
- Output: 365-day normal curve for each 4km pixel
- Save: `(pixel_id, x, y, yday, norm_mean, norm_lwr, norm_upr)`

**Step 6: Fit year-specific splines**
- Per-pixel, per-year GAM: `NDVIReprojected ~ s(yday, k=12)`
- With Dec/Jan edge padding to avoid boundary effects
- Output: `(pixel_id, x, y, year, yday, year_mean, year_lwr, year_upr)`

**Step 7: Calculate anomalies**
- `anomaly_mean = year_mean - norm_mean`
- `anomaly_lwr = year_lwr - norm_lwr`
- `anomaly_upr = year_upr - norm_upr`
- Propagate uncertainty through calculations

**Scripts to develop**:
- `03_4km_sensor_correction.R` (if needed)
- `04_4km_climatology_norms.R`
- `05_4km_year_splines.R`
- `06_4km_anomalies.R`

---

### Phase 4: Drought Product Generation
**Goal**: Create operational drought maps

**Step 8: Generate drought severity classifications**
- Classify anomalies into drought categories
- Potential scheme (similar to USDM):
  - D0 (Abnormally Dry): anomaly < -0.05
  - D1 (Moderate): anomaly < -0.10
  - D2 (Severe): anomaly < -0.15
  - D3 (Extreme): anomaly < -0.20
  - D4 (Exceptional): anomaly < -0.25
- Consider statistical significance using uncertainty bounds

**Step 9: Export as rasters/maps**
- Convert dataframe back to 4km rasters
- Daily/weekly 4km drought maps
- GeoTIFF exports for GIS integration
- Optional: Generate high-res 30m anomaly maps for specific dates of interest

**Step 10: Validation against USDM** (optional)
- Spatial correlation with US Drought Monitor
- Time series comparison
- Document agreements/disagreements

**Scripts to develop**:
- `07_drought_classification.R`
- `08_export_drought_maps.R`
- `09_usdm_validation.R` (optional)

---

## Key Decision Points

### Decision 1: Sensor Correction (after clean diagnostic)
- **If L30/S30 difference <5%**:
  - ✅ Skip sensor correction
  - Combine L30+S30 directly in aggregation
  - Faster workflow

- **If L30/S30 difference >5%**:
  - ⚠️ Implement sensor GAM correction at 4km level
  - Adds ~2-4 hours processing time

### Decision 2: Final Product Resolution
- **4km only**:
  - Faster, integration-ready
  - Appropriate for regional drought monitoring

- **4km + selected 30m products**:
  - Run full workflow at 4km
  - Generate high-res 30m anomaly maps for key dates/events
  - Best of both worlds

---

## Estimated Timeline

### Phase 1: Data Validation & Sensor Decision
- Re-run diagnostic: 30 min
- Analysis & decision: 30 min
- **Total: 1 hour**

### Phase 2: Spatial Aggregation to 4km
- Script development: 2 hours
- Execution (aggregate 12 years × 12 tiles): 2 hours
- **Total: 4 hours**

### Phase 3: Temporal GAM Modeling
- Script development: 4 hours
- GAM fitting (~4,000 pixels × 12 years): 4-6 hours
- **Total: 8-10 hours**

### Phase 4: Drought Product Generation
- Classification & export: 2 hours
- Validation (optional): 2 hours
- **Total: 2-4 hours**

**Overall: ~2-3 days of development + processing**

---

## Technical Notes

### Why 4km Resolution?
1. **Computational efficiency**: 133× reduction in pixels (30m → 4km)
2. **Climate data integration**: Matches PRISM, Daymet, gridMET
3. **Drought monitoring scale**: Appropriate for field-to-landscape patterns
4. **GAM tractability**: ~4,000 pixels manageable for pixel-by-pixel fitting

### Differences from Juliana's Approach
- **Juliana**: Pixel-by-pixel at native resolution (30m Landsat), Chicago metro only
- **This workflow**:
  - Aggregated to 4km for regional scale
  - Midwest DEWS domain (~10× larger area)
  - HLS (Landsat + Sentinel) instead of Landsat only
  - Quality filtering from start (Fmask)

### Reference Scripts (spatial_analysis/)
- `02_pixel_by_pixel_mission_gams.R` → sensor correction approach
- `03_pixel_by_pixel_norms.R` → climatology calculation
- `04_pixel_by_pixel_year_splines.R` → annual splines
- `07_yday_looped_anomalies.R` → anomaly calculation

---

## Scripts Created

### Current Session:
1. `diagnostic_hls_sensor_comparison.R` - L30/S30 comparison tool
2. `download_fmask_retroactive.R` - Download Fmask for existing data
3. `reprocess_ndvi_with_fmask.R` - Apply quality filtering to NDVI
4. `check_band_scaling.R` - Verify reflectance scaling

### Updated:
- `01_HLS_data_acquisition_FINAL.R` - Now includes Fmask download
- `02_midwest_pilot.R` - Now uses Fmask in NDVI calculation

### To Develop:
- `aggregate_to_4km.R`
- `03_4km_sensor_correction.R` (conditional)
- `04_4km_climatology_norms.R`
- `05_4km_year_splines.R`
- `06_4km_anomalies.R`
- `07_drought_classification.R`
- `08_export_drought_maps.R`

---

## Data Storage Structure

```
U:/datasets/ndvi_monitor/
├── raw_hls_data/
│   └── year_YYYY/
│       └── midwest_XX_XX/
│           ├── *_B04.tif (Red)
│           ├── *_B05.tif or *_B8A.tif (NIR)
│           └── *_Fmask.tif (Quality)
├── processed_ndvi/
│   ├── daily/
│   │   └── YYYY/
│   │       └── *_NDVI.tif (quality-filtered)
│   ├── daily_unmasked_backup/ (original without quality filtering)
│   └── 4km_aggregated/ (to be created)
├── gam_models/
│   ├── sensor_correction/ (if needed)
│   ├── norms/
│   └── year_splines/
├── anomaly_products/
│   ├── 4km_anomalies/
│   └── 30m_anomalies/ (optional)
└── logs/
    └── sensor_diagnostic_results.rds
```

---

## Session Resume Commands

When resuming work after Fmask implementation:

```r
# 1. Check Fmask download status
source("CONUS_HLS_drought_monitoring/download_fmask_retroactive.R")
# If incomplete, resume with: run_fmask_download()

# 2. Reprocess NDVI
source("CONUS_HLS_drought_monitoring/reprocess_ndvi_with_fmask.R")
results <- run_ndvi_reprocessing(overwrite = TRUE)

# 3. Re-run diagnostic
source("CONUS_HLS_drought_monitoring/diagnostic_hls_sensor_comparison.R")
results <- run_hls_sensor_diagnostic()

# 4. Review this workflow plan
file.edit("CONUS_HLS_drought_monitoring/WORKFLOW_PLAN.md")
```

---

## Contact & References

- **HLS Product Info**: https://lpdaac.usgs.gov/data/get-started-data/collection-overview/missions/harmonized-landsat-sentinel-2-hls-overview/
- **HLS User Guide**: https://lpdaac.usgs.gov/documents/1698/HLS_User_Guide_V2.pdf
- **NASA R Tutorial**: `CONUS_HLS_drought_monitoring/NASA_R_tutorial/HLS_Tutorial.Rmd`
- **Original Spatial Analysis**: `spatial_analysis/` directory (Juliana's GEE-based approach)

---

*Last updated: Session with Claude Code*
