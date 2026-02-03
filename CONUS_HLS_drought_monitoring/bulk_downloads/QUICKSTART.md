# Bulk Download Quick Start

Fast track to get 2019-2024 data downloaded and integrated with current workflow.

## Prerequisites

1. **NASA Earthdata credentials** in `~/.netrc`:
   ```bash
   cat > ~/.netrc << 'EOF'
   machine urs.earthdata.nasa.gov
   login YOUR_USERNAME
   password YOUR_PASSWORD
   EOF
   chmod 600 ~/.netrc
   ```

2. **Verify setup**:
   ```bash
   ls -la ~/.netrc  # Should show -rw------- permissions
   ```

## Quick Test (One Month)

Test with January 2019 to verify everything works:

```bash
cd /home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring/bulk_downloads

# 1. Download raw bands (test)
./getHLS_bands.sh \
  ../midwest_tiles.txt \
  2019-01-01 \
  2019-01-31 \
  raw

# 2. Process to NDVI
Rscript scripts/process_bulk_ndvi.R 2019 --workers=4

# 3. Verify output
ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/2019/ | wc -l
```

**Expected result**:
- Raw bands in `raw/L30/2019/` and `raw/S30/2019/`
- NDVI files in `/mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/2019/`
- Current download script will skip these when it reaches 2019

## Production Run (Full Year)

Once test succeeds, run full year in background:

```bash
cd /home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring/bulk_downloads

# Start download in background
nohup ./getHLS_bands.sh \
  ../midwest_tiles.txt \
  2019-01-01 \
  2019-12-31 \
  raw \
  > logs/download_2019.log 2>&1 &

# Monitor progress
tail -f logs/download_2019.log

# When download finishes, process to NDVI
nohup Rscript scripts/process_bulk_ndvi.R 2019 --workers=8 \
  > logs/process_2019.log 2>&1 &

# Monitor processing
tail -f logs/process_2019.log
```

## All Years 2019-2024

Create and run this script:

```bash
#!/bin/bash
# bulk_download_all.sh

cd /home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring/bulk_downloads

for year in 2019 2020 2021 2022 2023 2024; do
  echo "=== Starting year $year ==="

  # Download
  ./getHLS_bands.sh \
    ../midwest_tiles.txt \
    ${year}-01-01 \
    ${year}-12-31 \
    raw \
    > logs/download_${year}.log 2>&1

  echo "Download complete, processing..."

  # Process
  Rscript scripts/process_bulk_ndvi.R $year --workers=8 \
    > logs/process_${year}.log 2>&1

  # Count
  count=$(ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$year/ 2>/dev/null | wc -l)
  echo "✓ Year $year complete: $count NDVI files"

  # Optional: cleanup raw bands to save space
  # rm -rf raw/L30/$year raw/S30/$year

done

echo "=== All years complete ==="
```

Run it:
```bash
chmod +x bulk_download_all.sh
nohup ./bulk_download_all.sh > logs/all_years.log 2>&1 &
```

## Monitoring

Check progress anytime:

```bash
# Download progress
tail -100 logs/download_2019.log | grep -E "granules to download|Finished downloading"

# Processing progress
tail -100 logs/process_2019.log | grep -E "Progress:|PROCESSING COMPLETE"

# Final counts
for yr in 2019 2020 2021 2022 2023 2024; do
  echo -n "$yr: "
  ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$yr/ 2>/dev/null | wc -l
done
```

## Integration with Current Download

The current download script running in Docker checks for existing NDVI files:
```r
if (file.exists(ndvi_file)) {
  next  # Skip this scene
}
```

So any NDVI files you create via bulk download will be automatically skipped. The two workflows work together seamlessly.

## Performance Expectations

**Download speed**: ~5-10x faster than current method
- Reason: Direct tile targeting, 10 parallel workers, fewer bands

**Processing speed**: ~100-200 granules/minute
- Varies by year (more Sentinel-2 data in later years)

**Estimated timeline for all 6 years**:
- Download: 1-3 days total
- Processing: 6-12 hours total
- vs Current script: weeks

## Cleanup

After successful verification:

```bash
# Option 1: Delete raw bands (save ~300-400 GB)
rm -rf raw/L30/ raw/S30/

# Option 2: Archive for potential reprocessing
for year in 2019 2020 2021 2022 2023 2024; do
  tar -czf archive_${year}_raw.tar.gz raw/*/year
  rm -rf raw/*/$year
done
```

## Troubleshooting

**Download hangs**: Check `.netrc` auth, try reducing NP in getHLS_bands.sh

**Processing errors**: Verify bands downloaded, check terra package installed

**Integration issues**: Verify filename pattern matches (should be automatic)

## Next Session

When you return to work:
1. Check which years completed: `ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/`
2. Resume from where you left off
3. Current Docker download will skip all completed NDVI files automatically
4. Aggregate completed years when ready
