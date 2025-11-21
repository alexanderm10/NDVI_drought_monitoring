# ==============================================================================
# PHASE 2: LONG-TERM BASELINE NORMS (2013-2024)
# ==============================================================================
# Purpose: Fit pixel-by-pixel GAMs pooling all complete years for baseline norms
# Input: conus_4km_ndvi_timeseries.csv from Phase 1
# Output: Baseline curves with uncertainty (pixel_id, yday, norm_mean, norm_se)
# ==============================================================================

library(mgcv)
library(dplyr)
library(parallel)

# ==============================================================================
# PLATFORM CHECK: This script uses mclapply for parallel processing
# ==============================================================================
# ⚠️  WARNING: This script requires Linux or macOS for parallel processing!
#
# - Linux/Mac: Uses fork-based parallelization (mclapply) for optimal performance
# - Windows: mclapply falls back to sequential processing (1 core only)
#
# If running on Windows, expect significantly longer runtimes:
#   - Linux/Mac: ~13 hours for CONUS-scale analysis
#   - Windows:   ~3 days (sequential fallback)
#
# For Windows users: Consider running on a Linux server or in WSL2
# ==============================================================================

if (Sys.info()["sysname"] == "Windows") {
  cat("\n")
  cat("╔════════════════════════════════════════════════════════════════╗\n")
  cat("║  ⚠️  WARNING: Running on Windows                              ║\n")
  cat("║                                                                ║\n")
  cat("║  This script uses mclapply which does NOT support parallel    ║\n")
  cat("║  processing on Windows. It will fall back to sequential       ║\n")
  cat("║  processing (1 core), resulting in significantly longer       ║\n")
  cat("║  runtimes:                                                     ║\n")
  cat("║                                                                ║\n")
  cat("║    • Linux/Mac: ~13 hours (8 cores)                           ║\n")
  cat("║    • Windows:   ~3 days (1 core, sequential)                  ║\n")
  cat("║                                                                ║\n")
  cat("║  Recommendation: Run on Linux/Mac or in WSL2 for best         ║\n")
  cat("║  performance.                                                  ║\n")
  cat("╚════════════════════════════════════════════════════════════════╝\n")
  cat("\n")

  # Require explicit confirmation to proceed
  response <- readline(prompt = "Do you want to continue anyway? (Y/N): ")

  if (!toupper(response) %in% c("Y", "YES")) {
    stop("Execution cancelled by user. Please run this script on Linux/Mac or WSL2 for optimal performance.")
  }

  cat("\nProceeding with sequential processing on Windows...\n\n")
}

# Source path configuration
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

cat("=== PHASE 2: LONG-TERM BASELINE NORMS ===\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Baseline window: complete years only
  baseline_years = 2013:2024,

  # GAM parameters
  gam_knots = 12,
  gam_basis = "cc",  # Cyclic cubic for circular year

  # Input/output
  input_file = file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.csv"),
  output_file = file.path(hls_paths$gam_models, "conus_4km_baseline.csv"),
  model_archive = file.path(hls_paths$gam_models, "norms", "baseline_models.rds"),

  # Quality control
  min_observations = 20,  # Minimum obs per pixel for reliable fit

  # Parallel processing (capped for shared server - max 10 cores)
  n_cores = 8,  # Use 8 cores for good balance (set to 1 for sequential)

  # Checkpointing (RDS format for faster I/O and smaller files)
  checkpoint_interval = 500,  # Save progress every N pixels (was 100)
  resume_from_checkpoint = TRUE
)

# Ensure output directories exist
ensure_directory(hls_paths$gam_models)
ensure_directory(file.path(hls_paths$gam_models, "norms"))

