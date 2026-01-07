# Currently Running Analyses

**Updated**: 2026-01-07 16:23

## Active Processes

- **Script 03**: Year Predictions with k=150 Test
  - Container: conus-hls-drought-monitor
  - Process ID: 162028 (R process), parent 162027 (bash)
  - Started: 2026-01-07 12:18 (4 hours ago)
  - Status: Running (100% CPU, 14 GB memory usage)
  - Log: `03_k150_test_20260107_131813.log`
  - Expected completion: ~12-30 hours (by 2026-01-08 evening)
  - Monitor: `docker exec conus-hls-drought-monitor tail -f /workspace/03_k150_test_20260107_131813.log`
  - Testing: Modified spatial resolution (k=150 vs default k~30)
  - Year: 2024 only (11 other years use k~30, backed up at `modeled_ndvi_2024_k30_backup.rds`)

## Changes Made This Session (2026-01-07)

### Code Modifications

1. **Modified Script 03** ([03_doy_looped_year_predictions.R](03_doy_looped_year_predictions.R))
   - Added `spatial_k = 150` parameter to config (lines 47-52)
   - Modified `fit_year_spatial_gam()` function to accept spatial_k parameter (line 105)
   - Updated GAM call: `s(x, y, k = spatial_k)` instead of `s(x, y)` (line 110)
   - Updated function call to pass `config$spatial_k` (line 293)
   - **Rationale**: MIDWEST domain (2000km) requires finer spatial resolution than default k~30
     - k~30 gives 361 km resolution (state-scale)
     - k=150 gives 161 km resolution (county/watershed scale, appropriate for ecosystem impacts)
   - **Testing approach**: Changed k only, kept 33% threshold (one variable at a time)

### Documentation Created

1. **[MODIFICATIONS_FROM_JULIANA.md](MODIFICATIONS_FROM_JULIANA.md)**: Why we changed k from ~30 to 150
   - Documents the single change from Juliana's validated Chicago approach
   - Explains spatial scale difference: Chicago (100km) vs MIDWEST (2000km) = 201× size difference
   - Statistical validation: 84 pixels/basis at 10% coverage (well above 50-100 minimum)
   - Computational feasibility: 12-30 hours per year, 2 GB memory per DOY

2. **[SPATIAL_SCALE_ANALYSIS.md](/home/malexander/r_projects/github/NDVI_drought_monitoring/SPATIAL_SCALE_ANALYSIS.md)**: Scale mismatch between Chicago and MIDWEST
   - Same 33% threshold has vastly different spatial density implications
   - Juliana's 18km resolution vs our 361km resolution (with k~30)
   - Recommendation: Lower threshold to 10% for equivalent spatial sampling (deferred pending k test)

3. **[K_SELECTION_GUIDE.md](/home/malexander/r_projects/github/NDVI_drought_monitoring/K_SELECTION_GUIDE.md)**: Complete k vs resolution analysis
   - Table from k=30 to k=197 showing resolution, effective range, pixels/basis
   - Optimal ranges: k=75-120 for most uses, k=150 for ecosystem-scale work
   - Computational cost analysis and validation strategy

4. **[SPATIAL_INFLUENCE_OPTIONS.md](/home/malexander/r_projects/github/NDVI_drought_monitoring/SPATIAL_INFLUENCE_OPTIONS.md)**: How to control spatial influence
   - Explains TPRS (thin plate regression spline) already has distance-based influence
   - Options: Increase k (chosen), Gaussian Process, regional models, MRF
   - At k~30: pixels 500+ km away still influence predictions
   - At k=150: more localized (effective range 322-483 km vs 722-1,082 km)

5. **[GAP_FILLING_ANALYSIS.md](/home/malexander/r_projects/github/NDVI_drought_monitoring/GAP_FILLING_ANALYSIS.md)**: Gap-filling verification
   - Confirmed DOY-looping + spatial GAM achieves 100% prediction coverage
   - Our implementation matches Juliana's approach
   - 24,908,004 predictions with 0 NAs despite only 113 observation dates

