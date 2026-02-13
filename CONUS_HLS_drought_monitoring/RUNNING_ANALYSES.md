# Currently Running Analyses

**Updated**: 2026-02-12 11:00 CST

## Status: RUNNING (two parallel downloads inside Docker)

Both download processes are now running inside the Docker container (`conus-hls-drought-monitor`), where `terra` is available for NDVI processing.

### Download Process 1: Bulk Download (2019-2024) — Docker
- **Status**: RUNNING
- **Script**: `bulk_download_docker.sh` → `getHLS_bands.sh`
- **Current position**: 2019 L30 (Landsat), tile zone 12 (T12STB)
- **Log**: `bulk_downloads/logs/bulk_docker.log`
- **Per-year log**: `bulk_downloads/logs/download_2019_docker.log`
- **Tiles**: 1,209 Midwest MGRS tiles per year
- **Workers**: 10 parallel wget
- **Stability**: No crashes since Docker migration

### Download Process 2: 2025 R-based Download — Docker
- **Status**: RUNNING (restarted Feb 12 from March 2025)
- **Script**: `00_download_hls_data_parallel.R` with `start_year=2025`
- **Current position**: March 2025
- **Log**: `/mnt/malexander/datasets/ndvi_monitor/download_2025_restart.log` (also `/data/download_2025_restart.log` in Docker)
- **Jan-Feb 2025**: Skipped (already downloaded)
- **Workers**: 4 parallel R workers, 40 CONUS tiles
- **Stability**: Fresh restart, running clean

### Previous Download (Stopped)
- **Old host bulk download**: Killed Feb 12 (was running on host without `terra`)
  - 2019: Raw download complete, NDVI processing failed (no `terra`)
  - 2020: Raw download complete, NDVI processing failed (no `terra`)
  - 2021: L30 complete, S30 ~42% through — will resume in Docker
  - Now re-running inside Docker where NDVI processing will succeed
- **Old 2025 R download**: Crashed Feb 9 with zombie R workers, restarted Feb 12

---

## Monitoring

### Custom Agent (New)
A `download-monitor` agent was created at `.claude/agents/download-monitor.md`. In Claude Code, ask "check on my downloads" to trigger it.

### Manual Monitoring
```bash
# Bulk download (2019-2024)
tail -f CONUS_HLS_drought_monitoring/bulk_downloads/logs/bulk_docker.log

# 2025 download
tail -f /mnt/malexander/datasets/ndvi_monitor/download_2025_restart.log

# Docker container health
docker exec conus-hls-drought-monitor ps aux | grep -E "[R]script|[w]get"

# Check for zombies
docker exec conus-hls-drought-monitor ps aux | grep " Z "

# File counts
for yr in 2019 2020 2021 2022 2023 2024 2025; do
  echo -n "$yr: "
  ls /mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily/$yr/ 2>/dev/null | wc -l
done
```

---

## Session Summary (Feb 12, 2026)

### Work Completed
1. **Killed host processes**: Bulk download process group + 3 zombie `curl` processes
2. **Restarted Docker**: Cleared 4 zombie R workers from crashed 2025 download
3. **Moved bulk download into Docker**: Created `bulk_download_docker.sh` and `process_bulk_ndvi_docker.R` with Docker-internal paths (`/data/` instead of `/mnt/malexander/...`). `terra` now available for NDVI processing.
4. **Copied .netrc**: Earthdata credentials placed at `/.netrc` in container (matching `$HOME=/`)
5. **Restarted 2025 download**: `acquire_conus_data(start_year=2025)` — skipped Jan-Feb, now on March 2025
6. **Created download-monitor agent**: `.claude/agents/download-monitor.md` — custom Claude Code agent for automated status checks

### Files Created
- `.claude/agents/download-monitor.md`
- `bulk_downloads/bulk_download_docker.sh`
- `bulk_downloads/scripts/process_bulk_ndvi_docker.R`

### Commits
- `d3993a5` — `[ops][docker] Move bulk download into Docker and add download-monitor agent`

---

## Key Notes for Next Session

- **`.netrc` is ephemeral**: It was copied into the running container. If the container is rebuilt (`docker compose build`), you need to re-copy it: `docker cp ~/.netrc conus-hls-drought-monitor:/.netrc`
- **Bulk download is resumable**: `getHLS_bands.sh` skips existing files, so restarts are safe
- **2025 download is resumable**: R script checks for existing NDVI files before downloading
- **NDVI processing for 2019/2020**: Will happen automatically after each year's download completes inside Docker

---

## Pipeline Status

| Step | Script | Status |
|------|--------|--------|
| Download (2013-2018) | `redownload_all_years_cloud100.R` | COMPLETE |
| Download (2019-2024) | `bulk_download_docker.sh` | RUNNING - 2019 in Docker |
| Download (2025) | `00_download_hls_data_parallel.R` | RUNNING - March 2025 |
| Aggregation | `01_aggregate_to_4km_parallel.R` | 2013-2016 COMPLETE, 2017+ pending |
| Norms | `02_doy_looped_norms.R` | Pending aggregation |
| Year Predictions | `03_doy_looped_year_predictions.R` | Updated to k=50, ready |

---

## Aggregation Status (2013-2016)

| Year | Observations | Pixels | Obs/Pixel | Days | Sensors | File Size |
|------|-------------|--------|-----------|------|---------|-----------|
| 2013 | 1,270,784 | 142,099 | 8.9 | 222 | L30 only | 6.5 MB |
| 2014 | 1,583,381 | 141,769 | 11.2 | 320 | L30 only | 8.3 MB |
| 2015 | 1,616,606 | 142,466 | 11.3 | 305 | L30 97%, S30 3% | 8.5 MB |
| 2016 | 2,139,261 | 142,111 | 15.1 | 291 | L30 57%, S30 43% | 12 MB |

## Key Configuration

- **Spatial basis**: k=50 (validated)
- **Cloud cover filter**: 100% at scene level (Fmask handles pixel-level QA)
- **Aggregation**: 4km resolution, median, min 5 pixels per cell
- **Study area**: Midwest bbox (-104.5, 37.0, -82.0, 47.5)
