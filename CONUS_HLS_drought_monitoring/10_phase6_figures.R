# ==============================================================================
# 10_phase6_figures.R
#
# Phase 6 headline figures. Builds publication-grade ggplots from the four
# analysis-section outputs:
#   - continuous_spei_nlcd_10y.rds     (Section A — state agreement)
#   - usdm_confusion_nlcd_10y.rds      (Section A++ — USDM categorical)
#   - event_detection_nlcd_10y.rds     (Section B — transition alignment)
#
# Figures are written to paths$figures (typically /data/figures/phase6/).
#
# Usage (in container):
#   docker exec -w /workspace conus-hls-drought-monitor \
#     Rscript 10_phase6_figures.R [--fig=1|2|3|...|all]
#
# Naming: phase6_<figN>_<slug>.png at 300 dpi.
# ==============================================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
  library(scales)
  library(sf)
  library(maps)
  library(patchwork)
})

source("00_setup_paths.R")
source("00_posterior_functions.R")  # readRDS_retry
paths <- setup_hls_paths()

# Output directory
FIG_DIR <- file.path(paths$figures, "phase6")
dir.create(FIG_DIR, showWarnings = FALSE, recursive = TRUE)

# ------------------------------------------------------------------------------
# Shared constants
# ------------------------------------------------------------------------------
ECO_NAMES <- c(
  "5.2" = "Mixed Wood Plains",
  "6.2" = "Western Cordillera",
  "8.1" = "Mixed Wood Shield",
  "8.2" = "Central USA Plains",
  "8.3" = "S Central Semi-Arid Prairies",
  "8.4" = "Ozark / Ouachita / Appalachian",
  "9.2" = "Temperate Prairies (Corn Belt)",
  "9.3" = "West-Central Semi-Arid Prairies",
  "9.4" = "South Central Semi-Arid Prairies"
)

# Common ggplot theme
phase6_theme <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title       = element_text(face = "bold", size = rel(1.15)),
      plot.subtitle    = element_text(color = "grey30", size = rel(0.85)),
      plot.caption     = element_text(color = "grey40", size = rel(0.75),
                                      hjust = 0, margin = margin(t = 8)),
      strip.text       = element_text(face = "bold"),
      panel.grid.minor = element_blank(),
      legend.position  = "bottom"
    )
}

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

#' Build a per-event table from pixel_event_map joined with eco + LC attributes.
#' Returns wide table with one row per event; columns ndvi_z, spei_13w are logical.
build_event_agreement <- function(out_b, vp, nlcd) {
  pem <- out_b$pixel_event_map
  stopifnot("week_start" %in% names(pem))
  pew <- dcast(pem, pixel_id + week_start + event_type ~ headline_signal,
               value.var = "hit")
  pew <- merge(pew, vp[, .(pixel_id, L2_code, L2_name)], by = "pixel_id")
  pew <- merge(pew, nlcd[, .(pixel_id, nlcd_juliana)],
               by = "pixel_id", all.x = TRUE)
  # Collapse urban to 2-tier (mirror section_event_detection_nlcd)
  pew[nlcd_juliana %in% c("urban_high", "urban_med"),
      nlcd_juliana := "urban_dense"]
  pew[nlcd_juliana %in% c("urban_low", "urban_open"),
      nlcd_juliana := "urban_diffuse"]
  pew[]
}

#' Convert wide event agreement to long melt for stacked bar plotting.
agreement_long <- function(dt, by_cols = c("L2_code", "event_type")) {
  agr <- dt[, .(
    n_events = .N,
    both     = sum(ndvi_z &  spei_13w) / .N,
    `NDVI only` = sum(ndvi_z & !spei_13w) / .N,
    `SPEI only` = sum(!ndvi_z & spei_13w) / .N,
    neither    = sum(!ndvi_z & !spei_13w) / .N
  ), by = by_cols]
  long <- melt(agr, id.vars = c(by_cols, "n_events"),
               measure.vars = c("both", "NDVI only", "SPEI only", "neither"),
               variable.name = "category", value.name = "frac")
  long[]
}

