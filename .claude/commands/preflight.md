---
description: Pre-launch checklist for long-running nohup jobs — parse check, compression, integer overflow, shared state
---

# Preflight

Pre-launch checklist for long-running nohup jobs. Run before any job that will take >30 minutes.

## Usage

> `/preflight <script_path> [expected_runtime]`

Example: `/preflight CONUS_HLS_drought_monitoring/09_validate_drought_signal.R ~6hr`

## Checks

### 1. Verify Script Parses

```bash
Rscript -e 'parse("<script_path>")' 2>&1
```

Fail immediately if parse fails. Do not launch a broken script.

### 2. Check for Destination Conflicts

Before running anything that writes output:
- Read the script's output path(s)
- Check if those paths already exist
- Report: does output already exist? Is it complete? Would this overwrite valid data?

```bash
ls -lh <output_paths>
```

Ask the user to confirm before overwriting existing outputs.

### 3. Check Compression Choice

If the script writes large intermediate files, verify compression:
- `gzip` / `.gz` → OK for large row stores
- `xz` → WARN: too slow for multi-GB files, will stall the job (bit us on a 614M-row gridmet restart)
- `bzip2` → acceptable

If `xz` is detected on a large file context, flag it and suggest `gzip` instead.

### 4. Check for Integer Overflow Risk

Scan for columns that accumulate counts or products:
- Are denominators typed as `integer` where they could exceed 2^31-1?
- Are L-codes or categorical IDs read as `integer` (truncation risk) vs `character`?

Flag any `.R` pattern like `as.integer(`, `integer()`, or column reads where values might exceed 2,147,483,647.
Also check HSS denominators and L2 ecoregion codes — both have burned us.

### 5. Check U: Drive / Shared State

If the script reads from or writes to `/mnt/malexander/` (U: drive):
```bash
ls <shared_path>
```

Confirm the source data is present and complete before launching. Do not launch if source is missing or partial.

### 6. Monitor Pattern Review

Ask: "What monitoring pattern will you use?"

Suggest a tight, specific pattern:
```bash
tail -f <logfile> | grep --line-buffered -E "COMPLETE|ERROR|FAILED|Traceback|killed|Killed|done"
```

Review the proposed pattern for:
- Over-broad patterns that fire on every per-stratum log line (use specific stage markers, not generic progress)
- Missing failure signatures — must include: ERROR, FAILED, killed, Killed
- Buffering issues: grep needs `--line-buffered`

### 7. Launch Command Template

If all checks pass, generate the launch command:

```bash
nohup Rscript <script_path> > <logfile> 2>&1 &
PID=$!
echo "Launched PID $PID"
echo $PID > <script_name>.pid
ps -p $PID
```

## Preflight Summary

```
PREFLIGHT — <script> — <timestamp>
Parse:           PASS / FAIL
Output conflict: none / WARNING: <path> exists (N rows)
Compression:     OK / WARN: xz detected
Integer risk:    none / FLAG: <column> typed as integer
Shared state:    OK / MISSING: <path>
Monitor:         <reviewed pattern>

READY TO LAUNCH: YES / NO (resolve: <reason>)
```

Do not launch if any check is NO.
