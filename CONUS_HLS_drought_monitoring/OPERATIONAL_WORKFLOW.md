# Operational Monthly Update Workflow

**For near-real-time drought monitoring after initial historical setup**

---

## Prerequisites

Before using the monthly update workflow, you must complete the **historical data pipeline** (one-time setup):

1. ✓ Download all historical HLS data (2013-2024) - `redownload_all_years_cloud100.R`
2. ✓ Aggregate all years to 4km - `01_aggregate_to_4km_parallel.R` for each year
3. ✓ Fit baseline climatology - `02_doy_looped_norms.R` (2013-2024 pooled)
4. ✓ Fit year-specific GAMs - `03_doy_looped_year_predictions.R` (all historical years)
5. ✓ Calculate anomalies - `04_calculate_anomalies.R` (all historical years)

**Status (Jan 2026):** Historical setup in progress

---

## Monthly Update Process

### When to Run

**Trigger:** First week of each month (after previous month completes)

Example schedule:
- **Feb 5, 2026**: Process January 2026 data
- **Mar 5, 2026**: Process February 2026 data
- **Apr 5, 2026**: Process March 2026 data
- etc.

### Option 1: Automated (Cron)

**Setup cron job:**
```bash
# Edit crontab
crontab -e

# Add this line (runs 5th of each month at 2 AM):
0 2 5 * * /home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring/monthly_update.sh >> /home/malexander/monthly_update_cron.log 2>&1
```

**Monitor progress:**
```bash
# Check cron log
tail -f ~/monthly_update_cron.log

# Check monthly update log (created by script)
tail -f /mnt/malexander/datasets/ndvi_monitor/monthly_update_YYYY_MM.log
```

### Option 2: Manual Execution

**Process previous month (automatic detection):**
```bash
cd CONUS_HLS_drought_monitoring
./monthly_update.sh
```

**Process specific month:**
```bash
./monthly_update.sh 2026 02  # February 2026
```

**Or run R script directly:**
```bash
docker exec conus-hls-drought-monitor Rscript /workspace/00_monthly_update.R 2026 02
```

---

## What the Script Does

1. **Downloads new HLS scenes**
   - Uses `cloud_cover_max=100%` (pixel-level Fmask handles QA)
   - Only processes specified month
   - Runtime: ~1-2 hours

2. **Aggregates to 4km**
   - Calls `01_aggregate_to_4km_parallel.R` for target year
   - Updates year-specific RDS file
   - Runtime: ~30 minutes

3. **Updates combined timeseries** (optional)
   - Appends new data to `conus_4km_ndvi_timeseries.rds`
   - Deduplicates by pixel_id + date
   - Runtime: ~5 minutes

4. **Refits year-specific GAMs**
   - Calls `03_doy_looped_year_predictions.R --year=YYYY`
   - Only processes current year (not all historical years)
   - Runtime: ~2-3 hours

5. **Recalculates anomalies**
   - Calls `04_calculate_anomalies.R --year=YYYY`
   - Uses existing baseline (no refit needed)
   - Runtime: ~5 minutes

**Total runtime:** ~4-6 hours per month

---

## What the Script Does NOT Do

- ❌ Recalculate baseline climatology (only done annually on Jan 1)
- ❌ Reprocess historical years
- ❌ Update visualizations (run Script 05 manually if needed)
- ❌ Create derivative products (run Script 06 manually if needed)

---

## Annual Climatology Update

**When:** January 1st after previous year completes

**Example:** On Jan 1, 2027 (after 2026 data complete):

```bash
# 1. Verify data completeness
ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/2026/ | wc -l

# 2. Update baseline window in 02_doy_looped_norms.R
# Change: 2013-2024 → 2013-2025

# 3. Refit baseline climatology (~6-8 hours)
docker exec conus-hls-drought-monitor Rscript /workspace/02_doy_looped_norms.R

# 4. Refit ALL year-specific GAMs for consistency (~1.5-2 days)
docker exec conus-hls-drought-monitor Rscript /workspace/03_doy_looped_year_predictions.R

# 5. Recalculate ALL anomalies (~45 min)
docker exec conus-hls-drought-monitor Rscript /workspace/04_calculate_anomalies.R
```