# ------------------------------------------------------------------------------
# Figure 1: NDVI ⊥ SPEI complementarity per ecoregion
# ------------------------------------------------------------------------------
make_fig1_complementarity <- function() {
  cat("\n=== Figure 1: NDVI ⊥ SPEI complementarity per ecoregion ===\n")
  out_b <- readRDS_retry(file.path(paths$validation_data,
                                    "event_detection_nlcd_10y.rds"))
  vp    <- as.data.table(readRDS_retry(file.path(paths$validation_data,
                                                  "pixel_to_ecoregion_l2.rds")))
  nlcd  <- as.data.table(readRDS_retry(file.path(paths$gam_models,
                                                  "valid_pixels_nlcd2019.rds")))
  pew <- build_event_agreement(out_b, vp, nlcd)
  pew <- pew[!L2_code %in% c("0.0", "8.5")]
  agr_long <- agreement_long(pew, by_cols = c("L2_code", "event_type"))

  # Attach eco names; order ecos by L2_code (ascending = north→south roughly)
  agr_long[, eco_label := ifelse(L2_code %in% names(ECO_NAMES),
                                 sprintf("%s %s", L2_code, ECO_NAMES[L2_code]),
                                 L2_code)]
  agr_long[, eco_label := factor(eco_label, levels = unique(eco_label[order(L2_code)]))]
  agr_long[, event_type := factor(event_type, levels = c("onset", "recovery"))]
  agr_long[, category := factor(category,
                                levels = c("both", "NDVI only", "SPEI only", "neither"))]

  # n_events annotation per (eco × direction)
  n_lbl <- unique(agr_long[, .(eco_label, event_type, n_events)])
  n_lbl[, n_lbl := sprintf("n=%s", format(n_events, big.mark = ","))]

  pal <- c(
    "both"      = "#2E7D32",   # dark green — concurrent agreement
    "NDVI only" = "#1565C0",   # blue       — NDVI uniquely
    "SPEI only" = "#EF6C00",   # orange     — SPEI uniquely
    "neither"   = "#E0E0E0"    # light gray — missed by both
  )

  p <- ggplot(agr_long, aes(y = eco_label, x = frac, fill = category)) +
    geom_col(width = 0.75) +
    geom_text(data = n_lbl, aes(y = eco_label, x = 1.02, label = n_lbl),
              inherit.aes = FALSE, hjust = 0, size = 3.0, color = "grey30") +
    facet_wrap(~ event_type, ncol = 1,
               labeller = labeller(event_type = c(onset = "ONSET (none → D0+)",
                                                  recovery = "RECOVERY (any → none)"))) +
    scale_x_continuous(labels = percent_format(accuracy = 1),
                       limits = c(0, 1.18),
                       breaks = c(0, 0.25, 0.5, 0.75, 1.0)) +
    scale_y_discrete(limits = rev) +
    scale_fill_manual(values = pal, name = NULL) +
    labs(
      title    = "NDVI and SPEI fires are largely independent at the event level",
      subtitle = "Headline op-point: z=1.5, K=2 sustained weeks, lead ±8 weeks. Only 4-5% of USDM events have both signals firing.",
      x = "Fraction of USDM events",
      y = NULL,
      caption = paste0(
        "Section B (event_detection_nlcd, 2026-06-15). 'Both' = NDVI z and SPEI_13w both crossed threshold within ±8wk of the USDM transition.\n",
        "Complementarity argument: NDVI catches ~19% of events SPEI misses; SPEI catches ~14-22% of events NDVI misses."
      )
    ) +
    phase6_theme(base_size = 11) +
    theme(plot.title.position = "plot",
          plot.caption.position = "plot")

  out_path <- file.path(FIG_DIR, "phase6_fig1_ndvi_spei_complementarity.png")
  ggsave(out_path, p, width = 11, height = 8.5, dpi = 300, bg = "white")
  cat(sprintf("  wrote %s (%.2f MB)\n", out_path, file.size(out_path) / 1e6))
  invisible(out_path)
}

# ------------------------------------------------------------------------------
# CLI dispatch
# ------------------------------------------------------------------------------
args <- commandArgs(trailingOnly = TRUE)
fig_arg <- gsub("^--fig=", "", grep("^--fig=", args, value = TRUE))
if (length(fig_arg) == 0L) fig_arg <- "all"

