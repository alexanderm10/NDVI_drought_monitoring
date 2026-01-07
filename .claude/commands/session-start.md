---
description: Load project context and prepare for a new NDVI analysis session
---

# Session Start - Load NDVI Monitoring Context

Load project context and prepare for a new analysis session.

## Step 1: Read Project Configuration

Read key project documentation:
- **WORKFLOW.md**: Core pipeline workflow and script dependencies
- **GAM_METHODOLOGY.md**: Statistical methods and model specifications
- **DOCKER_SETUP.md**: Container environment setup
- **CLAUDE.md**: Project-specific instructions for code modifications

## Step 2: Check Current Pipeline Phase

Identify where we are in the workflow:
- Phase 1: Data Acquisition (Scripts 00-01) - Status?
- Phase 2: GAM Modeling (Scripts 02-03) - What's complete?
- Phase 3: Anomaly Analysis (Script 04) - Done?
- Phase 4: Visualization (Script 05) - Generated?
- Phase 5: Derivatives (Script 06) - Running?
- Phase 6: Additional Analysis (Script 07+) - Started?

## Step 3: Check Running Processes

```bash
# Check for running R scripts in Docker
docker exec conus-hls-drought-monitor ps aux | grep "[R]script"

# Check log files for recent activity
ls -lt CONUS_HLS_drought_monitoring/*.log 2>/dev/null | head -10
ls -lt CONUS_HLS_drought_monitoring/logs/*.log 2>/dev/null | head -10

# Check Docker container status
docker ps | grep conus-hls-drought-monitor
```

## Step 4: Review Git Status

```bash
git status                    # Uncommitted changes
git log --oneline -10         # Recent commits
git branch -v                 # Current branch
```

## Step 5: Check Recent Analysis Outputs

```bash
# Check most recent model outputs
ls -lth /mnt/malexander/datasets/ndvi_monitor/gam_models/ | head -15

# Check baseline posteriors status
ls /mnt/malexander/datasets/ndvi_monitor/gam_models/baseline_posteriors/ | wc -l

# Check year predictions status
ls /mnt/malexander/datasets/ndvi_monitor/gam_models/year_predictions_posteriors/

# Check derivative outputs
ls -lh /mnt/malexander/datasets/ndvi_monitor/gam_models/change_derivatives/

# Check most recent figures
ls -lt /mnt/malexander/datasets/ndvi_monitor/figures/ | head -10
```

## Step 6: Summarize and Ready

Provide a brief summary:

1. **Current Phase**: Where are we in the 6-phase workflow?
2. **Running Analyses**: Which scripts are currently executing (if any)?
3. **Recent Work**: Last commit message or recent script completion
4. **Data Status**: Latest model outputs available (years, DOYs)
5. **Pending**: Next analysis step based on WORKFLOW.md
6. **Issues**: Any failed runs, memory errors, or blockers?
7. **Git State**: Uncommitted changes?

Then ask: **"What would you like to work on today?"**

---

## Quick Reference

| Topic | Location |
|-------|----------|
| **Workflow overview** | `WORKFLOW.md` |
| **Statistical methods** | `GAM_METHODOLOGY.md` |
| **Project instructions** | `CLAUDE.md` |
| **Docker setup** | `DOCKER_SETUP.md` |
| **Raw HLS data** | `/mnt/malexander/datasets/ndvi_monitor/raw_hls_data/` |
| **GAM models** | `/mnt/malexander/datasets/ndvi_monitor/gam_models/` |
| **Baseline posteriors** | `/mnt/malexander/datasets/ndvi_monitor/gam_models/baseline_posteriors/` |
| **Year posteriors** | `/mnt/malexander/datasets/ndvi_monitor/gam_models/year_predictions_posteriors/` |
| **Derivatives** | `/mnt/malexander/datasets/ndvi_monitor/gam_models/change_derivatives/` |
| **Figures/plots** | `/mnt/malexander/datasets/ndvi_monitor/figures/` |
| **Monitor scripts** | `monitor_*.sh` (check pipeline progress) |
