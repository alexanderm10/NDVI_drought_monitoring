#!/usr/bin/env Rscript
# Generate a filtered list of MGRS tiles that overlap the Midwest 4km grid.
#
# The original midwest_tiles_noprefix.txt contains all 1209 CONUS tiles from
# the bulk download, ~77% of which fall outside the Midwest DEWS bbox and
# waste compute when passed to 01_aggregate_to_4km_parallel.R.
#
# This script tests each tile's geographic extent against the 4km grid bbox
# and writes only the overlapping tiles. Uses corner-point projection (fast)
# rather than full raster projection.

suppressPackageStartupMessages(library(terra))

# Match the bbox in 01_aggregate_to_4km_parallel.R::create_4km_grid()
bbox_latlon <- c(-104.5, 37.0, -82.0, 47.5)
target_crs  <- "EPSG:5070"

bbox_vect <- vect(
  data.frame(x = bbox_latlon[c(1, 3, 3, 1, 1)],
             y = bbox_latlon[c(2, 2, 4, 4, 2)]),
  geom = c("x", "y"), crs = "EPSG:4326"
)
grid_ext <- ext(project(bbox_vect, target_crs))
cat(sprintf("Target grid bbox (Albers): xmin=%.0f xmax=%.0f ymin=%.0f ymax=%.0f\n\n",
            grid_ext[1], grid_ext[2], grid_ext[3], grid_ext[4]))

# Read tiles from a complete year (2017 — done, not being actively written)
year_dir <- "/data/processed_ndvi/daily/2017"
all_files <- list.files(year_dir, pattern = "_NDVI\\.tif$", full.names = TRUE)
tiles <- gsub(".*\\.(T[0-9A-Z]+)\\..*", "\\1", basename(all_files))

unique_tiles <- sort(unique(tiles))
first_file   <- all_files[match(unique_tiles, tiles)]
cat(sprintf("Testing %d unique tiles for grid overlap...\n\n", length(unique_tiles)))

keep <- logical(length(unique_tiles))
pb_step <- max(1, floor(length(unique_tiles) / 20))

for (i in seq_along(first_file)) {
  keep[i] <- tryCatch({
    r <- rast(first_file[i])
    re <- ext(r)
    # Project just 4 corners + 4 edge midpoints (handles UTM curvature)
    corners <- vect(
      matrix(c(re[1], re[3], (re[1]+re[2])/2, re[3], re[2], re[3],
               re[2], (re[3]+re[4])/2, re[2], re[4], (re[1]+re[2])/2, re[4],
               re[1], re[4], re[1], (re[3]+re[4])/2),
             ncol = 2, byrow = TRUE),
      type = "points", crs = crs(r)
    )
    ce <- ext(project(corners, target_crs))
    !(ce[2] < grid_ext[1] | ce[1] > grid_ext[2] |
      ce[4] < grid_ext[3] | ce[3] > grid_ext[4])
  }, error = function(e) FALSE)

  if (i %% pb_step == 0) {
    cat(sprintf("  %d/%d tested, %d kept\n",
                i, length(unique_tiles), sum(keep[seq_len(i)])))
  }
}

n_kept    <- sum(keep)
n_dropped <- sum(!keep)
cat(sprintf("\nResults: %d kept (%.1f%%), %d dropped (%.1f%%)\n",
            n_kept,    100 * n_kept    / length(keep),
            n_dropped, 100 * n_dropped / length(keep)))

# Output without T prefix to match existing midwest_tiles_noprefix.txt format
midwest_tiles <- sub("^T", "", unique_tiles[keep])
out_path <- "/workspace/bulk_downloads/midwest_tiles_overlapping.txt"
writeLines(midwest_tiles, out_path)
cat(sprintf("\nWrote %d tiles to %s\n", length(midwest_tiles), out_path))
