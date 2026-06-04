#!/bin/bash
# ==============================================================================
# run_remaining_sequence.sh
#
# Resume the Phase 6 evening sequence from gridmet onward (skipping
# audit_backfill / 06c_rebuild / usdm_process which completed 2026-06-02).
# Sequence:
#   1. gridmet  — extract pr + pet (rewritten 2026-06-03 to fix OOM)
#   2. spei     — compute SPI/SPEI at 1/3/6 month per pixel
#   3. qc       — alignment + completeness checks
#
# Launch:
#   nohup ./run_remaining_sequence.sh > /dev/null 2>&1 &
#   disown
# ==============================================================================

set -u

PROJ=/home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring
DATA=/mnt/malexander/datasets/ndvi_monitor
RUN_TAG=$(date +%Y%m%d_%H%M%S)
LOG_DIR=$DATA/validation/remaining_run_$RUN_TAG
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

step_gridmet() {
  docker exec -w /workspace conus-hls-drought-monitor \
    Rscript 08_validation_data_setup.R --section=gridmet
}

step_spei() {
  docker exec -w /workspace conus-hls-drought-monitor \
    Rscript 08_validation_data_setup.R --section=spei
}

step_qc() {
  docker exec -w /workspace conus-hls-drought-monitor \
    Rscript 08_validation_data_setup.R --section=qc
}

main() {
  log "=== Phase 6 remaining sequence started ==="
  log "Run tag: $RUN_TAG"
  log "Log dir: $LOG_DIR"
  log "Steps: gridmet -> spei -> qc"
  log ""

  for step in gridmet spei qc; do
    if ! run_step "$step" "step_${step}"; then
      log ""
      log "XXX SEQUENCE ABORTED at step '$step' XXX"
      log "Inspect $LOG_DIR/${step}.log for the error."
      touch "$FAIL_MARKER"
      exit 1
    fi
  done

  log ""
  log "Final outputs in $DATA/validation/:"
  for f in midwest_extent.rds \
           pixel_to_ecoregion_l2.rds \
           ecoregions_midwest_l2.rds \
           usdm_4km_weekly_2013_2025.rds \
           gridmet_4km_daily_2013_2025.rds \
           spei_4km_monthly_2013_2025.rds \
           qc_report.rds; do
    if [ -f "$DATA/validation/$f" ]; then
      sz=$(ls -lh "$DATA/validation/$f" | awk '{print $5}')
      log "  OK $f ($sz)"
    else
      log "  MISSING $f"
    fi
  done

  log ""
  log "=== Phase 6 remaining sequence COMPLETE ==="
  touch "$DONE_MARKER"
}

main
