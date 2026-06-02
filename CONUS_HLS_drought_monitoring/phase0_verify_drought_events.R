# ==============================================================================
# phase0_verify_drought_events.R
#
# Phase 0 verification: download USDM weekly shapefiles for selected weeks
# spanning the candidate case-study drought events (2022 CONUS widespread +
# 2023 Northeast fall flash drought) and a calm reference week. Plot CONUS
# maps + summary tables so we can visually confirm the events match our
# scientific narrative before committing to figure designs around them.
#
# Run inside Docker container:
#   docker exec conus-hls-drought-monitor Rscript phase0_verify_drought_events.R
# ==============================================================================

suppressPackageStartupMessages({
  library(sf)
  library(dplyr)
  library(ggplot2)
  library(maps)
})

source("00_setup_paths.R")
paths <- setup_hls_paths()

config <- list(
  usdm_raw_dir   = file.path(paths$validation_data, "usdm_raw"),
  staging_dir    = file.path(paths$validation_data, "staging"),
  output_dir     = file.path("/data/figures/phase0_event_verification"),
  url_template   = "https://droughtmonitor.unl.edu/data/shapefiles_m/USDM_%s_M.zip",
  target_crs     = "EPSG:5070",
  weeks = list(
    list(date = "2022-07-26", event = "2022_CONUS"),
    list(date = "2022-08-09", event = "2022_CONUS"),
    list(date = "2022-08-23", event = "2022_CONUS"),
    list(date = "2022-09-06", event = "2022_CONUS"),
    list(date = "2022-09-20", event = "2022_CONUS"),
    list(date = "2022-10-04", event = "2022_CONUS"),
    list(date = "2023-09-12", event = "2023_NE_flash"),
    list(date = "2023-09-26", event = "2023_NE_flash"),
    list(date = "2023-10-10", event = "2023_NE_flash"),
    list(date = "2023-10-24", event = "2023_NE_flash"),
    list(date = "2023-11-07", event = "2023_NE_flash"),
    list(date = "2023-11-21", event = "2023_NE_flash"),
    list(date = "2017-05-30", event = "2017_NPlains"),
    list(date = "2017-06-27", event = "2017_NPlains"),
    list(date = "2017-07-25", event = "2017_NPlains"),
    list(date = "2017-08-22", event = "2017_NPlains"),
    list(date = "2017-09-19", event = "2017_NPlains"),
    list(date = "2023-06-13", event = "2023_early"),
    list(date = "2023-07-25", event = "2023_early"),
    list(date = "2019-06-04", event = "reference_calm")
  )
)

dir.create(config$usdm_raw_dir, recursive = TRUE, showWarnings = FALSE)
dir.create(config$staging_dir,  recursive = TRUE, showWarnings = FALSE)
dir.create(config$output_dir,   recursive = TRUE, showWarnings = FALSE)

cat("=== Phase 0: Verify drought event characterizations ===\n")
cat("Output:", config$output_dir, "\n\n")

# ------------------------------------------------------------------------------
# Download + unpack
# ------------------------------------------------------------------------------
download_week <- function(date_str) {
  yyyymmdd <- gsub("-", "", date_str)
  zip_path <- file.path(config$usdm_raw_dir, sprintf("USDM_%s_M.zip", yyyymmdd))
  if (!file.exists(zip_path) || file.size(zip_path) < 100e3) {
    url <- sprintf(config$url_template, yyyymmdd)
    download.file(url, zip_path, quiet = TRUE, mode = "wb")
  }
  unzip_dir <- file.path(config$staging_dir, yyyymmdd)
  if (!dir.exists(unzip_dir) || length(list.files(unzip_dir, pattern = "\\.shp$")) == 0) {
    dir.create(unzip_dir, showWarnings = FALSE, recursive = TRUE)
    unzip(zip_path, exdir = unzip_dir)
  }
  shp <- list.files(unzip_dir, pattern = "\\.shp$", full.names = TRUE)[1]
  shp
}

# ------------------------------------------------------------------------------
# Read + reproject + assemble
# ------------------------------------------------------------------------------
cat("--- Downloading + reading ", length(config$weeks), " weeks ---\n", sep = "")
all_shapes <- list()
for (w in config$weeks) {
  cat(sprintf("  %s (%s)... ", w$date, w$event))
  shp_path <- download_week(w$date)
  s <- st_read(shp_path, quiet = TRUE)
  s <- st_transform(s, crs = config$target_crs)
  s$week_date  <- as.Date(w$date)
  s$event_tag  <- w$event
  all_shapes[[w$date]] <- s
  cat("OK (", nrow(s), " records)\n", sep = "")
}

# ------------------------------------------------------------------------------
# Midwest DEWS domain (our actual analysis extent — NOT full CONUS).
# Bbox derived from valid_pixels_landcover_filtered.rds (147,880 4km cells).
# ------------------------------------------------------------------------------
v <- readRDS(file.path(paths$gam_models, "valid_pixels_landcover_filtered.rds"))
midwest_bbox <- st_bbox(c(xmin = min(v$x), ymin = min(v$y),
                          xmax = max(v$x), ymax = max(v$y)),
                        crs = config$target_crs)
midwest_poly <- st_as_sfc(midwest_bbox)
cat(sprintf("Midwest DEWS extent: %d x %d km in Albers\n",
            round(diff(midwest_bbox[c("xmin","xmax")])/1000),
            round(diff(midwest_bbox[c("ymin","ymax")])/1000)))

