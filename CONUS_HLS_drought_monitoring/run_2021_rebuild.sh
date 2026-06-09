#!/bin/bash
# ==============================================================================
# run_2021_rebuild.sh
#
# Recover derivatives_2021.rds after CIFS post-rename corruption (2026-06-08
# incident; same failure class as derivatives_2016.rds on 2026-05-27).
#
# PRE-REQUISITE: derivatives_2021.rds MUST already be renamed out of the way
# (e.g., to derivatives_2021.rds.corrupt-2026-06-08.bak). If the corrupt file
# still exists at the original path, 06's resume scan will crash on
# readRDS_retry of the LZMA-corrupt stream.
#
# Sequence:
#   1. rebuild_06          — Rscript 06_calculate_change_derivatives.R
#                            Resume mode skips the 9 healthy years (2016-2020,
#                            2022-2025) after ~50 min readRDS scan; recomputes
#                            year 2021. Wall: ~14-15 hr at 5 workers.
#   2. restore_stats_06c   — Rscript 06c_rebuild_change_derivatives_stats.R
#                            06 overwrites change_derivatives_stats.rds with a
#                            1-row file containing only 2021. 06c's mtime-based
#                            stale-detection rebuilds the other 12 rows from
#                            on-disk year files. ~3-5 min.
#
# Launch:
#   nohup ./run_2021_rebuild.sh > /dev/null 2>&1 &
#   disown
# ==============================================================================

set -u

PROJ=/home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring
DATA=/mnt/malexander/datasets/ndvi_monitor
RUN_TAG=$(date +%Y%m%d_%H%M%S)
LOG_DIR=$DATA/gam_models/rebuild_2021_$RUN_TAG
mkdir -p "$LOG_DIR"
MAIN_LOG="$LOG_DIR/sequence.log"
FAIL_MARKER="$LOG_DIR/SEQUENCE_FAILED"
DONE_MARKER="$LOG_DIR/SEQUENCE_COMPLETE"

CORRUPT_FILE="$DATA/gam_models/change_derivatives/derivatives_2021.rds"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $*" | tee -a "$MAIN_LOG"
}

run_step() {
  local name="$1"; shift
  local step_log="$LOG_DIR/${name}.log"
  log "=== START: $name (-> $(basename $step_log)) ==="
  local t0=$(date +%s)
  if "$@" > "$step_log" 2>&1; then
    local t1=$(date +%s)
    log "=== DONE: $name (exit 0, $((t1 - t0)) sec) ==="
    return 0
  else
    local rc=$?
    local t1=$(date +%s)
    log "=== FAIL: $name (exit $rc, $((t1 - t0)) sec) -- see $step_log ==="
    return $rc
  fi
}

step_rebuild_06() {
  docker exec -w /workspace conus-hls-drought-monitor \
    Rscript 06_calculate_change_derivatives.R
}

step_restore_stats_06c() {
  docker exec -w /workspace conus-hls-drought-monitor \
    Rscript 06c_rebuild_change_derivatives_stats.R
}

main() {
  log "=== derivatives_2021 rebuild sequence started ==="
  log "Run tag: $RUN_TAG"
  log "Log dir: $LOG_DIR"
  log "Steps:   rebuild_06 -> restore_stats_06c"
  log ""

  # ----- Pre-flight: refuse to launch if the corrupt file is still at the
  # ----- original path. 06's resume scan would crash on readRDS_retry.
  if [ -f "$CORRUPT_FILE" ]; then
    log "XXX PRE-FLIGHT FAIL XXX"
    log "  $CORRUPT_FILE still exists. Rename it out of the way before launch:"
    log "    mv $CORRUPT_FILE ${CORRUPT_FILE}.corrupt-$(date +%Y-%m-%d).bak"
    log "  06's resume scan will crash on the corrupt LZMA stream otherwise."
    touch "$FAIL_MARKER"
    exit 2
  fi
  log "Pre-flight OK: $CORRUPT_FILE absent (rename presumed done)."
  log ""

  for step in rebuild_06 restore_stats_06c; do
    if ! run_step "$step" "step_${step}"; then
      log ""
      log "XXX SEQUENCE ABORTED at step '$step' XXX"
      log "Inspect $LOG_DIR/${step}.log for the error."
      touch "$FAIL_MARKER"
      exit 1
    fi
  done

  log ""
  log "Final state:"
  if [ -f "$CORRUPT_FILE" ]; then
    sz=$(ls -lh "$CORRUPT_FILE" | awk '{print $5}')
    log "  OK derivatives_2021.rds ($sz)"
  else
    log "  MISSING derivatives_2021.rds — rebuild failed silently?"
  fi
  STATS_FILE="$DATA/gam_models/change_derivatives_stats.rds"
  if [ -f "$STATS_FILE" ]; then
    sz=$(ls -lh "$STATS_FILE" | awk '{print $5}')
    log "  OK change_derivatives_stats.rds ($sz)"
  fi

  log ""
  log "=== derivatives_2021 rebuild sequence COMPLETE ==="
  log "Next: verify output (see plan), then re-launch run_phase6_align_weekly.sh"
  touch "$DONE_MARKER"
}

main
