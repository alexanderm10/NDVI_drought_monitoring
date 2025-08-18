# ==============================================================================
# CROSS-PLATFORM PATH SETUP FOR HLS NDVI MONITORING
# ==============================================================================
# Purpose: Automatically detect OS and configure data paths for Windows/Linux
# Author: M. Ross Alexander
# Date: 2025-08-18
# ==============================================================================

setup_hls_paths <- function() {
  
  # Detect operating system
  os_type <- Sys.info()["sysname"]
  
  # Set base paths based on OS
  if (os_type == "Windows") {
    # Windows: Use network drive or local fallback
    if (dir.exists("U:/datasets/ndvi_monitor")) {
      base_path <- "U:/datasets/ndvi_monitor"
      cat("✓ Using Windows U: drive path\n")
    } else if (dir.exists("U:/datasets")) {
      base_path <- "U:/datasets/ndvi_monitor"
      ensure_directory(base_path)
      cat("✓ Created ndvi_monitor directory on U: drive\n")
    } else if (dir.exists("C:/Users/malexander/Documents/ndvi_data")) {
      base_path <- "C:/Users/malexander/Documents/ndvi_data"
      cat("✓ Using local Windows fallback path\n")
    } else {
      base_path <- "C:/Users/malexander/Documents/ndvi_data"
      ensure_directory(base_path)
      cat("⚠ Created local fallback directory - may not have enough space for CONUS data\n")
    }
  } else if (os_type == "Linux") {
    # Linux: Check Docker environment first, then mounted drive path
    if (dir.exists("/data/ndvi_monitor")) {
      base_path <- "/data/ndvi_monitor"
      cat("✓ Using Docker container data path\n")
    } else if (dir.exists("/data")) {
      base_path <- "/data/ndvi_monitor"
      ensure_directory(base_path)
      cat("✓ Created ndvi_monitor directory in Docker container\n")
    } else if (dir.exists("/mnt/malexander/datasets/ndvi_monitor")) {
      base_path <- "/mnt/malexander/datasets/ndvi_monitor"
      cat("✓ Using Linux mounted path\n")
    } else if (dir.exists("/mnt/malexander/datasets")) {
      base_path <- "/mnt/malexander/datasets/ndvi_monitor"
      ensure_directory(base_path)
      cat("✓ Created ndvi_monitor directory on mounted drive\n")
    } else {
      stop("❌ Linux: Cannot find data directory at /mnt/malexander/datasets or /data")
    }
  } else {
    stop("❌ Unsupported operating system: ", os_type)
  }
  
  # Construct full data paths
  data_paths <- list(
    base = base_path,
    
    # HLS data paths
    raw_hls_data = file.path(base_path, "raw_hls_data"),
    processed_ndvi = file.path(base_path, "processed_ndvi"),
    temporal_extracts = file.path(base_path, "temporal_extracts"),
    
    # Analysis paths
    gam_models = file.path(base_path, "gam_models"),
    anomaly_products = file.path(base_path, "anomaly_products"),
    validation_data = file.path(base_path, "validation"),
    
    # Metadata and logs
    metadata = file.path(base_path, "metadata"),
    processing_logs = file.path(base_path, "logs"),
    
    # Land cover and reference data
    reference_data = file.path(base_path, "reference_data"),
    land_cover = file.path(base_path, "reference_data/land_cover"),
    
    # Output products
    figures = file.path(base_path, "figures"),
    reports = file.path(base_path, "reports"),
    web_products = file.path(base_path, "web_products")
  )
  
  # Convert all paths to use forward slashes for cross-platform compatibility
  data_paths <- lapply(data_paths, function(x) gsub("\\\\", "/", x))
  
  return(data_paths)
}

#' Create directory if it doesn't exist
#' 
#' @param path Directory path to create
#' @param recursive Create parent directories if needed
ensure_directory <- function(path, recursive = TRUE) {
  if (!dir.exists(path)) {
    dir.create(path, showWarnings = FALSE, recursive = recursive)
    cat("✓ Created directory:", path, "\n")
  }
}

