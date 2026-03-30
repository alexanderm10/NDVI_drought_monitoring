#!/bin/bash
# safe_shutdown.sh — Gracefully stop the bulk download pipeline
# Usage: ./safe_shutdown.sh [--force]
#
# Steps:
#   1. Signal orchestrator scripts to stop (no new chunks/downloads start)
#   2. Wait for in-flight R workers to finish current chunk
#   3. Validate no truncated NDVI files from the last chunk
#   4. Record final pipeline state
#   5. Stop the Docker container
#
# The --force flag skips waiting for R workers (use only if time-critical)

set -euo pipefail

CONTAINER="conus-hls-drought-monitor"
NDVI_DIR="/mnt/malexander/datasets/ndvi_monitor/processed_ndvi/daily"
LOG_DIR="$(cd "$(dirname "$0")" && pwd)/bulk_downloads/logs"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FORCE=false
MAX_WAIT=7200  # 2 hours max wait for R workers

if [[ "${1:-}" == "--force" ]]; then
    FORCE=true
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

# --- Preflight checks ---
log "=== Safe Shutdown Starting ==="

if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    die "Container '${CONTAINER}' is not running"
fi

# --- Step 1: Signal orchestrators to stop ---
log "Step 1: Signaling orchestrators to stop..."

# Find PIDs of the orchestrator scripts inside the container
BULK_PID=$(docker exec "$CONTAINER" pgrep -f "bulk_download_docker.sh" 2>/dev/null | head -1 || true)
PREFETCH_PID=$(docker exec "$CONTAINER" pgrep -f "prefetch_downloads.sh" 2>/dev/null | head -1 || true)

if [[ -n "$BULK_PID" ]]; then
    log "  Sending SIGTERM to bulk_download_docker.sh (PID $BULK_PID)"
    docker exec "$CONTAINER" kill -TERM "$BULK_PID" 2>/dev/null || true
else
    log "  bulk_download_docker.sh not running (already stopped)"
fi

if [[ -n "$PREFETCH_PID" ]]; then
    log "  Sending SIGTERM to prefetch_downloads.sh (PID $PREFETCH_PID)"
    docker exec "$CONTAINER" kill -TERM "$PREFETCH_PID" 2>/dev/null || true
else
    log "  prefetch_downloads.sh not running (already stopped)"
fi

# Kill wget workers (prefetch) — these are safe to interrupt
log "  Stopping wget prefetch workers..."
docker exec "$CONTAINER" pkill -TERM wget 2>/dev/null || true

# --- Step 2: Wait for R workers to finish current chunk ---
log "Step 2: Waiting for R workers to finish current chunk..."

if [[ "$FORCE" == true ]]; then
    log "  --force: Skipping wait, killing R workers"
    docker exec "$CONTAINER" pkill -TERM Rscript 2>/dev/null || true
    sleep 5
    docker exec "$CONTAINER" pkill -KILL Rscript 2>/dev/null || true
else
    elapsed=0
    interval=30
    while true; do
        r_count=$(docker exec "$CONTAINER" pgrep -c Rscript 2>/dev/null || echo "0")
        if [[ "$r_count" -eq 0 ]]; then
            log "  All R workers have exited cleanly"
            break
        fi

        if [[ $elapsed -ge $MAX_WAIT ]]; then
            log "  WARNING: R workers still running after ${MAX_WAIT}s"
            log "  Sending SIGTERM to remaining R workers..."
            docker exec "$CONTAINER" pkill -TERM Rscript 2>/dev/null || true
            sleep 10
            break
        fi

        log "  $r_count R worker(s) still running... (${elapsed}s / ${MAX_WAIT}s max)"
        sleep "$interval"
        elapsed=$((elapsed + interval))
    done
fi

# --- Step 3: Validate no truncated NDVI files ---
log "Step 3: Checking for truncated NDVI files..."

# NDVI TIF files should be at least 50KB; anything smaller is likely truncated
truncated=$(find "$NDVI_DIR/2024/" "$NDVI_DIR/2025/" -name "*_NDVI.tif" -size -50k 2>/dev/null || true)
if [[ -n "$truncated" ]]; then
    count=$(echo "$truncated" | wc -l)
    log "  Found $count truncated NDVI file(s) — removing so they get reprocessed on restart"
    echo "$truncated" | while read -r f; do
        log "    Removing: $(basename "$f")"
        rm -f "$f"
    done
else
    log "  No truncated files found"
fi

# --- Step 4: Record final pipeline state ---
log "Step 4: Recording final pipeline state..."

STATE_FILE="$SCRIPT_DIR/shutdown_state_$(date '+%Y%m%d_%H%M%S').txt"
{
    echo "=== Shutdown State ==="
    echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    echo ""

    echo "--- NDVI File Counts ---"
    for yr in 2019 2020 2021 2022 2023 2024 2025; do
        count=$(find "$NDVI_DIR/$yr/" -name "*_NDVI.tif" 2>/dev/null | wc -l)
        echo "  $yr: $count files"
    done

    echo ""
    echo "--- Last Processing Log Entries ---"
    if [[ -f "$LOG_DIR/process_2024_docker.log" ]]; then
        echo "  (from process_2024_docker.log)"
        tail -30 "$LOG_DIR/process_2024_docker.log" 2>/dev/null | sed 's/^/  /'
    fi

    echo ""
    echo "--- Last Bulk Log Entries ---"
    if [[ -f "$LOG_DIR/bulk_docker.log" ]]; then
        echo "  (from bulk_docker.log)"
        tail -20 "$LOG_DIR/bulk_docker.log" 2>/dev/null | sed 's/^/  /'
    fi

    echo ""
    echo "--- Zombie Count at Shutdown ---"
    zombies=$(docker exec "$CONTAINER" ps aux 2>/dev/null | grep -c defunct || echo "unknown")
    echo "  $zombies zombies"
} > "$STATE_FILE"

log "  State saved to: $STATE_FILE"

# --- Step 5: Stop the container ---
log "Step 5: Stopping Docker container..."
docker stop -t 15 "$CONTAINER"

if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    die "Container failed to stop!"
else
    log "  Container stopped successfully"
fi

log ""
log "=== Shutdown Complete ==="
log "State file: $STATE_FILE"
log ""
log "To restart later:"
log "  docker start $CONTAINER"
log "  docker exec -d $CONTAINER bash -c 'cd /workspace/bulk_downloads && nohup ./bulk_download_docker.sh >> logs/bulk_docker.log 2>&1 &'"
log "  docker exec -d $CONTAINER bash -c 'cd /workspace/bulk_downloads && nohup ./prefetch_downloads.sh >> logs/prefetch.log 2>&1 &'"
