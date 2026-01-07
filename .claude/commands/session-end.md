---
description: End session properly - commit changes, document running processes
---

# Session End Workflow

Guide me through ending this NDVI monitoring session properly.

## Step 1: Check Running Processes

```bash
# Check for any R scripts still running in Docker
docker exec conus-hls-drought-monitor ps aux | grep "[R]script"

# If analyses are running in background, note their PIDs and log files
# Don't kill them unless instructed - document them instead
```

## Step 2: Review Changes

```bash
git status        # See all modified and untracked files
git diff          # Review actual changes
```

Identify files that shouldn't be committed:
- `*.rds` files > 100MB (should be on /mnt/ drive, not in repo)
- `*.RData` files
- Temporary files (`*.tmp`, `*.swp`)
- Personal notes or scratch files
- Log files from test runs (keep if documenting issues)
- Docker logs

## Step 3: Commit Workflow

Stage appropriate files and write descriptive commit message using tags:

| Tag | Use for |
|-----|---------|
| `[data]` | Data download, HLS acquisition scripts |
| `[aggregate]` | Script 01: 4km aggregation |
| `[gam]` | GAM model scripts (02, 03) |
| `[anomaly]` | Script 04: Anomaly calculations |
| `[viz]` | Script 05: Visualization, maps, animations |
| `[derivative]` | Script 06+: Derivative calculations |
| `[posterior]` | Posterior simulation functions |
| `[paths]` | Path setup, configuration |
| `[docker]` | Docker setup, compose files |
| `[docs]` | Documentation updates |
| `[fix]` | Bug fixes |
| `[test]` | Test runs, diagnostics |
| `[monitor]` | Monitoring scripts (check_*.sh) |

Example: `[derivative] Add visualization script for change rate anomalies (Script 07)`

```bash
git add <files>
git commit -m "[tag] Descriptive message"
git push origin main
```

## Step 4: Update Project Documentation

Update relevant documentation files:

### WORKFLOW.md
- Update script completion status
- Add new scripts to workflow diagram
- Update runtime estimates if changed
- Update storage requirements
- Note any workflow modifications

### CLAUDE.md (if relevant)
- Add new key functions or patterns
- Update common development tasks
- Note lessons learned

### Create Session Notes (if major milestone)

Create a markdown file documenting the session:
- Format: `SESSION_NOTES_YYYYMMDD.md`
- Include: purpose, scripts run, results, next steps
- Link to key figures and output files

Example:
```markdown
# Derivative Visualization Implementation - 2024-12-19

## Purpose
Implement spatial and temporal visualizations of change rate anomalies to identify
rapid vegetation browning/greening events across the Midwest.

## Scripts Created/Modified
- **07_visualize_derivatives.R**: New visualization script
  - Sample maps for different time windows
  - Time series of domain-wide change rates
  - Percent significant change plots

## Outputs Generated
- Location: `/data/figures/DERIVATIVES/`
- 198 figures for years 2016, 2020, 2024
- Time windows: 3, 7, 14, 30 days

## Status
- ✓ Script 07 implemented and tested
- ✓ 2016, 2020, 2024 visualizations complete
- ⏸ 2012 visualization pending (major drought year)

## Next Steps
1. Add 2012 to visualization config and generate plots
2. Consider adding other drought years (2017, 2021)
3. Create summary dashboard for all years
```

## Step 5: Note Running Processes

If analyses are running in background:

```bash
# Create/update a running analyses file
cat > CONUS_HLS_drought_monitoring/RUNNING_ANALYSES.md <<EOF
# Currently Running Analyses

**Updated**: $(date)

## Active Processes

- **Script XX**: Descriptive Name
  - Container: conus-hls-drought-monitor
  - Started: [timestamp]
  - Log: XX_script_name.log
  - Expected completion: ~HH:MM
  - Monitor: \`docker exec conus-hls-drought-monitor tail -f /workspace/XX_script_name.log\`

## Completed Today

- [List of completed scripts/analyses]

## Next Steps

- [What to run after current processes complete]
EOF
```

## Step 6: Docker Container Management

```bash
# If analyses are complete and no more work planned:
docker compose down

# If keeping container running for next session:
# Leave it running, but note this in session summary
```

## Step 7: Final Summary

Provide session summary:

1. **Work Completed**: Scripts run, analyses finished
2. **Files Created**: New scripts, outputs, figures
3. **Running**: Background processes (describe monitoring)
4. **Commits**: What was committed and pushed
5. **Data Status**: Years/DOYs processed, storage used
6. **Next Session**: Clear next steps from WORKFLOW.md

## Quick Commands for Next Session

```bash
# Start Docker container
docker compose up -d

# Check container status
docker ps | grep conus-hls-drought-monitor

# Check running processes
docker exec conus-hls-drought-monitor ps aux | grep "[R]script"

# Monitor active log
docker exec conus-hls-drought-monitor tail -f /workspace/[latest_log_file]

# Check recent outputs
ls -lt /mnt/malexander/datasets/ndvi_monitor/gam_models/ | head -10
```

---

**Remember**:
- Don't commit large .rds files (they belong on /mnt/ drive)
- Document running processes before ending session
- Long-running scripts (02, 03, 06) may take 1-2 days - don't interrupt unnecessarily