cat("Configuration:\n")
cat("  Baseline years:", paste(range(config$baseline_years), collapse = "-"), "\n")
cat("  GAM knots:", config$gam_knots, "\n")
cat("  Minimum observations per pixel:", config$min_observations, "\n")
cat("  Parallel cores:", config$n_cores, "\n")
cat("  Output:", config$output_file, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Fit baseline GAM for a single pixel
#'
#' @param pixel_data Data frame with yday and NDVI for one pixel (all years pooled)
#' @param k Number of knots
#' @param bs Basis type
#' @return Data frame with yday, norm_mean, norm_se
fit_pixel_baseline <- function(pixel_data, k = 12, bs = "cc") {

  # Check minimum observations
  if (nrow(pixel_data) < 20) {
    return(NULL)
  }

  # Fit GAM
  gam_model <- tryCatch({
    gam(NDVI ~ s(yday, k = k, bs = bs), data = pixel_data)
  }, error = function(e) {
    return(NULL)
  })

  if (is.null(gam_model)) return(NULL)

  # Check convergence
  if (!gam_model$converged) {
    return(NULL)
  }

  # Predict for all days of year
  newdata <- data.frame(yday = 1:365)

  pred <- predict(gam_model, newdata = newdata, se.fit = TRUE)

  result <- data.frame(
    yday = 1:365,
    norm_mean = pred$fit,
    norm_se = pred$se.fit
  )

  return(result)
}

#' Process a batch of pixels (parallelized worker function)
#'
#' @param pixel_batch Vector of pixel IDs to process
#' @param timeseries_baseline Full baseline timeseries (in parent environment)
#' @param config Configuration (in parent environment)
#' @return Data frame with baseline results for this batch
process_pixel_batch <- function(pixel_batch, timeseries_baseline, config) {

  batch_results <- list()

  for (pixel_id in pixel_batch) {

    # Extract pixel data
    pixel_data <- timeseries_baseline[timeseries_baseline$pixel_id == pixel_id, ]

    # Skip if insufficient data
    if (nrow(pixel_data) < config$min_observations) {
      next
    }

    # Fit baseline
    pixel_result <- fit_pixel_baseline(
      pixel_data,
      k = config$gam_knots,
      bs = config$gam_basis
    )

    if (!is.null(pixel_result)) {
      pixel_result$pixel_id <- pixel_id
      batch_results[[length(batch_results) + 1]] <- pixel_result
    }
  }

  if (length(batch_results) > 0) {
    return(do.call(rbind, batch_results))
  } else {
    return(NULL)
  }
}

#' Process baseline for all pixels (with parallel processing)
#'
#' @param timeseries_df Full timeseries dataframe
#' @param config Configuration list
#' @return Baseline dataframe
fit_all_baselines <- function(timeseries_df, config) {

  cat("=== FITTING LONG-TERM BASELINE GAMS ===\n\n")

  # Filter to baseline years
  cat("Filtering to baseline years:", paste(range(config$baseline_years), collapse = "-"), "\n")
  timeseries_baseline <- timeseries_df %>%
    filter(year %in% config$baseline_years)

  cat("  Total observations:", nrow(timeseries_baseline), "\n")

  # Get unique pixels
  pixel_ids <- unique(timeseries_baseline$pixel_id)
  n_pixels <- length(pixel_ids)

  cat("  Unique 4km pixels:", n_pixels, "\n\n")

  # CRITICAL OPTIMIZATION: Pre-split data by pixel_id for O(1) access in workers
  # This avoids repeated scanning of 18.7M rows during pixel processing
  # split() preserves row order within each group
  # On Linux: mclapply forks share this via copy-on-write (no serialization overhead!)
  cat("Pre-splitting data by pixel for fast worker access...\n")
  pixel_list <- split(timeseries_baseline, timeseries_baseline$pixel_id)
  cat("  Created indexed list of", length(pixel_list), "pixels\n")
  cat("  (Workers will access via copy-on-write shared memory)\n\n")

  # Check for checkpoint (RDS format for faster I/O)
  checkpoint_file <- sub("\\.csv$", "_checkpoint.rds", config$output_file)

  if (config$resume_from_checkpoint && file.exists(checkpoint_file)) {
    cat("Found checkpoint - loading previous progress...\n")
    baseline_df <- readRDS(checkpoint_file)

    processed_pixels <- unique(baseline_df$pixel_id)
    pixel_ids <- setdiff(pixel_ids, processed_pixels)
    n_pixels_from_checkpoint <- length(processed_pixels)

    cat("  Resuming from", n_pixels_from_checkpoint, "completed pixels\n")
    cat("  ", length(pixel_ids), "pixels remaining\n\n")
  } else {
    baseline_df <- data.frame()
    n_pixels_from_checkpoint <- 0
  }

  if (length(pixel_ids) == 0) {
    cat("All pixels already processed!\n")
    return(baseline_df)
  }

  # Process pixels with incremental checkpointing
  cat("Processing pixels with incremental checkpointing...\n")
  cat("Checkpoint interval:", config$checkpoint_interval, "pixels\n")
  cat("Parallel cores:", config$n_cores, "\n\n")

  start_time <- Sys.time()
  # Initialize counters - if resuming from checkpoint, start from checkpoint count
  n_processed <- n_pixels_from_checkpoint  # Total pixels (checkpoint + new)
  n_processed_this_run <- 0  # Pixels processed in THIS run only (for progress/checkpoint logic)
  n_failed <- 0
  last_saved_checkpoint <- 0  # Track checkpoint state for incremental saves (relative to this run)

  # Split pixels into small batches for better checkpointing
  # Each batch = config$n_cores pixels (one per core)
  batch_size <- config$n_cores
  pixel_batches <- split(pixel_ids, ceiling(seq_along(pixel_ids) / batch_size))

  cat("Split into", length(pixel_batches), "batches of ~", batch_size, "pixels each\n\n")

  # Set threading constraints for parallel workers
  # CRITICAL: Prevent nested parallelism - constrain each worker to 1 thread
  Sys.setenv(OMP_NUM_THREADS = 1)
  Sys.setenv(MKL_NUM_THREADS = 1)
  Sys.setenv(OPENBLAS_NUM_THREADS = 1)

  # Accumulate results in a list to avoid repeated rbind (MUCH faster)
  all_results <- list()
  result_counter <- 0

  # Process batches with incremental checkpointing
  for (i in seq_along(pixel_batches)) {
    batch_pixels <- pixel_batches[[i]]

    # Process batch using mclapply (forking on Linux - shares memory with parent!)
    # This avoids the serialization overhead of SOCK clusters
    # pixel_list is accessible via copy-on-write shared memory
    if (config$n_cores > 1) {
      batch_results <- mclapply(batch_pixels, function(pixel_id) {
        # Load mgcv in each fork
        library(mgcv)

        # O(1) access from pre-split list (shared via copy-on-write!)
        pixel_data <- pixel_list[[as.character(pixel_id)]]

        # Skip if insufficient data
        if (nrow(pixel_data) < config$min_observations) {
          return(NULL)
        }

        # Fit baseline
        pixel_result <- fit_pixel_baseline(
          pixel_data,
          k = config$gam_knots,
          bs = config$gam_basis
        )

        if (!is.null(pixel_result)) {
          pixel_result$pixel_id <- pixel_id
          return(pixel_result)
        } else {
          return(NULL)
        }
      }, mc.cores = config$n_cores)
    } else {
      # Sequential processing
      batch_results <- lapply(batch_pixels, function(pixel_id) {
        pixel_data <- pixel_list[[as.character(pixel_id)]]

        if (nrow(pixel_data) < config$min_observations) {
          return(NULL)
        }

        pixel_result <- fit_pixel_baseline(
          pixel_data,
          k = config$gam_knots,
          bs = config$gam_basis
        )

        if (!is.null(pixel_result)) {
          pixel_result$pixel_id <- pixel_id
          return(pixel_result)
        } else {
          return(NULL)
        }
      })
    }

    # Store successful results in list (avoid repeated rbind)
    batch_results <- batch_results[!sapply(batch_results, is.null)]

    if (length(batch_results) > 0) {
      for (result in batch_results) {
        result_counter <- result_counter + 1
        all_results[[result_counter]] <- result
      }
      n_processed <- n_processed + length(batch_results)
      n_processed_this_run <- n_processed_this_run + length(batch_results)
    }

    n_failed <- n_failed + (length(batch_pixels) - length(batch_results))

    # Progress reporting (based on total pixels attempted, not just successful)
    n_attempted_this_run <- n_processed_this_run + n_failed
    if (n_attempted_this_run %% 50 == 0 || i == length(pixel_batches)) {
      elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))
      # Calculate rate based on successful pixels processed THIS run
      successful_per_min <- if (elapsed > 0) n_processed_this_run / elapsed else 0
      remaining <- length(pixel_ids) - n_attempted_this_run
      eta_mins <- if (successful_per_min > 0) remaining / successful_per_min else Inf

      cat(sprintf("  Progress: %d successful, %d failed, %d remaining | %.1f/min | ETA: %.0f min\n",
                  n_processed, n_failed, remaining,
                  successful_per_min, eta_mins))
    }

    # Save checkpoint every N pixels (INCREMENTAL - only rbind new results to avoid quadratic slowdown)
    if (n_processed_this_run > 0 && (n_processed_this_run - last_saved_checkpoint) >= config$checkpoint_interval) {
      cat("  Saving checkpoint...\n")
      # Combine NEW results with existing checkpoint data
      new_data <- do.call(rbind, all_results)
      baseline_df <- rbind(baseline_df, new_data)
      saveRDS(baseline_df, checkpoint_file, compress = "gzip")
      # Clear accumulated results for next checkpoint interval (critical for performance!)
      all_results <- list()
      result_counter <- 0
      last_saved_checkpoint <- n_processed_this_run
    }
  }

  # Final conversion to dataframe (combine checkpoint with any remaining results since last checkpoint)
  cat("\nCombining all results...\n")
  if (length(all_results) > 0) {
    new_data <- do.call(rbind, all_results)
    baseline_df <- rbind(baseline_df, new_data)
  }

  # No cluster cleanup needed with mclapply (uses forking, not SOCK cluster)

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  cat("\n=== BASELINE FITTING COMPLETE ===\n")
  cat("Time elapsed:", round(elapsed, 1), "minutes\n")
  cat("Pixels processed:", n_processed, "\n")
  cat("Pixels failed:", n_failed, "\n")
  cat("Total baseline records:", nrow(baseline_df), "\n")
  cat("Expected records (pixels × 365 days):", n_processed * 365, "\n\n")

  # Save final output (CSV for compatibility)
  cat("Saving baseline to:", config$output_file, "\n")
  write.csv(baseline_df, config$output_file, row.names = FALSE)

  # Remove checkpoint
  if (file.exists(checkpoint_file)) {
    file.remove(checkpoint_file)
    cat("Checkpoint file removed\n")
  }

  cat("✓ Phase 2 complete\n\n")

  return(baseline_df)
}

