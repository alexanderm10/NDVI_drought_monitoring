# ==============================================================================
# REGIONAL CONFIGURATION FOR OPERATIONAL DROUGHT MONITORING
# ==============================================================================
# Purpose: Define regions and parameters for scalable monitoring
# Scale: Regional (Midwest) → CONUS-wide
# Author: M. Ross Alexander
# Date: 2025-10-21
# ==============================================================================

library(yaml)

# ==============================================================================
# REGIONAL DEFINITIONS
# ==============================================================================

#' Get region configuration by name
#'
#' @param region_name Character: "midwest", "conus", "custom"
#' @return List with region parameters
#' @export
get_region_config <- function(region_name = "midwest") {

  regions <- list(

    # Midwest DEWS domain (current)
    midwest = list(
      name = "Midwest DEWS",
      bbox_latlon = c(xmin = -104.5, ymin = 37.0, xmax = -82.0, ymax = 47.5),
      description = "Midwest Drought Early Warning System region",
      states = c("ND", "SD", "NE", "KS", "MN", "IA", "MO", "WI", "IL", "IN", "MI", "OH"),
      target_crs = "EPSG:5070",  # Albers Equal Area
      resolution = 4000,          # 4km
      expected_pixels = ~15000,
      hls_tiles = NULL,           # Auto-detected from bbox
      update_frequency = "weekly",
      baseline_years = 2013:2024
    ),

    # Full CONUS
    conus = list(
      name = "CONUS",
      bbox_latlon = c(xmin = -125.0, ymin = 24.0, xmax = -66.0, ymax = 50.0),
      description = "Continental United States",
      states = NULL,              # All lower 48
      target_crs = "EPSG:5070",   # Albers Equal Area
      resolution = 4000,           # 4km
      expected_pixels = ~500000,  # Rough estimate
      hls_tiles = NULL,
      update_frequency = "weekly",
      baseline_years = 2013:2024
    ),

    # Great Plains
    great_plains = list(
      name = "Great Plains",
      bbox_latlon = c(xmin = -106.0, ymin = 33.0, xmax = -94.0, ymax = 49.0),
      description = "Great Plains drought monitoring",
      states = c("MT", "ND", "SD", "WY", "NE", "KS", "OK", "TX"),
      target_crs = "EPSG:5070",
      resolution = 4000,
      expected_pixels = ~50000,
      hls_tiles = NULL,
      update_frequency = "weekly",
      baseline_years = 2013:2024
    ),

    # Western US
    western = list(
      name = "Western US",
      bbox_latlon = c(xmin = -125.0, ymin = 31.0, xmax = -102.0, ymax = 49.0),
      description = "Western US drought monitoring",
      states = c("WA", "OR", "CA", "ID", "NV", "UT", "AZ", "MT", "WY", "CO", "NM"),
      target_crs = "EPSG:5070",
      resolution = 4000,
      expected_pixels = ~150000,
      hls_tiles = NULL,
      update_frequency = "weekly",
      baseline_years = 2013:2024
    ),

    # Custom template
    custom = list(
      name = "Custom Region",
      bbox_latlon = c(xmin = NA, ymin = NA, xmax = NA, ymax = NA),
      description = "User-defined region",
      states = NULL,
      target_crs = "EPSG:5070",
      resolution = 4000,
      expected_pixels = NULL,
      hls_tiles = NULL,
      update_frequency = "weekly",
      baseline_years = 2013:2024
    )
  )

  if (!region_name %in% names(regions)) {
    stop("Unknown region: ", region_name,
         "\nAvailable regions: ", paste(names(regions), collapse = ", "))
  }

  config <- regions[[region_name]]
  config$region_id <- region_name

  return(config)
}

# ==============================================================================
# OPERATIONAL PARAMETERS
# ==============================================================================

