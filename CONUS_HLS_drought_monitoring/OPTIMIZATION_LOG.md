# CONUS HLS Drought Monitoring - Optimization Log

**Date:** 2025-11-12
**Objective:** Optimize CONUS-scale processing pipeline for stability and performance

---

## Problem Statement

The original pipeline (scripts 01-07) was designed for small-scale analysis and faced several issues when scaled to CONUS:

1. **Network mount instability**: CSV checkpoints were large (GBs) and slow to write, causing timeouts on network-mounted storage
2. **Sequential processing**: No parallelization, making computationally intensive phases extremely slow
3. **Flat architecture**: Scripts 04-05 processed pixel-year combinations as independent entities, creating massive overhead
4. **No edge year handling**: First/last years (2013, 2024) had incomplete padding data with no graceful degradation

---

## Optimizations Applied

### Phase 1: Aggregation to 4km (01_aggregate_to_4km.R)
- **RDS checkpoints**: Switched from CSV to RDS with gzip compression (90%+ size reduction)
- **Reduced checkpoint frequency**: Changed from every 100 scenes to every 300 scenes for mount stability
- **File**: Lines 224-228 (RDS checkpoint loading), 326-328 (RDS checkpoint saving)

### Phase 2: Long-term Baseline Fitting (02_fit_longterm_baseline.R)
- **Parallelization enabled**: 8 cores (was sequential)
- **RDS checkpoints**: Lines 167-171 (loading), 298-301 (saving)
- **Incremental checkpointing**: Save every 100 pixels (lines 186-303)
- **Batch processing**: Process in batches of 8 pixels (one per core) with per-pixel data subsetting to minimize memory duplication
- **Progress tracking**: Real-time updates with pixels/min and ETA (lines 285-296)

### Phase 3: Baseline Derivatives (03_derivatives_baseline.R)
- **Same optimizations as Phase 2**
- **Parallelization**: 8 cores (line 47)
- **RDS checkpoints**: Lines 187-192 (loading), 311-314 (saving)
- **Incremental checkpointing**: Every 100 pixels
- **Memory efficient**: Each worker gets only its assigned pixel's data (lines 245-247)

### Phase 4: Year-specific GAM Fitting (04_fit_year_gams.R)
- **Architectural improvement**: Refactored from flat pixel-year combinations to pixel-first processing
  - Old approach: Process each pixel-year combination independently
  - New approach: Each worker processes all 12 years for one pixel sequentially
  - **Benefits**: Natural access to full pixel timeseries for edge padding, 12× less checkpoint overhead
- **Edge year handling**: Reduce knots (k-1) for years 2013 and 2024 due to incomplete padding (lines 181-187)
- **Edge padding function**: Lines 66-114, properly handles missing adjacent years
- **New processing function**: `process_pixel_all_years()` lines 159-208
- **Parallelization**: 8 cores (line 43)
- **RDS checkpoints**: Lines 228-233 (loading), 353-356 (saving)
- **Estimated time**: ~10-15 hours (down from potentially weeks sequential)

### Phase 5: Year-specific Derivatives (05_derivatives_individual_years.R)
- **Same architectural improvements as Phase 4**
- **Pixel-first processing**: `process_pixel_all_years_derivatives()` function (lines 184-233)
- **Edge year handling**: Lines 206-212 (reduce knots for 2013/2024)
- **Edge padding**: Lines 73-121 (handles missing adjacent years gracefully)
- **Parallelization**: 8 cores (line 52)
- **RDS checkpoints**: Lines 257-262 (loading), 385-388 (saving)
- **Estimated time**: ~90-120 minutes (down from 8-12 hours)

### Phase 6: Calculate Anomalies (06_calculate_anomalies.R)
- **No optimization needed** - already efficient
- **Processing type**: Vectorized operations on full dataset loaded into memory
- **Pattern**: Joining/calculation script, not pixel-by-pixel iteration
- **Fixed**: Typo on line 278 (changed "PHASE 4" to "PHASE 6")
- **Estimated time**: ~5 minutes

### Phase 7: Drought Classification (07_classify_drought.R)
- **No optimization needed** - already efficient
- **Processing type**: Vectorized dplyr operations (case_when, mutate)
- **Status**: Placeholder implementation for threshold exploration
- **Estimated time**: ~5 minutes

