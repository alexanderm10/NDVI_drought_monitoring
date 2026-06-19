# USDM Data Query — Handoff to NIDIS_AI

Self-contained scripts to download the **U.S. Drought Monitor (USDM)** weekly
shapefile archive for CONUS, ready to drop into:

```
U:\projects\NIDIS_AI\dataQuery\usdmDataQuery
```

USDM coverage is intrinsically CONUS-wide (the national map). No spatial
subsetting is needed at fetch time — every weekly shapefile already contains
the full CONUS DM polygon set.

## What you get

| File | Purpose |
|---|---|
| `download_usdm.py` | Primary downloader (Python 3.8+, stdlib only) |
| `download_usdm.sh` | Equivalent `wget`-based downloader (bash, no Python) |
| `USDM_METADATA.md` | Data dictionary, CRS, schema, citation, license, gotchas |
| `requirements.txt` | Empty — both scripts use stdlib / standard CLI tools |
| `README.md` | This file |

Pick **one** downloader — they target the same destination layout and produce
the same `manifest.csv`. Python is recommended (better integrity checks and
the manifest is written natively); wget is the fallback for environments
without Python.

## Destination layout

```
U:\projects\NIDIS_AI\dataQuery\usdmDataQuery\
├── raw\                     # weekly ZIPs as published by NDMC
│   ├── USDM_20000104_M.zip
│   ├── USDM_20000111_M.zip
│   └── ...
├── manifest.csv             # per-file provenance (one row per ZIP)
├── logs\
│   └── download_YYYYMMDD_HHMMSS.log
└── USDM_METADATA.md         # copy of the data dictionary
```

Each weekly ZIP unpacks to a 7-file shapefile bundle
(`.shp .shx .dbf .prj .sbn .sbx .shp.xml`) — see `USDM_METADATA.md`.

## Usage

### Python (recommended)

```bash
# Default: 2000-01-04 through last completed Tuesday, into ./
python download_usdm.py --dest "U:/projects/NIDIS_AI/dataQuery/usdmDataQuery"

# Custom date range
python download_usdm.py --dest "U:/projects/NIDIS_AI/dataQuery/usdmDataQuery" \
                       --start 2020-01-07 --end 2025-12-30

# Re-download even if file exists (skip-if-present is the default)
python download_usdm.py --dest "U:/..." --force
```

### Bash + wget

```bash
DEST="/u/projects/NIDIS_AI/dataQuery/usdmDataQuery" \
  bash download_usdm.sh                       # default range
DEST="/u/..." START=2020-01-07 END=2025-12-30 \
  bash download_usdm.sh                       # custom range
```

Both scripts are **idempotent** — re-running picks up only missing weeks.
Both also write per-file rows to `manifest.csv` (created if absent, appended
otherwise; duplicate rows are deduped on `filename`).

## Manifest schema

`manifest.csv` is the provenance record. One row per successfully downloaded ZIP:

| column | example | notes |
|---|---|---|
| `filename` | `USDM_20240730_M.zip` | basename, primary key |
| `week_date` | `2024-07-30` | Tuesday the USDM is dated for |
| `source_url` | `https://droughtmonitor.unl.edu/data/shapefiles_m/USDM_20240730_M.zip` | exact URL fetched |
| `http_status` | `200` | response code at fetch time |
| `bytes` | `1842310` | on-disk size |
| `sha256` | `9e3a...` | hex digest of the ZIP |
| `fetched_utc` | `2026-06-19T14:23:11Z` | ISO-8601 UTC retrieval timestamp |
| `tool` | `download_usdm.py@1.0.0` | which script + version produced the row |

## Notes / gotchas

- **USDM publication cadence**: maps are **dated** for Tuesday but **released**
  Thursday morning Eastern. If you ask for the most recent Tuesday and it's
  still Wednesday, the file will 404. Both scripts handle this by trimming the
  end date to the most recent Tuesday at least 2 days in the past.
- **Pre-2000 weeks do not exist**: USDM started 2000-01-04. The default
  `--start` is hard-bounded to that date.
- **Network**: NDMC tolerates the weekly cadence but please don't hammer
  it. Both scripts insert a 0.5 s pause between requests.
- **No re-projection / no clipping**: this package is a *bit-perfect*
  archive of NDMC's published ZIPs. Downstream processing
  (reproject to EPSG:5070, rasterize, etc.) is the consumer's job and lives
  outside this package.

## Provenance

This package was extracted from the existing USDM ingest used by the NDVI
drought-monitoring project
(`CONUS_HLS_drought_monitoring/08_validation_data_setup.R`,
`section_usdm_download()`). The URL pattern and weekly cadence are unchanged;
the package was reformulated in Python / wget for the NIDIS_AI team's
toolchain and extended back to USDM's 2000-01-04 origin.