#' Get operational monitoring configuration
#'
#' @param region_config Region configuration from get_region_config()
#' @param mode Character: "development", "operational"
#' @return List with operational parameters
#' @export
get_operational_config <- function(region_config, mode = "operational") {

  base_config <- list(

    # Data update parameters
    update = list(
      lookback_days = 45,         # How far back to check for new data
      min_scenes_per_update = 10, # Minimum new scenes to trigger reprocessing
      max_cloud_cover = 50,       # Maximum cloud cover % for HLS scenes
      buffer_days = 3             # Extra days at edges for robustness
    ),

    # Baseline management
    baseline = list(
      recalculation_frequency = "annual",  # "monthly", "seasonal", "annual", "never"
      min_baseline_years = 10,             # Minimum years for stable baseline
      rolling_window = FALSE,              # Use rolling N-year window vs fixed
      rolling_window_years = 10,
      update_trigger = "january"           # When to recalculate ("january", "continuous")
    ),

    # Processing parameters
    processing = list(
      parallel_cores = parallel::detectCores() - 1,
      chunk_size = 1000,          # Pixels per processing chunk
      memory_limit_gb = 32,       # Memory constraint
      checkpoint_frequency = 100,  # Checkpoint every N chunks
      retry_failures = TRUE,
      max_retries = 3
    ),

    # Quality control
    qc = list(
      min_observations_baseline = 20,
      min_observations_year = 15,
      ndvi_range = c(-0.2, 1.0),  # Valid NDVI range
      flag_anomalies = TRUE,       # Flag suspicious values
      spatial_consistency_check = TRUE
    ),

    # Product generation
    products = list(
      generate_maps = TRUE,
      generate_timeseries = TRUE,
      generate_reports = TRUE,
      export_formats = c("csv", "geotiff", "netcdf"),
      retention_days = 730,        # Keep products for 2 years
      archive_baseline = TRUE
    ),

    # Alert thresholds (optional - for automated notifications)
    alerts = list(
      enable = FALSE,
      anomaly_threshold_zscore = -2.0,    # Z-score for magnitude alerts
      area_threshold_pct = 10,             # % of region in drought for alert
      persistence_days = 14,               # Days anomaly must persist
      email_recipients = NULL,
      webhook_url = NULL
    )
  )

  # Adjust based on mode
  if (mode == "development") {
    base_config$processing$parallel_cores <- 1
    base_config$update$min_scenes_per_update <- 1
    base_config$products$generate_maps <- FALSE
    base_config$alerts$enable <- FALSE
  }

  # Merge with region config
  config <- c(region = list(region_config), base_config)
  config$mode <- mode
  config$created <- Sys.time()

  return(config)
}

# ==============================================================================
# CONFIGURATION PERSISTENCE
# ==============================================================================

#' Save configuration to YAML file
#'
#' @param config Configuration list
#' @param output_path Path to save YAML
#' @export
save_config <- function(config, output_path) {

  # Convert to YAML-friendly format
  yaml_config <- config
  yaml_config$created <- as.character(config$created)

  # Write YAML
  yaml::write_yaml(yaml_config, output_path)

  cat("✓ Configuration saved to:", output_path, "\n")
}

#' Load configuration from YAML file
#'
#' @param config_path Path to YAML file
#' @return Configuration list
#' @export
load_config <- function(config_path) {

  if (!file.exists(config_path)) {
    stop("Configuration file not found: ", config_path)
  }

  config <- yaml::read_yaml(config_path)
  config$created <- as.POSIXct(config$created)

  cat("✓ Configuration loaded from:", config_path, "\n")

  return(config)
}

# ==============================================================================
# VALIDATION
# ==============================================================================

#' Validate configuration
#'
#' @param config Configuration list
#' @return Logical: TRUE if valid, stops with error if invalid
#' @export
validate_config <- function(config) {

  # Check required fields
  required <- c("region", "update", "baseline", "processing", "qc", "products")
  missing <- setdiff(required, names(config))

  if (length(missing) > 0) {
    stop("Missing required configuration sections: ", paste(missing, collapse = ", "))
  }

  # Check bbox
  bbox <- config$region$bbox_latlon
  if (any(is.na(bbox))) {
    stop("Bounding box contains NA values")
  }
  if (bbox["xmin"] >= bbox["xmax"] || bbox["ymin"] >= bbox["ymax"]) {
    stop("Invalid bounding box: min must be < max")
  }

  # Check baseline years
  if (length(config$region$baseline_years) < config$baseline$min_baseline_years) {
    warning("Baseline period shorter than minimum recommended (",
            length(config$region$baseline_years), " < ",
            config$baseline$min_baseline_years, " years)")
  }

  # Check resource limits
  if (config$processing$parallel_cores > parallel::detectCores()) {
    warning("Requested cores (", config$processing$parallel_cores,
            ") exceeds available (", parallel::detectCores(), ")")
    config$processing$parallel_cores <- parallel::detectCores() - 1
  }

  cat("✓ Configuration validated successfully\n")

  return(TRUE)
}