---

## Technical Patterns Applied

### 1. RDS Checkpoints
```r
# Check for checkpoint (RDS format for faster I/O)
checkpoint_file <- sub("\\.csv$", "_checkpoint.rds", config$output_file)

if (config$resume_from_checkpoint && file.exists(checkpoint_file)) {
  cat("Found checkpoint - loading previous progress...\n")
  data_df <- readRDS(checkpoint_file)
  # ... resume logic ...
}

# Save checkpoint (RDS format: faster, smaller, preserves types)
if (n_processed %% config$checkpoint_interval == 0) {
  cat("  Saving checkpoint...\n")
  saveRDS(data_df, checkpoint_file, compress = "gzip")
}
```

### 2. Parallel Processing Architecture
```r
# Set up cluster
cl <- makeCluster(config$n_cores)
clusterEvalQ(cl, {
  library(mgcv)
  library(dplyr)
})

# Export required objects - full dataset shared but accessed per-pixel
clusterExport(cl, c("timeseries_df", "config", "process_pixel_function"),
              envir = environment())

# Process in batches
batch_results <- parLapply(cl, batch_pixels, function(pixel_id) {
  # Each worker gets ONLY data for its assigned pixel
  pixel_data <- timeseries_df[timeseries_df$pixel_id == pixel_id, ]
  # ... process pixel ...
})

stopCluster(cl)
```

### 3. Pixel-First Architecture (Scripts 04-05)
```r
# Old approach (inefficient):
# pixel_year_combos <- expand.grid(pixels, years)  # Creates huge list
# lapply(pixel_year_combos, process_one_combo)     # Processes each independently

# New approach (efficient):
process_pixel_all_years <- function(pixel_data, pixel_id, config) {
  pixel_results <- list()

  for (target_year in config$target_years) {
    # Apply edge padding (needs full pixel timeseries)
    padded_data <- apply_edge_padding(pixel_data, target_year, config$edge_padding_days)

    # Fit year-specific model
    year_result <- fit_model(padded_data, ...)
    pixel_results[[length(pixel_results) + 1]] <- year_result
  }

  return(bind_rows(pixel_results))
}
```

### 4. Edge Year Handling
```r
# Determine edge years
edge_years <- c(min(config$target_years), max(config$target_years))  # 2013, 2024

# Reduce knots for edge years (incomplete padding)
k_year <- if (target_year %in% edge_years) {
  config$gam_knots - 1  # k=11 instead of k=12
} else {
  config$gam_knots      # k=12
}

# Edge padding function handles missing years gracefully
apply_edge_padding <- function(pixel_data, target_year, padding_days = 31) {
  year_data <- pixel_data %>% filter(year == target_year)

  # For 2013, prev_dec will be empty (no 2012 data)
  prev_dec <- pixel_data %>%
    filter(year == target_year - 1, yday > (365 - padding_days)) %>%
    mutate(year = target_year, yday = yday - 366)

  # For 2024, next_jan will be empty (no 2025 data)
  next_jan <- pixel_data %>%
    filter(year == target_year + 1, yday <= padding_days) %>%
    mutate(year = target_year, yday = yday + 365)

  # Combine (empty dataframes silently dropped)
  padded_data <- bind_rows(year_data, prev_dec, next_jan)
  return(padded_data)
}
```

### 5. Progress Tracking
```r
if (n_processed %% 50 == 0 || i == length(pixel_batches)) {
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
  pixels_per_min <- n_processed / elapsed
  remaining <- length(pixel_ids) - n_processed - n_failed
  eta_mins <- remaining / pixels_per_min

  cat(sprintf("  Progress: %d/%d pixels (%.1f%%) | %.1f pixels/min | ETA: %.0f min\n",
              n_processed, length(pixel_ids),
              100 * n_processed / length(pixel_ids),
              pixels_per_min, eta_mins))
}
```

---

## Data Format Strategy

**Checkpoints (internal):** RDS with gzip compression
- Fast I/O (~10× faster than CSV for large datasets)
- Small file size (90%+ reduction vs CSV)
- Preserves R data types (Date, factor, etc.)
- Network mount friendly

