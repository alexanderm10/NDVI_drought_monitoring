---
description: Spawn independent sub-agents to verify findings, figures, or outputs in parallel
---

# Parallel Verify

Spawn independent sub-agents to verify findings, figures, or outputs in parallel. Use when you want independent eyes rather than a single Claude reviewing its own work.

## When to Use

- Verifying figures for alignment issues (IQR crossbars, per-pixel vs per-event grouping, subtitle accuracy, ecoregion names)
- Auditing multi-section outputs independently (Section A, B, C each checked by a different agent)
- Peer-review comment passes (each comment verified independently)
- Any situation where "Claude reviewing its own work" is insufficient

## Usage

Tell me what to verify and how many agents to spawn:

> `/parallel-verify 3 agents: (1) audit script 09 outputs for years 2016-2025, (2) verify Fig 9 IQR alignment matches data, (3) check EPA L2 ecoregion names against pixel_to_ecoregion_l2.rds`

Or for figure verification:

> `/parallel-verify figures/phase6/ against phase6_results_memo.md — check alignment, grouping, and headline numbers`

## What Each Agent Will Do

Each sub-agent receives:
1. A specific, bounded task (no overlap with siblings)
2. The relevant files to examine (not the full codebase)
3. A structured output format to report findings

Each agent reports independently. I then synthesize: where do they agree? Where do they diverge? Divergence = flag for your review.

## Structured Output Per Agent

```
AGENT <N> — <task>
Files examined: <list>
Finding: PASS / FLAG
Detail: <specific observation>
Evidence: <line number, column name, pixel count, etc.>
```

## Important: Agents Do Not Iterate

Each agent does one pass and reports. If a figure needs fixing after verification, that is a separate step — the verify agents do not also fix. This separation ensures the verification is independent.

## Model Note

Verification agents run on Sonnet (cheaper) — they're reading and reporting, not reasoning about science. Escalate to Opus only if a finding requires scientific judgment about what the correct answer should be.