#' Generate summary statistics for baseline
#'
#' @param baseline_df Baseline dataframe
#' @return Summary table
summarize_baseline <- function(baseline_df) {

  cat("=== BASELINE SUMMARY ===\n\n")

  # Overall statistics
  cat("Total pixels:", length(unique(baseline_df$pixel_id)), "\n")
  cat("Total records:", nrow(baseline_df), "\n\n")

  # NDVI range by day of year
  yday_stats <- baseline_df %>%
    group_by(yday) %>%
    summarise(
      mean_ndvi = mean(norm_mean),
      min_ndvi = min(norm_mean),
      max_ndvi = max(norm_mean),
      sd_ndvi = sd(norm_mean),
      .groups = "drop"
    )

  cat("Day-of-year NDVI statistics:\n")
  cat("  Mean NDVI range:", round(min(yday_stats$mean_ndvi), 3), "to",
      round(max(yday_stats$mean_ndvi), 3), "\n")
  cat("  Peak NDVI day:", yday_stats$yday[which.max(yday_stats$mean_ndvi)], "\n")
  cat("  Minimum NDVI day:", yday_stats$yday[which.min(yday_stats$mean_ndvi)], "\n\n")

  # Uncertainty distribution
  cat("Prediction uncertainty (SE):\n")
  cat("  Median SE:", round(median(baseline_df$norm_se), 4), "\n")
  cat("  95th percentile SE:", round(quantile(baseline_df$norm_se, 0.95), 4), "\n\n")

  return(yday_stats)
}

