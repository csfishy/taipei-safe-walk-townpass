"""Write a static AssistancePoint[] snapshot of the Taipei AED dataset (offline tool, not a server).

    python aed_dump.py aed-points.json
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import aed_source
from aed_transform import SourceInfo, format_taipei_time, transform


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("output", type=Path)
    args = ap.parse_args()
    try:
        snap = aed_source.fetch_snapshot()
    except aed_source.SourceUnavailable as exc:
        print(f"provider_unavailable: {exc}", file=sys.stderr)  # no demo fallback
        return 2
    info = SourceInfo(format_taipei_time(snap.retrieved_at), snap.resource_last_modified, snap.license_name)
    points, rejected = transform(snap.rows, info)
    args.output.write_text(json.dumps(points, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"sourceRows": len(snap.rows), "converted": len(points), "rejected": rejected,
                      "retrievedAt": info.retrieved_at}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
