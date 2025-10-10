# CONUS HLS Drought Monitoring - Current Status

**Date:** 2025-01-07
**Status:** ✅ Fmask Download Complete - Ready for NDVI Reprocessing

---

## What We Accomplished Today

### Problem Solved
- **Issue:** Only 17% of NDVI files had matching Fmask (cloud mask) files due to internet interruptions during initial download
- **Solution:** Created direct scene ID query method to backfill all missing Fmask files
- **Result:** **100% Fmask coverage achieved** (4,863/4,863 scenes)

### Files Downloaded
- **Total Scenes:** 4,863 (2013-2024)
  - Landsat (L30): 2,723 scenes
  - Sentinel (S30): 2,140 scenes
- **Fmask Files:** ~3,700 new Fmask files downloaded (~2.2 GB)
- **Coverage:** 100% across all years

---

## Current Data Status

### ✅ Complete
- [x] Raw HLS band files (B04, B05, B8A) - stored in `U:/datasets/ndvi_monitor/raw_hls_data/year_XXXX/`
- [x] Fmask (cloud mask) files - co-located with band files
- [x] NDVI files (basic, no cloud masking) - stored in `U:/datasets/ndvi_monitor/processed_ndvi/daily/`
- [x] Scene inventory cache - `scene_list_cache.csv` (4,538 unique scenes)

### 📋 Ready for Next Step
- [ ] Reprocess NDVI with Fmask cloud masking
  - Reprocessing list ready: `U:/datasets/ndvi_monitor/logs/reprocessing_list.csv`
  - 4,863 scenes ready to reprocess

---

## Key Scripts & Their Purpose

### Operational Pipeline (for new data)
- **`02_midwest_pilot.R`** - Main data acquisition script
  - Downloads HLS bands (Red, NIR) + Fmask for new scenes
  - Calculates NDVI
  - Now includes Fmask warning if download fails
  - Ready for operational use

### Fmask Backfill Scripts (one-time fixes)
- **`download_fmask_direct.R`** - Direct scene ID query (WORKS ✅)
  - Queries NASA API by exact scene ID
  - 100% reliable method we used today
  - Use this if Fmask files go missing again

- **`download_fmask_cached.R`** - Scans U: drive and caches scene list
  - Useful for creating the scene inventory
  - Avoids repeated server hits

- **`00_fmaskArchiveDownloadExecute.R`** - Execute script
  - Currently points to `download_fmask_direct.R`

### Verification Scripts
- **`match_ndvi_fmask.R`** - Check NDVI/Fmask coverage
  - Generates matching report
  - Shows coverage by year/sensor
  - Creates reprocessing list

---

## Next Steps (To Do Tomorrow)

### 1. Reprocess NDVI with Cloud Masking
- **Purpose:** Apply Fmask to filter out clouds/bad pixels from NDVI
- **Input:** Reprocessing list at `U:/datasets/ndvi_monitor/logs/reprocessing_list.csv`
- **Script:** Need to create or identify existing reprocessing script
- **Output:** Cloud-masked NDVI files

### 2. Verify Reprocessed NDVI Quality
- Check sample scenes visually
- Compare pre/post cloud masking results
- Verify no data gaps

### 3. Continue Pipeline Development
- Set up temporal aggregation (daily → monthly → seasonal)
- GAM model fitting for anomaly detection
- Integration with USDM data

---

## Important File Locations

### Data Directories
```
U:/datasets/ndvi_monitor/
├── raw_hls_data/
│   ├── year_2013/ ... year_2024/
│   │   └── midwest_TXXXXX/
│   │       ├── *_B04.tif (Red band)
│   │       ├── *_B05.tif or *_B8A.tif (NIR band)
│   │       └── *_Fmask.tif (Cloud mask) ✅ NOW COMPLETE
│
├── processed_ndvi/
│   └── daily/
│       └── *_NDVI.tif (needs reprocessing with Fmask)
│
└── logs/
    ├── ndvi_fmask_matching_report.csv
    └── reprocessing_list.csv (4,863 scenes ready)
```

### Cache Files (in working directory)
- `scene_list_cache.csv` - Inventory of all 4,538 unique scenes

---

## Key Lessons Learned

### What Worked
1. **Direct scene ID query** - Most reliable method for targeted downloads
2. **Caching scene list locally** - Prevents repeated U: drive hits during download
3. **Monthly searches** - Avoids API result limits (100 scenes/request)

### What Didn't Work
1. ❌ Bbox-only searches - Returns global results, not Midwest specific
2. ❌ Tile-by-tile pagination - Too many API requests (3,145)
3. ❌ Year-level searches - Hit 100 scene limit, incomplete results

### For Future Reference
- Fmask files are ~0.6 MB each (compressed cloud masks)
- NASA STAC API direct item query: `https://cmr.earthdata.nasa.gov/stac/LPCLOUD/collections/{COLLECTION}/items/{SCENE_ID}`
- Collection name format: `HLSL30_2.0` or `HLSS30_2.0` (not `HLSL30.v2.0`)

---

## Questions to Address Tomorrow

1. **Which script reprocesses NDVI with Fmask?**
   - Check for existing reprocessing script
   - May need to modify `calculate_ndvi_from_hls()` function

2. **Output directory structure for reprocessed NDVI?**
   - Same location with overwrite?
   - New directory (e.g., `processed_ndvi/cloud_masked/`)?

3. **Quality checks needed?**
   - Visual inspection of sample scenes
   - Statistics on cloud masking impact

---

## Quick Start Commands for Tomorrow

### Check current status
```r
source("CONUS_HLS_drought_monitoring/match_ndvi_fmask.R")
matched <- run_matching_report()
```

### If any Fmask missing (should be 0)
```r
source("CONUS_HLS_drought_monitoring/download_fmask_direct.R")
results <- run_direct_download()
```

### Start NDVI reprocessing (script TBD)
```r
# To be determined - check for reprocessing script
source("CONUS_HLS_drought_monitoring/reprocess_ndvi_with_fmask.R")
```

---

**Status:** Ready to proceed with NDVI cloud masking and quality improvement! 🎉
