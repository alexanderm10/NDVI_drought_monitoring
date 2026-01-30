#!/bin/bash
# ==============================================================================
# MONTHLY UPDATE WRAPPER SCRIPT
# ==============================================================================
# Purpose: Wrapper script for automated monthly updates via cron
#
# Usage:
#   ./monthly_update.sh              # Process previous month
#   ./monthly_update.sh 2026 02      # Process specific month
#
# Cron example (run first week of month at 2 AM):
#   0 2 5 * * /path/to/monthly_update.sh >> /path/to/cron.log 2>&1
# ==============================================================================

set -e  # Exit on error

# Change to script directory
cd "$(dirname "$0")"

# Activate Docker container if needed
CONTAINER_NAME="conus-hls-drought-monitor"

# Check if container is running
if ! docker ps | grep -q "$CONTAINER_NAME"; then
    echo "ERROR: Docker container '$CONTAINER_NAME' is not running."
    echo "Start it with: docker compose up -d"
    exit 1
fi

# Run monthly update inside container
if [ $# -eq 0 ]; then
    # No arguments - process previous month
    echo "Running monthly update for previous month..."
    docker exec "$CONTAINER_NAME" Rscript /workspace/00_monthly_update.R current
elif [ $# -eq 2 ]; then
    # Specific year and month provided
    YEAR=$1
    MONTH=$2
    echo "Running monthly update for $YEAR-$MONTH..."
    docker exec "$CONTAINER_NAME" Rscript /workspace/00_monthly_update.R "$YEAR" "$MONTH"
else
    echo "Usage: $0 [YYYY MM]"
    echo "   or: $0              (process previous month)"
    exit 1
fi

# Check exit status
if [ $? -eq 0 ]; then
    echo "✓ Monthly update completed successfully"
    exit 0
else
    echo "✗ Monthly update failed"
    exit 1
fi
