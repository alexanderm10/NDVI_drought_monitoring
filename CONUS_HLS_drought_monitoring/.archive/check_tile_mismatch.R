# Quick script to diagnose tile mismatch

# Assuming you have the matched dataframe loaded from earlier
# matched <- run_matching_report()

# Show unique tiles in your NDVI data
ndvi_tiles <- sort(unique(matched$tile_id))
cat("=== TILES IN YOUR NDVI DATA ===\n")
cat("Total unique tiles:", length(ndvi_tiles), "\n\n")
print(ndvi_tiles)

# Now check what tiles exist in the downloaded Fmask
fmask_dirs <- list.dirs("U:/datasets/ndvi_monitor/raw_hls_data", recursive = FALSE)
fmask_tiles <- grep("midwest_T", basename(fmask_dirs), value = TRUE)
fmask_tiles <- sub("midwest_", "", fmask_tiles)

cat("\n\n=== TILES IN DOWNLOADED FMASK ===\n")
cat("Total unique tiles:", length(fmask_tiles), "\n\n")
print(sort(fmask_tiles))

# Find overlap
overlap <- intersect(ndvi_tiles, fmask_tiles)
ndvi_only <- setdiff(ndvi_tiles, fmask_tiles)
fmask_only <- setdiff(fmask_tiles, ndvi_tiles)

cat("\n\n=== OVERLAP ANALYSIS ===\n")
cat("Tiles in both NDVI and Fmask:", length(overlap), "\n")
cat("Tiles ONLY in NDVI (missing Fmask):", length(ndvi_only), "\n")
cat("Tiles ONLY in Fmask (extra downloads):", length(fmask_only), "\n\n")

if (length(ndvi_only) > 0) {
  cat("Missing tiles (need to download Fmask for these):\n")
  print(sort(ndvi_only))
}

cat("\n\nThis explains the low match rate!\n")
cat("You need to download Fmask for these", length(ndvi_only), "tiles specifically.\n")
