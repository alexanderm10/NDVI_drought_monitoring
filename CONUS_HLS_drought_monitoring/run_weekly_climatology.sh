#!/bin/bash
# ==============================================================================
# run_weekly_climatology.sh
#
# Extracts GridMET 1984-2025 weekly (pr + pet) and computes SPI/SPEI at
# 4/13/26 week windows for analysis years 2013-2025 using the full 42-year
# climatology for distribution fits.
#
# Sequence (sequential, each gated on prior success):
#   1. gridmet_weekly  — pr + pet ISO-week aggregation 1984-2025 (~2-3 hr)
#   2. spei_weekly     — SPI/SPEI 4w/13w/26w, parallel 4 workers (~10-14 hr)
#   3. qc              — alignment + completeness across all validation files
#
# Output markers:
#   $LOG_DIR/SEQUENCE_COMPLETE   — all 3 steps succeeded
#   $LOG_DIR/SEQUENCE_FAILED     — first failing step (see per-step .log)
#
# Launch (background, survives logout):
#   nohup ./run_weekly_climatology.sh > /dev/null 2>&1 &
#   disown
# ==============================================================================

set -u

PROJ=/home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring
DATA=/mnt/malexander/datasets/ndvi_monitor
RUN_TAG=$(date +%Y%m%d_%H%M%S)
LOG_DIR=$DATA/validation/weekly_run_$RUN_TAG
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

step_gridmet_weekly() {
  docker exec -w /workspace conus-hls-drought-monitor \
    Rscript 08_validation_data_setup.R --section=gridmet_weekly
}

step_spei_weekly() {
  docker exec -w /workspace conus-hls-drought-monitor \
    Rscript 08_validation_data_setup.R --section=spei_weekly
}

step_qc() {
  docker exec -w /workspace conus-hls-drought-monitor \
    Rscript 08_validation_data_setup.R --section=qc
}

main() {
  log "=== Weekly climatology sequence started ==="
  log "Run tag: $RUN_TAG"
  log "Log dir: $LOG_DIR"
  log "Steps: gridmet_weekly -> spei_weekly -> qc"
  log "Expected duration: ~12-17 hr total"
  log ""

  for step in gridmet_weekly spei_weekly qc; do
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
  for f in gridmet_4km_weekly_1984_2025.rds \
           spei_4km_weekly_2013_2025.rds \
           qc_report.rds; do
    if [ -f "$DATA/validation/$f" ]; then
      sz=$(ls -lh "$DATA/validation/$f" | awk '{print $5}')
      log "  OK $f ($sz)"
    else
      log "  MISSING $f"
    fi
  done

  log ""
  log "=== Weekly climatology sequence COMPLETE ==="
  touch "$DONE_MARKER"
}

main
