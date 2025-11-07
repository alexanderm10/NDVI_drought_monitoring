# Parallel HLS Download Implementation Notes

## Overview
Created parallel versions of HLS data acquisition scripts to achieve ~3-4x speedup by processing tiles simultaneously.

## Files Created
- `00_download_hls_data_parallel.R` - Main wrapper script
- `01a_midwest_data_acquisition_parallel.R` - Core parallel processing logic

## Key Implementation Details

### Worker Export Strategy
The most critical aspect of R parallelization is ensuring workers have access to all necessary resources.

**Problem:** With `plan(multisession)`, each worker is a completely separate R session with no access to:
- Functions defined in parent environment
- Global variables/objects
- Loaded packages
- Sourced scripts

**Solution:** Explicitly provide everything workers need in each worker's anonymous function:

```r
tile_results <- future_lapply(midwest_tiles, function(tile) {
  # 1. Load packages explicitly
  library(httr)
  library(terra)

  # 2. Source all required scripts (in dependency order)
  source("00_setup_paths.R")
  source("01_HLS_data_acquisition_FINAL.R")
  source("01a_midwest_data_acquisition_parallel.R")

  # 3. Initialize worker-specific objects
  worker_hls_paths <- get_hls_paths()

  # 4. Call worker function with all needed parameters
  process_tile_month_worker(tile, year, month_start, month_end,
                           cloud_cover_max, worker_hls_paths)
}, future.seed = TRUE)
```

### Worker Function Design

**Critical Decision:** Function definition at TOP LEVEL (not inside parent function)

```r
# ✓ CORRECT: Top-level function (line 72)
process_tile_month_worker <- function(tile, year, month_start, month_end,
                                      cloud_cover_max, worker_hls_paths) {
  # ... implementation
}

# Later sourced by workers:
source("01a_midwest_data_acquisition_parallel.R")  # Makes function available

# ✗ INCORRECT: Nested inside parent function
acquire_midwest_pilot_data <- function(...) {
  process_tile_month_worker <- function(...) {  # Workers can't access this!
    # ...
  }
}
```

### Parameter Passing

**Key insight:** Don't rely on global variables or closures - pass everything explicitly.

```r
# ✓ CORRECT: Explicit parameter
process_tile_month_worker <- function(..., worker_hls_paths) {
  file.path(worker_hls_paths$processed_ndvi, "daily", year, ...)
}

# ✗ INCORRECT: Relies on global `hls_paths`
process_tile_month_worker <- function(...) {
  file.path(hls_paths$processed_ndvi, "daily", year, ...)  # Won't exist in worker!
}
```

### NASA Session Management

Each worker creates its own independent NASA Earthdata session:

```r
# Inside each worker:
worker_nasa_session <- create_nasa_session()
download_hls_band(scene$red_url, red_file, worker_nasa_session)
```

This avoids HTTP connection conflicts that plague forked R processes.

## Resource Management

### Hard Limits
- **4 workers maximum** to prevent system overload
- Each worker processes 1 tile at a time
- 12 tiles total (4x3 grid) → 3 batches of 4 parallel tiles

```r
# Set at acquisition start:
plan(multisession, workers = 4)
```

### Expected Performance

**Sequential (original):**
- 12 tiles × 10 minutes = 120 minutes per month
- 12 months × 120 min = 24 hours per year

**Parallel (4 workers):**
- 3 batches × 10 minutes = 30 minutes per month
- 12 months × 30 min = 6 hours per year

**Speedup:** ~4x (limited by 4 cores)

## Scaling to CONUS

When expanding to full CONUS domain:
- Current: 12 tiles (4×3 Midwest)
- CONUS: 40 tiles (8×5)
- Still 4 workers → 10 batches instead of 40 sequential
- Similar 3-4x speedup expected

## Common R Parallel Pitfalls (Avoided)

1. ✗ **Forking with HTTP sessions** - We use multisession (not multicore/mclapply)
2. ✗ **Implicit global variables** - We pass everything explicitly
3. ✗ **Nested function definitions** - Worker function at top level
4. ✗ **Missing package loads** - Workers explicitly load packages
5. ✗ **Shared file writes** - Each tile writes to separate subdirectories

## Testing Before Full Run

```r
# Test with one recent month first
docker exec conus-hls-drought-monitor Rscript -e "
source('00_download_hls_data_parallel.R')
test_midwest_search(year=2024, month=10)
"
```

## Troubleshooting

If workers fail with "function not found" errors:
1. Check that function is at top level (not nested)
2. Verify all required scripts are sourced in worker
3. Ensure packages are loaded in worker
4. Check that all parameters are passed explicitly (no globals)

## References
- `future` package: https://future.futureverse.org/
- `future.apply`: https://future.apply.futureverse.org/
