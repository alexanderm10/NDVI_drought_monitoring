---
description: Quick check on running background jobs — process status, log tail, PID check
---

# Status

Quick check on running background jobs. Cheap — use this freely; it's haiku-tier work.

## What to Check

### 1. Running Processes

```bash
ps aux | grep -E "(Rscript|python3?|bash.*nohup)" | grep -v grep
```

For each running process: PID, elapsed time, command.

### 2. Recent Log Activity

Find the most recently modified log file:
```bash
ls -lt *.log nohup.out logs/*.log /mnt/malexander/datasets/ndvi_monitor/gam_models/*.log 2>/dev/null | head -5
```

Tail the most relevant one:
```bash
tail -30 <logfile>
```

Report:
- Last meaningful progress line (not just noise)
- Any ERROR, WARNING, or FAILED lines in the last 100 lines
- Estimated stage (based on log content)

### 3. PID File Check

If a `.pid` file exists:
```bash
cat *.pid 2>/dev/null
kill -0 $(cat *.pid) 2>/dev/null && echo "alive" || echo "DEAD"
```

Report whether the tracked PID is still running.

### 4. Output File Growth

```bash
ls -lh /mnt/malexander/datasets/ndvi_monitor/gam_models/ 2>/dev/null | tail -10
ls -lh /mnt/malexander/datasets/ndvi_monitor/validation/ 2>/dev/null | tail -5
```

If output files are growing, report the current size and whether growth looks healthy.

## Status Report Format

```
STATUS — <timestamp>
Process: <PID> running for <elapsed> / NOT RUNNING
Log: <last meaningful line>
Errors: none / <N> errors in last 100 lines
Stage: <inferred from log>
Output: <N files, total size, growing/stalled>
```

If the process is dead unexpectedly, immediately report the last 50 lines of the log to diagnose the failure.
