# Claude Commands for NDVI Drought Monitoring

These commands help maintain context and organization across analysis sessions.

## Available Commands

### `/session-start` - Begin a New Session

Use this at the **start of each Claude session** to load project context.

**What it does**:
1. Reads project documentation (WORKFLOW.md, CLAUDE.md, GAM_METHODOLOGY.md)
2. Checks current pipeline phase (Scripts 01-07+)
3. Reviews running Docker processes
4. Checks git status
5. Reviews recent model outputs and figures
6. Summarizes current state and pending work

**When to use**: Every time you start working with Claude on this project

**Example**:
```
User: /session-start
Claude: [Loads context and asks] "What would you like to work on today?"
```

---

### `/implement-script` - Create or Modify a Pipeline Script

Use this when **implementing a new analysis script** (Scripts 01-07, etc.).

**What it does**:
1. **Design**: Plans inputs, outputs, and approach
2. **Check**: Verifies data availability
3. **Implement**: Writes code following project templates
4. **Test**: Runs in Docker with monitoring
5. **Verify**: Confirms correct outputs
6. **Document**: Updates WORKFLOW.md
7. **Commit**: Creates clean git commit

**When to use**: Creating new scripts or significantly modifying existing ones

**Example**:
```
User: /implement-script for Script 08: Drought severity classification
Claude: [Guides through 7-stage process]
```

---

### `/session-end` - End Your Session Properly

Use this at the **end of each Claude session** to wrap up work.

**What it does**:
1. Checks for running background processes in Docker
2. Reviews uncommitted git changes
3. Guides commit workflow with proper tags
4. Updates project documentation (WORKFLOW.md, session notes)
5. Documents running analyses
6. Provides clear next steps

**When to use**: Before closing Claude or switching to different work

**Example**:
```
User: /session-end
Claude: [Guides through] checking changes → committing → updating docs → noting next steps
```

---

## Command Tags for Commits

Use these tags in commit messages for consistency:

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
| `[monitor]` | Monitoring scripts |

**Examples**:
```bash
git commit -m "[viz] Add 2012 to derivative visualization config"
git commit -m "[derivative] Fix memory issue in DOY loop (Script 06)"
git commit -m "[docs] Update WORKFLOW.md runtime estimates"
```

---

## Quick Workflow for Common Tasks

### Starting a Session
1. Type `/session-start` → Get project status
2. Identify next task from output
3. Proceed with work

### Implementing a New Script
1. Type `/implement-script` for Script XX: [description]
2. Follow 7-stage process
3. Use `/session-end` to commit

### Ending a Session
1. Type `/session-end`
2. Review and commit changes
3. Document running processes (if any)

---

## Project-Specific Context

### Key Files
- **WORKFLOW.md**: Pipeline overview, runtime estimates, data flow
- **GAM_METHODOLOGY.md**: Statistical methods, model specifications
- **CLAUDE.md**: AI assistant instructions for this codebase
- **DOCKER_SETUP.md**: Container configuration

### Data Locations
- **Raw HLS**: `/mnt/malexander/datasets/ndvi_monitor/raw_hls_data/`
- **GAM Models**: `/mnt/malexander/datasets/ndvi_monitor/gam_models/`
- **Posteriors**: `/mnt/malexander/datasets/ndvi_monitor/gam_models/[component]_posteriors/`
- **Figures**: `/mnt/malexander/datasets/ndvi_monitor/figures/`

### Long-Running Scripts
Scripts 02, 03, and 06 can run for 1-2 days each. Always:
- Run in Docker container with nohup
- Capture logs
- Use monitor scripts to check progress
- Don't interrupt unless necessary

### Valid Pixels
All analyses must use `valid_pixels_landcover_filtered.rds` (125,798 pixels) for consistency.

---

## Why These Commands?

These workflows prevent common issues:

❌ **Without structure**:
- Forgetting to update documentation
- Inconsistent commit messages
- Missing project context when resuming
- Incomplete verification of outputs
- Poor handoffs between sessions

✅ **With structure**:
- Systematic project loading
- Consistent documentation
- Clear commit history
- Verified outputs
- Smooth session transitions

---

## Customization

These commands are adapted from general templates in `/mnt/malexander/claude_helpers/` for the NDVI drought monitoring project specifically.

To customize further:
1. Edit the .md files in this directory
2. Update project-specific paths and conventions
3. Add new command files as needed
4. Keep README.md updated

---

**Version**: 2024-12-19
**Based on**: Templates from `excelon_veg_analysis` and `claude_helpers`