# State boundaries: load CONUS for context, derive 'midwest_states' for clipping
states <- st_as_sf(map("state", plot = FALSE, fill = TRUE))
states <- st_transform(states, crs = config$target_crs)
states <- st_make_valid(states)
midwest_states <- states[st_intersects(states, midwest_poly, sparse = FALSE)[,1], ]
# Clip state polygons to the actual domain bbox so areas reflect what's in-frame
midwest_states_clipped <- st_intersection(midwest_states, midwest_poly)
midwest_area <- as.numeric(sum(st_area(midwest_states_clipped)))
cat("Midwest DEWS land area (state polygons ∩ bbox):", round(midwest_area / 1e10, 1),
    "× 10^10 m^2\n\n")

# ------------------------------------------------------------------------------
# Plot one CONUS map per week
# ------------------------------------------------------------------------------
usdm_palette <- c(
  "0" = "#FFFF00",  # D0 abnormally dry: yellow
  "1" = "#FCD37F",  # D1 moderate: tan
  "2" = "#FFAA00",  # D2 severe: orange
  "3" = "#E60000",  # D3 extreme: red
  "4" = "#730000"   # D4 exceptional: dark red
)
usdm_labels <- c("0"="D0 abnormally dry", "1"="D1 moderate", "2"="D2 severe",
                 "3"="D3 extreme", "4"="D4 exceptional")

cat("\n--- Rendering Midwest DEWS-cropped maps ---\n")
for (date_key in names(all_shapes)) {
  s <- all_shapes[[date_key]]
  s$DM_fac <- factor(s$DM, levels = 0:4)

  # Clip USDM polygons to Midwest bbox for in-frame area calc
  s_clipped <- suppressWarnings(st_intersection(s, midwest_poly))

  in_frame_drought_pct <- if (nrow(s_clipped) > 0)
    100 * sum(as.numeric(st_area(s_clipped))) / midwest_area else 0

  p <- ggplot() +
    geom_sf(data = s, aes(fill = DM_fac), color = NA, alpha = 0.85) +
    geom_sf(data = states, fill = NA, color = "gray30", linewidth = 0.25) +
    # Heavier outline for in-domain states
    geom_sf(data = midwest_states, fill = NA, color = "black", linewidth = 0.5) +
    # Domain bbox rectangle
    geom_sf(data = midwest_poly, fill = NA, color = "blue", linewidth = 0.7,
            linetype = "dashed") +
    scale_fill_manual(values = usdm_palette, labels = usdm_labels, name = "USDM",
                      drop = FALSE, na.value = "transparent") +
    coord_sf(crs = config$target_crs,
             xlim = midwest_bbox[c("xmin","xmax")] + c(-1e5, 1e5),
             ylim = midwest_bbox[c("ymin","ymax")] + c(-1e5, 1e5)) +
    labs(title = sprintf("USDM %s   |   event tag: %s",
                         date_key, all_shapes[[date_key]]$event_tag[1]),
         subtitle = sprintf("Midwest DEWS in-frame drought area (D0+): %.1f%%   |   Records: %d (CONUS-wide)",
                            in_frame_drought_pct, nrow(s)),
         caption = "Blue dashed box = Midwest DEWS analysis extent (NDVI monitor domain)") +
    theme_minimal(base_size = 11) +
    theme(panel.grid.major = element_line(color = "gray90"),
          legend.position = "right")

  png_path <- file.path(config$output_dir,
                        sprintf("usdm_midwest_%s_%s.png", date_key,
                                all_shapes[[date_key]]$event_tag[1]))
  ggsave(png_path, p, width = 10, height = 7, dpi = 150)
  cat(sprintf("  wrote %s\n", basename(png_path)))
}

# ------------------------------------------------------------------------------
# Summary table: % CONUS area in each class per week
# ------------------------------------------------------------------------------
cat("\n--- Per-week summary: percent of MIDWEST DEWS area in each USDM class ---\n")
cat("(USDM polygons intersected with Midwest bbox, area expressed as % of Midwest land)\n")

summary_df <- bind_rows(lapply(all_shapes, function(s) {
  out <- data.frame(
    date  = s$week_date[1],
    event = s$event_tag[1],
    D0    = NA_real_, D1 = NA_real_, D2 = NA_real_,
    D3    = NA_real_, D4 = NA_real_
  )
  for (lvl in 0:4) {
    rows <- s[s$DM == lvl, ]
    if (nrow(rows) > 0) {
      clipped <- suppressWarnings(st_intersection(rows, midwest_poly))
      out[[paste0("D", lvl)]] <- if (nrow(clipped) > 0)
        100 * sum(as.numeric(st_area(clipped))) / midwest_area else 0
    } else {
      out[[paste0("D", lvl)]] <- 0
    }
  }
  out
}))

summary_df$D0_plus <- summary_df$D0 + summary_df$D1 + summary_df$D2 +
                      summary_df$D3 + summary_df$D4
summary_df$D2_plus <- summary_df$D2 + summary_df$D3 + summary_df$D4
summary_df$D3_plus <- summary_df$D3 + summary_df$D4

print(summary_df, row.names = FALSE, digits = 3)

# Save summary
saveRDS(summary_df, file.path(config$output_dir, "phase0_usdm_summary.rds"))
write.csv(summary_df, file.path(config$output_dir, "phase0_usdm_summary.csv"),
          row.names = FALSE)
cat("\nSaved summary to phase0_usdm_summary.{rds,csv}\n")
cat("Done.\n")
