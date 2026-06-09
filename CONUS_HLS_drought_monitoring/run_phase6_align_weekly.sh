#!/bin/bash
# ==============================================================================
# run_phase6_align_weekly.sh
#
# Phase 6 first concrete step: build the master pixel-week join table
# (NDVI anomaly + per-window derivative summaries + USDM + SPEI weekly +
# ecoregion attributes) for the chosen scope.
#
# Sequence:
#   1. align_weekly --scope=$SCOPE  — sole step (~5 hr for 10y, ~6.3 hr for 13y)
#
# Per-year cost is remarkably uniform: ~24 min/year (range 23.7-24.6 min) in the
# 2026-06-09 10y run. Add ~1 hr for rbindlist + dedup + USDM/SPEI joins + save.
#
# Output marker:
#   $LOG_DIR/SEQUENCE_COMPLETE   — step succeeded
#   $LOG_DIR/SEQUENCE_FAILED     — step failed (see align_weekly.log)
#
# Launch (background, survives logout):
#   nohup ./run_phase6_align_weekly.sh > /dev/null 2>&1 &
#   disown
#
# Override scope via env:
#   SCOPE=13y nohup ./run_phase6_align_weekly.sh > /dev/null 2>&1 & disown
# ==============================================================================

set -u

SCOPE=${SCOPE:-10y}
case "$SCOPE" in
  10y|13y) ;;
  *) echo "SCOPE must be '10y' or '13y' (got '$SCOPE')"; exit 2 ;;
esac

PROJ=/home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring
DATA=/mnt/malexander/datasets/ndvi_monitor
RUN_TAG=$(date +%Y%m%d_%H%M%S)
LOG_DIR=$DATA/validation/phase6_align_${SCOPE}_$RUN_TAG
mkdir -p "$LOG_DIR"
MAIN_LOG="$LOG_DIR/sequence.log"
FAIL_MARKER="$LOG_DIR/SEQUENCE_FAILED"
DONE_MARKER="$LOG_DIR/SEQUENCE_COMPLETE"

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

step_align_weekly() {
  docker exec -w /workspace conus-hls-drought-monitor \
    Rscript 09_validate_drought_signal.R --section=align_weekly --scope=$SCOPE
}

main() {
  log "=== Phase 6 align_weekly sequence started ==="
  log "Run tag: $RUN_TAG"
  log "Scope:   $SCOPE"
  log "Log dir: $LOG_DIR"
  log "Expected duration: ~5 hr (10y) / ~6.3 hr (13y)"
  log ""

  if ! run_step "align_weekly" step_align_weekly; then
    log ""
    log "XXX SEQUENCE ABORTED at step 'align_weekly' XXX"
    log "Inspect $LOG_DIR/align_weekly.log for the error."
    touch "$FAIL_MARKER"
    exit 1
  fi

  log ""
  out_file="ndvi_drought_join_weekly_${SCOPE}.rds"
  log "Final output in $DATA/validation/:"
  if [ -f "$DATA/validation/$out_file" ]; then
    sz=$(ls -lh "$DATA/validation/$out_file" | awk '{print $5}')
    log "  OK $out_file ($sz)"
  else
    log "  MISSING $out_file"
  fi

  log ""
  log "=== Phase 6 align_weekly sequence COMPLETE ==="
  touch "$DONE_MARKER"
}

main
