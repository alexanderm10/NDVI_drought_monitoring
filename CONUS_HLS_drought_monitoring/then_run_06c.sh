#!/bin/bash
# ==============================================================================
# then_run_06c.sh
#
# Waits for the active Phase 6 remaining-sequence run to terminate (either
# SEQUENCE_COMPLETE or SEQUENCE_FAILED marker), then — on success only — runs
# 06c_rebuild_change_derivatives_stats.R to refresh the 2018/2023 stats rows
# (which were left stale by the 2026-06-02 06b backfill; see 06c edit
# 2026-06-03 for the mtime-based stale-detection logic).
#
# Launched alongside the main sequence so the operator can step away.
#
# Usage:
#   nohup ./then_run_06c.sh <RUN_DIR> > /dev/null 2>&1 &
#   disown
# ==============================================================================

set -u

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <remaining_run_dir>" >&2
  exit 2
fi

RUN_DIR="$1"
DONE="$RUN_DIR/SEQUENCE_COMPLETE"
FAIL="$RUN_DIR/SEQUENCE_FAILED"
LOG="/mnt/malexander/datasets/ndvi_monitor/gam_models/change_derivatives_stats_rebuild_$(date +%Y%m%d_%H%M%S).log"
MARKER_OK="$RUN_DIR/06C_REBUILD_COMPLETE"
MARKER_FAIL="$RUN_DIR/06C_REBUILD_FAILED"
MARKER_SKIP="$RUN_DIR/06C_REBUILD_SKIPPED"

echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Waiting for $(basename $RUN_DIR) to finish..." >> "$LOG"

while [ ! -f "$DONE" ] && [ ! -f "$FAIL" ]; do
  sleep 60
done

if [ -f "$FAIL" ]; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Sequence FAILED — skipping 06c rebuild." >> "$LOG"
  touch "$MARKER_SKIP"
  exit 1
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] Sequence COMPLETE — launching 06c rebuild" >> "$LOG"
cd /home/malexander/r_projects/github/NDVI_drought_monitoring/CONUS_HLS_drought_monitoring || exit 1
Rscript 06c_rebuild_change_derivatives_stats.R >> "$LOG" 2>&1
RC=$?
echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] 06c rebuild finished, exit=$RC" >> "$LOG"

if [ $RC -eq 0 ]; then
  touch "$MARKER_OK"
else
  touch "$MARKER_FAIL"
fi
exit $RC