#' Set up complete directory structure for HLS processing
#' 
#' @param paths Path list from setup_hls_paths()
create_hls_directory_structure <- function(paths = setup_hls_paths()) {
  
  cat("Creating HLS data directory structure...\n")
  
  # Create all directories
  for (path_name in names(paths)) {
    ensure_directory(paths[[path_name]])
  }
  
  # Create subdirectories for organized storage
  
  # Raw data by year
  for (year in 2020:2024) {
    ensure_directory(file.path(paths$raw_hls_data, paste0("year_", year)))
  }
  
  # Processed NDVI by product type
  ndvi_subdirs <- c("daily", "monthly", "seasonal", "annual")
  for (subdir in ndvi_subdirs) {
    ensure_directory(file.path(paths$processed_ndvi, subdir))
  }
  
  # Temporal extracts by land cover type
  lc_types <- c("crop", "forest", "grassland", "urban_high", "urban_med", "urban_low", "urban_open", "wetland")
  for (lc_type in lc_types) {
    ensure_directory(file.path(paths$temporal_extracts, lc_type))
  }
  
  # Model outputs by analysis type
  model_types <- c("norms", "individual_years", "derivatives", "anomalies")
  for (model_type in model_types) {
    ensure_directory(file.path(paths$gam_models, model_type))
  }
  
  cat("✓ Complete directory structure created\n")
  return(paths)
}

#' Verify critical paths exist and are accessible
#' 
#' @param paths Path list from setup_hls_paths()
#' @param required_paths Vector of required path names to check
verify_hls_paths <- function(paths, required_paths = c("base", "raw_hls_data", "processed_ndvi")) {
  
  missing_paths <- c()
  
  for (path_name in required_paths) {
    if (path_name %in% names(paths)) {
      path <- paths[[path_name]]
      if (!dir.exists(path) && !file.exists(path)) {
        missing_paths <- c(missing_paths, paste0(path_name, ": ", path))
      }
    } else {
      missing_paths <- c(missing_paths, paste0("Path '", path_name, "' not defined"))
    }
  }
  
  if (length(missing_paths) > 0) {
    cat("⚠ Missing paths (will create if needed):\n")
    cat(paste(missing_paths, collapse = "\n"), "\n")
  } else {
    cat("✓ All required paths verified successfully\n")
  }
  
  cat("\n=== HLS DATA PATHS CONFIGURED ===\n")
  cat("Operating System:", Sys.info()["sysname"], "\n")
  cat("Base Path:", paths$base, "\n")
  cat("Storage space check: Run 'check_storage_space(paths$base)' to verify capacity\n")
  cat("Platform-specific paths ready for HLS processing\n")
  
  return(paths)
}

#' Check available storage space
#' 
#' @param path Directory path to check
check_storage_space <- function(path) {
  
  if (Sys.info()["sysname"] == "Windows") {
    # Use dir command on Windows
    result <- try({
      cmd <- paste0('dir "', dirname(path), '" /-c | findstr "bytes free"')
      system(cmd, intern = TRUE)
    }, silent = TRUE)
    
    if (class(result) == "try-error") {
      cat("⚠ Could not check storage space on Windows\n")
    } else {
      cat("Storage info:", result[length(result)], "\n")
    }
    
  } else {
    # Use df command on Linux
    result <- try({
      system(paste("df -h", path), intern = TRUE)
    }, silent = TRUE)
    
    if (class(result) == "try-error") {
      cat("⚠ Could not check storage space on Linux\n") 
    } else {
      cat("Storage info:\n")
      cat(paste(result, collapse = "\n"), "\n")
    }
  }
  
  cat("\n⚠ HLS CONUS data can be 100+ GB per year. Ensure adequate storage space.\n")
}

# Convenience function to source this in scripts
get_hls_paths <- function() {
  paths <- setup_hls_paths()
  return(verify_hls_paths(paths))
}