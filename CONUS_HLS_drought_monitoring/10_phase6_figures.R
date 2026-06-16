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
#' Authoritative names from EPA Level II ecoregion scheme (Omernik & Griffith 2014;
#' verified 2026-06-15 against L2_name in pixel_to_ecoregion_l2.rds).
#' DO NOT shuffle these — early labels in this session had 5.2/8.1 swapped and 8.3
#' mis-named as "S Central Semi-Arid Prairies"; the canonical pixel lookup is the
#' source of truth.
ECO_NAMES <- c(
  "5.2" = "Mixed Wood Shield",
  "6.2" = "Western Cordillera",
  "8.1" = "Mixed Wood Plains",
  "8.2" = "Central USA Plains",
  "8.3" = "Southeastern USA Plains",
  "8.4" = "Ozark/Ouachita-Appalachian Forests",
  "9.2" = "Temperate Prairies (Corn Belt)",
  "9.3" = "West-Central Semiarid Prairies",
  "9.4" = "South Central Semiarid Prairies"
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

  # Color palettes (palette is keyed by canonical name from ECO_NAMES; tweaked 9.3
  # to saturated purple for separation from 9.2)
  eco_pal <- setNames(
    c("#7FB069", "#A4C2A8", "#6BAED6", "#FDE68A", "#F4A261",
      "#9D6B53", "#E5989B", "#7E57C2", "#B0413E"),
    sprintf("%s %s", names(ECO_NAMES), unname(ECO_NAMES))
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

# ------------------------------------------------------------------------------
# Figure 2: 8.3 South Central Semi-Arid Prairies deep-dive
# Three panels:
#   A: small orientation map (Midwest with 8.3 highlighted)
#   B: per-pixel onset hit_rate map for 8.3 (combined NDVI OR SPEI fire)
#   C: HSS heatmap for 8.3 grass × dom × onset — signal × (z × K)
# ------------------------------------------------------------------------------
make_fig2_eco83_deepdive <- function() {
  cat("\n=== Figure 2: 8.3 Plains deep-dive ===\n")
  out_b <- readRDS_retry(file.path(paths$validation_data,
                                    "event_detection_nlcd_10y.rds"))
  vp    <- as.data.table(readRDS_retry(file.path(paths$validation_data,
                                                  "pixel_to_ecoregion_l2.rds")))
  nlcd  <- as.data.table(readRDS_retry(file.path(paths$gam_models,
                                                  "valid_pixels_nlcd2019.rds")))

  pix_eco <- merge(nlcd[, .(pixel_id, x, y)],
                   vp[, .(pixel_id, L2_code)], by = "pixel_id")
  pix_eco <- pix_eco[!is.na(L2_code) & !L2_code %in% c("0.0", "8.5")]
  pix_eco[, is_83 := (L2_code == "8.3")]

  # State outlines
  states <- st_transform(st_as_sf(map("state", plot = FALSE, fill = TRUE)), 5070)
  bbox_pix <- c(xmin = min(pix_eco$x) - 25e3, xmax = max(pix_eco$x) + 25e3,
                ymin = min(pix_eco$y) - 25e3, ymax = max(pix_eco$y) + 25e3)

  # === Panel A: orientation map ===
  p_a <- ggplot(pix_eco, aes(x = x, y = y, fill = is_83)) +
    geom_raster() +
    geom_sf(data = states, fill = NA, color = "grey25", linewidth = 0.35,
            inherit.aes = FALSE) +
    coord_sf(xlim = bbox_pix[c("xmin","xmax")],
             ylim = bbox_pix[c("ymin","ymax")],
             crs  = st_crs(5070), expand = FALSE) +
    scale_fill_manual(values = c(`FALSE` = "#E0E0E0", `TRUE` = "#F4A261"),
                      labels = c("Other ecoregions",
                                 sprintf("8.3 %s", ECO_NAMES["8.3"])),
                      name = NULL) +
    labs(title = "A. Where is 8.3?",
         subtitle = "Southeastern USA Plains — Arkansas / Missouri Ozark foothills / East Texas / Louisiana / parts of MS/TN") +
    theme_minimal(base_size = 10) +
    theme(plot.title       = element_text(face = "bold"),
          plot.subtitle    = element_text(color = "grey30", size = rel(0.85)),
          axis.text        = element_blank(),
          axis.title       = element_blank(),
          axis.ticks       = element_blank(),
          panel.grid       = element_blank(),
          legend.position  = "bottom",
          legend.text      = element_text(size = 9))

  # === Panel B: per-pixel onset hit_rate map for 8.3 (combined NDVI OR SPEI) ===
  pem83 <- merge(out_b$pixel_event_map, vp[, .(pixel_id, L2_code)],
                 by = "pixel_id")
  pem83 <- pem83[L2_code == "8.3" & event_type == "onset"]
  pem83_w <- dcast(pem83, pixel_id + week_start ~ headline_signal,
                   value.var = "hit")
  pem83_w[, either := ndvi_z | spei_13w]
  pix_hit <- pem83_w[, .(n_events = .N,
                         hit_rate_either = mean(either, na.rm = TRUE)),
                     by = pixel_id]
  pix_hit_xy <- merge(pix_hit, nlcd[, .(pixel_id, x, y, nlcd_juliana)],
                      by = "pixel_id")
  # Restrict to pixels with at least 10 events for stable per-pixel rate
  pix_hit_xy <- pix_hit_xy[n_events >= 10L]

  bbox_83 <- c(xmin = min(pix_hit_xy$x) - 20e3, xmax = max(pix_hit_xy$x) + 20e3,
               ymin = min(pix_hit_xy$y) - 20e3, ymax = max(pix_hit_xy$y) + 20e3)

  p_b <- ggplot(pix_hit_xy, aes(x = x, y = y, fill = hit_rate_either)) +
    geom_raster() +
    geom_sf(data = states, fill = NA, color = "grey25", linewidth = 0.45,
            inherit.aes = FALSE) +
    coord_sf(xlim = bbox_83[c("xmin","xmax")],
             ylim = bbox_83[c("ymin","ymax")],
             crs  = st_crs(5070), expand = FALSE) +
    scale_fill_viridis_c(option = "viridis",
                         name = "Combined POD\n(NDVI ∨ SPEI fires)",
                         labels = percent_format(accuracy = 1),
                         limits = c(0, 1)) +
    labs(title = "B. Per-pixel onset detection — 8.3 only",
         subtitle = sprintf(
           "%s pixels, mean events per pixel = %.0f. Headline op: z=1.5, K=2, ±8wk. 'Either fires' = NDVI z or SPEI_13w crossed threshold near USDM onset.",
           format(nrow(pix_hit_xy), big.mark = ","),
           mean(pix_hit_xy$n_events))) +
    theme_minimal(base_size = 10) +
    theme(plot.title       = element_text(face = "bold"),
          plot.subtitle    = element_text(color = "grey30", size = rel(0.85)),
          axis.text        = element_blank(),
          axis.title       = element_blank(),
          axis.ticks       = element_blank(),
          panel.grid       = element_blank(),
          legend.position  = "right",
          legend.title     = element_text(face = "bold", size = 9),
          legend.text      = element_text(size = 8))

  # === Panel C: HSS heatmap for 8.3 grass × dom — signal × (z × K), onset ===
  sk83 <- out_b$skill_lc[L2_code == "8.3" & nlcd_juliana == "grassland" &
                         dom_filter == "dom" & direction == "onset"]
  # signal ordering: NDVI then derivatives by window length, then SPEI by window
  sig_order <- c("ndvi_z", "deriv_w03_z", "deriv_w07_z", "deriv_w14_z", "deriv_w30_z",
                 "spei_4w", "spei_13w", "spei_26w")
  sk83[, signal_col := factor(signal_col, levels = rev(sig_order))]
  sk83[, op_label := sprintf("z=%.1f / K=%d", z_threshold, sustained_weeks)]
  # Order op_label: z=1.0/K=1, K=2, K=4, then z=1.5..., then z=2.0...
  op_order <- as.vector(outer(c(1, 2, 4),
                               c("z=1.0", "z=1.5", "z=2.0"),
                               function(k, z) paste(z, paste0("K=", k), sep=" / ")))
  sk83[, op_label := factor(op_label, levels = op_order)]

  p_c <- ggplot(sk83, aes(x = op_label, y = signal_col, fill = hss)) +
    geom_tile(color = "white", linewidth = 0.4) +
    geom_text(aes(label = sprintf("%+.2f", hss)),
              size = 3, color = "grey15") +
    scale_fill_gradient2(low = "#B0413E", mid = "#FAFAFA", high = "#2E7D32",
                        midpoint = 0,
                        name = "HSS",
                        limits = c(-0.1, 0.5), oob = scales::squish) +
    labs(
      title    = "C. HSS by signal × op-point — 8.3 grass dom × ONSET",
      subtitle = "Each cell = one (signal × threshold × sustained-weeks) op-point. dom = pixels where modal LC ≥ 60% (n_pixels = 270).",
      x = "Operating point",
      y = "Fire signal",
      caption = "spei_4w dominates onset detection in 8.3 grass: HSS = +0.47 at z=1.5/K=1, +0.45 at z=1.5/K=2. Derivative + NDVI signals show near-zero or slightly negative HSS — the meteorological short-window signal is the right tool for this stratum."
    ) +
    theme_minimal(base_size = 10) +
    theme(plot.title       = element_text(face = "bold"),
          plot.subtitle    = element_text(color = "grey30", size = rel(0.85)),
          plot.caption     = element_text(color = "grey45", size = 8, hjust = 0,
                                          margin = margin(t = 8)),
          axis.text.x      = element_text(angle = 0),
          panel.grid       = element_blank(),
          legend.position  = "right")

  # === Compose ===
  top_row <- p_a + p_b + plot_layout(widths = c(1, 1.4))
  combined <- (top_row / p_c) +
    plot_layout(heights = c(1, 1.1)) +
    plot_annotation(
      title    = "8.3 Southeastern USA Plains — the operational dark horse of Phase 6",
      subtitle = "Section A had 8.3 as SILENT (concurrent NDVI–SPEI agreement small-negative). Section B reveals best-in-class onset detection via spei_4w — humid subtropical precip pulses drive both meteorological signal and analyst declarations on similar timescales.",
      caption  = "event_detection_nlcd_10y.rds, 2026-06-15. NDVI z signals derived per-pixel; SPEI windows used raw.",
      theme    = theme(plot.title    = element_text(face = "bold", size = 14),
                       plot.subtitle = element_text(color = "grey30"),
                       plot.caption  = element_text(color = "grey45", size = 8, hjust = 0))
    )

  out_path <- file.path(FIG_DIR, "phase6_fig2_eco83_deepdive.png")
  ggsave(out_path, combined, width = 16, height = 13, dpi = 300, bg = "white")
  cat(sprintf("  wrote %s (%.2f MB)\n", out_path, file.size(out_path) / 1e6))
  invisible(out_path)
}

# ------------------------------------------------------------------------------
# Figure 6: case-year time series — NDVI anomaly + derivative anomaly + USDM
#
# Juliana-style three-row stacked panel, x-aligned by week_start:
#   Top:    domain-mean NDVI anomaly (95% CI ribbon, zero line)
#   Middle: domain-mean derivative anomaly (w07 window, 95% CI ribbon, zero line)
#   Bottom: USDM severity stacked area (% of domain pixel-weeks in D0..D4)
# Faceted by case_year (cols). Years chosen for HLS-era drought gradient:
#   2017 = moderate growing-season (peak D2+ 12% on 2017-07-31)
#   2019 = wet counterfactual      (peak D2+  3% all year — universal "no drought")
#   2021 = severe growing-season   (peak D2+ 27% on 2021-08-23)
#   2023 = extreme summer drought  (peak D3+  7.5%, D4 2.1%, peak 2023-06-26)
# Selection rationale: see USDM extent table 2026-06-16.
# ------------------------------------------------------------------------------
CASE_YEARS <- c(2017L, 2019L, 2021L, 2023L)
CASE_YEAR_LABELS <- c(
  "2017" = "2017  — moderate (peak D2+ 12%)",
  "2019" = "2019  — wet counterfactual",
  "2021" = "2021  — severe (peak D2+ 27%)",
  "2023" = "2023  — extreme (peak D4 2.1%)"
)
USDM_PAL <- c(
  "D0" = "#FFFF66",   # pale yellow — abnormally dry
  "D1" = "#FCD37F",   # burlywood — moderate
  "D2" = "#FFAA00",   # darkorange — severe
  "D3" = "#E60000",   # red — extreme
  "D4" = "#730000"    # brown4 — exceptional
)

# ------------------------------------------------------------------------------
# Helpers: factor data prep + rendering so Fig 6 (domain) and Fig 7 (per-stratum)
# share the same plot machinery.
# ------------------------------------------------------------------------------

#' Compute weekly NDVI/deriv median+IQR and USDM %-by-D-class for a subset.
#' dt_subset must contain the case-year filter already applied.
prep_case_year_panel <- function(dt_subset) {
  ts_long <- dt_subset[, .(
    ndvi_q25  = quantile(ndvi_anom_mean,      0.25, na.rm = TRUE),
    ndvi_med  = quantile(ndvi_anom_mean,      0.50, na.rm = TRUE),
    ndvi_q75  = quantile(ndvi_anom_mean,      0.75, na.rm = TRUE),
    deriv_q25 = quantile(deriv_w07_anom_mean, 0.25, na.rm = TRUE),
    deriv_med = quantile(deriv_w07_anom_mean, 0.50, na.rm = TRUE),
    deriv_q75 = quantile(deriv_w07_anom_mean, 0.75, na.rm = TRUE)
  ), by = .(cal_year, week_start)]
  ts_long[, yday := as.integer(format(week_start, "%j"))]
  ts_long[, year_label := factor(CASE_YEAR_LABELS[as.character(cal_year)],
                                 levels = CASE_YEAR_LABELS)]
  setorder(ts_long, cal_year, week_start)

  usdm_dt <- dt_subset[, .(
    pct_D0 = mean(usdm == 0L, na.rm = TRUE) * 100,
    pct_D1 = mean(usdm == 1L, na.rm = TRUE) * 100,
    pct_D2 = mean(usdm == 2L, na.rm = TRUE) * 100,
    pct_D3 = mean(usdm == 3L, na.rm = TRUE) * 100,
    pct_D4 = mean(usdm == 4L, na.rm = TRUE) * 100
  ), by = .(cal_year, week_start)]
  usdm_long <- melt(usdm_dt, id.vars = c("cal_year", "week_start"),
                    measure.vars = c("pct_D0","pct_D1","pct_D2","pct_D3","pct_D4"),
                    variable.name = "severity", value.name = "pct")
  usdm_long[, severity := factor(sub("^pct_", "", severity),
                                 levels = rev(c("D0","D1","D2","D3","D4")))]
  usdm_long[, yday := as.integer(format(week_start, "%j"))]
  usdm_long[, year_label := factor(CASE_YEAR_LABELS[as.character(cal_year)],
                                   levels = CASE_YEAR_LABELS)]

  list(
    ts_long   = ts_long,
    usdm_long = usdm_long,
    n_pixels  = uniqueno_na(dt_subset$pixel_id),
    n_pix_wks = nrow(dt_subset)
  )
}

uniqueno_na <- function(x) length(unique(x[!is.na(x)]))

#' Render the 3-row × 4-col case-year panel and save.
#' Pass an explicit subtitle + caption to support both domain and stratum titles.
#' usdm_axis_label appears on panel C's y-axis ("% of domain", "% of stratum", etc.).
render_case_year_panel <- function(prep,
                                   plot_title,
                                   plot_subtitle,
                                   plot_caption,
                                   usdm_axis_label,
                                   out_path,
                                   ndvi_title = "A. NDVI anomaly (line = weekly median; ribbon = IQR across pixels)",
                                   deriv_title = "B. Derivative anomaly (w07; line = weekly median; ribbon = IQR across pixels)",
                                   usdm_title  = NULL) {
  ts_long   <- prep$ts_long
  usdm_long <- prep$usdm_long

  month_breaks <- as.integer(format(as.Date(sprintf("2021-%02d-15", 1:12)), "%j"))
  month_labels <- month.abb
  grow_rect <- data.frame(xmin = as.integer(format(as.Date("2021-03-01"), "%j")),
                          xmax = as.integer(format(as.Date("2021-09-30"), "%j")),
                          ymin = -Inf, ymax = Inf)
  base_x <- list(
    scale_x_continuous(breaks = month_breaks, labels = month_labels,
                       expand = c(0, 0), limits = c(1, 366)),
    facet_wrap(~ year_label, nrow = 1)
  )

  p_a <- ggplot(ts_long, aes(x = yday)) +
    geom_rect(data = grow_rect, aes(xmin = xmin, xmax = xmax,
                                    ymin = ymin, ymax = ymax),
              inherit.aes = FALSE, fill = "#B7DCE7", alpha = 0.25) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    geom_ribbon(aes(ymin = ndvi_q25, ymax = ndvi_q75),
                fill = "#1565C0", alpha = 0.25) +
    geom_line(aes(y = ndvi_med), color = "#0D3D7A", linewidth = 0.8) +
    base_x +
    labs(title = ndvi_title, y = "NDVI anomaly", x = NULL) +
    phase6_theme(base_size = 11) +
    theme(strip.text = element_text(face = "bold", size = rel(1.0)),
          axis.text.x = element_blank(),
          axis.ticks.x = element_blank(),
          legend.position = "none")

  p_b <- ggplot(ts_long, aes(x = yday)) +
    geom_rect(data = grow_rect, aes(xmin = xmin, xmax = xmax,
                                    ymin = ymin, ymax = ymax),
              inherit.aes = FALSE, fill = "#B7DCE7", alpha = 0.25) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    geom_ribbon(aes(ymin = deriv_q25, ymax = deriv_q75),
                fill = "#AD1457", alpha = 0.25) +
    geom_line(aes(y = deriv_med), color = "#6A1B3A", linewidth = 0.8) +
    base_x +
    labs(title = deriv_title,
         y = "d(NDVI)/d(yday)\nanomaly", x = NULL) +
    phase6_theme(base_size = 11) +
    theme(strip.text = element_blank(),
          axis.text.x = element_blank(),
          axis.ticks.x = element_blank(),
          legend.position = "none")

  if (is.null(usdm_title)) {
    usdm_title <- sprintf("C. USDM severity (%% of %s in each D-class)",
                          usdm_axis_label)
  }
  p_c <- ggplot(usdm_long, aes(x = yday, y = pct, fill = severity)) +
    geom_area(position = "stack", alpha = 0.9) +
    scale_fill_manual(values = USDM_PAL, breaks = c("D0","D1","D2","D3","D4"),
                      name = NULL) +
    base_x +
    scale_y_continuous(name = paste0("% of ", usdm_axis_label),
                       limits = c(0, 100), expand = c(0, 0),
                       breaks = c(0, 25, 50, 75, 100),
                       labels = function(z) paste0(z, "%")) +
    labs(title = usdm_title, x = NULL) +
    phase6_theme(base_size = 11) +
    theme(strip.text = element_blank(),
          axis.text.x = element_text(angle = 0),
          legend.position = "bottom",
          legend.key.size = unit(0.4, "cm"))

  combined <- (p_a / p_b / p_c) +
    plot_layout(heights = c(1, 1, 1)) +
    plot_annotation(
      title    = plot_title,
      subtitle = plot_subtitle,
      caption  = plot_caption,
      theme    = theme(plot.title    = element_text(face = "bold", size = 14),
                       plot.subtitle = element_text(color = "grey30"),
                       plot.caption  = element_text(color = "grey45", size = 8,
                                                    hjust = 0))
    )

  ggsave(out_path, combined, width = 16, height = 11, dpi = 300, bg = "white")
  invisible(out_path)
}

#' Standard caption block — appears below every Fig 6/7 figure.
case_year_caption <- function(extra = NULL) {
  base <- paste0(
    "Source: ndvi_drought_join_weekly_10y.rds (Phase 6 align_weekly). ",
    "Derivative window = w07 (matches Section B's strongest recovery signal). ",
    "Years selected from local USDM-extent table 2016-2025."
  )
  if (!is.null(extra)) base <- paste0(base, "\n", extra)
  base
}

# ------------------------------------------------------------------------------
# Figure 6 driver: domain-wide overview
# ------------------------------------------------------------------------------
make_fig6_case_year_timeseries <- function() {
  cat("\n=== Figure 6: case-year NDVI + deriv anom + USDM (domain) ===\n")
  dt <- as.data.table(readRDS_retry(file.path(paths$validation_data,
                                              "ndvi_drought_join_weekly_10y.rds")))
  dt <- dt[cal_year %in% CASE_YEARS]
  cat(sprintf("  loaded %s pixel-weeks across %d case years\n",
              format(nrow(dt), big.mark = ","), length(CASE_YEARS)))

  prep <- prep_case_year_panel(dt)
  out_path <- file.path(FIG_DIR, "phase6_fig6_case_year_anom_deriv.png")
  render_case_year_panel(
    prep            = prep,
    plot_title      = "Domain-wide NDVI signals during four contrasting USDM years",
    plot_subtitle   = paste0(
      "Each column shows one calendar year. Light blue band marks growing season ",
      "(March through September — fixed calendar default). NDVI and derivative panels: line = weekly ",
      "domain median; shaded ribbon = IQR (Q25–Q75) across pixels — middle half of ",
      "the pixel distribution each week."
    ),
    plot_caption    = case_year_caption(),
    usdm_axis_label = "Midwest pixel-weeks",
    out_path        = out_path
  )
  cat(sprintf("  wrote %s (%.2f MB)\n", out_path, file.size(out_path) / 1e6))
  invisible(out_path)
}

# ------------------------------------------------------------------------------
# Figure 7: stratum exploration — same Fig 6 layout for every (eco × LC) cell,
# plus per-eco aggregates (all LCs) and per-LC aggregates (all ecos).
#
# Filenames:
#   phase6_fig7_eco<L2>_<lc>.png        per (eco × LC) cell
#   phase6_fig7_eco<L2>_all.png         per eco, all LCs
#   phase6_fig7_lc_<lc>_all.png         per LC, all ecos
#
# Small-n behavior: stratum is rendered regardless; if n_pixels < 50 the title
# is annotated "(small-n)" and a warning is printed at the run-end summary.
# ------------------------------------------------------------------------------
SMALL_N_FLOOR <- 50L

#' Resolve "9.4" → "South Central Semiarid Prairies" or fallback to the code.
eco_display_name <- function(L2_code) {
  ifelse(L2_code %in% names(ECO_NAMES),
         sprintf("%s %s", L2_code, ECO_NAMES[L2_code]),
         as.character(L2_code))
}

make_fig7_all_strata <- function() {
  cat("\n=== Figure 7: stratum exploration (eco × LC + per-eco + per-LC) ===\n")
  dt <- as.data.table(readRDS_retry(file.path(paths$validation_data,
                                              "ndvi_drought_join_weekly_10y.rds")))
  dt <- dt[cal_year %in% CASE_YEARS]
  cat(sprintf("  loaded %s pixel-weeks across %d case years\n",
              format(nrow(dt), big.mark = ","), length(CASE_YEARS)))

  # ---- attach NLCD Juliana class with 2-tier urban collapse -----------------
  nlcd <- as.data.table(readRDS_retry(file.path(paths$gam_models,
                                                "valid_pixels_nlcd2019.rds")))
  nlcd <- nlcd[, .(pixel_id, nlcd_juliana)]
  nlcd[nlcd_juliana %in% c("urban_high", "urban_med"),
       nlcd_juliana := "urban_dense"]
  nlcd[nlcd_juliana %in% c("urban_low", "urban_open"),
       nlcd_juliana := "urban_diffuse"]
  dt <- merge(dt, nlcd, by = "pixel_id", all.x = TRUE)
  # Drop ecos/LCs we don't want to expose (0.0 = water/no eco; 8.5 = Florida
  # sliver; "other" LC = NLCD classes that didn't map to a Juliana class)
  dt <- dt[!L2_code %in% c("0.0", "8.5") & nlcd_juliana != "other" &
           !is.na(L2_code) & !is.na(nlcd_juliana)]

  # ---- enumerate strata ------------------------------------------------------
  cells <- unique(dt[, .(L2_code, nlcd_juliana)])
  setorder(cells, L2_code, nlcd_juliana)
  ecos    <- sort(unique(dt$L2_code))
  lcs     <- sort(unique(dt$nlcd_juliana))
  cat(sprintf("  %d eco × LC cells, %d ecos, %d LCs\n",
              nrow(cells), length(ecos), length(lcs)))

  small_n_log <- character(0)

  # ---- per (eco × LC) cells --------------------------------------------------
  cat("\n[A] per (eco × LC) cells:\n")
  for (i in seq_len(nrow(cells))) {
    eco <- cells$L2_code[i]; lc <- cells$nlcd_juliana[i]
    sub <- dt[L2_code == eco & nlcd_juliana == lc]
    n_pix <- uniqueno_na(sub$pixel_id)
    is_small <- n_pix < SMALL_N_FLOOR
    if (is_small) small_n_log <- c(small_n_log,
                                    sprintf("eco=%s × lc=%s : n_pixels=%d",
                                            eco, lc, n_pix))
    prep <- prep_case_year_panel(sub)
    title <- sprintf("%s × %s — n_pixels = %s%s",
                     eco_display_name(eco), lc,
                     format(n_pix, big.mark = ","),
                     ifelse(is_small, "  (small-n)", ""))
    slug <- sprintf("eco%s_%s", gsub("\\.", "p", eco), lc)
    out_path <- file.path(FIG_DIR, sprintf("phase6_fig7_%s.png", slug))
    render_case_year_panel(
      prep            = prep,
      plot_title      = title,
      plot_subtitle   = paste0(
        "Stratum: pixels classified as ", lc, " within ecoregion ",
        eco_display_name(eco), ". Same layout as Fig 6 — line = weekly median, ",
        "ribbon = IQR across pixels, USDM = % of stratum pixel-weeks in each D-class."),
      plot_caption    = case_year_caption(),
      usdm_axis_label = "stratum pixel-weeks",
      out_path        = out_path
    )
    cat(sprintf("    [%2d/%d] %s  (n=%d%s)\n", i, nrow(cells),
                basename(out_path), n_pix,
                ifelse(is_small, ", small-n", "")))
  }

  # ---- per ecoregion (all LCs) ----------------------------------------------
  cat("\n[B] per ecoregion (all LCs):\n")
  for (i in seq_along(ecos)) {
    eco <- ecos[i]
    sub <- dt[L2_code == eco]
    n_pix <- uniqueno_na(sub$pixel_id)
    is_small <- n_pix < SMALL_N_FLOOR
    if (is_small) small_n_log <- c(small_n_log,
                                    sprintf("eco=%s × all LCs : n_pixels=%d",
                                            eco, n_pix))
    prep <- prep_case_year_panel(sub)
    title <- sprintf("%s — all land cover classes (n_pixels = %s%s)",
                     eco_display_name(eco), format(n_pix, big.mark = ","),
                     ifelse(is_small, ", small-n", ""))
    slug <- sprintf("eco%s_all", gsub("\\.", "p", eco))
    out_path <- file.path(FIG_DIR, sprintf("phase6_fig7_%s.png", slug))
    render_case_year_panel(
      prep            = prep,
      plot_title      = title,
      plot_subtitle   = paste0(
        "Aggregate across all NLCD Juliana classes in ", eco_display_name(eco),
        ". Same layout as Fig 6 — line = weekly median, ribbon = IQR across pixels."),
      plot_caption    = case_year_caption(),
      usdm_axis_label = "eco pixel-weeks",
      out_path        = out_path
    )
    cat(sprintf("    [%2d/%d] %s  (n=%d)\n", i, length(ecos),
                basename(out_path), n_pix))
  }

  # ---- per land cover (all ecos) --------------------------------------------
  cat("\n[C] per land cover (all ecos):\n")
  for (i in seq_along(lcs)) {
    lc <- lcs[i]
    sub <- dt[nlcd_juliana == lc]
    n_pix <- uniqueno_na(sub$pixel_id)
    prep <- prep_case_year_panel(sub)
    title <- sprintf("%s — all ecoregions (n_pixels = %s)",
                     lc, format(n_pix, big.mark = ","))
    slug <- sprintf("lc_%s_all", lc)
    out_path <- file.path(FIG_DIR, sprintf("phase6_fig7_%s.png", slug))
    render_case_year_panel(
      prep            = prep,
      plot_title      = title,
      plot_subtitle   = paste0(
        "Aggregate across all Midwest ecoregions for NLCD class '", lc,
        "'. Same layout as Fig 6 — line = weekly median, ribbon = IQR across pixels."),
      plot_caption    = case_year_caption(),
      usdm_axis_label = "LC pixel-weeks",
      out_path        = out_path
    )
    cat(sprintf("    [%d/%d] %s  (n=%d)\n", i, length(lcs),
                basename(out_path), n_pix))
  }

  if (length(small_n_log) > 0L) {
    cat(sprintf("\n  ⚠ %d stratum(s) below n_pixels < %d threshold:\n",
                length(small_n_log), SMALL_N_FLOOR))
    for (m in small_n_log) cat("    -", m, "\n")
  } else {
    cat("\n  (no small-n strata flagged)\n")
  }
  cat("\n  Total figures written:",
      nrow(cells) + length(ecos) + length(lcs), "\n")
  invisible(NULL)
}

# ------------------------------------------------------------------------------
# Figure 8: per-ecoregion LC overlay — all 5 NLCD classes on the same axes
#
# One figure per ecoregion. 3-row × 4-col layout:
#   A: NDVI anomaly weekly median, one colored line per LC (no ribbons — keeping
#      5 lines legible).
#   B: Derivative anomaly (w07) weekly median, same overlay.
#   C: USDM severity stacked area for that ecoregion.
#
# Filenames: phase6_fig8_eco<L2>_lc_overlay.png
# ------------------------------------------------------------------------------
LC_PALETTE <- c(
  "crop"          = "#DAA520",   # goldenrod — agricultural
  "forest"        = "#1B5E20",   # dark green — woody
  "grassland"     = "#9ACD32",   # yellow-green — herbaceous
  "urban_dense"   = "#424242",   # dark gray — high impervious
  "urban_diffuse" = "#9E9E9E"    # mid gray — low impervious
)

#' Per (eco, lc, week) median NDVI / derivative anomaly, plus per-eco USDM area.
prep_eco_lc_overlay <- function(dt_eco) {
  ts_long <- dt_eco[, .(
    ndvi_med  = quantile(ndvi_anom_mean,      0.50, na.rm = TRUE),
    deriv_med = quantile(deriv_w07_anom_mean, 0.50, na.rm = TRUE)
  ), by = .(cal_year, week_start, nlcd_juliana)]
  ts_long[, yday := as.integer(format(week_start, "%j"))]
  ts_long[, year_label := factor(CASE_YEAR_LABELS[as.character(cal_year)],
                                 levels = CASE_YEAR_LABELS)]
  ts_long[, nlcd_juliana := factor(nlcd_juliana,
                                    levels = c("crop","forest","grassland",
                                               "urban_dense","urban_diffuse"))]
  setorder(ts_long, cal_year, week_start, nlcd_juliana)

  # n_pixels per LC for the legend / annotation
  n_lc <- dt_eco[, .(n_pix = uniqueno_na(pixel_id)), by = nlcd_juliana]
  n_lc[, nlcd_juliana := factor(nlcd_juliana,
                                 levels = c("crop","forest","grassland",
                                            "urban_dense","urban_diffuse"))]
  setorder(n_lc, nlcd_juliana)

  usdm_dt <- dt_eco[, .(
    pct_D0 = mean(usdm == 0L, na.rm = TRUE) * 100,
    pct_D1 = mean(usdm == 1L, na.rm = TRUE) * 100,
    pct_D2 = mean(usdm == 2L, na.rm = TRUE) * 100,
    pct_D3 = mean(usdm == 3L, na.rm = TRUE) * 100,
    pct_D4 = mean(usdm == 4L, na.rm = TRUE) * 100
  ), by = .(cal_year, week_start)]
  usdm_long <- melt(usdm_dt, id.vars = c("cal_year", "week_start"),
                    measure.vars = c("pct_D0","pct_D1","pct_D2","pct_D3","pct_D4"),
                    variable.name = "severity", value.name = "pct")
  usdm_long[, severity := factor(sub("^pct_", "", severity),
                                 levels = rev(c("D0","D1","D2","D3","D4")))]
  usdm_long[, yday := as.integer(format(week_start, "%j"))]
  usdm_long[, year_label := factor(CASE_YEAR_LABELS[as.character(cal_year)],
                                   levels = CASE_YEAR_LABELS)]

  list(ts_long = ts_long, usdm_long = usdm_long, n_lc = n_lc)
}

#' Render one eco overlay figure.
render_eco_lc_overlay <- function(prep, plot_title, plot_subtitle, out_path) {
  ts_long   <- prep$ts_long
  usdm_long <- prep$usdm_long
  n_lc      <- prep$n_lc

  month_breaks <- as.integer(format(as.Date(sprintf("2021-%02d-15", 1:12)), "%j"))
  month_labels <- month.abb
  grow_rect <- data.frame(xmin = as.integer(format(as.Date("2021-03-01"), "%j")),
                          xmax = as.integer(format(as.Date("2021-09-30"), "%j")),
                          ymin = -Inf, ymax = Inf)
  base_x <- list(
    scale_x_continuous(breaks = month_breaks, labels = month_labels,
                       expand = c(0, 0), limits = c(1, 366)),
    facet_wrap(~ year_label, nrow = 1)
  )

  # Legend label includes n_pixels per LC so users see which strata are
  # large/stable vs small/noisy in this eco.
  lc_lbl <- setNames(
    sprintf("%s (n=%s)", n_lc$nlcd_juliana, format(n_lc$n_pix, big.mark = ",")),
    n_lc$nlcd_juliana
  )

  p_a <- ggplot(ts_long, aes(x = yday, y = ndvi_med,
                             color = nlcd_juliana, group = nlcd_juliana)) +
    geom_rect(data = grow_rect, aes(xmin = xmin, xmax = xmax,
                                    ymin = ymin, ymax = ymax),
              inherit.aes = FALSE, fill = "#B7DCE7", alpha = 0.25) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    geom_line(linewidth = 0.7, alpha = 0.9) +
    scale_color_manual(values = LC_PALETTE, labels = lc_lbl, name = NULL) +
    base_x +
    labs(title = "A. NDVI anomaly (weekly median per LC)",
         y = "NDVI anomaly", x = NULL) +
    phase6_theme(base_size = 11) +
    theme(strip.text = element_text(face = "bold", size = rel(1.0)),
          axis.text.x = element_blank(),
          axis.ticks.x = element_blank(),
          legend.position = "none")

  p_b <- ggplot(ts_long, aes(x = yday, y = deriv_med,
                             color = nlcd_juliana, group = nlcd_juliana)) +
    geom_rect(data = grow_rect, aes(xmin = xmin, xmax = xmax,
                                    ymin = ymin, ymax = ymax),
              inherit.aes = FALSE, fill = "#B7DCE7", alpha = 0.25) +
    geom_hline(yintercept = 0, linetype = "dashed", color = "grey40") +
    geom_line(linewidth = 0.7, alpha = 0.9) +
    scale_color_manual(values = LC_PALETTE, labels = lc_lbl, name = NULL) +
    base_x +
    labs(title = "B. Derivative anomaly (w07; weekly median per LC)",
         y = "d(NDVI)/d(yday)\nanomaly", x = NULL) +
    phase6_theme(base_size = 11) +
    theme(strip.text = element_blank(),
          axis.text.x = element_blank(),
          axis.ticks.x = element_blank(),
          legend.position = "bottom",
          legend.key.size = unit(0.5, "cm"))

  p_c <- ggplot(usdm_long, aes(x = yday, y = pct, fill = severity)) +
    geom_area(position = "stack", alpha = 0.9) +
    scale_fill_manual(values = USDM_PAL, breaks = c("D0","D1","D2","D3","D4"),
                      name = NULL) +
    base_x +
    scale_y_continuous(name = "% of eco",
                       limits = c(0, 100), expand = c(0, 0),
                       breaks = c(0, 25, 50, 75, 100),
                       labels = function(z) paste0(z, "%")) +
    labs(title = "C. USDM severity (% of ecoregion pixel-weeks in each D-class)",
         x = NULL) +
    phase6_theme(base_size = 11) +
    theme(strip.text = element_blank(),
          axis.text.x = element_text(angle = 0),
          legend.position = "bottom",
          legend.key.size = unit(0.4, "cm"))

  combined <- (p_a / p_b / p_c) +
    plot_layout(heights = c(1, 1.05, 1)) +
    plot_annotation(
      title    = plot_title,
      subtitle = plot_subtitle,
      caption  = case_year_caption(),
      theme    = theme(plot.title    = element_text(face = "bold", size = 14),
                       plot.subtitle = element_text(color = "grey30"),
                       plot.caption  = element_text(color = "grey45", size = 8,
                                                    hjust = 0))
    )

  ggsave(out_path, combined, width = 16, height = 11, dpi = 300, bg = "white")
  invisible(out_path)
}

make_fig8_eco_lc_overlay <- function() {
  cat("\n=== Figure 8: per-ecoregion LC overlay (NDVI + deriv + USDM) ===\n")
  dt <- as.data.table(readRDS_retry(file.path(paths$validation_data,
                                              "ndvi_drought_join_weekly_10y.rds")))
  dt <- dt[cal_year %in% CASE_YEARS]
  nlcd <- as.data.table(readRDS_retry(file.path(paths$gam_models,
                                                "valid_pixels_nlcd2019.rds")))
  nlcd <- nlcd[, .(pixel_id, nlcd_juliana)]
  nlcd[nlcd_juliana %in% c("urban_high", "urban_med"),
       nlcd_juliana := "urban_dense"]
  nlcd[nlcd_juliana %in% c("urban_low", "urban_open"),
       nlcd_juliana := "urban_diffuse"]
  dt <- merge(dt, nlcd, by = "pixel_id", all.x = TRUE)
  dt <- dt[!L2_code %in% c("0.0", "8.5") & nlcd_juliana != "other" &
           !is.na(L2_code) & !is.na(nlcd_juliana)]
  cat(sprintf("  loaded %s pixel-weeks after eco/LC filter\n",
              format(nrow(dt), big.mark = ",")))

  ecos <- sort(unique(dt$L2_code))
  for (i in seq_along(ecos)) {
    eco <- ecos[i]
    sub <- dt[L2_code == eco]
    prep <- prep_eco_lc_overlay(sub)
    title <- sprintf("%s — land cover overlay (n_pixels = %s)",
                     eco_display_name(eco),
                     format(uniqueno_na(sub$pixel_id), big.mark = ","))
    subtitle <- paste0(
      "All 5 NLCD Juliana classes overlaid on the same axes for direct comparison ",
      "within this ecoregion. Lines are weekly medians (no IQR ribbon — keeping ",
      "5 lines legible). Light blue band = March through September (fixed calendar default)."
    )
    slug <- sprintf("eco%s_lc_overlay", gsub("\\.", "p", eco))
    out_path <- file.path(FIG_DIR, sprintf("phase6_fig8_%s.png", slug))
    render_eco_lc_overlay(prep, title, subtitle, out_path)
    cat(sprintf("    [%d/%d] %s\n", i, length(ecos), basename(out_path)))
  }
  cat(sprintf("\n  Total Fig 8 figures written: %d\n", length(ecos)))
  invisible(NULL)
}

if (fig_arg %in% c("0",  "all")) make_fig0_domain_map()
if (fig_arg %in% c("1",  "all")) make_fig1_complementarity()
if (fig_arg %in% c("1b", "all")) make_fig1b_complementarity_lc()
if (fig_arg %in% c("2",  "all")) make_fig2_eco83_deepdive()
if (fig_arg %in% c("6",  "all")) make_fig6_case_year_timeseries()
if (fig_arg %in% c("7",  "all")) make_fig7_all_strata()
if (fig_arg %in% c("8",  "all")) make_fig8_eco_lc_overlay()

cat("\nDone.\n")
