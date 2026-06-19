#!/usr/bin/env python3
"""
download_usdm.py — USDM weekly shapefile downloader

Fetches the U.S. Drought Monitor weekly ZIP archive from NDMC
(https://droughtmonitor.unl.edu/data/shapefiles_m/USDM_<YYYYMMDD>_M.zip)
into <DEST>/raw/, maintaining a provenance manifest at <DEST>/manifest.csv.

Stdlib-only (Python 3.8+). No pip install required.

Usage:
    python download_usdm.py --dest "U:/projects/NIDIS_AI/dataQuery/usdmDataQuery"
    python download_usdm.py --dest "..." --start 2020-01-07 --end 2025-12-30
    python download_usdm.py --dest "..." --force          # re-fetch all

See README.md and USDM_METADATA.md for the data dictionary.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import hashlib
import logging
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

TOOL_VERSION = "download_usdm.py@1.0.0"
URL_TEMPLATE = "https://droughtmonitor.unl.edu/data/shapefiles_m/USDM_{ymd}_M.zip"
USDM_EPOCH = dt.date(2000, 1, 4)  # first USDM map
MIN_VALID_BYTES = 100_000          # smaller -> almost certainly an error page
REQUEST_SPACING_S = 0.5            # be polite to NDMC
RETRY_DELAYS_S = (2, 5, 15)        # exponential-ish backoff between attempts
MANIFEST_FIELDS = [
    "filename", "week_date", "source_url", "http_status",
    "bytes", "sha256", "fetched_utc", "tool",
]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(
        description="Download USDM weekly shapefile ZIPs for CONUS.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("--dest", required=True, type=Path,
                   help="Destination root (e.g. U:/projects/NIDIS_AI/dataQuery/usdmDataQuery)")
    p.add_argument("--start", type=date_arg, default=USDM_EPOCH,
                   help="First Tuesday to fetch (YYYY-MM-DD)")
    p.add_argument("--end", type=date_arg, default=None,
                   help="Last Tuesday to fetch (YYYY-MM-DD); default = most recent published Tuesday")
    p.add_argument("--force", action="store_true",
                   help="Re-download even if file already exists")
    p.add_argument("--dry-run", action="store_true",
                   help="List planned downloads without fetching")
    return p.parse_args()


def date_arg(s: str) -> dt.date:
    return dt.datetime.strptime(s, "%Y-%m-%d").date()


def most_recent_published_tuesday(today: dt.date | None = None) -> dt.date:
    """USDM is dated for Tuesday but released Thursday morning ET.
    Return the most recent Tuesday whose Thursday release has passed
    (we use a 2-day buffer to stay safely on the right side of TZs).
    """
    today = today or dt.date.today()
    cutoff = today - dt.timedelta(days=2)
    # Tuesday = weekday 1
    offset = (cutoff.weekday() - 1) % 7
    return cutoff - dt.timedelta(days=offset)


def tuesdays_between(start: dt.date, end: dt.date) -> list[dt.date]:
    if start < USDM_EPOCH:
        start = USDM_EPOCH
    # Snap start forward to first Tuesday on/after `start`
    offset = (1 - start.weekday()) % 7
    first_tue = start + dt.timedelta(days=offset)
    if end < first_tue:
        return []
    n = (end - first_tue).days // 7 + 1
    return [first_tue + dt.timedelta(weeks=i) for i in range(n)]


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch_one(url: str, target: Path, logger: logging.Logger) -> tuple[bool, int | None]:
    """Download URL to target with retries.

    Returns (success, last_http_status). On failure, target is removed if
    partially written.
    """
    last_status: int | None = None
    for attempt, delay in enumerate([0, *RETRY_DELAYS_S]):
        if delay:
            time.sleep(delay)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": TOOL_VERSION})
            with urllib.request.urlopen(req, timeout=60) as resp:
                last_status = resp.status
                # Stream to disk
                tmp = target.with_suffix(target.suffix + ".part")
                with tmp.open("wb") as f:
                    while True:
                        chunk = resp.read(1 << 16)
                        if not chunk:
                            break
                        f.write(chunk)
                size = tmp.stat().st_size
                if size < MIN_VALID_BYTES:
                    tmp.unlink(missing_ok=True)
                    logger.warning("attempt %d: %s returned %d bytes (<%d), discarding",
                                   attempt + 1, url, size, MIN_VALID_BYTES)
                    continue
                # Verify it actually opens as a zip
                try:
                    with zipfile.ZipFile(tmp) as zf:
                        if zf.testzip() is not None:
                            raise zipfile.BadZipFile("CRC failure in member")
                except zipfile.BadZipFile as e:
                    tmp.unlink(missing_ok=True)
                    logger.warning("attempt %d: %s failed ZIP integrity (%s)",
                                   attempt + 1, url, e)
                    continue
                tmp.replace(target)
                return True, last_status
        except urllib.error.HTTPError as e:
            last_status = e.code
            if e.code == 404:
                # 404 is terminal for this week — don't retry
                logger.warning("404 Not Found: %s", url)
                return False, 404
            logger.warning("attempt %d: HTTP %d on %s", attempt + 1, e.code, url)
        except (urllib.error.URLError, TimeoutError) as e:
            logger.warning("attempt %d: network error on %s (%s)", attempt + 1, url, e)
    return False, last_status


def load_manifest(path: Path) -> dict[str, dict]:
    """Read existing manifest into {filename: row} dict; empty if absent."""
    if not path.exists():
        return {}
    out: dict[str, dict] = {}
    with path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row.get("filename"):
                out[row["filename"]] = row
    return out


def write_manifest(path: Path, rows_by_name: dict[str, dict]) -> None:
    rows = sorted(rows_by_name.values(), key=lambda r: r["filename"])
    tmp = path.with_suffix(".csv.tmp")
    with tmp.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=MANIFEST_FIELDS)
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") for k in MANIFEST_FIELDS})
    tmp.replace(path)


def setup_logger(log_path: Path) -> logging.Logger:
    logger = logging.getLogger("usdm")
    logger.setLevel(logging.INFO)
    fmt = logging.Formatter("%(asctime)s [%(levelname)s] %(message)s",
                            datefmt="%Y-%m-%dT%H:%M:%SZ")
    fmt.converter = time.gmtime
    fh = logging.FileHandler(log_path, encoding="utf-8")
    fh.setFormatter(fmt)
    sh = logging.StreamHandler(sys.stdout)
    sh.setFormatter(fmt)
    logger.addHandler(fh)
    logger.addHandler(sh)
    return logger


def main() -> int:
    args = parse_args()

    dest = args.dest.expanduser().resolve()
    raw_dir = dest / "raw"
    log_dir = dest / "logs"
    raw_dir.mkdir(parents=True, exist_ok=True)
    log_dir.mkdir(parents=True, exist_ok=True)

    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%d_%H%M%SZ")
    logger = setup_logger(log_dir / f"download_{stamp}.log")
    logger.info("tool=%s dest=%s", TOOL_VERSION, dest)

    end = args.end or most_recent_published_tuesday()
    weeks = tuesdays_between(args.start, end)
    logger.info("planned weeks: %d (%s → %s)", len(weeks), weeks[0] if weeks else "-",
                weeks[-1] if weeks else "-")

    manifest_path = dest / "manifest.csv"
    manifest = load_manifest(manifest_path)

    n_existing = n_new = n_failed = n_skipped = 0
    failed_dates: list[str] = []

    try:
        for i, wk in enumerate(weeks, start=1):
            ymd = wk.strftime("%Y%m%d")
            fname = f"USDM_{ymd}_M.zip"
            target = raw_dir / fname
            url = URL_TEMPLATE.format(ymd=ymd)

            if target.exists() and target.stat().st_size >= MIN_VALID_BYTES and not args.force:
                # Already on disk; ensure manifest has a row
                if fname not in manifest:
                    manifest[fname] = {
                        "filename": fname,
                        "week_date": wk.isoformat(),
                        "source_url": url,
                        "http_status": "",
                        "bytes": str(target.stat().st_size),
                        "sha256": sha256_of(target),
                        "fetched_utc": "",  # unknown — pre-existing
                        "tool": f"{TOOL_VERSION} (manifest-only)",
                    }
                n_existing += 1
                continue

            if args.dry_run:
                logger.info("[dry-run] would fetch %s", url)
                n_skipped += 1
                continue

            ok, status = fetch_one(url, target, logger)
            time.sleep(REQUEST_SPACING_S)

            if ok:
                manifest[fname] = {
                    "filename": fname,
                    "week_date": wk.isoformat(),
                    "source_url": url,
                    "http_status": str(status) if status is not None else "",
                    "bytes": str(target.stat().st_size),
                    "sha256": sha256_of(target),
                    "fetched_utc": dt.datetime.now(dt.timezone.utc)
                        .strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "tool": TOOL_VERSION,
                }
                n_new += 1
                if n_new % 25 == 0:
                    write_manifest(manifest_path, manifest)  # checkpoint
                    logger.info("checkpoint: %d new / %d existing / %d failed",
                                n_new, n_existing, n_failed)
            else:
                n_failed += 1
                failed_dates.append(ymd)
    finally:
        write_manifest(manifest_path, manifest)
        logger.info("manifest: %s (%d rows)", manifest_path, len(manifest))
        logger.info("summary: existing=%d new=%d failed=%d skipped=%d",
                    n_existing, n_new, n_failed, n_skipped)
        if failed_dates:
            preview = ", ".join(failed_dates[:10])
            more = "..." if len(failed_dates) > 10 else ""
            logger.warning("failed weeks (%d): %s%s",
                           len(failed_dates), preview, more)

    return 0 if n_failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