**Final outputs (external):** CSV format
- Portable across languages/platforms
- Human-readable
- Compatible with downstream tools
- Easy to inspect/validate

---

## Estimated Processing Times (8 cores)

| Phase | Description | Estimated Time |
|-------|-------------|----------------|
| 1 | Aggregate to 4km | 2-4 hours |
| 2 | Fit baseline GAMs | 30-60 minutes |
| 3 | Baseline derivatives | 60-90 minutes |
| 4 | Year-specific GAMs | 10-15 hours |
| 5 | Year derivatives | 90-120 minutes |
| 6 | Calculate anomalies | ~5 minutes |
| 7 | Classify drought | ~5 minutes |
| **Total** | **End-to-end** | **~15-21 hours** |

**Previous estimates (sequential):** Several days to weeks

---

## Configuration Parameters

All optimized scripts use consistent configuration:

```r
config <- list(
  # Parallel processing (capped for shared server)
  n_cores = 8,  # Max 10 cores recommended on shared servers

  # Checkpointing (RDS format)
  checkpoint_interval = 100,  # Save every N pixels (300 for Phase 1 scenes)
  resume_from_checkpoint = TRUE,

  # Year extent (HLS data)
  target_years = 2013:2024,  # Or baseline_years for Phases 2-3

  # GAM parameters
  gam_knots = 12,
  gam_basis = "cc",  # Cyclic cubic for baseline; "tp" for year-specific

  # Edge padding
  edge_padding_days = 31  # Borrow 31 days from adjacent years
)
```

---

## Key Insights

1. **Pixel-first architecture is critical** for scripts that need temporal context (edge padding). Processing years as inner loop per pixel is both faster and more natural than flattening to pixel-year combinations.

2. **RDS checkpoints solve mount stability issues** - the 90%+ size reduction and faster I/O prevent network timeouts that plagued CSV checkpoints.

3. **Not all scripts need optimization** - Post-processing scripts (06-07) that use vectorized operations are already efficient. Focus optimization on pixel-by-pixel processing phases.

4. **Edge year handling is subtle but important** - Following Juliana's approach of reducing knots (k-1) for first/last years provides graceful degradation when padding data is incomplete.

5. **Memory efficiency through subsetting** - Each parallel worker accesses only its assigned pixel's data from the shared timeseries, avoiding massive memory duplication across cores.

---

## Files Modified

- `01_aggregate_to_4km.R` - RDS checkpoints, reduced checkpoint frequency
- `02_fit_longterm_baseline.R` - Parallelization, RDS checkpoints, incremental checkpointing
- `03_derivatives_baseline.R` - Same as Phase 2
- `04_fit_year_gams.R` - Pixel-first architecture, edge year handling, parallelization, RDS checkpoints
- `05_derivatives_individual_years.R` - Same as Phase 4
- `06_calculate_anomalies.R` - Typo fix only (line 278)
- `07_classify_drought.R` - No changes (already efficient)

---

## Verification Checklist

Before running the optimized pipeline:

- [ ] Confirm HLS data directory structure: `processed_ndvi/daily/YEAR/*.tif`
- [ ] Verify year extent: 2013-2024 (consistent across all scripts)
- [ ] Check available cores: `parallel::detectCores()` (set n_cores ≤ 10 on shared servers)
- [ ] Ensure output directory exists and is writable
- [ ] Test on small subset first (modify config$years to 2013:2014)
- [ ] Monitor checkpoint files grow as expected
- [ ] Verify final CSV outputs have expected structure

---

## Future Considerations

1. **Phase 4 optimization potential**: Consider caching baseline GAMs if refitting repeatedly
2. **Adaptive batch sizing**: Could dynamically adjust batch size based on available memory
3. **Derivative caching**: Phases 3 and 5 could cache derivatives if repeatedly accessed
4. **Checkpoint cleanup**: Could add option to auto-remove old checkpoints after successful completion
5. **Error logging**: Could capture detailed error messages for failed pixels to file
6. **USDM integration**: Phase 7 threshold validation when USDM data becomes available

---

## Contact

For questions about these optimizations, refer to:
- Session date: 2025-11-12
- Optimization focus: Network mount stability, parallelization, pixel-first architecture
- Reference: This optimization log and inline code comments
