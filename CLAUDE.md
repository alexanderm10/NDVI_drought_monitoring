# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is an R-based drought monitoring system that uses NDVI (Normalized Difference Vegetation Index) data from Landsat satellites to analyze vegetation stress patterns across different land cover types. The project implements Generalized Additive Models (GAMs) to identify drought conditions through vegetation anomalies.

## Key Architecture Components

### Core Analytical Framework
- **GAM Models**: Uses `mgcv` package to fit spline-based models for temporal NDVI patterns
- **Mission Correction**: Applies cross-satellite calibration to harmonize data from different Landsat missions (5, 7, 8, 9)
- **Posterior Distributions**: Custom function `post.distns()` in `0_Calculate_GAMM_Posteriors_Updated_Copy.R` generates uncertainty estimates using Bayesian posterior simulations
- **Derivative Analysis**: Calculates first and second derivatives of fitted splines to detect vegetation stress onset

### Data Structure
- **Time Series Analysis**: Day-of-year (yday) based modeling with cyclic cubic splines (k=12 knots)
- **Land Cover Types**: Separate models for crop, forest, grassland, urban high/medium/low density, urban open space, and wetland-forest
- **Reprojection Workflow**: Standardizes all missions to Landsat 8 reference frame for consistent comparisons

### Spatial vs. Temporal Analysis
- **Main Directory**: Site-level aggregated analysis across land cover types
- **spatial_analysis/**: Pixel-by-pixel spatial analysis using Google Earth Engine integration via `rgee` package

## Data Workflow

### Temporal Analysis Pipeline
1. **01_raw_data.R**: Load and preprocess NDVI data, fit mission-specific GAMs, reproject to common baseline
2. **02_norms.R**: Calculate long-term normal curves for each land cover type
3. **03_individual_years.R**: Fit GAMs for specific years to identify anomalies
4. **04-08_**: Various plotting and statistical analysis scripts for USDM comparisons
5. **09-13_**: Derivative-based analysis for detecting vegetation stress timing

### Spatial Analysis Pipeline
1. **00_landsat*_spatial_data_acquisition.R**: Download satellite data via Google Earth Engine
2. **01_all_satellites_raw_data_save.R**: Combine multi-satellite raster data
3. **02-07_**: Pixel-level GAM fitting and anomaly detection

## Key Dependencies

### Required R Packages
- `mgcv`: GAM model fitting
- `rgee`: Google Earth Engine integration for spatial data
- `raster`/`terra`: Spatial data handling
- `ggplot2`, `dplyr`, `lubridate`: Data manipulation and visualization
- `MASS`: Statistical functions for posterior simulation

### Data Sources
- Google Drive integration (`~/Google Drive/Shared drives/Urban Ecological Drought/`)
- NDVI data from multiple Landsat missions (2001-2024)
- USDM (US Drought Monitor) comparison data

## Common Development Tasks

### Running the Full Temporal Analysis
```r
# Execute scripts in numerical order
source("01_raw_data.R")
source("02_norms.R") 
source("03_individual_years.R")
# Continue with plotting/analysis scripts as needed
```

### Spatial Analysis Setup
```r
# Requires Google Earth Engine authentication
library(rgee)
ee_Initialize()
```

### Key Functions
- `post.distns()`: Generate posterior distributions from GAM objects (in `0_Calculate_GAMM_Posteriors_Updated_Copy.R`)
- Mission-specific GAM fitting pattern: `gam(NDVI ~ s(yday, k=12, by=mission) + mission-1)`
- Reprojection workflow for cross-mission standardization

## File Organization Logic

- **Numbered scripts (01-17)**: Follow sequential data processing workflow
- **0_prefix files**: Core utility functions used across multiple scripts
- **spatial_analysis/**: Self-contained pixel-level analysis pipeline
- Scripts with similar numbers handle related analysis steps (e.g., 04-08 for plotting, 09-13 for derivatives)