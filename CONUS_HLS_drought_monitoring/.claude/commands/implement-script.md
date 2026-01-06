---
description: Create or modify a pipeline script with 7-stage workflow
argument-hint: for Script [number] [description]
allowed-tools: Read, Bash(*), Write, Edit
---

# Implement Script Workflow

Guide me through implementing a new NDVI monitoring script following best practices.

## Pre-Flight Check

Understand what we're building:

1. What script are we implementing?
   - Data acquisition/processing
   - GAM model fitting
   - Anomaly calculation
   - Derivative analysis
   - Visualization/mapping
   - Diagnostic check

2. Check dependencies:
   - What data inputs are required?
   - Which prior scripts must be complete?
   - Are input files available on /mnt/ drive?
   - Is Docker container running?

3. Check workflow position:
   - Review WORKFLOW.md for context
   - Check script numbering sequence
   - Identify where output will be used

## Stage 1: Design and Planning

**Goal**: Clear plan before writing code.

- [ ] Identify inputs (HLS data, GAM models, posteriors)
- [ ] Identify outputs (.rds files, figures, logs)
- [ ] Define processing steps in comments
- [ ] Check for similar existing scripts to use as template
- [ ] Estimate runtime and memory requirements
- [ ] Plan posterior handling (if applicable)

**Example header**:
```r
# ==============================================================================
# Script XX: Descriptive Title
# ==============================================================================
#
# PURPOSE: [Clear 1-2 sentence purpose]
#
# CONTEXT: [How does this fit in the overall workflow?]
#
# INPUT:
#   - file1.rds (from Script YY)
#   - posteriors (from baseline_posteriors/ or year_predictions_posteriors/)
#   - land cover: valid_pixels_landcover_filtered.rds
#
# OUTPUT:
#   - summary_file.rds → /data/gam_models/
#   - posteriors/ → /data/gam_models/component_posteriors/
#   - Figures → /data/figures/SECTION/
#
# METHODS:
#   - [Brief description of GAM approach or analysis method]
#   - [Key assumptions or decisions]
#
# RUNTIME: ~X hours (Y cores)
# MEMORY: ~Z GB peak
#
# ==============================================================================
```

## Stage 2: Check Data Availability

**Goal**: Verify all required inputs exist.

```bash
# Check for input files
ls -lh /mnt/malexander/datasets/ndvi_monitor/gam_models/[input_files]

# Check for posteriors if needed
ls /mnt/malexander/datasets/ndvi_monitor/gam_models/baseline_posteriors/ | wc -l
ls /mnt/malexander/datasets/ndvi_monitor/gam_models/year_predictions_posteriors/

# Check Docker container
docker ps | grep conus-hls-drought-monitor

# Verify packages in container
docker exec conus-hls-drought-monitor Rscript -e "library(mgcv); library(dplyr); library(parallel)"
```

- [ ] All input files exist
- [ ] All required R packages installed in container
- [ ] Sufficient disk space for outputs (check /mnt/ drive)
- [ ] Docker container running and accessible

## Stage 3: Implementation

**Goal**: Write the script following project conventions.

### Script Structure

```r
# 1. HEADER (as above)

# 2. CONFIGURE THREADING (if using parallel processing)
Sys.setenv(OMP_NUM_THREADS = 2)
Sys.setenv(OPENBLAS_NUM_THREADS = 2)

# 3. LOAD PACKAGES
library(dplyr)
library(parallel)
library(mgcv)      # if fitting GAMs
library(ggplot2)   # if creating visualizations
library(data.table)  # for memory-efficient operations

# 4. SOURCE UTILITIES
source("00_setup_paths.R")
hls_paths <- setup_hls_paths()

source("00_posterior_functions.R")  # if using posteriors

# 5. CONFIGURATION
config <- list(
  # Input paths
  input_file = file.path(hls_paths$gam_models, "input.rds"),
  posteriors_dir = file.path(hls_paths$gam_models, "posteriors"),

  # Output paths
  output_file = file.path(hls_paths$gam_models, "output.rds"),
  output_posteriors_dir = file.path(hls_paths$gam_models, "output_posteriors"),

  # Processing parameters
  n_cores = 3,
  n_posterior_sims = 100,

  # Analysis parameters
  param1 = value1
)

# 6. PRINT CONFIGURATION
cat("\n")
cat("==============================================================================\n")
cat("SCRIPT TITLE\n")
cat("==============================================================================\n\n")

cat("Configuration:\n")
cat("  Input:", config$input_file, "\n")
cat("  Output:", config$output_file, "\n")
cat("  Cores:", config$n_cores, "\n\n")

# 7. CREATE OUTPUT DIRECTORIES
if (!dir.exists(config$output_dir)) {
  dir.create(config$output_dir, recursive = TRUE)
}

# 8. LOAD DATA
cat("Loading data...\n")
data <- readRDS(config$input_file)
cat(sprintf("  Loaded: %s rows\n\n", format(nrow(data), big.mark = ",")))

# 9. DATA PREPARATION
cat("Preparing data...\n")
# ... processing steps with informative messages
flush.console()

# 10. MAIN ANALYSIS
cat("\n========================================\n")
cat("MAIN ANALYSIS SECTION\n")
cat("========================================\n\n")

# For parallel processing with progress
results <- mclapply(items, function(item) {
  tryCatch({
    # Analysis code
    result
  }, error = function(e) {
    cat(sprintf("ERROR in item %s: %s\n", item, e$message))
    return(NULL)
  })
}, mc.cores = config$n_cores, mc.preschedule = FALSE)

# 11. SAVE OUTPUTS
cat("\nSaving outputs...\n")
saveRDS(results, config$output_file, compress = "xz")
cat(sprintf("  Saved: %s\n", config$output_file))

# 12. DIAGNOSTICS
cat("\n========================================\n")
cat("DIAGNOSTICS\n")
cat("========================================\n\n")

# Check results, print summaries
cat(sprintf("  Results: %s items\n", length(results)))
cat(sprintf("  Valid: %d (%.1f%%)\n",
            sum(!sapply(results, is.null)),
            100 * sum(!sapply(results, is.null)) / length(results)))

# 13. VISUALIZATION (if applicable)
if (create_figures) {
  cat("\nCreating figures...\n")
  fig_dir <- file.path(hls_paths$figures, "SECTION_NAME")
  dir.create(fig_dir, showWarnings = FALSE, recursive = TRUE)

  # ... create plots

  cat(sprintf("  Figures saved to: %s\n", fig_dir))
}

# 14. FINAL SUMMARY
cat("\n==============================================================================\n")
cat("SCRIPT COMPLETE\n")
cat("==============================================================================\n\n")

cat("Key results:\n")
cat(sprintf("  - Metric 1: %s\n", format_value))
cat(sprintf("  - Metric 2: %s\n", format_value))
cat("\n")

cat("Output files:\n")
cat(sprintf("  - %s\n", basename(config$output_file)))
if (exists("fig_dir")) {
  cat(sprintf("  - Figures: %s\n", fig_dir))
}
cat("\n")

elapsed_time <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
cat(sprintf("Total time: %.1f minutes\n\n", elapsed_time))
```

