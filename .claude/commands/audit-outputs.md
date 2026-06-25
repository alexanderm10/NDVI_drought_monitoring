---
description: Verify pipeline outputs — row counts, year coverage, schema, headline metrics — before declaring a job complete
---

# Audit Outputs

Verify pipeline outputs before declaring a job complete. Never claim SEQUENCE_COMPLETE without running this.

## Usage

Invoke as: `/audit-outputs` — then specify the results directory and expected schema when prompted, or pass them directly:

> `/audit-outputs results/ expected_years=2003-2020 expected_cols=pixel_id,date,value,flag`

## What to Check

### 1. File Inventory

```bash
ls -lh <results_dir>/
find <results_dir> -name "*.parquet" -o -name "*.csv" -o -name "*.rds" | sort
```

Report: file count, sizes, last-modified timestamps.

### 2. Row Counts

For each output file, report row count:

```bash
# For CSV:
wc -l <file>.csv

# For RDS:
Rscript -e 'cat(nrow(readRDS("<file>")), "\n")'
```

Flag if any file is unexpectedly empty or much smaller than peers.

### 3. Year/Time Coverage

```bash
Rscript -e 'd<-readRDS("<file>"); cat(range(d$year), "\n")'
```

Report: first year, last year, any gaps in between.
Flag missing years against the expected range.

### 4. Schema Check

```bash
Rscript -e 'd<-readRDS("<file>"); cat(names(d), "\n")'
```

Flag: missing columns, unexpected columns, wrong types (especially integers where numeric expected — integer overflow risk).

### 5. Sanity Checks

```bash
# NaN/Inf counts (R):
Rscript -e 'd<-readRDS("<file>"); cat(sum(!is.finite(d$value)), "non-finite values\n")'
```

Use `is.finite()` not `!is.na()` — SPEI cache contains rare ±Inf values from CDF boundaries.

Check sign distribution on key metric columns; flag negatives where not expected.

### 6. Headline Metric

If the job produces a summary statistic (skill score, correlation, category hit rate), report the top-line number. If it differs drastically from expectations or prior runs, flag it before proceeding.

## Output Format

```
AUDIT REPORT — <results_dir> — <timestamp>
Files: N found, total size X
Row counts: file1=N, file2=M, ...
Year coverage: YYYY–YYYY (gaps: none / YYYY missing)
Schema: OK / MISSING: col_x, col_y / EXTRA: col_z
Non-finite values: N (in col_x)
Headline metric: X.XX
STATUS: PASS / FLAG (reasons)
```

If STATUS is FLAG, do not declare the job complete. Report the specific issue and ask how to proceed.
