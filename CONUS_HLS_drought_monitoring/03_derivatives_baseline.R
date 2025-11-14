# ==============================================================================
# PHASE 3: BASELINE DERIVATIVE ANALYSIS
# ==============================================================================
# Purpose: Calculate derivatives of climatological baseline to identify
#          expected timing of phenological transitions (green-up, senescence)
# Input: conus_4km_baseline.csv (Phase 2 output) + timeseries for GAM refitting
# Output: Baseline derivatives (pixel_id, yday, deriv_mean, deriv_lwr, deriv_upr, sig)
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
#   - Linux/Mac: ~60-90 minutes for CONUS-scale analysis
#   - Windows:   ~8-12 hours (sequential fallback)
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
  cat("║    • Linux/Mac: ~60-90 minutes (8 cores)                      ║\n")
  cat("║    • Windows:   ~8-12 hours (1 core, sequential)              ║\n")
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

# Source configuration and utility functions
source("00_setup_paths.R")
source("00_gam_utility_functions.R")
hls_paths <- get_hls_paths()

cat("=== PHASE 3: BASELINE DERIVATIVE ANALYSIS ===\n\n")

# ==============================================================================
# CONFIGURATION
# ==============================================================================

config <- list(
  # Input files
  baseline_file = file.path(hls_paths$gam_models, "conus_4km_baseline.csv"),
  timeseries_file = file.path(hls_paths$gam_models, "conus_4km_ndvi_timeseries.csv"),

  # Baseline parameters (must match Phase 2)
  baseline_years = 2013:2024,
  gam_knots = 12,
  gam_basis = "cc",  # Cyclic cubic

  # Derivative parameters
  n_posterior_sims = 1000,  # Number of posterior simulations for uncertainty
  alpha_level = 0.05,       # Significance level for derivatives

  # Output
  output_file = file.path(hls_paths$gam_models, "conus_4km_baseline_derivatives.csv"),
  derivatives_archive = file.path(hls_paths$gam_models, "derivatives"),

  # Quality control
  min_observations = 20,

  # Parallel processing (capped for shared server - max 10 cores)
  n_cores = 8,  # Use 8 cores for good balance (set to 1 for sequential)

  # Checkpointing
  checkpoint_interval = 100,
  resume_from_checkpoint = TRUE
)

# Ensure output directories exist
ensure_directory(hls_paths$gam_models)
ensure_directory(config$derivatives_archive)

cat("Configuration:\n")
cat("  Baseline years:", paste(range(config$baseline_years), collapse = "-"), "\n")
cat("  Posterior simulations:", config$n_posterior_sims, "\n")
cat("  Significance level:", config$alpha_level, "\n")
cat("  Output:", config$output_file, "\n\n")

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

#' Fit baseline GAM and calculate derivatives for a single pixel
#'
#' @param pixel_data Data frame with yday and NDVI for one pixel (all years)
#' @param pixel_id Pixel identifier
#' @param config Configuration list
#' @return Data frame with derivatives (yday, deriv_mean, deriv_lwr, deriv_upr, sig)
fit_pixel_baseline_derivatives <- function(pixel_data, pixel_id, config) {

  # Check minimum observations
  if (nrow(pixel_data) < config$min_observations) {
    return(NULL)
  }

  # Fit baseline GAM (same as Phase 2)
  gam_model <- tryCatch({
    gam(NDVI ~ s(yday, k = config$gam_knots, bs = config$gam_basis),
        data = pixel_data)
  }, error = function(e) {
    return(NULL)
  })

  if (is.null(gam_model)) return(NULL)

  # Check convergence
  if (!gam_model$converged) {
    return(NULL)
  }

  # Calculate derivatives
  newdata <- data.frame(yday = 1:365)

  derivs <- tryCatch({
    calc.derivs(
      model.gam = gam_model,
      newdata = newdata,
      vars = "yday",
      n = config$n_posterior_sims,
      alpha = config$alpha_level
    )
  }, error = function(e) {
    return(NULL)
  })

  if (is.null(derivs)) return(NULL)

  # Format output
  result <- data.frame(
    pixel_id = pixel_id,
    yday = derivs$yday,
    deriv_mean = derivs$mean,
    deriv_lwr = derivs$lwr,
    deriv_upr = derivs$upr,
    sig = as.character(derivs$sig)  # "*" if significant, NA otherwise
  )

  return(result)
}

# ==============================================================================
# MAIN PROCESSING WORKFLOW
# ==============================================================================