**Archive previous version:**
```bash
# Save old baseline with timestamp
cp /data/gam_models/doy_looped_norms.rds \
   /data/gam_models/archive/doy_looped_norms_2013-2024.rds
```

---

## Monitoring & Troubleshooting

### Check Container Status
```bash
docker ps | grep conus-hls-drought-monitor
```

### Monitor Running Processes
```bash
docker exec conus-hls-drought-monitor ps aux | grep Rscript
```

### Check Logs
```bash
# Monthly update log
tail -f /mnt/malexander/datasets/ndvi_monitor/monthly_update_2026_02.log

# Download log (if issues with Step 1)
tail -f /mnt/malexander/datasets/ndvi_monitor/download_2026_02.log

# Aggregation log (if issues with Step 2)
tail -f /mnt/malexander/datasets/ndvi_monitor/aggregate_2026.log
```

### Verify Outputs
```bash
# Check that year file was updated
ls -lh /mnt/malexander/datasets/ndvi_monitor/gam_models/aggregated_years/ndvi_4km_2026.rds

# Check GAM output
ls -lh /mnt/malexander/datasets/ndvi_monitor/gam_models/modeled_ndvi/modeled_ndvi_2026.rds

# Check anomaly output
ls -lh /mnt/malexander/datasets/ndvi_monitor/gam_models/modeled_ndvi_anomalies/anomalies_2026.rds
```

### Common Issues

**1. Container not running:**
```bash
cd CONUS_HLS_drought_monitoring
docker compose up -d
```

**2. Baseline not found:**
- Run `02_doy_looped_norms.R` first (historical setup)

**3. Script 03/04 doesn't support --year flag:**
- Scripts may need modification to accept year parameter
- For now, manually edit scripts or run full pipeline

**4. Download fails (NASA API issues):**
- Check NASA Earthdata credentials
- Retry after a few hours (API may be temporarily down)

---

## Output Files

After each monthly update:

```
/data/gam_models/
├── aggregated_years/
│   └── ndvi_4km_2026.rds              # Updated with new month
├── modeled_ndvi/
│   └── modeled_ndvi_2026.rds          # Refitted for current year
└── modeled_ndvi_anomalies/
    └── anomalies_2026.rds             # Recalculated for current year
```

Logs:
```
/data/
└── monthly_update_2026_02.log         # Step-by-step log
```

---

## Visualization & Reporting

After monthly update completes, optionally run:

**1. Update visualizations:**
```bash
docker exec conus-hls-drought-monitor Rscript /workspace/05_visualize_anomalies.R
```

**2. Create derivative products:**
```bash
docker exec conus-hls-drought-monitor Rscript /workspace/06_calculate_change_derivatives.R --year=2026
```

**3. Export for web dashboard:**
```r
# Custom script (TBD) to export to GeoJSON, CSV, or database
```

---

## Backup & Archiving

**Monthly backups (recommended):**
```bash
# Backup current year files
rsync -av /mnt/malexander/datasets/ndvi_monitor/gam_models/aggregated_years/ndvi_4km_2026.rds \
          /backup/location/

# Archive logs
mv /mnt/malexander/datasets/ndvi_monitor/monthly_update_*.log \
   /archive/logs/
```

**Annual backups (required):**
- Full baseline climatology
- All year-specific GAM outputs
- Posteriors (if storage permits)

---

## Future Enhancements

### Planned Features
- [ ] Email notifications on completion/failure
- [ ] Automated quality checks (scene counts, pixel coverage)
- [ ] Web dashboard auto-update
- [ ] Multi-index integration (SPI, EDDI)
- [ ] Automated USDM comparison

### Script Modifications Needed
- [ ] Update Script 03 to accept `--year` parameter
- [ ] Update Script 04 to accept `--year` parameter
- [ ] Add acquisition date range function to `01a_midwest_data_acquisition_parallel.R`

---

## References

- **METHODOLOGY.md**: Complete end-to-end pipeline documentation
- **GAM_METHODOLOGY.md**: Statistical modeling details
- **RUNNING_ANALYSES.md**: Current processing status
- **DOCKER_SETUP.md**: Container configuration

---

## Contact

For questions about operational workflow:
- See `METHODOLOGY.md` Section 5.2 for detailed procedures
- See `CLAUDE.md` for AI assistance with modifications
