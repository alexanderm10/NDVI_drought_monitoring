# ==============================================================================
# PHASE 2: CLIMATOLOGICAL NORMS (2013-2024)
# ==============================================================================
# Purpose: Fit pixel-by-pixel GAMs pooling all complete years for baseline norms
# Input: conus_4km_ndvi_timeseries.csv from Phase 1
# Output: Climatology curves with uncertainty (pixel_id, yday, norm_mean, norm_se)
# ==============================================================================

library(mgcv)
library(dplyr)
library(parallel)

# Source path configuration
source("00_setup_paths.R")
hls_paths <- get_hls_paths()

cat("=== PHASE 2: CLIMATOLOGICAL NORMS ===\n\n")

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
  output_file = file.path(hls_paths$gam_models, "conus_4km_climatology.csv"),
  model_archive = file.path(hls_paths$gam_models, "norms", "climatology_models.rds"),

  # Quality control
  min_observations = 20,  # Minimum obs per pixel for reliable fit

  # Parallel processing
  n_cores = parallel::detectCores() - 1,

  # Checkpointing
  checkpoint_interval = 100,
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

#' Fit climatological GAM for a single pixel
#'
#' @param pixel_data Data frame with yday and NDVI for one pixel (all years pooled)
#' @param k Number of knots
#' @param bs Basis type
#' @return Data frame with yday, norm_mean, norm_se
fit_pixel_climatology <- function(pixel_data, k = 12, bs = "cc") {

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

#' Process climatology for all pixels (with parallel processing)
#'
#' @param timeseries_df Full timeseries dataframe
#' @param config Configuration list
#' @return Climatology dataframe
fit_all_climatologies <- function(timeseries_df, config) {

  cat("=== FITTING CLIMATOLOGICAL GAMS ===\n\n")

  # Filter to baseline years
  cat("Filtering to baseline years:", paste(range(config$baseline_years), collapse = "-"), "\n")
  timeseries_baseline <- timeseries_df %>%
    filter(year %in% config$baseline_years)

  cat("  Total observations:", nrow(timeseries_baseline), "\n")

  # Get unique pixels
  pixel_ids <- unique(timeseries_baseline$pixel_id)
  n_pixels <- length(pixel_ids)

  cat("  Unique 4km pixels:", n_pixels, "\n\n")

  # Check for checkpoint
  checkpoint_file <- sub("\\.csv$", "_checkpoint.csv", config$output_file)

  if (config$resume_from_checkpoint && file.exists(checkpoint_file)) {
    cat("Found checkpoint - loading previous progress...\n")
    climatology_df <- read.csv(checkpoint_file, stringsAsFactors = FALSE)

    processed_pixels <- unique(climatology_df$pixel_id)
    pixel_ids <- setdiff(pixel_ids, processed_pixels)

    cat("  Resuming from", length(processed_pixels), "completed pixels\n")
    cat("  ", length(pixel_ids), "pixels remaining\n\n")
  } else {
    climatology_df <- data.frame()
  }

  if (length(pixel_ids) == 0) {
    cat("All pixels already processed!\n")
    return(climatology_df)
  }

  # Parallel processing function
  process_pixel_batch <- function(pixel_batch) {

    batch_results <- list()

    for (pixel_id in pixel_batch) {

      # Extract pixel data
      pixel_data <- timeseries_baseline %>%
        filter(pixel_id == !!pixel_id)

      # Skip if insufficient data
      if (nrow(pixel_data) < config$min_observations) {
        next
      }

      # Fit climatology
      pixel_clim <- fit_pixel_climatology(
        pixel_data,
        k = config$gam_knots,
        bs = config$gam_basis
      )

      if (!is.null(pixel_clim)) {
        pixel_clim$pixel_id <- pixel_id
        batch_results[[length(batch_results) + 1]] <- pixel_clim
      }
    }

    if (length(batch_results) > 0) {
      return(bind_rows(batch_results))
    } else {
      return(NULL)
    }
  }

  # Split pixels into batches for parallel processing
  batch_size <- ceiling(length(pixel_ids) / config$n_cores)
  pixel_batches <- split(pixel_ids, ceiling(seq_along(pixel_ids) / batch_size))

  cat("Processing", length(pixel_batches), "batches in parallel...\n")
  cat("Batch size:", batch_size, "pixels\n\n")

  start_time <- Sys.time()

  # Set up cluster
  cl <- makeCluster(config$n_cores)
  clusterEvalQ(cl, {
    library(mgcv)
    library(dplyr)
  })
  clusterExport(cl, c("timeseries_baseline", "config", "fit_pixel_climatology"),
                envir = environment())

  # Process batches
  batch_results <- parLapply(cl, pixel_batches, process_pixel_batch)

  stopCluster(cl)

  # Combine results
  new_climatology <- bind_rows(batch_results)

  if (nrow(new_climatology) > 0) {
    climatology_df <- bind_rows(climatology_df, new_climatology)
  }

  elapsed <- as.numeric(difftime(Sys.time(), start_time, units = "mins"))

  cat("\n=== CLIMATOLOGY FITTING COMPLETE ===\n")
  cat("Time elapsed:", round(elapsed, 1), "minutes\n")
  cat("Pixels processed:", length(unique(climatology_df$pixel_id)), "\n")
  cat("Total climatology records:", nrow(climatology_df), "\n")
  cat("Expected records (pixels × 365 days):", length(unique(climatology_df$pixel_id)) * 365, "\n\n")

  # Save final output
  cat("Saving climatology to:", config$output_file, "\n")
  write.csv(climatology_df, config$output_file, row.names = FALSE)

  # Remove checkpoint
  if (file.exists(checkpoint_file)) {
    file.remove(checkpoint_file)
  }

  cat("✓ Phase 2 complete\n\n")

  return(climatology_df)
}

#' Generate summary statistics for climatology
#'
#' @param climatology_df Climatology dataframe
#' @return Summary table
summarize_climatology <- function(climatology_df) {

  cat("=== CLIMATOLOGY SUMMARY ===\n\n")

  # Overall statistics
  cat("Total pixels:", length(unique(climatology_df$pixel_id)), "\n")
  cat("Total records:", nrow(climatology_df), "\n\n")

  # NDVI range by day of year
  yday_stats <- climatology_df %>%
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
  cat("  Median SE:", round(median(climatology_df$norm_se), 4), "\n")
  cat("  95th percentile SE:", round(quantile(climatology_df$norm_se, 0.95), 4), "\n\n")

  return(yday_stats)
}

# ==============================================================================
# EXECUTION
# ==============================================================================

cat("=== READY TO FIT CLIMATOLOGICAL NORMS ===\n")
cat("This will fit GAMs for all pixels using", paste(range(config$baseline_years), collapse = "-"), "data\n")
cat("Estimated time: ~30 minutes with", config$n_cores, "cores\n")
cat("Output will be saved to:", config$output_file, "\n\n")
cat("To run:\n")
cat("  # Load timeseries from Phase 1\n")
cat("  timeseries_4km <- read.csv(config$input_file, stringsAsFactors = FALSE)\n")
cat("  timeseries_4km$date <- as.Date(timeseries_4km$date)\n\n")
cat("  # Fit climatologies\n")
cat("  climatology <- fit_all_climatologies(timeseries_4km, config)\n\n")
cat("  # Summarize results\n")
cat("  yday_stats <- summarize_climatology(climatology)\n\n")
