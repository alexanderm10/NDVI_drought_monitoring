#!/bin/bash
# ==============================================================================
# run_evening_sequence.sh
#
# Unattended overnight sequence: wait for the 06b backfill to finish, then run:
#   1. audit_backfill   — confirm 2018 + 2023 derivative outputs are intact
#   2. 06c_rebuild      — refresh change_derivatives_stats.rds for the 2 years
#   3. usdm_process     — clip + rasterize 678 weekly USDM polygons onto our grid
#   4. gridmet          — extract daily pr + pet at 129,310 pixel centroids
#   5. spei             — compute SPI/SPEI at 1/3/6 month accumulation
#   6. qc               — alignment + completeness checks across outputs
#
# All steps log to a timestamped subdir under validation/. Markers:
#   SEQUENCE_COMPLETE — all steps OK (check this in the morning)
#   SEQUENCE_FAILED   — at least one step failed; check sequence.log + step log
#
# Launch:
#   nohup ./run_evening_sequence.sh > /dev/null 2>&1 &
#   disown
#
# Check in the morning:
#   ls -la /mnt/malexander/datasets/ndvi_monitor/validation/evening_run_*/
# ==============================================================================

set -u   # treat unset variables as error (but allow pipefail-controlled failures)

PROJ=/home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring
DATA=/mnt/malexander/datasets/ndvi_monitor
RUN_TAG=$(date +%Y%m%d_%H%M%S)
LOG_DIR=$DATA/validation/evening_run_$RUN_TAG
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
  log "=== START: $name (→ $(basename $step_log)) ==="
  local t0=$(date +%s)
  if "$@" > "$step_log" 2>&1; then
    local t1=$(date +%s)
    log "=== DONE: $name (exit 0, $((t1 - t0)) sec) ==="
    return 0
  else
    local rc=$?
    local t1=$(date +%s)
    log "=== FAIL: $name (exit $rc, $((t1 - t0)) sec) — see $step_log ==="
    return $rc
  fi
}

# -----------------------------------------------------------------------------
# Step 0: wait for backfill PID to exit
# -----------------------------------------------------------------------------
step_wait_backfill() {
  log "Waiting for 06b backfill (any PID matching '06b_backfill_change_derivatives')..."
  local n=0
  while pgrep -f "06b_backfill_change_derivatives" > /dev/null 2>&1; do
    sleep 60
    n=$((n + 1))
    if [ $((n % 10)) -eq 0 ]; then
      log "  still waiting (~$((n)) min elapsed since wait began)..."
    fi
  done
  log "Backfill process exited."
}

# -----------------------------------------------------------------------------
# Step 1: audit backfill outputs
# -----------------------------------------------------------------------------
step_audit_backfill() {
  cd "$PROJ" || return 1

  # 1a. Year-summary RDS row count + size check
  Rscript -e '
  for (yr in c(2018, 2023)) {
    f <- file.path("/mnt/malexander/datasets/ndvi_monitor/gam_models/change_derivatives",
                   sprintf("derivatives_%d.rds", yr))
    stopifnot(file.exists(f))
    sz_gb <- round(file.size(f) / 1e9, 2)
    cat(sprintf("  %d: %s (%.2f GB)\n", yr, basename(f), sz_gb))
    if (sz_gb < 10) stop(sprintf("FAILED: %d size %.2f GB < 10 GB", yr, sz_gb))
    d <- readRDS(f)
    cat(sprintf("    rows: %s (expected: 188,792,600)\n",
                format(nrow(d), big.mark=",")))
    if (nrow(d) != 188792600L) stop(sprintf("FAILED: %d row count %d != 188,792,600", yr, nrow(d)))
  }
  cat("Year-summary audit: OK\n")
  ' || return 2

  # 1b. Per-DOY × window file inventory check
  for yr in 2018 2023; do
    DRV=/mnt/malexander/datasets/ndvi_monitor/gam_models/change_derivatives_posteriors/$yr
    n_files=$(ls $DRV 2>/dev/null | wc -l)
    if [ "$n_files" != "1460" ]; then
      echo "FAILED: $yr has $n_files window files (expected 1460)"
      return 3
    fi
    # Smallest file should be >= 50 MB (resume guard)
    smallest=$(find $DRV -name "*.rds" -printf '%s\n' | sort -n | head -1)
    if [ "$smallest" -lt 50000000 ]; then
      echo "FAILED: $yr smallest window file = $smallest bytes (< 50 MB)"
      return 4
    fi
    echo "  $yr: $n_files window files OK (smallest $smallest bytes)"
  done

  echo "Audit complete."
}

# -----------------------------------------------------------------------------
# Step 2: 06c — refresh change_derivatives_stats.rds for the 2 updated years
# -----------------------------------------------------------------------------
step_06c_rebuild() {
  cd "$PROJ" || return 1
  Rscript 06c_rebuild_change_derivatives_stats.R
}

# -----------------------------------------------------------------------------
# Steps 3-6: Phase 1 validation sections (in container, /gdo mount needed)
# -----------------------------------------------------------------------------
step_usdm_process() {
  docker exec -w /workspace conus-hls-drought-monitor \
    Rscript 08_validation_data_setup.R --section=usdm_process
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

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  log "=== Phase 6 evening sequence started ==="
  log "Run tag: $RUN_TAG"
  log "Log dir: $LOG_DIR"
  log "Steps: wait_backfill → audit → 06c → usdm_process → gridmet → spei → qc"
  log ""

  step_wait_backfill

  for step in audit_backfill 06c_rebuild usdm_process gridmet spei qc; do
    if ! run_step "$step" "step_${step}"; then
      log ""
      log "✗✗✗ SEQUENCE ABORTED at step '$step' ✗✗✗"
      log "Inspect $LOG_DIR/${step}.log for the error."
      touch "$FAIL_MARKER"
      exit 1
    fi
  done

  # Output summary
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
      log "  ✓ $f ($sz)"
    else
      log "  ⨯ $f MISSING"
    fi
  done

  log ""
  log "=== Phase 6 evening sequence COMPLETE ==="
  touch "$DONE_MARKER"
}

main