# ------------------------------------------------------------------------------
# Figure 1b: NDVI ⊥ SPEI complementarity per ecoregion × land cover
# ------------------------------------------------------------------------------
make_fig1b_complementarity_lc <- function() {
  cat("\n=== Figure 1b: NDVI ⊥ SPEI complementarity per ecoregion × LC ===\n")
  out_b <- readRDS_retry(file.path(paths$validation_data,
                                    "event_detection_nlcd_10y.rds"))
  vp    <- as.data.table(readRDS_retry(file.path(paths$validation_data,
                                                  "pixel_to_ecoregion_l2.rds")))
  nlcd  <- as.data.table(readRDS_retry(file.path(paths$gam_models,
                                                  "valid_pixels_nlcd2019.rds")))
  pew <- build_event_agreement(out_b, vp, nlcd)
  pew <- pew[!L2_code %in% c("0.0", "8.5") &
             nlcd_juliana %in% c("crop", "forest", "grassland",
                                 "urban_dense", "urban_diffuse")]
  agr_long <- agreement_long(pew, by_cols = c("L2_code", "nlcd_juliana",
                                              "event_type"))
  # Filter to cells with enough events to be plottable (avoid noisy bars)
  agr_long[, n_events_cell := n_events]
  agr_long <- agr_long[n_events_cell >= 500L]

  # Attach eco names; order ecos by L2_code
  agr_long[, eco_label := ifelse(L2_code %in% names(ECO_NAMES),
                                 sprintf("%s %s", L2_code, ECO_NAMES[L2_code]),
                                 L2_code)]
  agr_long[, eco_label := factor(eco_label,
                                 levels = unique(eco_label[order(L2_code)]))]
  agr_long[, event_type := factor(event_type, levels = c("onset", "recovery"))]
  agr_long[, category := factor(category,
                                levels = c("both", "NDVI only",
                                           "SPEI only", "neither"))]
  agr_long[, nlcd_juliana := factor(nlcd_juliana,
                                    levels = c("crop", "forest", "grassland",
                                               "urban_dense", "urban_diffuse"))]
  lc_labels <- c(crop = "crop", forest = "forest", grassland = "grassland",
                 urban_dense = "urban dense", urban_diffuse = "urban diffuse")

  # n_events annotation per (eco × LC × direction)
  n_lbl <- unique(agr_long[, .(eco_label, nlcd_juliana, event_type, n_events)])
  n_lbl[, n_lbl := sprintf("n=%s", format(n_events, big.mark = ","))]

  pal <- c(
    "both"      = "#2E7D32",
    "NDVI only" = "#1565C0",
    "SPEI only" = "#EF6C00",
    "neither"   = "#E0E0E0"
  )

  # Layout: rows = LC (5), columns = direction (2). Need wider canvas.
  p <- ggplot(agr_long, aes(y = eco_label, x = frac, fill = category)) +
    geom_col(width = 0.75) +
    geom_text(data = n_lbl, aes(y = eco_label, x = 1.02, label = n_lbl),
              inherit.aes = FALSE, hjust = 0, size = 2.4, color = "grey30") +
    facet_grid(nlcd_juliana ~ event_type,
               scales = "free_y", space = "free_y",
               labeller = labeller(
                 nlcd_juliana = lc_labels,
                 event_type   = c(onset    = "ONSET (none → D0+)",
                                  recovery = "RECOVERY (any → none)"))) +
    scale_x_continuous(labels = percent_format(accuracy = 1),
                       limits = c(0, 1.22),
                       breaks = c(0, 0.25, 0.5, 0.75, 1.0)) +
    scale_y_discrete(limits = rev) +
    scale_fill_manual(values = pal, name = NULL) +
    labs(
      title    = "NDVI–SPEI complementarity holds across land cover, with LC-specific texture",
      subtitle = "Headline op-point: z=1.5, K=2 sustained weeks, lead ±8 weeks. Cells with <500 events suppressed (small-N).",
      x = "Fraction of USDM events",
      y = NULL,
      caption = paste0(
        "Section B (event_detection_nlcd, 2026-06-15). Each row = LC class; each panel column = USDM transition direction.\n",
        "'Both' = NDVI z and SPEI_13w both crossed threshold within ±8wk of the USDM transition. ",
        "'NDVI only' and 'SPEI only' segments together quantify complementarity per (eco × LC × direction)."
      )
    ) +
    phase6_theme(base_size = 10) +
    theme(plot.title.position   = "plot",
          plot.caption.position = "plot",
          strip.text.y          = element_text(angle = 0, hjust = 0))

  out_path <- file.path(FIG_DIR, "phase6_fig1b_ndvi_spei_complementarity_lc.png")
  ggsave(out_path, p, width = 14, height = 13, dpi = 300, bg = "white")
  cat(sprintf("  wrote %s (%.2f MB)\n", out_path, file.size(out_path) / 1e6))
  invisible(out_path)
}

