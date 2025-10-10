# Download Fmask Using Original Search Method
# Use the same proven search_hls_data() function that worked for initial download

library(httr)
library(jsonlite)

source("00_setup_paths.R")
source("01_HLS_data_acquisition_FINAL.R")

hls_paths <- get_hls_paths()

cat("=== FMASK DOWNLOAD - ORIGINAL METHOD ===\n\n")

######################
# Load Scene Cache
######################

load_scene_cache <- function(cache_file = "scene_list_cache.csv") {
  scenes_df <- read.csv(cache_file, stringsAsFactors = FALSE)
  scenes_df$date <- as.Date(scenes_df$date)

  cat("Loaded", nrow(scenes_df), "scenes from cache\n")
  cat("Date range:", min(scenes_df$date), "to", max(scenes_df$date), "\n\n")

  return(scenes_df)
}

######################
# Search and Match
######################

download_fmask_original <- function(cache_file = "scene_list_cache.csv") {

  # Load our scene list
  scenes_df <- load_scene_cache(cache_file)

  # Create scene ID lookup with paths
  scene_lookup <- setNames(scenes_df$scene_dir, scenes_df$scene_id)

  # Midwest bbox - same as original
  midwest_bbox <- c(-104.5, 37.0, -82.0, 47.5)

  # Get unique years
  years <- sort(unique(scenes_df$year))

  cat("=== STARTING FMASK DOWNLOAD ===\n")
  cat("Using original search_hls_data() method\n")
  cat("Searching by MONTH to avoid API limits\n")
  cat("Processing", length(years), "years × 12 months =", length(years) * 12, "searches\n\n")

  # Set up NASA session
  nasa_session <- create_nasa_session()

  success_count <- 0
  fail_count <- 0
  skip_count <- 0

  for (year in years) {

    cat("\n--- Year", year, "---\n")

    # Search month by month to stay under API limit
    for (month in 1:12) {

      # Calculate month date range
      start_date <- as.Date(paste0(year, "-", sprintf("%02d", month), "-01"))
      if (month == 12) {
        end_date <- as.Date(paste0(year, "-12-31"))
      } else {
        end_date <- as.Date(paste0(year, "-", sprintf("%02d", month + 1), "-01")) - 1
      }

      # Search using original method
      month_scenes <- search_hls_data(
        bbox = midwest_bbox,
        start_date = as.character(start_date),
        end_date = as.character(end_date),
        cloud_cover = 100,  # Get all scenes regardless of clouds
        max_items = 1000
      )

      if (length(month_scenes) > 0) {
        cat("  ", format(start_date, "%b"), ":", length(month_scenes), "scenes\n")
      }

      # Match and download
      for (scene in month_scenes) {

        # Check if this scene is in our cache
        if (scene$scene_id %in% names(scene_lookup)) {

          scene_dir <- scene_lookup[[scene$scene_id]]
          fmask_file <- file.path(scene_dir, paste0(scene$scene_id, "_Fmask.tif"))

          # Skip if already exists
          if (file.exists(fmask_file)) {
            skip_count <- skip_count + 1
            next
          }

          # Download Fmask - same function as original
          success <- download_hls_band(scene$fmask_url, fmask_file, nasa_session)

          if (success) {
            success_count <- success_count + 1
          } else {
            fail_count <- fail_count + 1
          }

          Sys.sleep(0.05)
        }
      }

      Sys.sleep(0.2)  # Brief pause between months
    }

    cat("Year", year, "complete: Success =", success_count, "Skip =", skip_count, "Fail =", fail_count, "\n")
  }

  cat("\n\n=== DOWNLOAD COMPLETE ===\n")
  cat("Successfully downloaded:", success_count, "\n")
  cat("Skipped (already exist):", skip_count, "\n")
  cat("Failed:", fail_count, "\n")
  cat("Total scenes in cache:", nrow(scenes_df), "\n")

  final_coverage <- round(100 * (success_count + skip_count) / nrow(scenes_df), 1)
  cat("\nFinal Fmask coverage:", final_coverage, "%\n\n")

  return(list(
    success = success_count,
    failed = fail_count,
    skipped = skip_count
  ))
}

######################
# Main Function
######################

run_original_method <- function(cache_file = "scene_list_cache.csv") {

  cat("=== USING ORIGINAL DOWNLOAD METHOD ===\n")
  cat("This uses the same search_hls_data() that worked initially\n\n")

  results <- download_fmask_original(cache_file)

  return(results)
}

# Instructions
cat("=== ORIGINAL METHOD FMASK DOWNLOAD READY ===\n")
cat("Uses the proven search_hls_data() function from initial download\n\n")
cat("To run:\n")
cat("  results <- run_original_method()\n\n")
cat("This approach:\n")
cat("  - Searches by Midwest bbox + year (same as original)\n")
cat("  - Returns scenes with fmask_url already included\n")
cat("  - Matches to your scene cache\n")
cat("  - Downloads missing Fmask files\n\n")