# ==============================================================================
# CONVENIENCE FUNCTIONS
# ==============================================================================

#' Initialize operational monitoring for a region
#'
#' @param region_name Region identifier
#' @param mode "development" or "operational"
#' @param output_dir Directory to save config
#' @return Configuration list
#' @export
#' @examples
#' # Midwest operational
#' config <- init_monitoring("midwest", "operational")
#'
#' # CONUS development/testing
#' config <- init_monitoring("conus", "development")
init_monitoring <- function(region_name = "midwest",
                            mode = "operational",
                            output_dir = "operational_monitoring/config") {

  cat("\n=== INITIALIZING OPERATIONAL MONITORING ===\n\n")

  # Get region config
  region_config <- get_region_config(region_name)
  cat("Region:", region_config$name, "\n")
  cat("Bbox:", paste(region_config$bbox_latlon, collapse = ", "), "\n")
  cat("Resolution:", region_config$resolution, "m\n")
  cat("Baseline period:", paste(range(region_config$baseline_years), collapse = "-"), "\n\n")

  # Get operational config
  config <- get_operational_config(region_config, mode)
  cat("Mode:", mode, "\n")
  cat("Update frequency:", config$region$update_frequency, "\n")
  cat("Parallel cores:", config$processing$parallel_cores, "\n\n")

  # Validate
  validate_config(config)

  # Save
  if (!is.null(output_dir)) {
    if (!dir.exists(output_dir)) {
      dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
    }

    output_path <- file.path(output_dir, paste0(region_name, "_", mode, ".yaml"))
    save_config(config, output_path)
  }

  cat("\n✓ Operational monitoring initialized\n")
  cat("Region:", region_name, "| Mode:", mode, "\n\n")

  return(config)
}

#' Print configuration summary
#'
#' @param config Configuration list
#' @export
print_config_summary <- function(config) {

  cat("\n=== CONFIGURATION SUMMARY ===\n\n")
  cat("Region:", config$region$name, "\n")
  cat("Mode:", config$mode, "\n")
  cat("Created:", as.character(config$created), "\n\n")

  cat("Spatial:\n")
  cat("  Bbox:", paste(config$region$bbox_latlon, collapse = ", "), "\n")
  cat("  Resolution:", config$region$resolution, "m\n")
  cat("  CRS:", config$region$target_crs, "\n")
  cat("  Expected pixels:", config$region$expected_pixels, "\n\n")

  cat("Temporal:\n")
  cat("  Baseline:", paste(range(config$region$baseline_years), collapse = "-"), "\n")
  cat("  Update frequency:", config$region$update_frequency, "\n")
  cat("  Lookback days:", config$update$lookback_days, "\n\n")

  cat("Processing:\n")
  cat("  Cores:", config$processing$parallel_cores, "\n")
  cat("  Chunk size:", config$processing$chunk_size, "pixels\n")
  cat("  Memory limit:", config$processing$memory_limit_gb, "GB\n\n")

  cat("Products:\n")
  cat("  Formats:", paste(config$products$export_formats, collapse = ", "), "\n")
  cat("  Retention:", config$products$retention_days, "days\n\n")

  if (config$alerts$enable) {
    cat("Alerts: ENABLED\n")
    cat("  Threshold:", config$alerts$anomaly_threshold_zscore, "z-score\n")
    cat("  Area threshold:", config$alerts$area_threshold_pct, "%\n\n")
  } else {
    cat("Alerts: DISABLED\n\n")
  }
}

# ==============================================================================
# QUICK START EXAMPLES
# ==============================================================================

# Example 1: Initialize Midwest operational monitoring
# config_midwest <- init_monitoring("midwest", "operational")

# Example 2: Initialize CONUS development/testing
# config_conus <- init_monitoring("conus", "development")

# Example 3: Load existing config
# config <- load_config("operational_monitoring/config/midwest_operational.yaml")

# Example 4: Print summary
# print_config_summary(config)
