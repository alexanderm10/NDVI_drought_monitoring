# NDVI as a Drought-Monitoring Indicator: Validation in the Midwest DEWS

**Draft — internal review version**
**Date**: 2026-06-19
**Status**: Sections 3-6 in draft; Section 1 (executive summary) written last.

> This memo synthesizes the Phase 6 validation work conducted from 2026-06-10
> through 2026-06-17 on a per-pixel HLS-NDVI pipeline spanning the Midwest
> regional DEWS domain. The live working notes are in
> [`PHASE6_VALIDATION_MEMO.md`](PHASE6_VALIDATION_MEMO.md); this document is the
> distilled, shareable version.

---

## 1. Executive summary

> **Trent, Christy, Lindsay** — I'm sharing this now as a working draft, not a finished product. The pipeline is complete and the numbers are real, but I'd like your read on the interpretation before we settle on any framing. The four-mechanism story below is where I feel least certain — particularly the northern grass result in the Mixed Wood ecoregions (5.2 Mixed Wood Shield, 8.1 Mixed Wood Plains), which may be a snow-contamination artifact rather than a real ecological signal and I haven't ruled that out. The SPEI-4w and complementarity findings feel more robust to me. Please push back wherever something reads as overreaching; that's exactly what I need at this stage.

**Question.** Can a per-pixel NDVI monitor built on NASA's Harmonized
Landsat–Sentinel-2 (HLS) record serve as a useful ecological-drought
monitor across the Midwest regional DEWS — and if so, where and how?

**Data and methods.** We spatially aggregated 30 m HLS NDVI
observations to a 4 km grid, estimated per-pixel NDVI anomalies at
each day-of-year via DOY-looped spatial GAMs (extending Juliana's
Chicago-domain methodology to the Midwest scale; §4.1–4.2), and
collapsed the resulting DOY-level anomaly estimates to a weekly grain
(~130,000 pixels × 520 weeks, 2013–2025) matching the temporal
resolution of the reference datasets. The analysis domain is a
1976 × 1212 km bounding box approximating the NIDIS Midwest DEWS
footprint. We validated the resulting NDVI signals against two
independent references — USDM (categorical, operational, partially
NDVI-dependent) and gridMET-derived SPEI (continuous, meteorological,
fully independent) — through three complementary lenses: continuous
state agreement (β/r² via fixed-effects regression), categorical
concurrence (POD/FAR/HSS vs. USDM severity), and event-anchored skill
(POD/FAR/HSS at USDM transitions). All headline results are stratified
by EPA Level II ecoregion × NLCD land cover (crop / forest / grassland
/ urban_dense / urban_diffuse).

**Headline findings.**

1. **The Midwest-aggregate NDVI signal is approximately zero.** Within
   ecoregions, the signal appears to decompose into **four distinct
   response signatures** — ALIGNED in semiarid rangelands (β ≈ +0.18 in 9.4 South Central Semiarid Prairies),
   SILENT in mesic-buffered systems (β ≈ −0.05 in 8.2/8.3/8.4),
   REVERSED-CROP in the corn belt (β = −0.10 in 9.2 Temperate Prairies cropland, +0.0 in
   grass), and REVERSED-GRASS in northern Mixed Wood ecoregions (a
   pattern consistent with dormant-season snow contamination of grass
   NDVI, but not yet tested). The aggregate near-zero appears to reflect
   the cancellation of these opposite-sign regional responses.
2. **The 4-week SPEI window appears to outperform the conventional
   3-month SPEI window for matching USDM events.** Across 35 (eco × LC)
   cells, spei_4w wins 33 onset cells and 30 recovery cells as the
   strongest single signal. SPEI-3 (~13-week), the conventional default,
   rarely wins. Based on these results, spei_4w emerges as the stronger
   meteorological partner for NDVI in this domain.
3. **NDVI and SPEI appear to catch largely different events.** Only
   4–5 % of USDM transitions have both NDVI and SPEI firing
   concurrently; NDVI uniquely catches ~19 % of events SPEI misses (and
   vice versa for SPEI). The OR ensemble lifts per-event hit rate by
   +15.5 pt on onset and +13.9 pt on recovery over the best single
   signal, though HSS is roughly unchanged (POD up, FAR up cancel).
4. **These results suggest NDVI may function as a slow-drought monitor
   rather than a flash-drought detector.** As the flash-drought filter
   tightens, SPEI's hit rate climbs sharply while NDVI's hit rate drops.
   One potentially informative exception is 9.4 South Central Semiarid Prairies grass, where
   NDVI's hit rate lifts +25 pt on flash recoveries vs. its baseline —
   consistent with the faster vegetation response in semiarid rangeland,
   though the sample is one ecoregion × LC combination.
5. **The strongest single result in our dataset is 8.3 Southeastern USA Plains
   grassland: HSS = 0.47 for onset detection.** Twelve of the top-20
   onset cells in the full table are 8.3 Southeastern USA Plains strata, which may reflect
   genuine skill or the particular USDM-transition climatology of that
   region (maybe?).

**Operational bottom line.** These results suggest the HLS-NDVI monitor
may serve as a useful **complementary** signal to existing meteorological
products, with potential operational value in (a) concurrent state
monitoring of natural-cover semiarid rangelands, (b) event-timing
alignment in humid mixed-cover ecoregions, and (c) early-growing-season
recovery detection across much of the domain. It does not appear to
function as a replacement for SPEI as the primary meteorological drought
signal, does not appear appropriate as a standalone flash-drought
monitor, and shows limited reliability as a drought indicator in managed
cropland where the signal can run counter to the meteorological deficit.
Skill magnitudes are statistically robust at our sample sizes but
operationally modest in most strata; the value, if confirmed, is
structural — where the monitor adds information beyond existing products
— rather than magnitude-based.

**Caveats.** USDM is not fully independent of NDVI — three NDVI-derived
composites (VegDRI, QuickDRI, VHI) are formal USDM inputs (§3.3). The
HLS record has known cross-mission density drift (§3.7a) and a small
pre-Sentinel-2 winter coverage gap. All claims are scoped to the
Midwest DEWS; domain generalization is a hypothesis to be tested,
not a result.

---



---

## 2. Background and motivation

### 2.1 Ecological drought and the measurement gap

Drought is conventionally framed along three intersecting axes:
meteorological (precipitation deficit), hydrological (streamflow
and reservoir deficit), and agricultural (soil moisture and crop
yield impact). A fourth framing, ecological drought — the response
of natural and managed vegetation to compound water-balance,
temperature, and management stresses — has emerged more recently as
distinct from the older three. Ecological drought is the drought
condition that exerts more influence over carbon uptake, forest mortality,
wildlife habitat, water-use planning, and the long-term integrity of
managed landscapes. It is also the drought axis we have the *least
direct way to measure*.

The standard U.S. drought monitoring products approach ecological
impact only indirectly. The U.S. Drought Monitor (USDM) serves as
the operational categorical product — weekly, expert-authored, six-class
severity, the reference for disaster declarations and assistance — but
it integrates many drought axes into a single classification rather
than reporting on vegetation state per se. Meteorological indices
(SPI, SPEI, PDSI, EDDI) characterize the water-balance *driver* of
ecological stress, not the vegetation *response*. Existing vegetation products (VegDRI, QuickDRI, VHI; §3.3) build on coarser-resolution
NDVI from AVHRR and MODIS to capture vegetation condition, and feed
into the USDM author workflow as inputs, but they were not designed
specifically to measure ecological drought as a stand-alone signal at
the spatial and temporal resolution needed for sub-regional planning.

The motivation for this work is to test whether a **per-pixel NDVI
monitor built on the harmonized Landsat / Sentinel-2 (HLS) record** —
the most direct satellite-observable proxy for vegetation greenness
currently available at sub-weekly cadence — can provide a useful,
operationally tractable ecological-drought signal. The HLS record (NASA
Landsat 8 / 9 + Sentinel-2 A / B harmonized to 30 m surface
reflectance, 2013–present) is the densest harmonized vegetation
observation record we can build a monitor on; what remains is to
evaluate whether the resulting NDVI signal *carries skill against
established drought references*, and where it does and does not.

### 2.2 Why two reference datasets, not one

The choice to validate against both USDM and SPEI is intended to provide multiple perspectives on
the performance of NDVI as a drought indicator. Each answers different
questions, and reporting both prevents reading a single
finding as the whole story.

- **USDM tells us "is the monitor operationally useful?"** A vegetation
  monitor that doesn't align with USDM is not going to be adopted by
  state climatologists or NIDIS DEWS authors, regardless of its
  scientific elegance. But USDM is partially built on vegetation
  products (§3.3), so high USDM agreement is partly expected by
  construction.
- **SPEI tells us "does the monitor track real meteorological
  drought?"** SPEI is computed from precipitation and ET only, fully
  independent of vegetation observations. NDVI–SPEI agreement is a
  cleaner scientific statement about whether vegetation responds to
  water-balance deficit in the way drought theory predicts.

These references can — and in this work, do — disagree. There are
ecoregions where NDVI tracks USDM well but not SPEI, and vice versa
(§5.3, §5.4). The disagreement is itself diagnostic: it tells us whether
the NDVI monitor is capturing something USDM authors already see (in
which case its operational value is in spatial resolution and timing
rather than in detecting new events), or whether it is detecting
vegetation stress that the meteorological signal alone does not show.

### 2.3 The prior work: Juliana's Chicago-domain analyses