6. **[TIMESERIES_GAPS_ANALYSIS.md](/home/malexander/r_projects/github/NDVI_drought_monitoring/TIMESERIES_GAPS_ANALYSIS.md)**: Why time series show gaps
   - 33% pixel coverage threshold causes 167 of 365 DOYs to be skipped
   - Only 198 DOYs predicted (54% temporal coverage)
   - Solutions: Lower threshold (deferred), interpolate for viz, expand window

## Next Steps

### 1. When k=150 Test Completes (~tomorrow evening, 2026-01-08)

**Validation checklist:**
- [ ] Compare results to k~30 backup (`modeled_ndvi_2024_k30_backup.rds`)
- [ ] Verify same 198 DOYs predicted (33% threshold unchanged)
- [ ] Check R² values (should be similar or better)
- [ ] Compare predictions for high-coverage DOYs
- [ ] Visual inspection: more localized spatial patterns?
- [ ] Better match to known 2024 drought events?
- [ ] Sharper transitions at ecoregion boundaries?
- [ ] Record computation time (expected 12-30 hours)
- [ ] Check memory usage stayed reasonable (<10 GB per core)

### 2. If Validation Passes

**Apply k=150 to all years (2013-2024):**
- Modify Script 03 to process all years
- Estimated time: 12-30 hours per year × 12 years = 6-15 days total
- Can parallelize across years if needed (run multiple years in separate containers)
- Update downstream analyses:
  - Script 04 (anomalies): Should work automatically with new predictions
  - Script 05 (visualization): Re-generate time series
  - Script 06 (derivatives): Re-calculate if predictions change significantly

### 3. After k=150 Implemented (Optional Phase 2)

**Test lower threshold to fill time series gaps:**
- Test 10% threshold on 2024 with k=150
- Expected improvement: ~280-300 DOYs (77-82%) instead of 198 (54%)
- Would fill winter gaps (DOY 1-35, 356-365) and scattered gaps
- Validation: Check prediction uncertainty in low-coverage DOYs

## Session Context

### Problem Addressed

User observed "tons of gaps in the data" in time series plots and questioned:
1. Whether our implementation matched Juliana's gap-filling approach ✅ (verified yes)
2. Why time series plots showed systematic gaps → 33% coverage threshold
3. Whether 33% threshold operates differently at MIDWEST scale → **critical insight**: yes, vastly different
4. Whether spatial influence should be limited → yes, via increasing k

### Key Insight

**Spatial scale mismatch:** Juliana's 33% threshold was appropriate for Chicago (100km domain, k~30 gives 18km resolution) but too conservative for MIDWEST (2000km domain, k~30 gives 361km resolution). Increasing k to 150 improves spatial resolution to 161km (ecosystem-scale: watersheds, counties, sub-ecoregions).

### Decision Rationale

User wisely chose to test one variable at a time:
- **First**: Test k=150 with existing 33% threshold
- **Later**: If needed, test lower threshold (10%)

This approach allows isolating the effect of spatial resolution changes before modifying coverage requirements.

## How to Monitor

```bash
# Check if process is still running
docker exec conus-hls-drought-monitor ps aux | grep Rscript

# View latest log output
docker exec conus-hls-drought-monitor tail -f /workspace/03_k150_test_20260107_131813.log

# Check container status
docker ps --filter "name=conus-hls-drought-monitor"

# Check memory/CPU usage
docker stats conus-hls-drought-monitor --no-stream
```

## Backup Information

- Original 2024 results: `/mnt/malexander/datasets/ndvi_monitor/gam_models/modeled_ndvi/modeled_ndvi_2024_k30_backup.rds`
- Years 2013-2023: Still using k~30 (unchanged)
- Posterior files for 2024: Will be overwritten by k=150 test