#' Calculate baseline derivatives for all pixels
#'
#' @param timeseries_df Full timeseries dataframe
#' @param config Configuration list
#' @return Baseline derivatives dataframe
calculate_baseline_derivatives <- function(timeseries_df, config) {

  cat("=== CALCULATING BASELINE DERIVATIVES ===\n\n")

  # Filter to baseline years
  cat("Filtering to baseline years:", paste(range(config$baseline_years), collapse = "-"), "\n")
  timeseries_baseline <- timeseries_df %>%
    filter(year %in% config$baseline_years)

  cat("  Total observations:", nrow(timeseries_baseline), "\n")

  # Get unique pixels
  pixel_ids <- unique(timeseries_baseline$pixel_id)
  n_pixels <- length(pixel_ids)

  cat("  Unique pixels:", n_pixels, "\n\n")

  # CRITICAL OPTIMIZATION: Pre-split data by pixel_id for O(1) access in workers
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
    derivatives_df <- readRDS(checkpoint_file)

    processed_pixels <- unique(derivatives_df$pixel_id)
    pixel_ids <- setdiff(pixel_ids, processed_pixels)
    n_pixels_from_checkpoint <- length(processed_pixels)

    cat("  Resuming from", n_pixels_from_checkpoint, "completed pixels\n")
    cat("  ", length(pixel_ids), "pixels remaining\n\n")
  } else {
    derivatives_df <- data.frame()
    n_pixels_from_checkpoint <- 0
  }

  if (length(pixel_ids) == 0) {
    cat("All pixels already processed!\n")
    return(derivatives_df)
  }

  # Process pixels with incremental checkpointing
  cat("Processing pixels with incremental checkpointing...\n")
  cat("Checkpoint interval:", config$checkpoint_interval, "pixels\n")
  cat("Parallel cores:", config$n_cores, "\n\n")

  start_time <- Sys.time()
  # Initialize counters - if resuming from checkpoint, start from checkpoint count
  n_processed <- n_pixels_from_checkpoint
  n_failed <- 0

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
    # pixel_list is accessible via copy-on-write shared memory
    if (config$n_cores > 1) {
      batch_results <- mclapply(batch_pixels, function(pixel_id) {
        # Load required libraries in each fork
        library(mgcv)
        library(dplyr)

        # O(1) access from pre-split list (shared via copy-on-write!)
        pixel_data <- pixel_list[[as.character(pixel_id)]]

        # Skip if insufficient data
        if (nrow(pixel_data) < config$min_observations) {
          return(NULL)
        }

        # Fit baseline and calculate derivatives
        pixel_result <- fit_pixel_baseline_derivatives(pixel_data, pixel_id, config)

        if (!is.null(pixel_result)) {
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

        pixel_result <- fit_pixel_baseline_derivatives(pixel_data, pixel_id, config)

        if (!is.null(pixel_result)) {
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
    }

    n_failed <- n_failed + (length(batch_pixels) - length(batch_results))

    # Progress reporting
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

    # Save checkpoint every N pixels (convert list to df only when checkpointing)
    if (n_processed %% config$checkpoint_interval == 0) {
      cat("  Saving checkpoint...\n")
      derivatives_df <- do.call(rbind, all_results)
      saveRDS(derivatives_df, checkpoint_file, compress = "gzip")
    }
  }

  # Final conversion to dataframe
  cat("\nCombining all results...\n")
  derivatives_df <- do.call(rbind, all_results)

  # No cluster cleanup needed with mclapply (uses forking, not SOCK cluster)

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  cat("\n=== BASELINE DERIVATIVES COMPLETE ===\n")
  cat("Time elapsed:", round(elapsed, 1), "minutes\n")
  cat("Pixels processed:", n_processed, "\n")
  cat("Pixels failed:", n_failed, "\n")
  cat("Total derivative records:", nrow(derivatives_df), "\n")
  cat("Expected records (pixels × 365 days):", n_processed * 365, "\n")
  cat("Significant changes:", sum(derivatives_df$sig == "*", na.rm = TRUE),
      "(", round(100 * mean(derivatives_df$sig == "*", na.rm = TRUE), 1), "%)\n\n")

  # Save final output
  cat("Saving baseline derivatives to:", config$output_file, "\n")
  write.csv(derivatives_df, config$output_file, row.names = FALSE)

  # Remove checkpoint
  if (file.exists(checkpoint_file)) {
    file.remove(checkpoint_file)
  }

  cat("✓ Phase 3 complete\n\n")

  return(derivatives_df)
}

#' Summarize baseline derivatives
#'
#' @param derivatives_df Derivatives dataframe
#' @return Summary statistics
summarize_baseline_derivatives <- function(derivatives_df) {

  cat("=== BASELINE DERIVATIVES SUMMARY ===\n\n")

  # Overall statistics
  cat("Total pixels:", length(unique(derivatives_df$pixel_id)), "\n")
  cat("Total records:", nrow(derivatives_df), "\n\n")

  # Derivative statistics by day of year
  yday_stats <- derivatives_df %>%
    group_by(yday) %>%
    summarise(
      mean_deriv = mean(deriv_mean),
      n_sig = sum(sig == "*", na.rm = TRUE),
      pct_sig = 100 * mean(sig == "*", na.rm = TRUE),
      .groups = "drop"
    )

  cat("Derivative patterns:\n")
  cat("  Mean derivative range:",
      round(min(yday_stats$mean_deriv), 5), "to",
      round(max(yday_stats$mean_deriv), 5), "\n")

  # Find peak green-up (maximum positive derivative)
  peak_greenup <- yday_stats$yday[which.max(yday_stats$mean_deriv)]
  cat("  Peak green-up (max +derivative):", peak_greenup, "\n")

  # Find peak senescence (maximum negative derivative)
  peak_senescence <- yday_stats$yday[which.min(yday_stats$mean_deriv)]
  cat("  Peak senescence (max -derivative):", peak_senescence, "\n\n")

  # Significance by season
  cat("Significant change by season:\n")
  derivatives_df_season <- derivatives_df %>%
    mutate(season = case_when(
      yday >= 60 & yday <= 151 ~ "Spring (Mar-May)",
      yday >= 152 & yday <= 243 ~ "Summer (Jun-Aug)",
      yday >= 244 & yday <= 334 ~ "Fall (Sep-Nov)",
      TRUE ~ "Winter (Dec-Feb)"
    ))

  season_summary <- derivatives_df_season %>%
    group_by(season) %>%
    summarise(
      pct_sig = round(100 * mean(sig == "*", na.rm = TRUE), 1),
      .groups = "drop"
    )

  print(season_summary)
  cat("\n")

  return(yday_stats)
}

# ==============================================================================
# EXECUTION
# ==============================================================================

# Check if running as main script (not being sourced)
if (!interactive() || exists("run_phase3")) {

  cat("\n=== EXECUTING PHASE 3: BASELINE DERIVATIVES ===\n")
  cat("Started at:", as.character(Sys.time()), "\n\n")

  # Load timeseries from Phase 1
  cat("Loading Phase 1 timeseries data...\n")
  timeseries_4km <- read.csv(config$timeseries_file, stringsAsFactors = FALSE)
  timeseries_4km$date <- as.Date(timeseries_4km$date)

  cat("  Total observations:", nrow(timeseries_4km), "\n")
  cat("  Unique pixels:", length(unique(timeseries_4km$pixel_id)), "\n")
  cat("  Date range:", paste(range(timeseries_4km$date), collapse = " to "), "\n\n")

  # Calculate baseline derivatives
  start_time <- Sys.time()
  baseline_derivs <- calculate_baseline_derivatives(timeseries_4km, config)
  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "hours"))

  # Summarize results
  cat("\nGenerating summary statistics...\n")
  yday_stats <- summarize_baseline_derivatives(baseline_derivs)

  # Final summary
  cat("\n=== PHASE 3 COMPLETE ===\n")
  cat("Total time:", round(elapsed, 2), "hours\n")
  cat("Output saved to:", config$output_file, "\n\n")
  cat("Interpretation:\n")
  cat("  - Derivatives show rate of NDVI change through the year\n")
  cat("  - Positive derivatives = green-up (increasing vegetation)\n")
  cat("  - Negative derivatives = senescence (decreasing vegetation)\n")
  cat("  - Significant (sig='*') = change is statistically detectable\n")
  cat("  - These serve as baseline for comparing individual years (Phase 5)\n\n")

} else {
  cat("\n=== PHASE 3 FUNCTIONS LOADED ===\n")
  cat("Ready to calculate baseline derivatives for climatological norms\n")
  cat("Estimated time: ~60-90 minutes with", config$n_cores, "core(s)\n")
  cat("Output will be saved to:", config$output_file, "\n\n")
  cat("To run manually:\n")
  cat("  timeseries_4km <- read.csv(config$timeseries_file, stringsAsFactors = FALSE)\n")
  cat("  timeseries_4km$date <- as.Date(timeseries_4km$date)\n")
  cat("  baseline_derivs <- calculate_baseline_derivatives(timeseries_4km, config)\n\n")
}
