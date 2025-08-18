# CONUS HLS Drought Monitoring Pipeline

This pipeline scales the Chicago-region drought monitoring approach to CONUS (Continental United States) using NASA's Harmonized Landsat Sentinel-2 (HLS) L30 data, replacing the original Google Earth Engine dependency with direct NASA API access.

## Overview

**Original Approach**: Chicago region → Google Earth Engine → Landsat data → GAM analysis  
**New Approach**: CONUS scale → NASA APIs → HLS L30 data → Scaled GAM analysis

## Key Changes

1. **Data Source**: Switched from Google Earth Engine Landsat to NASA HLS L30
2. **Geographic Scope**: Expanded from Chicago region to full CONUS
3. **Data Access**: Direct NASA API access instead of GEE (no corporate restrictions)
4. **Harmonization**: HLS data pre-harmonized across Landsat 8/9 missions

## Files

### Production Scripts
- `00_setup_paths.R` - Cross-platform path configuration (Windows/Linux)
- `01_HLS_data_acquisition.R` - Main CONUS HLS data acquisition pipeline

### Reference Materials
- `NASA_R_tutorial/` - Official NASA HLS tutorial for reference
- `README.md` - This documentation

## Setup Requirements

### 1. NASA Earthdata Account
- Register at: https://urs.earthdata.nasa.gov/
- Authorize "LP DAAC Data Pool" application in your profile

### 2. Authentication File
**Windows**: Create `C:\Users\[username]\_netrc` with:
```
machine urs.earthdata.nasa.gov login YOUR_USERNAME password YOUR_PASSWORD
```

**Linux**: Create `~/.netrc` with same content, then run:
```bash
chmod 600 ~/.netrc
```

### 3. R Dependencies
```r
install.packages(c("httr", "jsonlite", "terra", "sf", "dplyr", "lubridate", "stringr"))
```

## Usage

### Basic Test
```r
source("01_HLS_data_acquisition.R")

# Test the complete pipeline
test_hls_pipeline()
```

### CONUS Data Acquisition
```r
# Full CONUS for summer 2024
result <- acquire_hls_conus(
  start_date = "2024-06-01",
  end_date = "2024-08-31", 
  cloud_cover_max = 30
)

# Custom region/time period
chicago_tile <- list(list(
  id = "chicago_test",
  bbox = c(-88.5, 41.5, -87.5, 42.0),
  region = "midwest"
))

result <- acquire_hls_conus(
  start_date = "2024-07-01",
  end_date = "2024-07-15",
  tile_subset = chicago_tile
)
```

## Data Products

### HLS L30 Specifications
- **Temporal Resolution**: ~2-3 days (combined Landsat 8/9)
- **Spatial Resolution**: 30m 
- **Bands Used**: B04 (Red), B05 (NIR) for NDVI calculation
- **Coverage**: Global, cloud-optimized GeoTIFFs
- **Preprocessing**: Atmospheric correction, geometric correction, cross-sensor harmonization

### Output Structure
```
U:/datasets/ndvi_monitor/
├── raw_hls_data/           # Original HLS bands by year/tile
├── processed_ndvi/         # Calculated NDVI products
├── temporal_extracts/      # Time series by land cover type
├── gam_models/            # Statistical model outputs
└── anomaly_products/      # Drought anomaly results
```

## Technical Notes

### CONUS Processing Strategy
- **Tiling**: CONUS divided into manageable processing tiles
- **Regions**: West, Mountain, Central, East for organization
- **Storage**: Network drive (U:/) to handle large data volumes
- **Authentication**: NASA Earthdata credentials for protected data access

### Performance Considerations
- **File Sizes**: ~50-100MB per band, ~100GB+ for full CONUS/year
- **Processing**: Parallel tile processing recommended
- **Network**: Requires stable internet for NASA API access
- **Storage**: Ensure adequate space on target drive

### Quality Control
- **Cloud Filtering**: Configurable cloud cover thresholds
- **Mission Harmonization**: HLS provides cross-Landsat consistency
- **NDVI Validation**: Automatic range checking (-1 to 1)
- **Download Verification**: File size and integrity checks

## Integration with Original Workflow

This pipeline produces NDVI time series compatible with the original GAM-based drought monitoring approach:

1. **Raw NDVI Data** → Replace original Landsat extracts
2. **Temporal Structure** → Same yday-based modeling approach  
3. **Land Cover Integration** → Compatible with existing LC stratification
4. **GAM Analysis** → Use existing `mgcv` workflow from original scripts
5. **Anomaly Detection** → Same statistical approach, larger spatial scale

## Next Steps

1. **Test Pipeline**: Verify complete workflow with small region
2. **Scale to CONUS**: Run full continental acquisition
3. **Integrate GAMs**: Adapt original GAM scripts for HLS data
4. **Operational Setup**: Schedule regular data updates
5. **Validation**: Compare with original Chicago results for consistency

## Support

- **NASA HLS Documentation**: https://lpdaac.usgs.gov/data/get-started-data/collection-overview/missions/harmonized-landsat-sentinel-2-hls-overview/
- **HLS Data Resources**: https://github.com/nasa/HLS-Data-Resources
- **LP DAAC**: https://lpdaac.usgs.gov/