### Key Conventions

- **Progress messages**: Use `cat()` and `flush.console()` liberally
- **Section headers**: Use `========` for major sections
- **File paths**: Use `hls_paths` from `00_setup_paths.R`
- **Error handling**: Wrap parallel operations in `tryCatch()`
- **Memory safety**: Use `rm()` and `gc()` after large operations
- **Incremental saving**: For posteriors, save immediately to prevent buildup
- **Resume capability**: Check for existing outputs, skip if present
- **Comments**: Explain *why*, not just *what*

## Stage 4: Testing

**Goal**: Run the script and verify outputs.

### For Quick Scripts (<10 min):
```bash
# Direct execution in container
docker exec conus-hls-drought-monitor Rscript XX_script_name.R
```

### For Medium Scripts (10-60 min):
```bash
# Run with log capture
docker exec conus-hls-drought-monitor Rscript XX_script_name.R > XX_test.log 2>&1

# Monitor in real-time
docker exec conus-hls-drought-monitor tail -f /workspace/XX_test.log
```

### For Long Scripts (>1 hour):
```bash
# Run in background with nohup (inside container)
docker exec conus-hls-drought-monitor bash -c "nohup Rscript XX_script_name.R > XX_full.log 2>&1 &"

# Monitor progress
docker exec conus-hls-drought-monitor tail -f /workspace/XX_full.log

# Check if running
docker exec conus-hls-drought-monitor ps aux | grep "[X]X_script_name"

# Use monitor script if available
./monitor_progress.sh  # or monitor_phase2.sh
```

## Stage 5: Verification

**Goal**: Confirm outputs are correct.

- [ ] Output files created with expected sizes
- [ ] No errors in log file
- [ ] Memory usage stayed within limits
- [ ] Summary statistics look reasonable
- [ ] Figures render correctly (if created)
- [ ] Pixel counts match expected (125,798 valid pixels)
- [ ] Results match expectations (or understand why they don't)

```bash
# Check outputs
ls -lh /mnt/malexander/datasets/ndvi_monitor/gam_models/[outputs]

# Check figures
ls -lh /mnt/malexander/datasets/ndvi_monitor/figures/[section]/

# Review log for errors
grep -i "error\|warning" XX_full.log

# Check memory usage during run
docker stats conus-hls-drought-monitor --no-stream
```

## Stage 6: Documentation

**Goal**: Document the script for future reference.

- [ ] Verify header has complete INPUT/OUTPUT documentation
- [ ] Update WORKFLOW.md with new script
- [ ] Update runtime and storage estimates if needed
- [ ] Add comments explaining non-obvious code
- [ ] Document any methodological decisions

**Update WORKFLOW.md**:
```markdown
#### **Script XX: Descriptive Title** (~X hours, Y cores)
\`\`\`bash
docker exec conus-hls-drought-monitor Rscript XX_script_name.R
\`\`\`
- **Purpose**: [One-line description]
- **Input**: [Key input files]
- **Output**: [Key output files and location]
- **Features**: [Unique capabilities or approaches]
```

## Stage 7: Commit

**Goal**: Clean commit with descriptive message.

```bash
git add XX_script_name.R
git add WORKFLOW.md  # If updated
git commit -m "[tag] Descriptive message (Script XX)"
git push origin main
```

Use appropriate tag from session-end.md

---

## Critical Reminders

### Always Run in Docker
All scripts must run inside the Docker container for consistent R environment.

### Check Posteriors Carefully
Posterior files are large - ensure incremental saving and compression.

### Memory-Efficient Parallel Processing
Use `mc.preschedule = FALSE` for load balancing with large objects.

### Land Cover Consistency
Always use the same `valid_pixels_landcover_filtered.rds` file.

### Full Paths from hls_paths
Never hardcode paths - use `setup_hls_paths()` for cross-platform compatibility.

### Resume Capability
For long scripts, check for existing outputs and skip completed items.

### Monitor Long Runs
Scripts 02, 03, 06 run for days - use monitoring scripts and `tail -f` logs.

---

## Ready to Start?

Tell me what script you'd like to implement:
- **What** is the script purpose?
- **Inputs** required?
- **Expected outputs**?
- **Where** does it fit in WORKFLOW.md?

I'll guide you through each stage, confirming completion before moving forward.
