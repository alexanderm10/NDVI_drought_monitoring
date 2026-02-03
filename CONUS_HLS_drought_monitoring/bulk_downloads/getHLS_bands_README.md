# getHLS_bands.sh - Band-Specific HLS Bulk Download

Modified version of NASA's `getHLS.sh` that downloads only the bands needed for NDVI calculation.

## What This Script Does

Downloads **only these bands** from HLS data:
- **B04** - Red band (both L30 and S30)
- **B05** - NIR for Landsat (L30 only)
- **B8A** - NIR narrow for Sentinel (S30 only)
- **Fmask** - Quality mask (both L30 and S30)

**Data savings:** ~60-70% less download size and time compared to full granules

## Prerequisites

### 1. NASA Earthdata Account
You need an account at https://urs.earthdata.nasa.gov

### 2. Configure `.netrc` File
Create `~/.netrc` with your credentials:

```bash
cat > ~/.netrc << 'EOF'
machine urs.earthdata.nasa.gov
login YOUR_USERNAME
password YOUR_PASSWORD
EOF

chmod 600 ~/.netrc
```

### 3. Generate HLS Tile List
You need a text file containing 5-character MGRS tile IDs that cover your study area.

For the Midwest bbox (-104.5, 37.0, -82.0, 47.5), you can:
- Use the provided `midwest_tiles.txt` (if generated)
- Or manually identify tiles using: https://hls.gsfc.nasa.gov/products-description/tiling-system/

## Usage

```bash
./getHLS_bands.sh <tilelist> <date_begin> <date_end> <out_dir>
```

### Parameters

1. **tilelist**: Text file with one tile ID per line (e.g., `midwest_tiles.txt`)
2. **date_begin**: Start date in format `YYYY-MM-DD` (e.g., `2019-01-01`)
3. **date_end**: End date in format `YYYY-MM-DD` (e.g., `2019-12-31`)
4. **out_dir**: Base output directory (subdirectories will be created)

### Example

```bash
# Download 2019 data for Midwest tiles
./getHLS_bands.sh midwest_tiles.txt 2019-01-01 2019-12-31 /mnt/malexander/datasets/ndvi_monitor/hls_raw
```

## Configuration Parameters

Edit these at the top of the script (lines 75-77):

```bash
NP=10        # Number of parallel download processes (adjust based on network/CPU)
CLOUD=100    # Maximum cloud cover % (100 = download all scenes)
SPATIAL=0    # Minimum spatial coverage % (0 = download all tiles)
```

## Output Structure

Files are organized as:
```
<out_dir>/
  L30/                    # Landsat products
    2019/
      15/T/V/M/           # Tile subdirectories
        HLS.L30.T15TVM.2019001T165228.v2.0/
          HLS.L30.T15TVM.2019001T165228.v2.0.B04.tif
          HLS.L30.T15TVM.2019001T165228.v2.0.B05.tif
          HLS.L30.T15TVM.2019001T165228.v2.0.Fmask.tif
  S30/                    # Sentinel products
    2019/
      15/T/V/M/
        HLS.S30.T15TVM.2019001T170719.v2.0/
          HLS.S30.T15TVM.2019001T170719.v2.0.B04.tif
          HLS.S30.T15TVM.2019001T170719.v2.0.B8A.tif
          HLS.S30.T15TVM.2019001T170719.v2.0.Fmask.tif
```

## Resume Capability

The script automatically skips already-downloaded files, so you can:
- Safely re-run if interrupted
- Add more date ranges without re-downloading existing data

## Performance Tips

1. **Parallel processes**: Increase `NP` if you have good bandwidth (try 15-20)
2. **Run in background**: Use `nohup` for long downloads:
   ```bash
   nohup ./getHLS_bands.sh tiles.txt 2019-01-01 2024-12-31 /data/output > download.log 2>&1 &
   ```
3. **Monitor progress**:
   ```bash
   tail -f download.log
   ```

## Integration with Existing Pipeline

After downloading with this script:

1. **Move/link files** to your processing directory structure
2. **Calculate NDVI** using your existing R functions
3. **Aggregate** using `01_aggregate_to_4km_parallel.R`

## Troubleshooting

### Authentication fails
- Check `.netrc` file exists and has correct permissions (600)
- Verify credentials at https://urs.earthdata.nasa.gov

### No files downloaded
- Verify tile IDs are correct 5-character MGRS codes
- Check date range has available data
- Confirm network connectivity to LP DAAC

### Downloads incomplete
- The script uses `-C -` (resume) flag - just re-run the same command

## Modification Details

**Original script**: https://github.com/nasa/HLS-Data-Resources/tree/main/bash/hls-bulk-download

**Key change** (line 237):
```bash
# Original:
grep $granule $flist > $allfile

# Modified:
grep $granule $flist | egrep '\.(B04|B05|B8A|Fmask)\.' > $allfile
```

This regex filter selects only the 4 bands needed for NDVI calculation.

## Next Steps

To use this for years 2019-2024:

1. Generate or obtain Midwest tile list
2. Set up `.netrc` authentication
3. Test with a small date range (one week)
4. Run full download for each year
5. Integrate downloaded bands into your existing NDVI workflow

Created: 2026-02-03
Modified from: NASA LP DAAC getHLS.sh