# ------------------------------------------------------------------------------
# Figure 0: Domain reference map (LC + ecoregion zones)
# ------------------------------------------------------------------------------
make_fig0_domain_map <- function() {
  cat("\n=== Figure 0: Domain reference map (LC + ecoregion zones) ===\n")
  nlcd <- as.data.table(readRDS_retry(file.path(paths$gam_models,
                                                 "valid_pixels_nlcd2019.rds")))
  vp   <- as.data.table(readRDS_retry(file.path(paths$validation_data,
                                                 "pixel_to_ecoregion_l2.rds")))

  # Collapse urban to 2-tier (mirror analysis convention)
  nlcd[nlcd_juliana %in% c("urban_high", "urban_med"),
       nlcd_juliana := "urban_dense"]
  nlcd[nlcd_juliana %in% c("urban_low", "urban_open"),
       nlcd_juliana := "urban_diffuse"]

  pix <- merge(nlcd[, .(pixel_id, x, y, nlcd_juliana, modal_frac)],
               vp[, .(pixel_id, L2_code)], by = "pixel_id")
  pix <- pix[!is.na(L2_code)]

  # Drop the rare "0.0" + "8.5" L2 codes (small N boundary pixels) for clarity
  pix_eco <- pix[!L2_code %in% c("0.0", "8.5")]

  # Build eco_label column
  pix_eco[, eco_label := ifelse(L2_code %in% names(ECO_NAMES),
                                 sprintf("%s %s", L2_code, ECO_NAMES[L2_code]),
                                 L2_code)]
  pix_eco[, eco_label := factor(eco_label,
                                 levels = unique(eco_label[order(L2_code)]))]
  pix[, nlcd_juliana := factor(nlcd_juliana,
                                levels = c("crop", "forest", "grassland",
                                           "urban_dense", "urban_diffuse",
                                           "other"))]

  # State outlines reprojected to EPSG:5070 (NLCD CRS, same as pixel x/y)
  states <- st_as_sf(map("state", plot = FALSE, fill = TRUE))
  states <- st_transform(states, 5070)
  # Tight clip to plot extent (25 km buffer)
  bbox_pix <- c(xmin = min(pix$x) - 25e3, xmax = max(pix$x) + 25e3,
                ymin = min(pix$y) - 25e3, ymax = max(pix$y) + 25e3)

  # Color palettes (tweaked 9.3 to a more saturated purple for separation from 9.2)
  eco_pal <- c(
    "5.2 Mixed Wood Plains"             = "#7FB069",  # green
    "6.2 Western Cordillera"            = "#A4C2A8",  # pale green
    "8.1 Mixed Wood Shield"             = "#6BAED6",  # blue
    "8.2 Central USA Plains"            = "#FDE68A",  # pale yellow
    "8.3 S Central Semi-Arid Prairies"  = "#F4A261",  # orange
    "8.4 Ozark / Ouachita / Appalachian" = "#9D6B53", # brown
    "9.2 Temperate Prairies (Corn Belt)" = "#E5989B", # pink/coral
    "9.3 West-Central Semi-Arid Prairies" = "#7E57C2",# saturated purple
    "9.4 South Central Semi-Arid Prairies" = "#B0413E" # dark red
  )
  lc_pal <- c(
    "crop"          = "#F4D03F",   # warm yellow
    "forest"        = "#196F3D",   # dark green
    "grassland"     = "#A2B362",   # olive
    "urban_dense"   = "#7B241C",   # dark red
    "urban_diffuse" = "#D98880",   # light red
    "other"         = "#B0BEC5"    # gray
  )

  # Shared theme — no axis labels (reference map, not measurement)
  map_theme <- function() {
    theme_minimal(base_size = 11) +
      theme(
        plot.title       = element_text(face = "bold"),
        panel.grid.major = element_blank(),
        panel.grid.minor = element_blank(),
        axis.text        = element_blank(),
        axis.title       = element_blank(),
        axis.ticks       = element_blank(),
        legend.position  = "right",
        legend.title     = element_text(face = "bold", size = 10),
        legend.text      = element_text(size = 9)
      )
  }

  p_eco <- ggplot(pix_eco, aes(x = x, y = y, fill = eco_label)) +
    geom_raster() +
    geom_sf(data = states, fill = NA, color = "grey25", linewidth = 0.45,
            inherit.aes = FALSE) +
    coord_sf(xlim = bbox_pix[c("xmin","xmax")],
             ylim = bbox_pix[c("ymin","ymax")],
             crs  = st_crs(5070), expand = FALSE) +
    scale_fill_manual(values = eco_pal, name = "EPA L2 Ecoregion",
                      drop = FALSE) +
    guides(fill = guide_legend(ncol = 1, override.aes = list(size = 4))) +
    labs(title = "EPA Level II Ecoregions",
         subtitle = sprintf("%s analysis pixels at 4 km",
                            format(uniqueN(pix_eco$pixel_id), big.mark = ","))) +
    map_theme()

  p_lc <- ggplot(pix, aes(x = x, y = y, fill = nlcd_juliana)) +
    geom_raster() +
    geom_sf(data = states, fill = NA, color = "grey25", linewidth = 0.45,
            inherit.aes = FALSE) +
    coord_sf(xlim = bbox_pix[c("xmin","xmax")],
             ylim = bbox_pix[c("ymin","ymax")],
             crs  = st_crs(5070), expand = FALSE) +
    scale_fill_manual(values = lc_pal,
                      name = "NLCD 2019 land cover\n(modal class per 4 km cell)",
                      drop = FALSE) +
    guides(fill = guide_legend(ncol = 1, override.aes = list(size = 4))) +
    labs(title = "Land cover (NLCD 2019, modal class per 4 km cell)",
         subtitle = sprintf("crop %d%% / grass %d%% / forest %d%% / urban %d%% / other %d%%",
                            round(100 * mean(pix$nlcd_juliana == "crop")),
                            round(100 * mean(pix$nlcd_juliana == "grassland")),
                            round(100 * mean(pix$nlcd_juliana == "forest")),
                            round(100 * mean(pix$nlcd_juliana %in% c("urban_dense","urban_diffuse"))),
                            round(100 * mean(pix$nlcd_juliana == "other")))) +
    map_theme()

  combined <- (p_eco | p_lc) +
    plot_annotation(
      title    = "Midwest DEWS analysis domain",
      subtitle = "1976 × 1212 km Midwest extent, 14 states. All Phase 6 stratification is per (L2 ecoregion × land cover).",
      caption  = "EPA L2 ecoregions (Omernik & Griffith 2014). NLCD 2019 16-class collapsed to {crop, forest, grassland, urban_dense, urban_diffuse, other} per `00b_extract_nlcd_2019.R`. CRS EPSG:5070.",
      theme    = theme(plot.title    = element_text(face = "bold", size = 14),
                       plot.subtitle = element_text(color = "grey30"),
                       plot.caption  = element_text(color = "grey45", size = 8, hjust = 0))
    )

  out_path <- file.path(FIG_DIR, "phase6_fig0_domain_reference_map.png")
  ggsave(out_path, combined, width = 16, height = 7.5, dpi = 300, bg = "white")
  cat(sprintf("  wrote %s (%.2f MB)\n", out_path, file.size(out_path) / 1e6))
  invisible(out_path)
}

if (fig_arg %in% c("0",  "all")) make_fig0_domain_map()
if (fig_arg %in% c("1",  "all")) make_fig1_complementarity()
if (fig_arg %in% c("1b", "all")) make_fig1b_complementarity_lc()

cat("\nDone.\n")
