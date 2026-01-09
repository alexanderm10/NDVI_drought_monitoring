# k=150 Test Results and Next Steps

**Date**: 2026-01-09
**Test**: Increased spatial basis dimension from k=30 to k=150 for Script 03
**Year tested**: 2024 only

## Summary of Findings

### Test Completed Successfully (Technical)
- Runtime: 609.6 minutes (~10 hours) for year 2024
- No crashes or memory errors
- Model R² = 0.766, RMSE = 0.0755
- Output: `/mnt/malexander/datasets/ndvi_monitor/gam_models/modeled_ndvi/modeled_ndvi_2024.rds`
- Backup of k=30 version: `modeled_ndvi_2024_k30_backup.rds`

### Critical Problems Identified

**OVERFITTING DUE TO DATA SPARSITY**

1. **Impossible NDVI predictions**:
   - 5,407 negative NDVI values (0.02% of predictions)
   - 49,166 predictions > 1.0 (0.20% of predictions)
   - Worst cases: -0.88 NDVI (should be physically impossible)

2. **Uncertainty explosion**:
   - k=30 CI width: 0.006 (mean)
   - k=150 CI width: 0.014 (mean) - **DOUBLED**
   - Indicates severe overfitting

3. **Root cause - Too few observations per pixel**:
   - Median: 13 observations per pixel per year
   - 88.5% of pixels have < 20 observations
   - Fitting 150 basis functions with ~13 data points = massive overfitting
   - Specific problem areas: DOY 49-50, 201-202, 338-343 (data gaps)

### Comparison: k=150 vs k=30
- Overall correlation: r = 0.97 (high agreement where data exists)
- Mean difference: 0.0009 (tiny on average)
- But 24.8% of pixels differ by > 0.05 NDVI
- Large differences concentrated in sparse-data pixels

## DECISION: DO NOT USE k=150

k=150 is inappropriate for current data density.

## Next Steps - MULTI-YEAR POOLING APPROACH

### Proposed Strategy
Instead of increasing k with single-year data, **pool multiple years** to increase data density:

1. **Test configuration**:
   - Randomly select 3 years for testing
   - Pool all observations from those 3 years together
   - Use k=100 (middle ground between 30 and 150)
   - Median obs per pixel would increase: ~13 → ~39 observations

2. **Expected benefits**:
   - 3x more data per pixel → supports higher k
   - Reduces extrapolation in sparse regions
   - Better spatial resolution without overfitting
   - More stable uncertainty estimates

3. **Implementation needs**:
   - Modify [Script 03](../03_doy_looped_year_predictions.R) to accept multi-year data pooling
   - Still predict for each year separately, but fit spatial GAM with pooled data
   - Test on 3 random years first before full rerun

### Questions to Investigate
1. **Why only ~13 obs/pixel/year for HLS?**
   - HLS combines Landsat 8/9 + Sentinel-2A/B
   - Should theoretically have 2-4 day revisit
   - Likely aggressive cloud/QA filtering or data gaps
   - Need to check: `/mnt/malexander/datasets/ndvi_monitor/gam_models/conus_4km_ndvi_timeseries.rds`

2. **Which years to pool?**
   - Random selection of 3 years (e.g., 2017, 2020, 2023)
   - Or neighboring years (e.g., 2022, 2023, 2024)
   - Trade-off: more data vs. phenology drift over time

3. **How to structure multi-year GAM?**
   - Option A: Pool all years, fit `gam(NDVI ~ s(x,y,k=100) + s(yday) + s(year))`
   - Option B: Use year as a factor in spatial term
   - Option C: Fit spatial term on pooled, apply to each year separately

## Current Git Status
- 2024 with k=150: Already committed (e3b16c9)
- May need to revert to k=30 for consistency with 2013-2023
- Or rerun 2024 with multi-year pooling approach

## Files Modified
- [CONUS_HLS_drought_monitoring/03_doy_looped_year_predictions.R](../03_doy_looped_year_predictions.R) - Changed k=30 to k=150 (committed)

## Logs
- Test run log: [03_k150_test_20260107_131813.log](../03_k150_test_20260107_131813.log)
- Visualization run: [05_run_20260107_072009.log](../05_run_20260107_072009.log)
