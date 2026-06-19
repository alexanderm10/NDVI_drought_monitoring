#!/usr/bin/env bash
# download_usdm.sh — USDM weekly shapefile downloader (wget edition)
#
# Bash + wget alternative to download_usdm.py. Same destination layout and
# same manifest schema. Stdlib tools only: bash, wget, sha256sum, stat, date.
#
# Usage:
#   DEST=/u/projects/NIDIS_AI/dataQuery/usdmDataQuery               bash download_usdm.sh
#   DEST=... START=2020-01-07 END=2025-12-30                        bash download_usdm.sh
#   DEST=... FORCE=1                                                bash download_usdm.sh
#
# See README.md and USDM_METADATA.md for the data dictionary.

set -euo pipefail

# -------- config --------
TOOL_VERSION="download_usdm.sh@1.0.0"
URL_TMPL="https://droughtmonitor.unl.edu/data/shapefiles_m/USDM_%s_M.zip"
USDM_EPOCH="2000-01-04"
MIN_VALID_BYTES=100000
REQUEST_SPACING_S=0.5

DEST="${DEST:?Set DEST to destination root, e.g. U:/projects/NIDIS_AI/dataQuery/usdmDataQuery}"
START="${START:-$USDM_EPOCH}"
FORCE="${FORCE:-0}"

# -------- compute END default (most recent Tuesday whose release is ≥2 days past) --------
if [[ -z "${END:-}" ]]; then
    cutoff_epoch=$(( $(date -u +%s) - 2*86400 ))
    cutoff=$(date -u -d "@$cutoff_epoch" +%Y-%m-%d)
    cutoff_dow=$(date -u -d "$cutoff" +%u)   # 1=Mon..7=Sun
    offset=$(( (cutoff_dow - 2 + 7) % 7 ))
    END=$(date -u -d "$cutoff - $offset days" +%Y-%m-%d)
fi

# -------- snap START forward to first Tuesday on/after --------
start_dow=$(date -u -d "$START" +%u)
snap_offset=$(( (2 - start_dow + 7) % 7 ))
if [[ "$snap_offset" -gt 0 ]]; then
    START=$(date -u -d "$START + $snap_offset days" +%Y-%m-%d)
fi

# -------- clamp START to USDM epoch --------
if [[ "$START" < "$USDM_EPOCH" ]]; then
    START="$USDM_EPOCH"
fi

RAW_DIR="$DEST/raw"
LOG_DIR="$DEST/logs"
mkdir -p "$RAW_DIR" "$LOG_DIR"
STAMP=$(date -u +%Y%m%d_%H%M%SZ)
LOG_FILE="$LOG_DIR/download_${STAMP}.log"
MANIFEST="$DEST/manifest.csv"

log() {
    printf '%s [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG_FILE"
}
warn() {
    printf '%s [WARN] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG_FILE" >&2
}

log "tool=$TOOL_VERSION dest=$DEST"
log "range: $START -> $END"

# -------- ensure manifest exists with header --------
if [[ ! -f "$MANIFEST" ]]; then
    printf 'filename,week_date,source_url,http_status,bytes,sha256,fetched_utc,tool\n' > "$MANIFEST"
fi

# -------- iterate Tuesdays --------
n_existing=0; n_new=0; n_failed=0
failed_dates=()

cur="$START"
while [[ "$cur" < "$END" || "$cur" == "$END" ]]; do
    ymd=$(date -u -d "$cur" +%Y%m%d)
    fname="USDM_${ymd}_M.zip"
    url=$(printf "$URL_TMPL" "$ymd")
    target="$RAW_DIR/$fname"

    # skip if present and large enough and not forcing
    if [[ "$FORCE" != "1" && -f "$target" ]]; then
        size=$(stat -c %s "$target" 2>/dev/null || stat -f %z "$target")
        if [[ "$size" -ge "$MIN_VALID_BYTES" ]]; then
            n_existing=$((n_existing+1))
            # ensure manifest row exists; if not, backfill (no fetched_utc)
            if ! grep -q "^$fname," "$MANIFEST"; then
                sha=$(sha256sum "$target" | awk '{print $1}')
                printf '%s,%s,%s,,%s,%s,,%s\n' \
                    "$fname" "$cur" "$url" "$size" "$sha" \
                    "$TOOL_VERSION (manifest-only)" >> "$MANIFEST"
            fi
            cur=$(date -u -d "$cur + 7 days" +%Y-%m-%d)
            continue
        fi
        rm -f "$target"
    fi

    # fetch with wget — retries handled by wget itself
    http_status=""
    if wget --quiet --tries=3 --waitretry=5 --timeout=60 \
            --user-agent="$TOOL_VERSION" \
            --server-response \
            -O "$target.part" "$url" 2> "$target.headers"; then
        http_status=$(awk '/^  HTTP\//{code=$2} END{print code}' "$target.headers")
        rm -f "$target.headers"
        size=$(stat -c %s "$target.part" 2>/dev/null || stat -f %z "$target.part")
        if [[ "$size" -lt "$MIN_VALID_BYTES" ]]; then
            warn "$url returned $size bytes (<$MIN_VALID_BYTES); discarding"
            rm -f "$target.part"
            n_failed=$((n_failed+1)); failed_dates+=("$ymd")
        elif ! unzip -tq "$target.part" >/dev/null 2>&1; then
            warn "$url failed ZIP integrity test; discarding"
            rm -f "$target.part"
            n_failed=$((n_failed+1)); failed_dates+=("$ymd")
        else
            mv "$target.part" "$target"
            sha=$(sha256sum "$target" | awk '{print $1}')
            now_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
            printf '%s,%s,%s,%s,%s,%s,%s,%s\n' \
                "$fname" "$cur" "$url" "$http_status" "$size" "$sha" \
                "$now_utc" "$TOOL_VERSION" >> "$MANIFEST"
            n_new=$((n_new+1))
            if (( n_new % 25 == 0 )); then
                log "checkpoint: new=$n_new existing=$n_existing failed=$n_failed"
            fi
        fi
    else
        http_status=$(awk '/^  HTTP\//{code=$2} END{print code}' "$target.headers" 2>/dev/null || echo "")
        rm -f "$target.part" "$target.headers"
        warn "wget failed ($http_status) for $url"
        n_failed=$((n_failed+1)); failed_dates+=("$ymd")
    fi

    sleep "$REQUEST_SPACING_S"
    cur=$(date -u -d "$cur + 7 days" +%Y-%m-%d)
done

# -------- dedup manifest in-place (keep LAST row per filename, so a FORCE=1
#          re-fetch supersedes the prior row; sort body alphabetically) --------
tmp_manifest=$(mktemp)
{
  head -n1 "$MANIFEST"
  tail -n +2 "$MANIFEST" | awk -F, '{rows[$1]=$0} END{for(k in rows) print rows[k]}' | sort
} > "$tmp_manifest"
mv "$tmp_manifest" "$MANIFEST"

log "manifest: $MANIFEST ($(($(wc -l < "$MANIFEST") - 1)) rows)"
log "summary: existing=$n_existing new=$n_new failed=$n_failed"

if (( ${#failed_dates[@]} > 0 )); then
    preview="${failed_dates[*]:0:10}"
    more=""
    if (( ${#failed_dates[@]} > 10 )); then more="..."; fi
    warn "failed weeks (${#failed_dates[@]}): $preview$more"
    exit 1
fi

exit 0
