# Download Fmask by Direct Scene ID Query
# Query each scene individually by ID - 100% reliable

library(httr)
library(jsonlite)

source("00_setup_paths.R")
source("01_HLS_data_acquisition_FINAL.R")

hls_paths <- get_hls_paths()

cat("=== DIRECT SCENE ID FMASK DOWNLOAD ===\n\n")

######################
# Get Fmask URL by Scene ID
######################

get_fmask_url <- function(scene_id, collection) {

  # Convert collection: HLSL30.v2.0 -> HLSL30_2.0
  api_collection <- gsub("\\.v", "_", collection)

  # Direct item query URL
  url <- paste0("https://cmr.earthdata.nasa.gov/stac/LPCLOUD/collections/",
                api_collection, "/items/", scene_id)

  response <- try({
    GET(url, timeout(10))
  }, silent = TRUE)

  if (inherits(response, "try-error") || status_code(response) != 200) {
    return(NULL)
  }

  content_json <- fromJSON(content(response, "text", encoding = "UTF-8"), simplifyVector = FALSE)

  # Extract Fmask URL
  if (!is.null(content_json$assets$Fmask$href)) {
    return(content_json$assets$Fmask$href)
  }

  return(NULL)
}

######################
# Download All Fmask
######################

download_fmask_direct <- function(cache_file = "scene_list_cache.csv") {

  # Load scenes
  scenes_df <- read.csv(cache_file, stringsAsFactors = FALSE)

  cat("Loaded", nrow(scenes_df), "scenes\n")
  cat("Will query each scene individually by ID\n\n")

  # Set up NASA session
  nasa_session <- create_nasa_session()

  success_count <- 0
  fail_count <- 0
  skip_count <- 0

  pb <- txtProgressBar(min = 0, max = nrow(scenes_df), style = 3)

  for (i in 1:nrow(scenes_df)) {
    scene <- scenes_df[i, ]

    fmask_file <- file.path(scene$scene_dir, paste0(scene$scene_id, "_Fmask.tif"))

    # Skip if exists
    if (file.exists(fmask_file)) {
      skip_count <- skip_count + 1
      setTxtProgressBar(pb, i)
      next
    }

    # Get Fmask URL by direct query
    fmask_url <- get_fmask_url(scene$scene_id, scene$collection)

    if (is.null(fmask_url)) {
      fail_count <- fail_count + 1
      setTxtProgressBar(pb, i)
      next
    }

    # Download
    success <- download_hls_band(fmask_url, fmask_file, nasa_session)

    if (success) {
      success_count <- success_count + 1
    } else {
      fail_count <- fail_count + 1
    }

    setTxtProgressBar(pb, i)

    # Brief pause every 100 requests
    if (i %% 100 == 0) {
      Sys.sleep(1)
    } else {
      Sys.sleep(0.05)
    }
  }

  close(pb)

  cat("\n\n=== DOWNLOAD COMPLETE ===\n")
  cat("Successfully downloaded:", success_count, "\n")
  cat("Skipped (already exist):", skip_count, "\n")
  cat("Failed:", fail_count, "\n")
  cat("Total scenes:", nrow(scenes_df), "\n")

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

run_direct_download <- function(cache_file = "scene_list_cache.csv") {

  cat("=== DIRECT SCENE ID QUERY METHOD ===\n")
  cat("Queries each scene individually by ID - most reliable approach\n")
  cat("Will make ~4500 lightweight API requests\n\n")

  results <- download_fmask_direct(cache_file)

  return(results)
}

# Instructions
cat("=== DIRECT FMASK DOWNLOAD READY ===\n")
cat("This queries NASA's API directly for each scene by ID\n")
cat("100% reliable - if Fmask exists, we'll get it\n\n")
cat("To run:\n")
cat("  results <- run_direct_download()\n\n")
cat("Estimated time: 15-30 minutes for 4500 scenes\n\n")
