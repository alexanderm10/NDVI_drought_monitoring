#!/bin/bash
# ==============================================================================
# OPERATIONAL DROUGHT MONITORING - MASTER UPDATE SCRIPT
# ==============================================================================
# Purpose: Automated weekly/daily operational monitoring workflow
# Usage: ./run_operational_update.sh [region] [mode]
# Example: ./run_operational_update.sh midwest full
# Example: ./run_operational_update.sh conus quick
# ==============================================================================

set -e  # Exit on error

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Default parameters
REGION="${1:-midwest}"
MODE="${2:-full}"  # full, quick, data-only, conditions-only
LOG_DIR="$(dirname "$0")/../logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/${REGION}_update_${TIMESTAMP}.log"

# Ensure log directory exists
mkdir -p "${LOG_DIR}"

# ==============================================================================
# LOGGING SETUP
# ==============================================================================

# Redirect all output to log file and console
exec 1> >(tee -a "${LOG_FILE}")
exec 2>&1

echo "================================================================================"
echo "  OPERATIONAL DROUGHT MONITORING UPDATE"
echo "================================================================================"
echo "Started: $(date)"
echo "Region: ${REGION}"
echo "Mode: ${MODE}"
echo "Log: ${LOG_FILE}"
echo ""

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

log_step() {
    echo ""
    echo "--------------------------------------------------------------------------------"
    echo "$1"
    echo "--------------------------------------------------------------------------------"
    echo "Time: $(date)"
    echo ""
}

run_r_script() {
    local script=$1
    local description=$2
    local required_vars=$3

    log_step "${description}"

    # Build R command with environment variables
    R_CMD="Rscript"
    if [ -n "$required_vars" ]; then
        R_CMD="${required_vars} ${R_CMD}"
    fi

    ${R_CMD} "${script}" || {
        echo "❌ FAILED: ${description}"
        echo "Check log: ${LOG_FILE}"
        exit 1
    }

    echo "✓ COMPLETED: ${description}"
}

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

log_step "Pre-flight Checks"

# Check if Docker container is needed
if [ -f "../../docker-compose.yml" ]; then
    echo "Checking Docker container status..."
    if ! docker ps | grep -q "conus-hls-drought-monitor"; then
        echo "⚠ Docker container not running"
        echo "Starting container..."
        docker-compose -f ../../docker-compose.yml up -d
        sleep 5
    fi
    echo "✓ Docker container running"
fi

# Check R installation
if ! command -v Rscript &> /dev/null; then
    echo "❌ Rscript not found. Please install R."
    exit 1
fi
echo "✓ R installed: $(Rscript --version 2>&1 | head -1)"

# Check configuration file
CONFIG_FILE="../config/${REGION}_operational.yaml"
if [ ! -f "${CONFIG_FILE}" ]; then
    echo "⚠ Configuration not found: ${CONFIG_FILE}"
    echo "Initializing configuration..."
    Rscript -e "source('../config/region_configs.R'); init_monitoring('${REGION}', 'operational')"
fi
echo "✓ Configuration: ${CONFIG_FILE}"

echo ""

# ==============================================================================
# WORKFLOW EXECUTION
# ==============================================================================

START_TIME=$(date +%s)

# Step 1: Data Update
if [ "${MODE}" = "full" ] || [ "${MODE}" = "data-only" ]; then
    run_r_script \
        "01_update_recent_data.R" \
        "STEP 1: Update Recent Data" \
        "region_config=${REGION}_operational run_update=TRUE"
fi

# Step 2: Baseline Update (if needed)
if [ "${MODE}" = "full" ]; then
    run_r_script \
        "02_update_rolling_baseline.R" \
        "STEP 2: Check/Update Baseline" \
        "region_config=${REGION}_operational run_baseline_update_script=TRUE"
fi

# Step 3: Current Conditions
if [ "${MODE}" = "full" ] || [ "${MODE}" = "quick" ] || [ "${MODE}" = "conditions-only" ]; then
    # Decide whether to include derivatives
    INCLUDE_DERIVS="TRUE"
    if [ "${MODE}" = "quick" ]; then
        INCLUDE_DERIVS="FALSE"
    fi

    run_r_script \
        "03_current_conditions.R" \
        "STEP 3: Calculate Current Conditions" \
        "region_config=${REGION}_operational include_derivatives=${INCLUDE_DERIVS} run_current_conditions_script=TRUE"
fi

# ==============================================================================
# POST-PROCESSING
# ==============================================================================

log_step "Post-Processing"

# Calculate elapsed time
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
HOURS=$((ELAPSED / 3600))
MINUTES=$(((ELAPSED % 3600) / 60))
SECONDS=$((ELAPSED % 60))

echo "Total runtime: ${HOURS}h ${MINUTES}m ${SECONDS}s"

# Check for latest products
PRODUCTS_DIR="$(dirname "$0")/../../data/web_products/current_conditions"
if [ -d "${PRODUCTS_DIR}" ]; then
    echo ""
    echo "Latest Products:"
    if [ -L "${PRODUCTS_DIR}/latest_summary.json" ]; then
        echo "  Summary: ${PRODUCTS_DIR}/latest_summary.json"
        echo ""
        echo "Current Conditions:"
        cat "${PRODUCTS_DIR}/latest_summary.json" | grep -E '"date"|"mean_anomaly"|"pct_sig_below"' || true
    fi
fi

# Archive old logs (keep last 30 days)
log_step "Cleanup"
find "${LOG_DIR}" -name "*_update_*.log" -mtime +30 -delete 2>/dev/null || true
echo "✓ Old logs archived"

# ==============================================================================
# COMPLETION
# ==============================================================================

echo ""
echo "================================================================================"
echo "  UPDATE COMPLETE"
echo "================================================================================"
echo "Region: ${REGION}"
echo "Mode: ${MODE}"
echo "Status: SUCCESS"
echo "Completed: $(date)"
echo "Log: ${LOG_FILE}"
echo "================================================================================"
echo ""

exit 0