# ==============================================================================
# EXECUTION
# ==============================================================================

# Check if running as main script (not being sourced)
if (!interactive() || exists("run_phase2")) {

  cat("\n=== EXECUTING PHASE 2: LONG-TERM BASELINE FITTING ===\n")
  cat("Started at:", as.character(Sys.time()), "\n\n")

  # Load timeseries from Phase 1
  cat("Loading Phase 1 timeseries data...\n")
  timeseries_4km <- read.csv(config$input_file, stringsAsFactors = FALSE)
  timeseries_4km$date <- as.Date(timeseries_4km$date)

  cat("  Total observations:", nrow(timeseries_4km), "\n")
  cat("  Unique pixels:", length(unique(timeseries_4km$pixel_id)), "\n")
  cat("  Date range:", paste(range(timeseries_4km$date), collapse = " to "), "\n\n")

  # Fit baselines
  start_time <- Sys.time()
  baseline <- fit_all_baselines(timeseries_4km, config)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  # Summarize results
  cat("\nGenerating summary statistics...\n")
  yday_stats <- summarize_baseline(baseline)

  # Final summary
  cat("\n=== PHASE 2 COMPLETE ===\n")
  cat("Total time:", round(elapsed, 1), "minutes\n")
  cat("Output saved to:", config$output_file, "\n")

} else {
  cat("\n=== PHASE 2 FUNCTIONS LOADED ===\n")
  cat("Ready to fit long-term baseline norms for", paste(range(config$baseline_years), collapse = "-"), "\n")
  cat("Estimated time: ~30-60 minutes with", config$n_cores, "cores\n")
  cat("Output will be saved to:", config$output_file, "\n\n")
  cat("To run manually:\n")
  cat("  timeseries_4km <- read.csv(config$input_file, stringsAsFactors = FALSE)\n")
  cat("  timeseries_4km$date <- as.Date(timeseries_4km$date)\n")
  cat("  baseline <- fit_all_baselines(timeseries_4km, config)\n\n")
}
