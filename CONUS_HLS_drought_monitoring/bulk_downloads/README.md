# Bulk Download Workflow

This directory contains tools and scripts for fast bulk downloading of HLS data for years 2019-2024.

## Directory Structure

```
bulk_downloads/
├── raw/                    # Raw band files from getHLS_bands.sh
│   ├── L30/               # Landsat products
│   │   └── YYYY/          # Year
│   │       └── ##/L/T/G/  # Tile organization (e.g., 15/T/V/M/)
│   │           └── HLS.L30.T15TVM.2019001T165228.v2.0/
│   │               ├── HLS.L30.T15TVM.2019001T165228.v2.0.B04.tif
│   │               ├── HLS.L30.T15TVM.2019001T165228.v2.0.B05.tif
│   │               └── HLS.L30.T15TVM.2019001T165228.v2.0.Fmask.tif
│   └── S30/               # Sentinel products
│       └── YYYY/
│           └── ##/S/T/U/
│               └── HLS.S30.T15TVM.2019001T170719.v2.0/
│                   ├── HLS.S30.T15TVM.2019001T170719.v2.0.B04.tif
│                   ├── HLS.S30.T15TVM.2019001T170719.v2.0.B8A.tif
│                   └── HLS.S30.T15TVM.2019001T170719.v2.0.Fmask.tif
├── scripts/               # Processing scripts
│   └── process_bulk_ndvi.R
└── logs/                  # Log files from bulk operations
```

## Workflow

### 1. Bulk Download Raw Bands

Download HLS bands for a specific year using the modified getHLS.sh script:

```bash
cd /home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring

# Download 2019 data (example)
nohup ./getHLS_bands.sh \
  midwest_tiles.txt \
  2019-01-01 \
  2019-12-31 \
  bulk_downloads/raw \
  > bulk_downloads/logs/download_2019.log 2>&1 &

# Monitor progress
tail -f bulk_downloads/logs/download_2019.log
```

**Output**: Raw bands saved to `bulk_downloads/raw/L30/2019/` and `bulk_downloads/raw/S30/2019/`

### 2. Process Bands to NDVI

Calculate NDVI from downloaded bands and save to the location expected by current download script:

```bash
# Inside Docker container (if needed)
docker exec -it conus-hls-drought-monitor bash

# Process year
Rscript bulk_downloads/scripts/process_bulk_ndvi.R 2019 --workers=8

# Or run in background
nohup Rscript bulk_downloads/scripts/process_bulk_ndvi.R 2019 --workers=8 \
  > bulk_downloads/logs/process_2019.log 2>&1 &
```

**Output**: NDVI files saved to `/mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/2019/`

**Result**: Current download script will see these NDVI files exist and skip downloading those scenes.

### 3. Verify Integration

Check that NDVI files are in the expected location:

```bash
# Count NDVI files for the year
ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/2019/ | wc -l

# Check a sample filename format
ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/2019/ | head -5
```

Filenames should match pattern: `HLS.L30.T15TVM.2019001T165228.v2.0_NDVI.tif`

## Complete Workflow for Multiple Years

Process all years 2019-2024:

```bash
#!/bin/bash
# run_bulk_workflow.sh

REPO_DIR="/home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring"
cd $REPO_DIR

for year in 2019 2020 2021 2022 2023 2024; do
  echo "=== Processing year $year ==="

  # 1. Bulk download
  echo "Step 1: Downloading bands..."
  ./getHLS_bands.sh \
    midwest_tiles.txt \
    ${year}-01-01 \
    ${year}-12-31 \
    bulk_downloads/raw \
    > bulk_downloads/logs/download_${year}.log 2>&1

  if [ $? -eq 0 ]; then
    echo "✓ Download complete for $year"

    # 2. Process to NDVI
    echo "Step 2: Processing to NDVI..."
    Rscript bulk_downloads/scripts/process_bulk_ndvi.R $year --workers=8 \
      > bulk_downloads/logs/process_${year}.log 2>&1

    if [ $? -eq 0 ]; then
      echo "✓ Processing complete for $year"

      # 3. Verify
      count=$(ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$year/ 2>/dev/null | wc -l)
      echo "✓ Created $count NDVI files for $year"
    else
      echo "✗ Processing failed for $year"
    fi
  else
    echo "✗ Download failed for $year"
  fi

  echo ""
done

echo "=== Bulk workflow complete ==="
echo "Current download script will skip all processed scenes."
```

## Resume Capability

Both scripts support resume:
- **getHLS_bands.sh**: Won't re-download existing band files
- **process_bulk_ndvi.R**: Skips if NDVI file already exists

Safe to re-run if interrupted.

## Performance

**Expected performance** (1,209 Midwest tiles):
- **Download**: ~5-10x faster than current R script
  - 10 parallel workers
  - Only 3-4 bands per granule (vs 10-12)
  - Direct tile targeting (vs bbox search)

- **Processing**: ~100-200 granules/minute (8 workers)

**Storage per year** (estimated):
- Raw bands: ~50-80 GB
- NDVI output: ~15-25 GB
- Can delete raw bands after processing if needed

## Cleanup

After successful processing and verification:

```bash
# Option 1: Delete raw bands (keep disk space)
rm -rf bulk_downloads/raw/L30/2019
rm -rf bulk_downloads/raw/S30/2019

# Option 2: Archive raw bands (for reprocessing if needed)
tar -czf bulk_downloads/archive_2019_raw.tar.gz bulk_downloads/raw/*/2019
rm -rf bulk_downloads/raw/*/2019
```

## Troubleshooting

### Download issues
- Check `.netrc` authentication
- Verify tile list: `wc -l midwest_tiles.txt`
- Check log: `tail -f bulk_downloads/logs/download_YYYY.log`

### Processing issues
- Verify band files exist: `find bulk_downloads/raw -name "*.tif" | wc -l`
- Check output directory writable
- Review log: `tail -f bulk_downloads/logs/process_YYYY.log`

### Integration issues
- Verify filename pattern matches current script
- Check output directory: `/mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/YYYY/`
- Test current script's skip logic

## Notes

- This workflow is **complementary** to current download script
- Current script continues running for 2017-2018 and any non-Midwest tiles
- Bulk method only handles Midwest tiles (1,209 tiles)
- If scaling to full CONUS needed, just use full tile list instead of midwest_tiles.txt
