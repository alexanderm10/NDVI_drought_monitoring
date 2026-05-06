#!/bin/bash
# Polls for ndvi_4km_2025.rds, then launches 01b combine inside Docker.
# Runs detached; safe to leave going for hours. Logs to watch_then_combine.log.
set -euo pipefail

TARGET="/mnt/malexander/datasets/ndvi_monitor/gam_models/aggregated_years/ndvi_4km_2025.rds"
# COMBINE_LOG_CONTAINER is the path used for the redirect inside docker exec
# (container only sees /data, not /mnt/malexander). Host equivalent for tailing
# is COMBINE_LOG_HOST. Using the host path inside docker exec was the May 5 bug
# that caused 01b to silently fail to launch.
COMBINE_LOG_CONTAINER="/data/gam_models/combine_2013_2025.log"
COMBINE_LOG_HOST="/mnt/malexander/datasets/ndvi_monitor/gam_models/combine_2013_2025.log"
WATCH_LOG="/home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring/watch_then_combine.log"
CONTAINER="conus-hls-drought-monitor"

log() { echo "[$(date '+%F %T')] $*" >> "$WATCH_LOG"; }

log "Watcher started; waiting for $TARGET"

# Phase 1: wait for file to exist
while [ ! -f "$TARGET" ]; do
  sleep 60
done
log "File appeared"

# Phase 2: wait for size to stabilize (60s unchanged) - signals saveRDS is done
prev_size=-1
stable_count=0
while [ "$stable_count" -lt 6 ]; do  # 6 * 10s = 60s stable
  cur_size=$(stat -c '%s' "$TARGET" 2>/dev/null || echo 0)
  if [ "$cur_size" = "$prev_size" ] && [ "$cur_size" -gt 0 ]; then
    stable_count=$((stable_count + 1))
  else
    stable_count=0
  fi
  prev_size=$cur_size
  sleep 10
done
log "File size stable at $cur_size bytes; aggregation appears complete"

# Phase 3: launch 01b combine inside the container. Redirect target is the
# CONTAINER path (/data/...) — host paths fail at redirect time (no such dir
# inside container) and the Rscript silently never runs.
log "Launching 01b_combine_year_files.R inside $CONTAINER"
docker exec -d "$CONTAINER" bash -c \
  "cd /workspace && Rscript 01b_combine_year_files.R 2013 2025 > $COMBINE_LOG_CONTAINER 2>&1"
log "Launched 01b (detached). Tail $COMBINE_LOG_HOST to follow."
