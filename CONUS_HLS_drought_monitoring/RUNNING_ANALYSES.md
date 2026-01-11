# Currently Running Analyses

**Updated**: 2026-01-11 14:50 CST

## Active Processes

### Script 03: k=80 Spatial Resolution Test
- **Container**: conus-hls-drought-monitor
- **Started**: 2026-01-11 14:46:26
- **Log**: `03_k80_test_20260111_144626.log`
- **Processing**: Years 2017, 2020, 2022, 2024 (4 years total)
- **Configuration**:
  - Spatial basis k=80 (middle ground between k=30 and k=150)
  - 125,798 pixels
  - 3 cores for parallel processing
  - 365 DOYs per year
- **Expected completion**: ~32-40 hours (approx. Jan 12 evening/Jan 13 morning)
- **Monitor**:
  ```bash
  docker exec conus-hls-drought-monitor tail -f /workspace/03_k80_test_20260111_144626.log
  ```

### Backups Created
Before starting k=80 test, backed up existing k=30 versions:
- `/mnt/malexander/datasets/ndvi_monitor/gam_models/modeled_ndvi/modeled_ndvi_2017_k30_backup.rds`
- `/mnt/malexander/datasets/ndvi_monitor/gam_models/modeled_ndvi/modeled_ndvi_2020_k30_backup.rds`
- `/mnt/malexander/datasets/ndvi_monitor/gam_models/modeled_ndvi/modeled_ndvi_2022_k30_backup.rds`
- `/mnt/malexander/datasets/ndvi_monitor/gam_models/modeled_ndvi/modeled_ndvi_2024_k30_backup.rds`

## Purpose of k=80 Test

Testing k=80 to find optimal spatial resolution:
- **k=30** (baseline): Stable, no overfitting, but lower spatial resolution
- **k=150** (tested Jan 7): Severe overfitting - 5,407 negative NDVI predictions due to data sparsity (~13 obs/pixel/year)
- **k=80** (current): Middle ground - 2.67x better resolution than k=30, less overfitting risk than k=150

## Completed Today

- ✅ Analyzed k=150 test results from Jan 7
- ✅ Identified overfitting issues (negative NDVI, doubled uncertainty)
- ✅ Configured Script 03 for k=80 test
- ✅ Created backups of k=30 versions
- ✅ Started k=80 test run on 4 representative years
- ✅ Committed changes to git (commit a0895e2)

## Next Steps (After k=80 Completion)

1. **Compare k=80 results to k=30 and k=150**:
   - Check for negative NDVI predictions
   - Compare uncertainty widths
   - Evaluate spatial pattern differences
   - Assess model statistics (R², RMSE)

2. **Decision point**:
   - If k=80 performs well: Rerun all years 2013-2024 with k=80
   - If k=80 shows issues: Revert to k=30 or test intermediate value (k=50, k=60)

3. **Alternative approach** (if needed):
   - Investigate multi-year data pooling to increase obs/pixel
   - Test adaptive k based on pixel data density

## Monitoring Commands

Check progress:
```bash
# View log tail
docker exec conus-hls-drought-monitor tail -f /workspace/03_k80_test_20260111_144626.log

# Check for output files
ls -lth /mnt/malexander/datasets/ndvi_monitor/gam_models/modeled_ndvi/

# Check process
docker exec conus-hls-drought-monitor ps aux | grep Rscript

# Container status
docker ps | grep conus-hls-drought-monitor
```

## Notes

- Container left running to allow analysis to complete
- Do NOT stop container until analysis completes
- Analysis is memory-intensive but stable with 3 cores
- Each year takes approximately 8-10 hours to process
