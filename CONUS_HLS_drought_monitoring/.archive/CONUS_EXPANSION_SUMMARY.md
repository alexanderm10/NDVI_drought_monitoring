# CONUS Expansion Summary

## Changes Made to Parallel Download Scripts

The parallel HLS download scripts have been expanded from Midwest pilot to full CONUS domain with 2025 data included.

## Key Changes

### 1. Temporal Expansion
- **Before:** 2013-2024 (12 years)
- **After:** 2013-2025 (13 years)

### 2. Spatial Expansion
- **Before:** Midwest DEWS domain
  - Bbox: (-104.5, 37.0, -82.0, 47.5)
  - Tiles: 12 (4×3 grid)
  - Coverage: ~8 states (Iowa, Illinois, Indiana, parts of surrounding states)

- **After:** Full CONUS domain
  - Bbox: (-125, 25, -66, 49)
  - Tiles: 40 (8×5 grid)
  - Coverage: 48 contiguous states

### 3. Processing Scale
- **Tiles per month:** 40 (up from 12)
- **Batches per month:** 10 (with 4 workers, up from 3)
- **Total tile-months:** 40 tiles × 13 years × 12 months = 6,240 tile-months

### 4. Resource Estimates

#### Time
- **Sequential (if we hadn't parallelized):** ~10+ days
- **Parallel (4 workers):** 2-3 days
- **Speedup:** ~4x faster than sequential

#### Data Volume
- **Before (Midwest):** ~150 GB
- **After (CONUS):** ~500-800 GB
- **Increase:** ~5x more data

#### Disk I/O
- Much more intense - ensure aggregation completes first!
- Each worker reading/writing ~50 MB/scene
- 4 workers × 50 MB = 200 MB/s peak I/O

### 5. File Changes

**Modified Files:**
1. `00_download_hls_data_parallel.R`
   - Updated config: years 2013-2025
   - Updated config: CONUS bbox
   - Updated function call: `acquire_conus_data()`
   - Updated estimates: 2-3 days, 500-800 GB

2. `01a_midwest_data_acquisition_parallel.R`
   - Renamed functions: `create_conus_tiles()`, `acquire_conus_data()`, `test_conus_search()`
   - Updated domain: CONUS bbox
   - Changed tile grid: 8×5 = 40 tiles
   - Updated all documentation strings

## Usage

### Before Running
```bash
# Check available disk space
df -h /mnt/malexander/datasets/ndvi_monitor/

# Ensure at least 1 TB free for CONUS data
```

### Test First
```r
# In Docker container:
docker exec -it conus-hls-drought-monitor R

# Test search before full download
source("00_download_hls_data_parallel.R")
test_conus_search(year = 2024, month = 10)
```

### Full Acquisition
```bash
# Option 1: Direct Rscript execution
docker exec conus-hls-drought-monitor Rscript 00_download_hls_data_parallel.R

# Option 2: Background with logging
docker exec -d conus-hls-drought-monitor bash -c "Rscript 00_download_hls_data_parallel.R > phase0_conus_download.log 2>&1"

# Monitor progress
docker exec conus-hls-drought-monitor tail -f phase0_conus_download.log
```

## Resumability

The script is fully resumable:
- Checks if NDVI files already exist before downloading
- Skips existing files automatically
- Can stop and restart without losing progress

Example: If download stops after 5 days of 2013, restarting will:
- Skip all 2013 January-May files
- Resume from 2013 June
- Continue through 2025

## Output Structure

```
/mnt/malexander/datasets/ndvi_monitor/
├── raw_hls_data/
│   ├── year_2013/
│   │   ├── conus_01_01/  (40 tile directories)
│   │   ├── conus_01_02/
│   │   └── ...
│   ├── year_2014/
│   └── ...
│   └── year_2025/
└── processed_ndvi/
    └── daily/
        ├── 2013/
        │   └── *_NDVI.tif  (final processed NDVI files)
        ├── 2014/
        └── ...
        └── 2025/
```

## Monitoring Progress

```bash
# Check number of NDVI files processed by year
for year in {2013..2025}; do
  count=$(docker exec conus-hls-drought-monitor bash -c "ls /data/processed_ndvi/daily/$year/*_NDVI.tif 2>/dev/null | wc -l")
  echo "$year: $count scenes"
done

# Estimate total data size so far
docker exec conus-hls-drought-monitor bash -c "du -sh /data/processed_ndvi/daily/"
```

## Expected Scene Counts (Approximate)

Based on HLS availability and cloud cover threshold (40%):

| Year | Expected Scenes per Tile | Total CONUS |
|------|-------------------------|-------------|
| 2013 | ~50-100                | 2,000-4,000 |
| 2014-2023 | ~150-250              | 6,000-10,000 per year |
| 2024 | ~200-300               | 8,000-12,000 |
| 2025 | ~50-150 (partial)      | 2,000-6,000 |

**Total Expected:** ~80,000-130,000 scenes across all CONUS for 2013-2025

## Performance Optimization

The 4-worker parallelization was chosen to:
1. ✅ Maximize speedup (4x faster than sequential)
2. ✅ Avoid system overload (leaves resources for other users)
3. ✅ Prevent NASA API rate limiting (4 simultaneous connections okay)
4. ✅ Manage disk I/O (4 workers won't saturate disk)

## When to Run

**Recommended timing:**
- ✅ After Phase 1 aggregation completes (to avoid I/O conflicts)
- ✅ During off-hours (less competition for system resources)
- ✅ When you can monitor for first few hours (catch any errors early)

**Do NOT run:**
- ❌ While Phase 1 aggregation is running (I/O conflict)
- ❌ During peak server usage times
- ❌ Without adequate disk space

## Troubleshooting

### "No space left on device"
```bash
# Check space
df -h /mnt/malexander/datasets/

# Clean up if needed (be careful!)
# Option: Remove raw band files, keep only NDVI
docker exec conus-hls-drought-monitor bash -c "find /data/raw_hls_data -name '*_B04.tif' -delete"
```

### NASA authentication errors
```bash
# Verify netrc file exists
docker exec conus-hls-drought-monitor cat /workspace/.netrc
```

### Worker crashes
- Check logs for specific error
- May need to reduce workers from 4 to 2
- Check system memory: `free -h`

## Next Steps After Completion

1. Verify data completeness
2. Re-run Phase 1 aggregation on expanded dataset
3. Update GAM models with full CONUS data
4. Generate CONUS-wide drought products

## Estimated Timeline

| Stage | Duration |
|-------|----------|
| Test search | 5 minutes |
| First year (2013) | 4-6 hours |
| Full years (2014-2024) | 2-2.5 days |
| Partial year (2025) | 2-4 hours |
| **Total** | **2-3 days** |

Progress is checkpointed continuously - can pause/resume anytime!
