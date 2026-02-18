#!/bin/bash
# =============================================================================
# DOWNLOAD QUEUE - 2025 THEN BACKWARDS FROM 2024 TO 2022
# =============================================================================
# Runs 2025 first (with cloud_cover=100 to capture all scenes), then processes
# years in reverse order until meeting the bulk download (working forwards).
#
# Usage: Run inside Docker container via nohup
# =============================================================================

LOG_DIR="/data"
WORKSPACE="/workspace"

echo "=== DOWNLOAD QUEUE (cloud_cover=100, max_items=1000) ===" | tee "${LOG_DIR}/download_queue.log"
echo "Queue: 2025 -> 2024 -> 2023 -> 2022" | tee -a "${LOG_DIR}/download_queue.log"
echo "Started: $(date)" | tee -a "${LOG_DIR}/download_queue.log"

# Process years: 2025 first (re-run with full cloud cover), then backwards
for YEAR in 2025 2024 2023 2022; do
    echo "" | tee -a "${LOG_DIR}/download_queue.log"
    echo "=== STARTING YEAR ${YEAR} ===" | tee -a "${LOG_DIR}/download_queue.log"
    echo "Start time: $(date)" | tee -a "${LOG_DIR}/download_queue.log"

    cd "${WORKSPACE}"
    Rscript -e "source('01a_midwest_data_acquisition_parallel.R'); acquire_conus_data(start_year = ${YEAR}, end_year = ${YEAR}, cloud_cover_max = 100)" \
        > "${LOG_DIR}/download_${YEAR}_conus.log" 2>&1

    EXIT_CODE=$?
    echo "Year ${YEAR} finished at $(date) (exit code: ${EXIT_CODE})" | tee -a "${LOG_DIR}/download_queue.log"

    if [ $EXIT_CODE -ne 0 ]; then
        echo "WARNING: Year ${YEAR} exited with error. Continuing to next year..." | tee -a "${LOG_DIR}/download_queue.log"
    fi
done

echo "" | tee -a "${LOG_DIR}/download_queue.log"
echo "=== DOWNLOAD QUEUE COMPLETE ===" | tee -a "${LOG_DIR}/download_queue.log"
echo "Finished: $(date)" | tee -a "${LOG_DIR}/download_queue.log"
