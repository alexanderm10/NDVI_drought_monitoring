# Fmask Download - Direct Scene ID Query
# Query each scene individually - 100% reliable

source("download_fmask_direct.R")
results <- run_direct_download()

# This will:
#   - Query NASA API directly by scene ID (proven to work - see curl test)
#   - Get Fmask URL for each scene individually
#   - Download missing Fmask files
#   - ~4500 lightweight API requests
#   - 100% reliable if Fmask exists in archive

# Estimated time: 15-30 minutes

# After it completes, verify with:
source("match_ndvi_fmask.R")
matched <- run_matching_report()
