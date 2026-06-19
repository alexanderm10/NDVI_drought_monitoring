# USDM Shapefile Metadata

Data dictionary and provenance reference for the U.S. Drought Monitor weekly
shapefile archive downloaded by `download_usdm.py` / `download_usdm.sh`.

## Source

| Field | Value |
|---|---|
| **Producer** | National Drought Mitigation Center (NDMC), University of Nebraska–Lincoln, in partnership with USDA, NOAA, and NASA |
| **Authoritative URL** | https://droughtmonitor.unl.edu |
| **Archive endpoint** | `https://droughtmonitor.unl.edu/data/shapefiles_m/USDM_<YYYYMMDD>_M.zip` |
| **Filename date** | The Tuesday that the map is *valid for*. Maps are *released* the Thursday morning following. |
| **First map** | 2000-01-04 (Tuesday) |
| **Cadence** | Weekly, every Tuesday |
| **Terms of use** | Not formally public domain. NDMC requests attribution when reproducing the map; no prior permission required. See https://droughtmonitor.unl.edu/About/Permission.aspx for the exact recommended credit line. |
| **Recommended attribution** | "The U.S. Drought Monitor is jointly produced by the National Drought Mitigation Center at the University of Nebraska–Lincoln, the United States Department of Agriculture, and the National Oceanic and Atmospheric Administration. Map courtesy of NDMC." |
| **Suggested citation** | NDMC, USDA, NOAA. *U.S. Drought Monitor*. https://droughtmonitor.unl.edu, accessed `<YYYY-MM-DD>`. |

## File layout (within each weekly ZIP)

```
USDM_YYYYMMDD.shp        # polygon geometry
USDM_YYYYMMDD.shx        # shape index
USDM_YYYYMMDD.dbf        # attribute table
USDM_YYYYMMDD.prj        # projection (WKT)
USDM_YYYYMMDD.sbn        # spatial index (binary)
USDM_YYYYMMDD.sbx        # spatial index (binary)
USDM_YYYYMMDD.shp.xml    # FGDC/ESRI metadata
```

## Coordinate reference system (`.prj`)

```
GEOGCS["GCS_WGS_1984",
       DATUM["D_WGS_1984",SPHEROID["WGS_1984",6378137.0,298.257223563]],
       PRIMEM["Greenwich",0.0],
       UNIT["Degree",0.0174532925199433]]
```

Equivalent EPSG: **4326** (WGS 84 geographic). All weekly files ship in this
CRS. Note that NDMC's *internal* processing uses USA Contiguous Albers Equal
Area (`EPSG:5070`-equivalent); the published shapefiles are re-projected back
to WGS 84 before release. For area calculations, re-project to an equal-area
CRS (5070 for CONUS).

## Attribute table (`.dbf`)

Each weekly shapefile contains exactly **5 records**, one polygon per drought
category (a single record may be a `MultiPolygon`).

| Field | Type | Width | Meaning |
|---|---|---|---|
| `OBJECTID` | integer | 10 | Internal NDMC row ID — not stable across weeks; do not join on this |
| `DM` | integer | 5 | **Drought category** code, 0–4 — see legend below |
| `Shape_Leng` | float | 19 | Perimeter, decimal degrees |
| `Shape_Area` | float | 19 | Area, decimal degrees² (not a useful area; re-project first if you need m²) |

### DM category legend

| `DM` | Label | Name | Description |
|---|---|---|---|
| 0 | D0 | Abnormally Dry | Going into drought: short-term dryness slowing planting/growth; coming out of drought: some lingering deficits |
| 1 | D1 | Moderate Drought | Some damage to crops/pastures; streams/reservoirs/wells low |
| 2 | D2 | Severe Drought | Crop/pasture losses likely; water shortages common; water restrictions imposed |
| 3 | D3 | Extreme Drought | Major crop/pasture losses; widespread water shortages |
| 4 | D4 | Exceptional Drought | Exceptional/widespread crop/pasture losses; shortages of water creating water emergencies |

Polygons are **nested-by-severity**: the D2 polygon is a subset of the D1
polygon, which is a subset of the D0 polygon, etc. To get "areas where the
max severity is exactly D1", subtract D2 from D1.

A pixel/county not covered by any polygon is implicitly **no drought** (the
USDM does not publish a "D−1 = wet" or "none" polygon).

## Spatial coverage

Each map covers the **conterminous United States** plus Puerto Rico, Alaska,
Hawaii, and the U.S. Virgin Islands. Drought conditions in the Pacific and
Caribbean territories are mapped separately. Filtering by bounding box is the
consumer's responsibility — these files are not split by region.

## Temporal coverage

- **First file**: `USDM_20000104_M.zip` (Tuesday, 2000-01-04)
- **Cadence**: every Tuesday, no gaps
- **Latest file**: the most recent Tuesday *for which release Thursday has passed*

Total expected file count, for any start through end (inclusive Tuesdays):
```
n = ((end - start).days // 7) + 1
```

For 2000-01-04 → 2025-12-30 that's **1,357** weekly files.

## Known sharp edges

1. **`.shp.xml` is inconsistent**: some weeks have a full FGDC metadata record;
   others have a minimal ESRI export. Do not rely on it programmatically.
2. **`DM` is signed**: it is stored as a numeric field but only takes values
   0–4. Don't apply `-1` as a sentinel inside the file — use a separate column
   downstream.
3. **`Shape_Area` is in degrees²**: useless for thematic analysis. Compute
   areas after reprojecting to an equal-area CRS (EPSG:5070 for CONUS).
4. **`OBJECTID` is per-week**: it is regenerated each Tuesday. Do not use it
   as a key across weeks.
5. **Holidays do not shift the release**: even when Tuesday or Thursday falls
   on a federal holiday, the publication date is unchanged. (No back-shift to
   Monday or forward-shift to Friday has been observed.)

## Recommended downstream processing

For drought monitoring use, the typical pipeline is:

1. Unzip → load with `geopandas.read_file()` or `sf::st_read()`
2. Re-project to **EPSG:5070** (USA Contiguous Albers) for any area/distance
   calculation or rasterization
3. Rasterize the `DM` field with `max` aggregation onto your target grid (use
   `background=0` if you want "no drought" as a value, `background=-1` if you
   want a sentinel for "outside USDM coverage")
4. Stack weeks along a time dimension

## Reference / further reading

- NDMC, *About the U.S. Drought Monitor*: https://droughtmonitor.unl.edu/About.aspx
- Svoboda, M. et al. (2002) "The Drought Monitor." *Bull. Amer. Meteor. Soc.* 83(8): 1181–1190. doi:10.1175/1520-0477-83.8.1181