Methods development for this project began with Juliana's Chicago-area
work (described in [§4.1](#41-the-prior-work---julianas-chicago-domain-spatial-gam)),
which scaled per-pixel HLS-NDVI anomaly estimation to a 100 × 100 km
metropolitan domain (~625 4 km pixels). That work demonstrated three
things relevant here:

1. **The DOY-looped spatial GAM is technically viable at the
   metropolitan scale.** Per-pixel anomalies with proper uncertainty
   propagation were computed at near-daily resolution and validated
   against ground-station-derived greenness products.
2. **Land-cover stratification reveals patterns that pixel-level
   analysis alone hides.** Urban, forest, grassland, and cropland
   patches responded differently to the same regional drought events,
   which established LC as a meaningful axis for any vegetation-drought
   analysis at metropolitan or larger scales.
3. **The NLCD collapse to a working 5-class schema is operationally
   useful.** Juliana developed and validated the crop / forest /
   grassland / urban / other groupings used in this memo (§3.5),
   including the empirical decision to fold Woody Wetlands into the
   forest stratum at 4 km. We adopted that schema unchanged, extending
   it only by splitting urban into dense / diffuse on the 50%
   impervious-cover boundary.

What the Chicago work did *not* establish was whether the same approach
generalizes beyond a single metropolitan area. A 100 km domain spans
one ecoregion at the EPA Level II grain; one climate; one
urban-rural gradient. The within-Chicago patterns might or might not
hold when the analysis crosses semiarid prairie, mesic forest, intensive
corn belt, and northern Mixed Wood ecoregions in a single grid.

### 2.4 What this work scales up and what it tests

The Midwest regional DEWS work documented here scales the Chicago
approach by roughly two orders of magnitude in area (~200× larger by
extent) and 200× in pixel count (~130,000 4 km pixels). The scaling
brings three new tests:

1. **Does the per-pixel GAM pipeline still run at scale?** This was a
   non-trivial infrastructure question (memory, runtime, parallel
   stability), addressed in §4.2. We retained the 4 km analysis grain
   from the Chicago pipeline rather than working at the HLS native 30 m
   resolution for two reasons: (a) running a per-pixel GAM at 30 m
   across the full Midwest extent is not currently computationally
   tractable; and (b) the meteorological and operational reference
   datasets we validate against (USDM, gridMET-derived SPI/SPEI) are
   themselves 4 km native, so a finer NDVI grain would not buy
   additional validation traction. A two-stage approach — 4 km
   monitoring with targeted 30 m drill-downs on flagged events — is
   plausible future work, and discussed in §7.
2. **Do the within-Chicago land-cover patterns hold across biomes?**
   The Midwest spans 11 EPA Level II ecoregions; if the LC patterns
   are stable across them, that supports treating LC as a globally
   meaningful axis. If they vary by ecoregion, then ecoregion × LC
   becomes the operational stratification.
3. **Does HLS-NDVI carry useful skill against USDM and SPEI at this
   regional scale?** This is the validation question this memo
   addresses directly. The answer is nuanced — neither "yes, NDVI is a
   strong drought monitor across the board" nor "no, NDVI is not
   useful" — and the bulk of §5 is devoted to characterizing where the
   signal is strong, where it is weak, and where it carries information
   the meteorological references do not.

Questions (1) and (2) are largely settled by the existence of the
working pipeline and the cross-ecoregion stratified results that
follow: the pipeline runs (with the operational caveats noted in §3.7);
the LC patterns are not constant across ecoregions (and the within-9.2 Temperate Prairies
crop-vs-grass split in §4.6 is a clean example of why ecoregion × LC
matters). The remainder of this memo focuses on (3).

---

## 3. Data

We assembled four primary data products on a common 4 km weekly grid covering the
Midwest regional Drought Early Warning System (DEWS) domain over 2013–2025. All
analyses in this memo operate on this aligned cache.

### 3.1 NDVI from NASA HLS v2.0

The vegetation signal comes from NASA's Harmonized Landsat Sentinel-2 (HLS) v2.0
surface reflectance product. We used HLSL30 (Landsat 8 + 9) and HLSS30
(Sentinel-2A + 2B) at 30 m native resolution, harmonized by NASA via BRDF
normalization, spectral bandpass adjustment, and atmospheric correction so
that surface reflectance from the different sensors is directly comparable.

We computed per-pixel NDVI from the harmonized red and NIR bands. Scene-level
filtering retained all scenes regardless of cloud cover (vs. the traditional
40 % cap), which gave us ~7× more scenes; cloud, cloud-shadow, adjacent-cloud,
snow/ice, and water pixels were then masked using the Fmask quality layer
bit-by-bit. Validation on 2018 data showed +23 % valid pixel observations
after Fmask filtering compared with the 40 %-scene-cap approach.

The NDVI record begins in 2013 (Landsat 8 launch), with Sentinel-2A
contributing from late 2015 and Sentinel-2B from mid 2017. Landsat 9 launched
late 2021. The four-mission ensemble means satellite revisit density rises
monotonically over the record; a caveat we return to in §3.7.

### 3.2 Analysis domain — approximating the Midwest regional DEWS

The
analysis was scoped to approximate the NIDIS Midwest regional Drought
Early Warning System (DEWS) footprint. The
domain is a 1976 × 1212 km rectangular bounding box in EPSG:5070 Albers
(`midwest_extent.rds`); after applying land-cover and data-density
filters, we retained **129,310 4 km pixels** as the working population.

The bounding box intersects 19 states; nine of them contribute ≥6 % of
the working pixels each (Nebraska, South Dakota, Minnesota, Kansas, Iowa,
Michigan, Illinois, Wisconsin, Missouri), and another six contribute
between 2 % and 6 % (North Dakota, Indiana, Kentucky, Ohio, Colorado,
Montana). Four additional states (Wyoming, West Virginia, Virginia,
Tennessee) are present only as marginal tails (<2 % each).
**Fig 1** ([phase6_fig0_domain_reference_map.png](../../../../mnt/malexander/datasets/ndvi_monitor/figures/phase6/phase6_fig0_domain_reference_map.png))
shows the domain extent, EPA Level II ecoregion polygons, and modal
NLCD land-cover class on the working 4 km grid.

This domain choice was made to focus on a region where (a) the
NIDIS Midwest DEWS provides a natural stakeholder community, and (b) the
mix of intensively-managed cropland, mesic forest, grassland, and urban
land covers gives interpretive contrast within reach of a single 4 km
grid. All claims in this memo are scoped to this domain; we do not
assert that results generalize to the West, Southeast, or Pacific
Northwest.

### 3.3 USDM weekly categorical drought

The U.S. Drought Monitor (USDM) is the standard operational drought
declaration product in the United States: a weekly, expert-authored consensus
that integrates SPEI, PDSI, streamflow, soil-moisture, satellite, and
ground-report inputs into six categorical classes (None / D0 abnormally dry /
D1 moderate / D2 severe / D3 extreme / D4 exceptional). We obtained USDM
shapefiles for 2013–2025 and rasterized them to the 4 km HLS grid, retaining
the maximum severity class within each 4 km cell per week.

A pipeline-side note that matters for downstream interpretation: the
rasterized cache encodes "None" as `dm_max = -1` (a sentinel chosen during
`08_validation_data_setup.R`), with D0..D4 as 0..4. In §4.4 we describe how
this was recoded to an ordinal `usdm_ord ∈ {0..5}` after an early version of
the analysis treated the -1 sentinel as numeric and produced a structural
bug (None→D0 transitions scoring as if D2→D3).

**USDM is not a fully independent reference for NDVI.** The NDMC's
published USDM Inputs catalog ([droughtmonitor.unl.edu/ConditionsOutlooks/Inputs.aspx](https://droughtmonitor.unl.edu/ConditionsOutlooks/Inputs.aspx))
explicitly lists three NDVI-derived products among the GIS layers available
to author-week analysts: the NDMC Vegetation Drought Response Index
(VegDRI, built on AVHRR NDVI), the NDMC Quick Drought Response Index
(QuickDRI, MODIS NDVI-derived SVI), and the NOAA CPC Vegetation Health
Index (VHI, AVHRR/VIIRS NDVI plus brightness temperature). NDVI itself is
not in the catalog by name, but it enters indirectly via these three
composites alongside SPI/SPEI, soil moisture (NLDAS, GRACE), streamflow,
snowpack, evaporative demand, and qualitative state-partner reports under
what NDMC describes as a "convergence of evidence" framework.

We treat USDM–NDVI agreement as a **shared-information benchmark, not a
fully circular one**: agreement at coarse intensity and timing is
partially expected by construction, but disagreement, lead-lag offsets,
and per-pixel and per-class skill remain meaningful diagnostics. No
published decomposition exists of how much any single USDM input — NDVI
products or otherwise — moves the weekly classification, and the
USDM's one-category-per-week pacing rule damps the influence of any
single fast-moving indicator. For the cleanest scientific question
("does NDVI track meteorological drought?") we lean on SPEI as the
reference (§5.2). USDM (§5.3, §5.4) serves as the operational reference,
whose partial dependence on NDVI products we acknowledge and live with
rather than attempt to deconfound.

### 3.4 SPI/SPEI from gridMET

For an independent, mechanistically-defined drought reference we computed
weekly Standardized Precipitation Index (SPI) and Standardized
Precipitation-Evapotranspiration Index (SPEI) at three accumulation windows
(4, 13, and 26 weeks) from the gridMET daily 4 km product over 1984–2025.
SPI uses precipitation alone; SPEI uses the water balance (precipitation
minus Penman-Monteith reference ET). Both are standardized against the full
1984–2025 baseline so that values are approximately standard-normal: zero
means typical, negative means dry.

We followed the recommendation of [match-validation-resolution] and
computed the standardization on weekly rather than monthly grain so that
the reference matches the temporal resolution of the vegetation analysis.
The full weekly cache is 5.5 GB; we read it into the analyses via memory-
mapped reads.

Coverage caveats: the SPEI weekly cache occasionally contains ±Inf values
arising from the SPEI package's CDF boundary handling near very dry or
very wet extremes. All downstream code uses `is.finite()` rather than
`!is.na()` when filtering, per [reference_spei_cache_inf_quirk].

### 3.5 Land cover from NLCD 2019

For land-cover stratification we used the National Land Cover Database
(NLCD) 2019 16-class product at 30 m native CONUS coverage (EPSG:5070).
We resampled to the 4 km HLS grid via `terra::segregate` (one 0/1 layer
per class) followed by `aggregate(fun="mean")` (giving per-class cover
fraction at 4 km), then took the modal class and its dominance fraction
per cell.

For analysis-ready strata we applied the same NLCD class groupings
Juliana developed for the Chicago analysis (crop, forest, grassland,
urban, other), with one extension: we split urban into `urban_dense`
(NLCD Developed Medium + High, ≥50 % impervious) and `urban_diffuse`
(NLCD Developed Low + Open Space, <50 % impervious) to preserve the
operationally meaningful managed-vs.-mixed-cover contrast that the raw
four-class urban schema cannot support at our sample sizes (NLCD
Developed High alone has only 28 pixels Midwest-wide). The aggregation
of NLCD Woody Wetlands (90) into the forest stratum follows Juliana's
empirical Chicago test, which found no meaningful difference between a
separate forest-wet stratum and folding it into forest at 4 km.

Midwest distribution at the 4 km modal class:

| Class           | % of valid pixels |
|-----------------|-------------------:|
| crop            | 47.4 %             |
| grassland       | 28.4 %             |
| forest          | 20.0 %             |
| other           |  2.2 %             |
| urban_diffuse   |  1.4 %             |
| urban_dense     |  0.6 %             |

We carried two parallel tracks in all stratified analyses: `all` (every
pixel in the stratum) and `dom` (only pixels where the modal NLCD class
covers ≥60 % of the 4 km cell). The `dom` track concentrates on cells
where the stratum label is faithful at sub-cell resolution; the `all`
track preserves sample size in mixed-cover regions. Dense urban
essentially never crosses the 60 % dominance floor (4 km cells are rarely
60 % pure dense urban anywhere in CONUS), so urban findings are reported
on the `all` track.

### 3.6 EPA Level II ecoregions

For climatological stratification we used EPA Level II ecoregions, the
intermediate tier of the Omernik / Commission for Environmental
Cooperation hierarchy. Eleven L2 ecoregions intersect the Midwest DEWS
domain (canonical names from `pixel_to_ecoregion_l2.rds`, per
[verify_epa_l2_names]):

| L2 code | Canonical L2 name                                          |
|--------:|------------------------------------------------------------|
| 5.2     | Mixed Wood Shield                                          |
| 6.2     | Western Cordillera                                         |
| 8.1     | Mixed Wood Plains                                          |
| 8.2     | Central USA Plains                                         |
| 8.3     | Southeastern USA Plains                                    |
| 8.4     | Ozark/Ouachita-Appalachian Forests                         |
| 8.5     | Mississippi Alluvial and Southeast USA Coastal Plains      |
| 9.2     | Temperate Prairies                                         |
| 9.3     | West-Central Semiarid Prairies                             |
| 9.4     | South Central Semiarid Prairies                            |

Ecoregions are not land-cover classes — they are climate-and-biophysical
regions, several of which contain heterogeneous land cover internally
(e.g., the Temperate Prairies ecoregion 9.2 Temperate Prairies is dominated by row-crop
agriculture in practice, despite the name). We therefore stratify by
**ecoregion × land cover** jointly in the headline analyses; ecoregion
alone is reported only as supporting context.

### 3.7 Known data-quality caveats

Three caveats affect interpretation throughout, and we flag them once
here rather than repeating at each result.

**(a) Sentinel-2 density drift.** The within-week sampling density of the
vegetation signal increases monotonically across the record: Landsat 8
only in 2013–2015, +Sentinel-2A from late 2015, +Sentinel-2B from mid 2017,
+Landsat 9 from late 2021. A diagnostic we ran (Section C of script 09,
`within_week_diagnostic`) showed the ratio of within-week NDVI-anomaly
SD to across-week SD dropped from ~0.375 in 2016 to ~0.23 in 2023–2025 — i.e.,
the weekly aggregate becomes a tighter estimate of the underlying weekly mean
as more missions contribute. This does not invalidate the GAM-based anomalies
(which are estimated per pixel-DOY and then collapsed to weekly means,
carrying per-DOY uncertainty forward), but it means cross-year
comparisons should be read with the understanding that later years
have lower observation noise than earlier years.

**(b) Pre-Sentinel-2 winter gap (2014–2015).** Six day-of-year windows in
2014 (Feb 14–16) and 2015 (Jan 15–17) are permanently missing from the
year-predictions cache because the 33 % unique-pixel coverage threshold
that the spatial GAM requires (inherited from Juliana's Chicago pipeline)
cannot be met in the pre-Sentinel-2 winter when only Landsat 8 contributes.
We accept these gaps rather than tweak parameters per-year
([systematic_over_tailored]); the affected windows are well outside the
growing season and have minimal effect on the validation analyses, all of
which are weekly aggregations that span more than a single 16-day window.

**(c) USDM dependence on NDVI.** As detailed in §3.3, the USDM's input
catalog includes three NDVI-derived composite products (VegDRI, QuickDRI,
VHI). The cleanest scientific comparison is therefore NDVI vs. SPEI
(§5.2), which is fully independent at the input level. USDM-side analyses
(§5.3, §5.4) report a shared-information rather than fully-independent
benchmark — meaningful, but to be read with this overlap acknowledged.

---

## 4. Methods

The pipeline that produced the NDVI anomalies validated in this memo is a
per-pixel scaling of Juliana's Chicago-domain spatial GAM methodology. We
describe the prior work briefly, then the modifications required to operate
the same conceptual approach across a domain that is roughly two orders of
magnitude larger.

### 4.1 The prior work — Juliana's Chicago-domain spatial GAM

Juliana's Chicago-area work (`spatial_analysis/`) established a per-pixel
NDVI-anomaly pipeline over a 100 × 100 km Chicago metropolitan domain
(~625 4 km pixels). The core analytical steps were:

1. **4 km spatial aggregation.** Aggregate 30 m HLS NDVI to a 4 km grid by
   taking the **median** of valid pixels within each cell. Median (rather
   than mean) is robust to residual cloud / shadow contamination that
   survives Fmask masking.
2. **Day-of-year spatial norm.** For each day-of-year (DOY 1–365), pool
   observations from a ±7-day window across all calendar years and fit a
   spatial-smooth GAM, `NDVI ~ s(x, y)`, with the basis dimension `k` left
   at the mgcv default (~30). Posterior simulation via Wood's
   simultaneous-interval method (`MASS::mvrnorm` of `coef`/`vcov`, 100
   draws) gives a mean and 95 % CI per pixel × DOY for the climatological
   normal.
3. **Year-specific spatial GAM.** For each year × DOY, pull a 16-day
   trailing window of observations from that year, and fit
   `NDVI ~ norm + s(x, y) - 1` — the climatological normal as a covariate
   (no intercept), plus a within-year spatial smooth that captures
   year-specific departures. Again 100 posterior simulations give the
   year-specific mean and CI.
4. **Coverage gate.** Require ≥33 % of pixels in the domain to have an
   observation in the trailing window; otherwise skip that year × DOY.
5. **Anomaly + uncertainty propagation.**
   `anomaly = year_mean − norm_mean`, with
   `anomaly_se = sqrt(year_se² + norm_se²)` under independence; per-pixel
   z = anomaly / anomaly_se.

The Chicago analysis used these anomalies to characterize census-tract-level
vegetation drought response and the urban heat-island modulation of
drought stress (Chicago_NDVI_censustract.R). Juliana's collapse of NLCD
classes (crop, forest, grassland, urban, other), described in §3.5, was
developed for those analyses and adopted here unchanged.

### 4.2 Scaling to the Midwest domain (the CONUS_HLS pipeline)

We kept Juliana's analytical structure intact and made one substantive
modification, which the spatial-basis dimension `k`. The Midwest DEWS
domain is ~200× larger by area than Chicago and contains ~130,000 4 km
pixels (vs. ~625). The mgcv default `k ≈ 30` on a 100 km domain gives a
spatial resolution of ~18 km (100 / √30); on a 1976 km domain the same `k`
gives ~361 km, which is coarser than a typical sub-ecoregion and far
coarser than the watershed-to-county scales at which drought impacts
manifest.

We tested four `k` values (30, 50, 80, 150) on a 2024 holdout, scoring
on R², RMSE on held-out observations, and the fraction of GAM
predictions that fell below zero (a proxy for overfitting at NDVI's
physical floor). The k=50 fit had R² = 0.698, RMSE = 0.089, and 0.11 %
negative predictions; k=80 and k=150 gave more negative predictions
(overfitting at sparse-data DOYs), and k=30 underfit visibly. We
settled on `k = 50` ([03_doy_looped_year_predictions.R:60-66](03_doy_looped_year_predictions.R#L60-L66)),
which corresponds to a spatial resolution of ~280 km — coarser than
Juliana's Chicago resolution proportionally, but appropriate for the
larger domain's signal-to-noise ratio at 4 km × ~100-observation pixel-DOY
samples.

Everything else in the pipeline (DOY-looped spatial norms with 100
posterior draws; 16-day trailing window for year-specific GAMs; 33 %
coverage threshold; uncertainty-propagated anomalies and z-scores) follows
the Chicago specification. The implementation differences relative to
Juliana's code are infrastructural rather than analytical: parallel
execution across DOYs (futures-backed multiprocessing), checkpoint-and-resume
to survive long runs, and the worker-recycling pattern described in
[MEMORY.md](../MEMORY.md) for stability under terra/raster memory pressure.

### 4.3 Derivative signals (rate-of-change anomalies)

Beyond the magnitude anomaly itself, we computed four **rolling derivative
windows** — 3, 7, 14, and 30 days — at each pixel × DOY, where the
derivative is the change in mean NDVI anomaly between the target DOY and
the same pixel `w` days prior, with uncertainty propagated through 100
posterior draws ([06_calculate_change_derivatives.R](06_calculate_change_derivatives.R)).
Each window has its own per-pixel mean, SE, and z-score.

The intuition is that vegetation stress onset may show up as a rapid
*change* in greenness before the *level* of greenness departs noticeably
from climatology — e.g., crops browning over 1–2 weeks during a flash dry-down.
We carried all four window widths through the validation work so that the
question "does the rate signal add information beyond the level signal?"
could be answered empirically (§5).

In the validation results that follow we refer to the magnitude signal as
`ndvi_z` and the four derivative signals as `deriv_w03_z`, `deriv_w07_z`,
`deriv_w14_z`, and `deriv_w30_z`.

### 4.4 Weekly alignment with reference datasets

For validation we joined the per-pixel weekly NDVI products to USDM and
SPI/SPEI on a common (pixel × ISO-week) grid. GAM-derived per-DOY NDVI
anomalies were collapsed to weekly means and observation counts; USDM weekly classes were attached
by ISO-week; SPI/SPEI at three windows (4 / 13 / 26 weeks) were attached
on the same week index. Per-pixel z-standardization
((signal − pixel mean) / pixel SD across the full record) was computed on
the cached side so that downstream sections work in a common units convention.

The full aligned cache (`ndvi_drought_join_weekly_10y.rds`, 8.3 GB) contains
~68 million pixel-week rows across 129,310 pixels × 520 weeks, with 12
columns (ndvi mean / SE / n / z; four derivative z's; usdm class; three
SPEI windows). All Phase 6 analyses read this cache rather than the source
files, to ensure consistent weekly alignment.

### 4.5 Validation framework — three questions, three lenses

A drought monitor can be "good" in several distinct senses. We organized the validation around
three questions, each implemented as an analysis in
[09_validate_drought_signal.R](09_validate_drought_signal.R) and each
answering to a different downstream use of the monitor:

| Lens | What it measures | Reference dataset | Headline metric (gloss) | Operational use |
|---|---|---|---|---|
| **State agreement (continuous)** | Do week-to-week NDVI z-scores covary with the continuous meteorological state of drought? | SPEI (continuous, 4 / 13 / 26-week windows) | **β** — slope of NDVI z on SPEI per stratum; **r²** — within-stratum variance explained | A drought *characterization* product: "How dry are conditions, on a continuous scale?" |
| **Categorical concurrence** | Does NDVI agree categorically with USDM drought severity in the same week? | USDM (categorical D0–D4) | **HSS** — Heidke Skill Score (categorical skill above chance, range −1..+1); **POD** — Probability of Detection; **FAR** — False Alarm Ratio; **Spearman ρ** within-drought (signal vs USDM severity change) | A *concurrent classification* product: "Right now, what USDM class would NDVI suggest?" |
| **Event-anchored skill** | Does NDVI fire (cross threshold and sustain) near the timing of USDM drought transitions? | USDM (transition-anchored: onset = None → D0+; recovery = any drought → None) | POD / FAR / HSS via 4-week block contingency; per-event hit rate; lead-time distribution (NDVI fire vs USDM transition, in weeks) | An *event-detection* product: "When USDM transitions, does NDVI catch the same events?" |

All three metrics are bounded skill measures. **POD** answers "of all real
events, how many did the monitor catch?" (0 = none, 1 = all). **FAR**
answers "of all alarms, how many were false?" (0 = perfect, 1 = all
false). **HSS** combines both into a single score corrected for
chance-level agreement: 0 = no skill, 1 = perfect, negative = worse than
random. We report all three rather than HSS alone because POD and FAR
trade off against each other — a high-POD / high-FAR monitor (catches
everything but cries wolf often) and a low-POD / low-FAR monitor
(misses events but rarely false-alarms) can have the same HSS while being
operationally very different.

Throughout the memo we report each lens on its own terms and resist the
temptation to collapse them into a single headline. A monitor can be
strong on event timing in 8.3 Southeastern USA Plains (§5.4) but silent on
continuous state agreement there (§5.2) — both findings are true; they
just answer different questions.

A fourth analysis (`within_week_diagnostic`) tested whether weekly
aggregation preserves the per-pixel signal — it does, and is documented
in §5.1 as a gate decision. Three downstream analyses (`flash_drought`,
`ensemble_or`, `ensemble_multi`) reuse the event-anchored scaffolding
and are described in §5.6–§5.8.

### 4.6 Stratification — ecoregion × land cover

All headline results are reported stratified by **EPA Level II
ecoregion × NLCD land cover** (the 5-class Juliana collapse described in
§3.5). Both axes were anticipated to matter from the design stage.
Vegetation drought response is a known function of biome
(semiarid grasslands respond to short-window precipitation; mesic
forests buffer against it through deeper rooting and longer leaf retention)
and a known function of land cover (irrigated cropland and managed
turfgrass break the precipitation-response link entirely in seasons when
management is active). The natural design is to control for both, and we
adopted EPA Level II ecoregions as the climate-and-biome axis and the
NLCD-derived Juliana collapse as the land-cover axis from the outset.

The data confirmed both axes carry independent signal:

- **Ecoregion-level heterogeneity.** A simple Midwest-aggregate
  regression of NDVI z on SPEI 13w gives β ≈ −0.04 — essentially zero.
  Within-ecoregion the same regression reveals slopes ranging from +0.18
  in the South Central Semiarid Prairies (9.4 South Central Semiarid Prairies, expected positive
  response) to −0.12 in the Temperate Prairies (9.2 Temperate Prairies, *opposite* sign).
  These two ecoregions are adjacent in the central Plains; aggregating
  across them cancels the signal to near-zero.
- **LC-mediated modulation within ecoregion.** Within 9.2 Temperate Prairies (the
  reversed-sign Temperate Prairies / corn belt), the −0.12 ecoregion
  slope decomposes to β = −0.10 ± 0.01 in crop pixels and
  β = −0.01 ± 0.02 in grass pixels. A by-ecoregion view alone would
  invite a climate explanation for the reversal; the LC decomposition
  shows it is a land-use signal.

We therefore designed the analyses so that every headline metric is
reported at the (eco × LC) stratum, with ecoregion-level summaries
shown only as supporting context. This gives readers the granularity to
distinguish "this ecoregion behaves differently because of its climate"
from "this ecoregion behaves differently because of what is grown in
it" — a distinction the aggregate signal cannot make.

We carried two dominance tracks throughout, as noted in §3.5: `all`
(every pixel in the stratum) and `dom` (modal class fraction ≥60 %). The
`dom` track is the cleaner-LC story; the `all` track preserves sample
size and is the default when both are similar. We flag explicitly when a
finding holds on one track but not the other (most do not depend on the
choice).

### 4.7 Choice of weekly aggregation

Before settling on weekly aggregation as the working temporal grain, we
ran a diagnostic (Section C, `within_week_diagnostic`) to confirm the
weekly aggregate preserves signal. For each (pixel × ISO-week) we computed
the SD of `anoms_mean` across DOYs in that week and compared to the
per-pixel SD of weekly means across weeks. A ratio of within-week to
across-week SD below 1 means weekly aggregation preserves more signal than
it loses.

All 11 ecoregions returned median ratios in [0.22, 0.36] — i.e.,
within-week noise is 22–36 % of week-to-week signal everywhere — and
zero pixels had a ratio above 1. Weekly aggregation is safe everywhere
in the domain. The diagnostic also surfaced the Sentinel-2 density drift
discussed in §3.7(a): within-week SD ratios trend downward from ~0.375 in
2016 to ~0.23 by 2023, as more missions contribute to the weekly
aggregate. We carried this caveat into the cross-year interpretation
rather than restricting the record.

---

## 5. Results

The results below build the validation argument from a gate decision
about the working temporal grain (§5.1), through the central
state-agreement and event-detection findings (§5.2–§5.4), to the
operationally important complementarity and ensemble findings
(§5.5–§5.8). Each subsection reports what we tested, what the data
showed, and what it means; caveats are flagged inline.

Numbers below are weighted-mean values across the (eco × LC) strata
unless otherwise noted, and all skill metrics are computed on the
full population (10 years, ~129K pixels) rather than smoke-test
subsets.

### 5.1 Gate decision: weekly aggregation preserves the per-pixel signal

The first analysis we ran was a per-pixel diagnostic confirming that
weekly aggregation was the right working grain. For each
(pixel × ISO-week) we computed the SD of the daily NDVI anomalies
within that week and compared it to the per-pixel SD of weekly means
across weeks. A within-week / across-week SD ratio < 1 means weekly
aggregation preserves more signal than it averages out (§4.7).

All 11 EPA Level II ecoregions returned median ratios in [0.22, 0.36];
no pixel in the domain had a ratio > 1. Weekly aggregation is safe
everywhere. The diagnostic surfaced two structural features we carry
through the rest of the analysis:

- **Sentinel-2 density drift** (§3.7a). The within-week SD ratio
  dropped monotonically from ~0.375 in 2016 to ~0.23 by 2023–2025
  as Sentinel-2A, Sentinel-2B, and Landsat 9 each added to the
  observing constellation. The ratios do not invalidate any single
  pixel-week estimate, but cross-year comparisons should be read with
  the understanding that later years have lower observation noise.
- **2016 wk-50 snow contamination hotspot.** Roughly 5,000 upper-Midwest
  pixels showed elevated within-week SD in mid-December 2016 that the
  Fmask snow flag did not capture. We left the data in and flag it where dormant-season
  anomalies are read in subsequent analyses.

The remainder of §5 operates on the weekly join cache
(`ndvi_drought_join_weekly_10y.rds`, ~68 M pixel-week rows).

### 5.2 State agreement: the four-mechanism story (continuous SPEI)

The first headline result came from a fixed-effects regression of
NDVI z-scores on raw SPEI within each (eco × LC) stratum, at three
SPEI windows (4 / 13 / 26 weeks). The question: did NDVI track the
meteorological state of drought, and where?

A naive Midwest-aggregate fit gave β ≈ −0.04 at SPEI-13w — essentially
zero, and slightly in the *wrong* direction (NDVI z negatively related
to SPEI, when the expected response is positive: drier SPEI →
lower NDVI). This near-zero aggregate was the cancellation of
substantial heterogeneity across ecoregions and land covers. The
stratified results decomposed into **four distinct operational
signatures**:

| Signature | Ecoregions | β pattern (spei_26w × ndvi_z) | Interpretation |
|---|---|---|---|
| **ALIGNED** | 9.4 South Central Semiarid Prairies, 6.2 Western Cordillera, 9.3 West-Central Semiarid Prairies (grass only) | β positive across LCs (9.4: crop +0.16, forest +0.19, grass +0.20) | Semiarid rangeland: sustained dry → less green, as expected. The clear operational success case. |
| **SILENT** | 8.2 Central USA Plains, 8.3 Southeastern USA Plains, 8.4 Ozark/Ouachita-Appalachian Forests | β uniformly small-negative (−0.02 to −0.05) across LCs | Water-buffered systems (mesic forest, humid mixed cover) where vegetation does not linearly respond to SPEI. |
| **REVERSED-CROP** | 9.2 Temperate Prairies (corn belt) | crop −0.100, grass −0.007 (Wald χ² = 2,685, p ≈ 0) | The reversal lives in cropland. Most likely mechanism: irrigation buffers, plus planting/harvest cycles that decouple NDVI from water-balance deficit at the cell level. |
| **REVERSED-GRASS** | 5.2 Mixed Wood Shield, 8.1 Mixed Wood Plains | All negative, **grass is worst** (5.2: crop −0.060, forest −0.070, grass −0.100) | Northern boreal-influenced ecoregions; leading mechanistic hypothesis is dormant-season snow contamination of grass NDVI (untested as of this draft; flagged in §7). |

The geographic and timescale-dependent structure of these signatures
is summarized in **Fig 2**
([phase6_fig11_three_window_mechanism_map.png](../../../../mnt/malexander/datasets/ndvi_monitor/figures/phase6/phase6_fig11_three_window_mechanism_map.png)),
the cover figure for the validation story. Fig 2 has two rows: the
top row shows the eco-mean β as a continuous diverging heatmap (red ↔
grey ↔ green centered at zero) for each of the three SPEI integration
windows; the bottom row plots the same per-ecoregion β as trajectories
across the windows. For per-ecoregion LC decomposition visuals (the
data underneath the eco-mean), see **Fig 3** (per-eco LC overlays:
`phase6_fig8_eco{5p2,6p2,8p1,8p2,8p3,8p4,9p2,9p3,9p4}_lc_overlay.png`),
which display the case-year NDVI anomaly time series for each ecoregion
broken out by land cover. A more comprehensive supplementary set
(`phase6_fig7_eco*_*.png`, ~60 panels per case year × eco × LC and
per-eco / per-LC aggregates from `make_fig7_all_strata()`) is also
available on disk for deeper per-stratum exploration; not included
in this memo to keep the figure inventory focused.

**The four mechanisms are not all observable at every window.** The
table above is read off `spei_26w` (the 6-month integration); at
shorter windows the picture compresses dramatically. At `spei_4w` (1
month), eco-mean β is negative across **every** Midwest ecoregion —
the entire domain reads REVERSED. At `spei_13w` (3 months), only 9.4 South Central Semiarid Prairies
crosses into the ALIGNED tier; 6.2/8.3/8.4 transition toward SILENT;
the rest remain REVERSED. The full four-mechanism picture above only
resolves at `spei_26w`, where ALIGNED appears in semiarid west (9.4 South Central Semiarid Prairies,
6.2 Western Cordillera), SILENT in mesic-buffered systems (8.2 Central USA Plains, 8.3 Southeastern USA Plains, 8.4 Ozark/Ouachita-Appalachian Forests, plus 9.3 West-Central Semiarid Prairies under
the eco-mean rule), and REVERSED persists in 9.2 Temperate Prairies, 5.2 Mixed Wood Shield, 8.1 Mixed Wood Plains. The
implication is ecological, not methodological: vegetation greenness
tracks *integrated* water balance, not weekly meteorological
excursions, and the integration window required to detect the
relationship is the timescale of vegetation response itself. REVERSED
coupling is by contrast structural — it survives every window in
9.2/5.2/8.1, indicating mechanisms (irrigation, management, snow
contamination) that do not average out at longer timescales.

Two extensions of the four-mechanism picture warrant explicit mention:

- **The 9.3 West-Central Semiarid Prairies mystery — table view vs. figure view.** 9.3 West-Central Semiarid Prairies is the cell
  where the per-LC table above (which classifies it ALIGNED, with the
  "grass only" caveat) and Fig 2 (which classifies it SILENT under the
  eco-mean rule at 26w) genuinely diverge. Both readings are correct:
  9.3 West-Central Semiarid Prairies *is* ALIGNED if you look at grasslands alone (β = +0.063), but
  the LC heterogeneity within 9.3 West-Central Semiarid Prairies (crop −0.018, forest flat) averages
  the eco-mean down to β ≈ +0.026 — below the |β| > 0.05 ALIGNED
  threshold the figure uses. The figure is conservative because it
  collapses across LCs; the table is faithful to the per-LC structure.
  Use both views together: 9.3 West-Central Semiarid Prairies grass is operationally meaningful;
  9.3 West-Central Semiarid Prairies-as-a-whole is not.
- **The corn-belt urban-density split.** Within 9.2 Temperate Prairies, the dense urban
  stratum joined the crop reversal pattern (β = −0.072, n = 91),
  while diffuse urban behaved like grass (β = −0.008, n = 214). This
  is the *only* ecoregion in the analysis where dense and diffuse
  urban diverge meaningfully. It is consistent with a "managed-surface"
  mechanism: high-impervious urban surfaces (with lawn irrigation,
  evapotranspirative cooling, landscape water management) behave like
  managed cropland under drought, while low-impervious / mixed-cover
  urban tracks the natural cover it sits within.

**Caveat:** the headline β values are modest in absolute magnitude
(r² values are 0.2–4 % within stratum); the *direction* and *pattern*
across (eco × LC) are the load-bearing findings. All |β| > 0.01 cells
had permutation-null z-scores > 100; the signals were statistically
robust at our 67 M pixel-week sample size, even when modest in
explanatory variance.

### 5.3 Categorical concurrence: USDM agrees with SPEI in some ecoregions and disagrees in others

A parallel analysis (`categorical_usdm_nlcd`) computed within-drought
Spearman ρ between NDVI z (sign-flipped: positive ρ = NDVI below-normal
precedes USDM intensifying = expected skill) and USDM severity change
at K=4 lead, by (eco × LC). The question: where USDM declared drought,
did NDVI carry information about its evolution?

The headline finding was that the USDM-side picture **does not cleanly
replicate the four-mechanism SPEI story**. Three patterns of
disagreement matter:

1. **8.4 Ozark/Ouachita-Appalachian Forests: SILENT on SPEI, but ALIGNED on USDM.** 8.4 Ozark/Ouachita-Appalachian Forests showed
   β ≈ −0.05 on SPEI (slight wrong-direction across LCs, the SILENT
   pattern), but USDM ρ ranged +0.016 to +0.148 across LCs, with grass
   the most-sampled cell at ρ = +0.042 (n = 184K) and a small-N
   dense-urban cell at ρ = +0.148 (suspect for sample size). USDM
   declarations in 8.4 Ozark/Ouachita-Appalachian Forests appear to track something the meteorological
   water-balance signal alone does not — possibly streamflow,
   reservoir, or other inputs that USDM authors integrate in this
   region.
2. **8.2 Central USA Plains grass: mild negative on SPEI, sharply
   negative on USDM.** 8.2 Central USA Plains|grass shows ρ = −0.171 (the most-negative
   cell in the table, n = 16K within-drought weeks), against an SPEI
   β = −0.030. USDM thinks 8.2 Central USA Plains grass is doing the opposite of what
   NDVI says, at much larger magnitude than the meteorological
   signal alone would predict.
3. **ALIGNED replicates but magnitudes shrink 3–4× from SPEI to USDM.**
   9.4 South Central Semiarid Prairies SPEI β ranges +0.16 to +0.20; 9.4 South Central Semiarid Prairies USDM ρ ranges +0.01 to +0.05.
   This is the expected signature of USDM-as-lagging-categorical-product:
   the meteorological signal (SPEI) is strong and clean; the
   categorical USDM signal is weaker and noisier because expert weekly
   binning adds latency and information loss.

**The 9.2 Temperate Prairies urban-density split that was visible on SPEI is absent on
USDM.** On SPEI, dense urban (β = −0.072) joined crop's reversal while
diffuse urban (β = −0.008) behaved like grass. On USDM, both urban
tiers cluster around ρ ≈ −0.045 — they do not differentiate. SPEI's
continuous water-balance picks up a surface-management gradient that
USDM's categorical expert-consensus product does not.

The best USDM intensification skill cell at meaningful sample size was
**8.2 Central USA Plains urban_dense, HSS = +0.020, POD = 0.077, FAR = 0.892, n = 223K**.
Small in absolute magnitude but statistically real; worth flagging for
follow-up.

### 5.4 Event-anchored skill — spei_4w dominates; 8.3 Southeastern USA Plains is the operational sweet spot

A third analysis (`event_detection_nlcd`) anchored skill on USDM
*transitions* rather than on USDM levels. We defined drought events at
the per-pixel transitions (onset: None → D0+; recovery: any drought →
None) and asked: across eight candidate signals (ndvi_z, four
derivative windows, three SPEI windows), how skillfully did each
*fire* near the transitions? Skill was scored via 4-week temporal-block
POD/FAR/HSS contingency, per (eco × LC × dom).

Two findings stand out:

**(a)** `spei_4w` **is the strongest single signal across the board.** Of
35 (eco × LC × dom) cells with ≥5,000 events, spei_4w won 33 of 35
onset cells and 30 of 35 recovery cells; derivatives won 3 + 5 cells;
the longer SPEI windows (13w, 26w) almost never won. Domain-weighted
HSS at the headline op (z = 1.5, K = 2, ±8 wk match): spei_4w 0.171
onset / 0.088 recovery; the next-best single signal at this op is
ndvi_z at HSS = −0.035 / +0.010 (i.e., spei_4w was the only single
signal with consistently positive HSS at the headline op).

This is a meaningful finding in its own right: **the conventional
SPEI-3 (3-month, ~13-week) window is *not* the best SPEI window for
matching USDM transitions in this domain — the 4-week (~SPEI-1) window
is.** We discuss the operational implication of this in §5.7.

**(b) 8.3 Southeastern USA Plains is the operational dark horse.**
The best onset HSS in the full 50-stratum table was **0.473** at
**8.3 Southeastern USA Plains grassland (dom) × spei_4w × z = 1.5 / K = 1**, n = 6,480
(POD = 0.526, FAR = 0.473). Twelve of the top-20 onset cells were 8.3 Southeastern USA Plains
strata. 8.3 Southeastern USA Plains — the Southeastern USA Plains, spanning Arkansas /
Missouri Ozark foothills / East Texas / Louisiana / parts of MS/TN —
is a humid subtropical mixed grass-crop-forest region with episodic
summer storms that produce sharp SPEI excursions. Both USDM
declarations and spei_4w fires responded on aligned weeks-to-month
timescales, and the result was operationally meaningful onset
detection. **Fig 4** ([phase6_fig2_eco83_deepdive.png](../../../../mnt/malexander/datasets/ndvi_monitor/figures/phase6/phase6_fig2_eco83_deepdive.png))
is the 8.3 Southeastern USA Plains deep-dive panel showing per-LC HSS and per-signal skill
ranking.

This finding sits in tension with §5.2: 8.3 Southeastern USA Plains was in the SILENT tier of
the SPEI state-agreement table (β ≈ −0.03 across LCs). The same
ecoregion is silent on concurrent state and excellent on event-timing
alignment. This is a clean example of the three-lens framing in §4.5
paying off: the lenses answer different questions and a stratum can
score well on one while being silent on another. Both findings are real.
**Fig 5** ([phase6_fig3_section_a_vs_b_scatter.png](../../../../mnt/malexander/datasets/ndvi_monitor/figures/phase6/phase6_fig3_section_a_vs_b_scatter.png))
plots Section A (state agreement β) against Section B (event-detection
HSS) per (eco × LC) stratum, visualizing exactly this kind of
cross-lens disagreement.

Two additional patterns from the full event-detection table:

- **Recovery > onset detectability.** 50% of strata had positive
  recovery HSS vs. 40% for onset; the best recovery cell was
  **8.3 Southeastern USA Plains grass × deriv_w07_z × z = 1.5 / K = 2 at HSS = +0.223**
  (n = 6,448). Greening events left a cleaner signature than stressed
  onsets.
- **9.3 West-Central Semiarid Prairies had the weakest meteorological
  signature at USDM onset.** At 9.3 West-Central Semiarid Prairies onset, mean SPEI-13w post-event
  was −0.44 and only 51.6% of events crossed SPEI ≤ −1 in the window
  (vs ~65–70% in most other ecoregions). USDM declared drought in 9.3 West-Central Semiarid Prairies
  with thinner SPEI evidence; the drivers were likely soil moisture,
  streamflow, or agricultural reports, not precipitation deficit alone.

**Caveat:** the HSS magnitudes are bounded by the imbalance of the
USDM transition base rate. HSS = 0.47 in 8.3 Southeastern USA Plains grass is the cell where
the operational claim is strongest; most cells sit between −0.05 and
+0.10. The operational story is that a few cells work *very well* and
most cells provide modest skill — not that NDVI uniformly tracks USDM
events.

### 5.5 Complementarity — NDVI and SPEI catch largely different events

A side product of the event-detection analysis was the **agreement
matrix** between NDVI and SPEI fires at the headline op-point (z = 1.5,
K = 2, lead = ±8 wk):

| Direction | Both fire | NDVI only | SPEI only | Neither |
|---|---:|---:|---:|---:|
| Onset | 5 % | 19 % | 22 % | 54 % |
| Recovery | 4 % | 19 % | 14 % | 63 % |

**Only 4–5% of USDM events had both NDVI and SPEI firing at this
op-point.** The two signals caught largely different events, not the
same ones. This is the strongest single argument for the value of a
vegetation monitor as a complement to the meteorological signal: NDVI
uniquely caught ~19% of events that SPEI missed, and SPEI uniquely
caught 14–22% that NDVI missed.

Per-ecoregion the complementarity rate ranged from ~30% combined hit
rate in mesic forest ecoregions to ~50% in 8.3 Southeastern USA Plains. **Fig 6**
([phase6_fig1_ndvi_spei_complementarity.png](../../../../mnt/malexander/datasets/ndvi_monitor/figures/phase6/phase6_fig1_ndvi_spei_complementarity.png))
is the per-ecoregion 100%-stacked bar of {both / NDVI-only / SPEI-only
/ neither} at the headline op. **Fig 7**
([phase6_fig4_complementarity_atlas.png](../../../../mnt/malexander/datasets/ndvi_monitor/figures/phase6/phase6_fig4_complementarity_atlas.png))
maps the per-pixel rate at which NDVI fired without SPEI; it is the
most direct visualization of where a vegetation monitor adds operational
information beyond the meteorological signal alone.

LC-stratified complementarity (**Fig 8**,
[phase6_fig1b_ndvi_spei_complementarity_lc.png](../../../../mnt/malexander/datasets/ndvi_monitor/figures/phase6/phase6_fig1b_ndvi_spei_complementarity_lc.png))
sharpens the picture further:

- **Crop onset**: 8.3 Southeastern USA Plains had the largest "both" segment — Southeastern
  USA Plains cropland (Arkansas / east Texas / Louisiana / Mississippi
  delta), *not* the corn belt. 8.2 Central USA Plains + 9.4 South Central Semiarid Prairies crop showed strong NDVI-only
  segments, possibly via irrigation-stress signatures.
- **Forest onset**: 8.2 Central USA Plains forest had the largest
  NDVI-only share — forest NDVI carried information SPEI missed there.
- **Grass onset**: 8.3 Southeastern USA Plains grass had the clearest "both" segment;
  6.2 Western Cordillera grass was nearly all "neither" at this
  threshold (low signal-to-noise in semiarid grass at z = 1.5).
- **Recovery (all LCs)**: NDVI-only dominated almost everywhere. SPEI
  is structurally poor at greening detection; NDVI's value-add is
  largest in recovery monitoring.

The complementarity finding sets up the question §5.7 takes on: if
NDVI and SPEI catch different events, can we combine them into a
better ensemble?

### 5.6 Flash drought subset — positioning NDVI as a slow monitor

A targeted analysis (`section_flash_drought`) subset events to the
Otkin-style *flash drought* subset: events where the USDM trajectory
crossed at least D1 (lenient) or D2 (strict) in a ±4-week window
around the event. The question: how does vegetation-detected drought
signal vary as we restrict to events where meteorological drought
arrived (or departed) within a vegetation-response timescale?

The original flash-drought analysis used `spei_13w` as the SPEI
partner (inherited from an earlier headline op-point); §5.7
established that `spei_4w` is the canonical partner, and we re-ran
the per-event hit-rate analysis with `spei_4w` for this memo
(see table below). **Fig 9**
([phase6_fig9_flash_drought_color_dual.png](../../../../mnt/malexander/datasets/ndvi_monitor/figures/phase6/phase6_fig9_flash_drought_color_dual.png),
with companion LC and ecoregion variants
`phase6_fig9_flash_drought_color_{lc,eco}.png`) shows the
per-stratum NDVI–SPEI flash-drought scatter; **Fig 10**
([phase6_fig6_case_year_anom_deriv.png](../../../../mnt/malexander/datasets/ndvi_monitor/figures/phase6/phase6_fig6_case_year_anom_deriv.png))
gives concrete case-year time-series of NDVI anomalies and derivatives
during representative drought years.

Domain-wide hit rates at the headline op:

**Onset:**

| Subset | n events | NDVI hit | SPEI hit |
|---|---:|---:|---:|
| All events | 1.50 M | 24.6 % | 42.9 % |
| Flash ≥ D1 in 4 wk | 477 K | 22.3 % | 61.7 % |
| Flash ≥ D2 in 4 wk | 65 K | 17.1 % | **81.0 %** |

**Recovery:**

| Subset | n events | NDVI hit | SPEI hit |
|---|---:|---:|---:|
| All events | 1.45 M | 23.4 % | 38.0 % |
| Flash ≥ D1 in 4 wk | 374 K | 23.7 % | 47.5 % |
| Flash ≥ D2 in 4 wk | 34 K | 21.7 % | 58.0 % |

As the flash filter tightens, **SPEI's hit rate climbs sharply
(43% → 62% → 81% on onset) while NDVI's hit rate drops (25% → 22% →
17%)**. NDVI-only firings on onset collapse from 16% (all events) to
3% (strict flash). The mechanism is intuitive: SPEI is the
meteorological trigger by definition, while NDVI captures the
vegetation *response* on a weeks-to-month lag. A 4-week look-ahead
window is approximately the vegetation lag time itself; NDVI simply
has not had time to respond when the flash event is declared.

**One ecologically informative cell.** **9.4 South Central Semiarid Prairies grass shows NDVI hit rate +25 percentage points on flash
recoveries vs. all recoveries (54% vs 29%)**, and 9.4 South Central Semiarid Prairies crop shows
+12 pt. These are the only two strata in the 35-cell matrix with a
within-NDVI flash-recovery lift above +5 pt; everything else is flat
or declining (third place: 8.3 Southeastern USA Plains forest at +2.6 pt). The pattern matches
the underlying ecology: warm-season C4 grasses on the southern Plains
respond to moisture pulses on a 1–3 week timescale that fits inside
the 4-week flash-recovery window, and dryland crops in the same
ecoregion track it. SPEI_4w also lifts sharply on this cell (+31 pt
on D2 recovery, from 45% → 77%), so this is not a case of NDVI
outperforming the meteorological signal — both signals see the rapid
rebound. The result is the only stratum where NDVI provides
corroborating, biologically grounded vegetation evidence of the
meteorological recovery on a flash timescale. Elsewhere, the absence
of an NDVI lift on flash subsets is itself the finding: vegetation
cannot integrate a 4-week meteorological excursion into a detectable
canopy signal in (e.g.) eastern forests, irrigated corn-belt crops, or
northern grasslands where the temperature ceiling on growth limits how
quickly canopies can respond.

The picture that emerges is consistent with NDVI functioning as a
slow-drought monitor rather than a flash detector — a complement to
meteorological signals on sustained baseline events, less suited to
rapid-onset detection where vegetation response lags the meteorological
trigger. Whether that framing holds across domains beyond the Midwest
is a hypothesis, not yet a result.

### 5.7 Ensemble — `ndvi_z OR spei_4w` is the canonical NDVI–SPEI pair

Given the strong complementarity (§5.5), the natural next question
was whether a logical-OR ensemble of NDVI and SPEI beats either alone.
We tested 8 single signals × 3 z thresholds × 2 directions = 48
fire-detection passes, plus three cross-family OR pairs
(`ndvi_z OR spei_{4w, 13w, 26w}`).

Full-transparency tables at three z thresholds (domain-weighted):

**z = 1.0 (lenient — large event population)**

| | spei_4w | spei_13w | ndvi_z | OR spei_4w | OR spei_13w |
|---|---:|---:|---:|---:|---:|
| **Onset HSS** | **0.197** | 0.115 | −0.036 | 0.089 | 0.033 |
| **Onset POD** | 0.367 | 0.181 | 0.115 | **0.445** | 0.279 |
| **Onset hit-rate** | 73.8 % | 54.9 % | 47.5 % | **86.0 %** | 77.9 % |
| **Recovery HSS** | **0.105** | 0.011 | 0.013 | 0.065 | 0.013 |
| **Recovery POD** | 0.324 | 0.115 | 0.167 | **0.434** | 0.262 |
| **Recovery hit-rate** | 67.0 % | 38.4 % | 52.5 % | **83.9 %** | 71.7 % |

**z = 1.5 (headline op; balanced event population)**

| | spei_4w | spei_13w | ndvi_z | OR spei_4w | OR spei_13w |
|---|---:|---:|---:|---:|---:|
| **Onset HSS** | **0.171** | 0.014 | −0.035 | 0.098 | −0.017 |
| **Onset POD** | 0.218 | 0.053 | 0.048 | **0.260** | 0.099 |
| **Onset hit-rate** | 42.9 % | 27.0 % | 24.6 % | **58.4 %** | 46.6 % |
| **Recovery HSS** | **0.088** | −0.017 | 0.010 | 0.070 | −0.006 |
| **Recovery POD** | 0.175 | 0.045 | 0.067 | **0.228** | 0.108 |
| **Recovery hit-rate** | 38.0 % | 17.7 % | 23.4 % | **51.9 %** | 37.1 % |

**z = 2.0 (strict — small event population, extreme departures only)**

| | spei_4w | spei_13w | ndvi_z | OR spei_4w | OR spei_13w |
|---|---:|---:|---:|---:|---:|
| **Onset HSS** | **0.053** | −0.011 | −0.021 | 0.024 | −0.028 |
| **Onset POD** | 0.045 | 0.004 | 0.018 | **0.063** | 0.022 |
| **Onset hit-rate** | 9.9 % | 4.6 % | 10.0 % | **19.5 %** | 14.3 % |
| **Recovery HSS** | **0.039** | −0.014 | 0.005 | 0.037 | −0.008 |
| **Recovery POD** | 0.049 | 0.010 | 0.022 | **0.069** | 0.032 |
| **Recovery hit-rate** | 10.9 % | 4.5 % | 8.2 % | **18.1 %** | 12.2 % |

Two clean findings emerge across all three z thresholds:

**(a)** `spei_4w` **is the best SPEI partner for NDVI — not the
conventional SPEI-3 (~13-week) window.** At every z threshold and
every direction, the `ndvi_z OR spei_4w` pair beats `OR spei_13w` and
`OR spei_26w` on both hit rate and HSS. This is consistent with the
single-signal finding from §5.4 (spei_4w dominates 33/35 onset cells),
but it is a stronger statement: the 4-week SPEI window is the right
partner for NDVI in this domain, not the conventional 3-month default.
We adopt `ndvi_z OR spei_4w` as the canonical NDVI–SPEI ensemble for
the remainder of the memo and any downstream operational claim. (Fig 11,
the op-point heatmap, gives a visual at-a-glance ranking of best HSS
across all (signal × direction) cells.)

**(b) The OR ensemble lifts hit rate substantially but does not
improve HSS over the best single signal.** Per-event hit rate
(POD-equivalent on the event base) goes up by **+15.5 percentage
points on onset** (42.9% → 58.4%) and **+13.9 pt on recovery**
(38.0% → 51.9%) relative to spei_4w alone, and by **+33.8 / +28.5 pt**
relative to ndvi_z alone (~2.5× lift). But block-based HSS goes
*down* relative to spei_4w alone — POD goes up because the ensemble
catches more events, but FAR also goes up because either signal can
false-alarm, and the two effects roughly cancel on HSS.

The operational reading depends on what metric matters:

- **For event capture / POD-priority operations** (e.g., "don't miss
  drought events; we can tolerate some false alarms"), the OR
  ensemble is the recommended monitor. +15 percentage points more
  onset events caught for the cost of more false alarms is
  operationally significant.
- **For balanced detection skill (HSS-priority)**, `spei_4w` alone
  remains the best single monitor in this domain. NDVI's contribution
  is to flag specific (eco × LC) cells where it adds skill that the
  meteorological signal alone misses.
- **Per-stratum exceptions exist.** A handful of cells — including
  9.4 South Central Semiarid Prairies grass / crop on recovery and 9.2 Temperate Prairies urban_diffuse on recovery —
  do show positive HSS lift from the OR ensemble. These are the
  cells where NDVI carries operational information beyond what
  spei_4w already provides.

The memo's bottom-line ensemble claim: **NDVI + spei_4w (logical OR)
catches +15 percentage points more USDM events than the strongest
single signal alone, at the cost of more false alarms. For balanced
HSS, the best single signal (spei_4w) remains the recommended monitor;
NDVI adds value as a complementary signal in specific (eco × LC)
cells, particularly on recovery in semiarid grass and corn systems.**

We did not test weighted or learned ensembles (logistic regression,
random forest, threshold-tuned, signal-specific stratified). Naive OR
is the simplest combination; smarter combinations are likely to
out-perform it but introduce model complexity that may not be
appropriate for an operational product. Flagged in §7 as future work.

### 5.8 Firing climatology — seasonally asymmetric complementarity

A final descriptive analysis plotted the weekly composition of NDVI
and SPEI fires across the calendar year, by direction and by stratum.
**Fig 12a** ([phase6_fig10a_firing_climatology_domain.png](../../../../mnt/malexander/datasets/ndvi_monitor/figures/phase6/phase6_fig10a_firing_climatology_domain.png))
shows the domain-pooled climatology, **Fig 12b**
([phase6_fig10b_firing_climatology_lc.png](../../../../mnt/malexander/datasets/ndvi_monitor/figures/phase6/phase6_fig10b_firing_climatology_lc.png))
the per-LC breakdown, and **Fig 12c**
([phase6_fig10c_firing_climatology_eco.png](../../../../mnt/malexander/datasets/ndvi_monitor/figures/phase6/phase6_fig10c_firing_climatology_eco.png))
the per-ecoregion breakdown. The picture sharpens the operational claim
about complementarity (§5.5) into a *seasonal* statement:

- **SPEI leads onset year-round.** SPEI-only firings dominate the
  onset composition every week of the year; NDVI-only catches a
  steady but smaller fraction; "both" firings are rare (~5–8%);
  "neither" is the modal category every week.
- **NDVI catches recovery in the growing season — especially early
  growing season.** During March–June green-up, NDVI-only recovery
  firings rise sharply across natural land covers (especially in
  ALIGNED-tier ecoregions). This is the seasonally specific window in
  which NDVI's contribution is most distinct from SPEI.
- **9.4 South Central Semiarid Prairies grass recovery NDVI is very high in growing-season weeks.**
  Consistent with the 9.4 South Central Semiarid Prairies ALIGNED mechanism (§5.2) and the 9.4 South Central Semiarid Prairies grass
  flash-recovery exception (§5.6).
- **9.2 Temperate Prairies corn-belt onset NDVI is conspicuously low across all weeks.**
  Consistent with the 9.2 Temperate Prairies REVERSED-CROP mechanism (§5.2) — NDVI does
  not catch drought onset in managed cropland because the vegetation
  signal is decoupled from the meteorological deficit there.

The seasonally asymmetric picture refines the headline operational
claim: **NDVI's unique operational value is on early-growing-season
recovery transitions in natural land covers**, particularly in
semiarid grass and rangeland ecoregions where vegetation greens up
visibly within weeks of drought breaks. For drought onset across most
of the year, the meteorological signal (spei_4w) is the stronger and
faster detector.

---

## 6. Discussion

### 6.1 Where the NDVI monitor works

The picture that emerges across the three validation lenses is not
"NDVI is a viable drought monitor" or "NDVI is not viable" — it is
"NDVI may be viable in specific operational niches we can begin to
characterize." The emerging picture:

1. **Concurrent state agreement in semiarid rangelands (ALIGNED tier).**
   In 9.4 South Central Semiarid Prairies, 6.2 Western Cordillera,
   and the grass component of 9.3 West-Central Semiarid Prairies, NDVI
   tracks SPEI in the expected direction at long integration windows
   (β = +0.16 to +0.20 at SPEI-26w). For users asking "what is the
   continuous drought state of this rangeland right now," NDVI is
   an operational answer in these ecoregions.
2. **Event-anchored skill in humid mixed cover (8.3 Southeastern USA Plains).** The
   strongest single operational result in this work is HSS = 0.47 for
   NDVI-derived signals matched to USDM onset events in the
   Southeastern USA Plains. For users asking "did the USDM transition
   in this region get caught by an independent signal," the answer in
   8.3 Southeastern USA Plains is yes — at meaningful operational skill.
3. **Recovery monitoring across the domain.** Across 50 stratified
   cells, 50 % showed positive recovery HSS vs. 40 % for onset, and
   the relative advantage was largest in the early growing season
   (March–June green-up; §5.8). NDVI catches greening transitions
   the meteorological signal alone cannot — a structural fact about
   how vegetation and the water balance relate, not a methodological
   choice.
4. **Flash recovery in semiarid grass (9.4 South Central Semiarid Prairies).** The +25 percentage-point
   NDVI hit-rate lift on flash recoveries in 9.4 South Central Semiarid Prairies grass (§5.6) is the
   one cell where NDVI's vegetation signal lifts substantially above
   its baseline on a *flash* transition — corroborating (not
   outperforming) the meteorological signal, and only on recovery,
   not onset.
5. **Complementary event detection across the domain.** Only 4–5 % of
   USDM events have both NDVI and SPEI firing at the headline op;
   NDVI uniquely catches ~19 % of events that SPEI misses. A
   vegetation monitor used alongside the meteorological signal catches
   substantially more events than either alone (+15.5 pt onset / +13.9 pt
   recovery hit-rate lift from the OR ensemble; §5.7).

### 6.2 Where the NDVI monitor does not work

The same stratified picture identifies where NDVI does *not* belong
as the primary signal:

1. **Managed cropland during the growing season (REVERSED-CROP).**
   In 9.2 Temperate Prairies (corn belt) and similar managed-ag
   contexts, the NDVI–SPEI relationship is *inverted* at our cell-level
   grain (β = −0.10 for crop pixels). Irrigation, planting/harvest
   timing, and surface-water management decouple the vegetation signal
   from water-balance deficit. A user trying to monitor drought stress
   on corn-belt cropland with NDVI alone would get an unreliable
   signal that may run *opposite* to actual drought conditions.
2. **Flash drought onset.** As §5.6 made explicit, NDVI's vegetation
   response lag is roughly the same as the 4-week window used to
   define flash drought events. NDVI cannot warn about flash onsets;
   for that, the meteorological signal must lead.
3. **Northern mesic ecoregions with grass dormant-season noise
   (REVERSED-GRASS).** In 5.2 Mixed Wood Shield and 8.1 Mixed Wood Plains, the grass NDVI signal runs the wrong way (β = −0.09 to
   −0.10). The leading hypothesis is dormant-season snow contamination
   of grass NDVI in northern ecoregions; this is not yet tested
   (§7). Users in these regions should treat NDVI-derived drought
   claims for grass cover with skepticism until the mechanism is
   resolved.
4. **Mesic forest (SILENT tier).** In 8.2 Central USA Plains, 8.3 Southeastern USA Plains, and 8.4 Ozark/Ouachita-Appalachian Forests, the
   continuous NDVI–SPEI relationship is essentially absent
   (|β| < 0.05). Forest canopies buffer against water-balance
   anomalies through deeper rooting and longer leaf retention. NDVI
   in these systems carries information at the *event* scale (§5.4)
   but does not characterize concurrent drought state in a way users
   can read directly.

### 6.3 Operational positioning — a complementary monitor in a specific niche

Synthesizing across §6.1 and §6.2, our provisional interpretation —
and we'd welcome your read on whether this framing holds — is that
**the per-pixel HLS-NDVI monitor may serve as a useful complementary
signal to existing meteorological drought products, with potential
operational value in (a) state monitoring of natural-cover semiarid
rangelands, (b) event-timing alignment in humid mixed-cover ecoregions
like 8.3 Southeastern USA Plains, and (c) early-growing-season recovery detection across much
of the domain. It does not appear to function as a replacement for SPEI
as the primary meteorological drought signal, and does not appear
appropriate as a standalone flash-drought monitor. In managed cropland,
the NDVI signal can run counter to the meteorological signal, and
drought characterization there should be treated cautiously without
accounting for the irrigation/management confound.**

The natural place this monitor sits in an operational stack:

- **As input to USDM authors**, alongside VegDRI / QuickDRI / VHI but
  at finer native resolution and on the still-flying Sentinel-2 +
  Landsat 9 constellation.
- **As a regional drought-condition map** for state climatologists
  and NIDIS DEWS partners, with the (eco × LC) caveats made explicit
  in the legend.
- **As one component of a multi-signal ensemble** for event
  detection, where the +15 pt hit-rate lift over the best single
  signal is operationally meaningful even when HSS does not move.

### 6.4 Comparison to Juliana's Chicago-domain findings

Three of Juliana's key findings replicate at the Midwest scale:

- **The per-pixel GAM pipeline produces meaningful per-pixel
  anomalies at scale.** What worked at ~625 Chicago-area pixels works
  at ~129,000 Midwest pixels with one analytical change (k=50 vs.
  mgcv default) and a substantial amount of infrastructure
  engineering.
- **Land-cover stratification reveals patterns hidden at higher
  aggregation.** Juliana's Chicago work showed urban / forest / grass
  / crop responding differently to the same regional events; we see
  the same effect across the Midwest, with the additional finding
  that the LC effect is itself ecoregion-dependent (the 9.2 Temperate Prairies crop
  reversal is not the 9.4 South Central Semiarid Prairies crop response).
- **The Juliana NLCD-class collapse is the right working schema.**
  Crop / forest / grassland / urban / other captured the operationally
  meaningful contrasts; the only extension we needed was splitting
  urban into dense vs. diffuse on the 50 % impervious-cover boundary
  to surface the corn-belt urban-density divergence (§5.2).

The new findings the Midwest scale-up surfaces — that Juliana's
single-metropolitan-area picture cannot show — are the **cross-biome
heterogeneity** (the four-mechanism story; §5.2) and the **across-LC
behavior within ecoregion** (the 9.2 Temperate Prairies corn-belt mechanism; §5.3). These
required a domain that spans both semiarid and mesic biomes and
contains substantial managed cropland; Chicago, as a single
metropolitan area inside one ecoregion (8.1 Mixed Wood Plains), could
not have surfaced them.

### 6.5 The skill-magnitude caveat — statistically robust, operationally modest

A pattern visible across §5.2, §5.4, and §5.7: the headline skill
metrics are **statistically robust at our sample sizes but small in
absolute magnitude**. Best continuous-state β values are 0.16–0.20
(r² ≈ 2–4 % within stratum). The best categorical-USDM HSS is +0.05.
The best event-anchored HSS is +0.47 in 8.3 Southeastern USA Plains grass — a stratum that
contains 6,480 events; most strata sit between −0.05 and +0.10.
Best ensemble HSS is +0.10 at the domain-weighted level.

Three things to keep in mind reading these numbers:

1. **Statistical significance is overwhelming because the sample is
   enormous** (67 M pixel-week rows; 3 M events). Permutation-null
   z-scores of 100–800 are routine for cells with |β| > 0.01. The
   signal is real; the magnitude is modest. Significance and
   magnitude are different facts; both matter.
2. **The direction and pattern across strata are the load-bearing
   findings.** The four-mechanism story (§5.2) holds because the
   *pattern* — semiarid positive, corn-belt negative crop, mesic
   silent, northern grass reversed — is interpretable mechanistically.
   Any individual β at |β| ≈ 0.10 is not operationally striking by
   itself, but the across-stratum pattern is what gives the result
   its scientific weight.
3. **A few cells work very well, most cells work modestly.** This is
   the right characterization rather than "the monitor works
   uniformly across the domain." 8.3 Southeastern USA Plains grass at HSS = 0.47 is the
   operational sweet spot; 9.4 South Central Semiarid Prairies is the state-agreement
   sweet spot; the rest of the domain provides modest skill that is
   nevertheless operationally interpretable when stratified
   appropriately.

We resist any claim that NDVI produces large-magnitude single-cell
skill across the Midwest domain. It does not. The argument for the
monitor is structural and complementary, not magnitude-based.

### 6.6 The USDM shared-information caveat

A second consolidated caveat. As §3.3 documented, three NDVI-derived
composite products (VegDRI, QuickDRI, VHI) are formally listed in the
NDMC's published USDM input catalog, alongside SPI / SPEI / soil
moisture / streamflow / qualitative reports. NDVI itself is not in
the catalog by name, but it enters indirectly via these composites,
weighed by author-week analysts under a "convergence of evidence"
framework. There is no published quantitative decomposition of how
much any single input — NDVI-derived or otherwise — moves the weekly
classification.

The implication for the validation findings:

- **§5.3 (categorical USDM agreement) and §5.4 (event-anchored skill
  against USDM transitions) are shared-information benchmarks, not
  fully independent ones.** Some fraction of the NDVI–USDM agreement
  we report is structurally expected because USDM authors have NDVI
  composites available when classifying.
- **§5.2 (continuous SPEI state agreement) is a fully independent
  benchmark.** SPEI is computed from precipitation and ET only and
  has no NDVI input. NDVI–SPEI agreement reports cleanly on whether
  vegetation tracks meteorological drought as theory predicts.
- **The disagreement findings remain meaningful.** 8.4 Ozark/Ouachita-Appalachian Forests USDM-ALIGNED-
  but-SPEI-SILENT (§5.3) tells us something USDM authors are
  responding to in 8.4 Ozark/Ouachita-Appalachian Forests that the meteorological signal alone does not
  contain; this finding is not weakened by USDM's dependence on NDVI
  composites because the disagreement is about what USDM has *beyond*
  the vegetation signal.

We therefore emphasize SPEI agreement when claiming "NDVI tracks
drought as theory predicts" and emphasize USDM event-detection skill
(with the caveat) when claiming "NDVI catches what the operational
product catches."

---

## 7. Open questions and next steps

The Phase 6 validation work answers the central question — where and
how usefully NDVI tracks drought in the Midwest DEWS — at the per-pixel
4 km scale. Several threads remain open that would extend, validate,
or operationalize the findings. We list them here in rough priority
order; this is a punch list, not an exhaustive research agenda.

### Near-term (close out the current validation cycle)

1. **Test the snow-contamination hypothesis for REVERSED-GRASS
   ecoregions.** The 5.2 Mixed Wood Shield + 8.1 Mixed Wood Plains grass-worst β pattern is consistent
   with dormant-season snow inflating NDVI on northern grass cover.
   Re-run the continuous-SPEI fit on a DJF-excluded subset for 5.2 Mixed Wood Shield +
   8.1 Mixed Wood Plains specifically. If grass β jumps toward zero / positive when
   winter is excluded → snow hypothesis supported; if unchanged →
   look elsewhere. ~1–2 hr including re-fits.
2. **Deep-dive 8.4 Ozark/Ouachita-Appalachian Forests.** The USDM-ALIGNED-but-SPEI-SILENT pattern
   in 8.4 Ozark/Ouachita-Appalachian Forests (§5.3) is the cleanest case where USDM authors are
   responding to something the meteorological water balance does not
   contain. Worth pulling streamflow / soil-moisture / agricultural-
   report inputs and asking what specifically aligns with USDM
   declarations in 8.4 Ozark/Ouachita-Appalachian Forests. Could inform future input choices for
   vegetation-based monitors in that ecoregion. Half-day to one-day
   investigation.
3. **L2_name verification across all figures and tables.** A subset
   of session-era figures used incorrect ecoregion names (e.g., 8.3 Southeastern USA Plains
   mislabeled as "S Central Semi-Arid Prairies" — that's 9.4 South Central Semiarid Prairies). All
   figures cited in this memo use canonical names from
   `pixel_to_ecoregion_l2.rds`, but a sample check of the figure
   files themselves before external distribution is worthwhile.

### Medium-term (extend the validation framework)

4. **Test weighted / learned ensembles.** §5.7 tested only logical
   OR. A logistic-regression or random-forest ensemble that weights
   NDVI and SPEI by signal-strength per stratum is likely to
   outperform naive OR on HSS, not just hit rate. Worth testing as
   a follow-up; if the model is simple enough (logistic regression
   with a small number of features), it can stay in the operational
   pipeline without losing interpretability.
5. **Evaluate alternative z-standardization baselines.** All current
   z-standardizations are per-pixel. Pooled baselines (ecoregion-week,
   land-cover-week) might preserve drought-prone information that
   per-pixel z removes. Side-by-side comparison on the same skill
   tables would settle whether per-pixel is the right default.
6. **Stratify by *current USDM state*** (D0, D1, D2, D3+). The
   recovery-vs.-onset asymmetry suggests skill may concentrate at
   specific USDM severities. A within-class breakdown of the skill
   metrics is cheap to compute post-hoc and would sharpen the
   operational claims about where the monitor adds value within an
   already-classified drought.
7. **Extend the validation record back to 2013–2015 with appropriate
   caveats.** The Phase 6 analyses ran on 2016–2025 because the
   Sentinel-2 density drift (§3.7a) makes pre-2016 comparisons
   noisier. A 2013–2025 supplementary run with the noise caveat
   explicit would confirm the operational story is not era-specific.

### Longer-term (operational and methodological extensions)

8. **Two-stage 4 km + 30 m approach.** The 4 km monitoring grain is
   matched to driver-data resolution and computational tractability
   (§4.2). For flagged drought events, a targeted 30 m HLS drill-down
   could resolve subpixel structure — irrigation patches within a
   4 km crop cell, urban dense vs. low-density gradient, forest
   mosaics — that the 4 km signal averages over. The corn-belt
   urban-density split (§5.2) is the clearest leading candidate for
   sub-4 km investigation. Architecture and computational feasibility
   are open questions.
9. **Mission-continuity analysis.** The HLS record depends on
    Landsat 8 / 9 + Sentinel-2 A / B; both Landsat 8 and Sentinel-2A
    are aging. A simple sensitivity analysis estimating the skill
    loss if one or two missions retire (by re-running on a subset
    that excludes that mission's contributions) would inform
    long-term operational planning.
10. **Expand domain beyond Midwest DEWS.** All claims in this memo
    are scoped to the Midwest. The four-mechanism story is mechanistic
    enough to plausibly generalize (irrigation buffers crop signal
    everywhere; semiarid grass tracks SPEI everywhere; mesic forest
    buffers everywhere), but generalization is a hypothesis, not a
    result. Running the same pipeline on Southwest, Southeast, or
    West Coast DEWS regions would test it.
11. **Operational deployment infrastructure.** The current pipeline
    is a research pipeline with parallel R scripts and Docker
    containers (§4.2). An operational deployment would need
    automated weekly updates, anomaly-detection alerting, web-mapping
    output, and stakeholder-facing APIs. Out of scope for this memo;
    flagged as the natural follow-on if the validation findings are
    accepted.

### Scientific publications

12. **Methods/results paper.** This memo synthesizes the findings
    that would form the basis of a peer-reviewed publication. Target
    journal candidates: *Remote Sensing of Environment*,
    *Earth's Future*, *J. Hydrometeorology*, or *Earth Interactions*.
    The four-mechanism story and the spei_4w-vs-spei_13w finding are
    both publishable results in their own right.

---

