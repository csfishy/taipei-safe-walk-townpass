"""Regenerate ../fixtures/aed_expected_points.json from ../fixtures/aed_raw_sample.json (offline).

The Dart test asserts that DataTaipeiAedRepository's normalizer produces exactly this output.
"""
from __future__ import annotations

import json
from pathlib import Path

from aed_transform import SourceInfo, transform

FIXTURES = Path(__file__).resolve().parent.parent / "fixtures"
FIXED_INFO = SourceInfo("2026-11-07T14:44:57+08:00", "2026-09-04 18:15:48", "依政府資料開放授權條款-第1版")


def build() -> list[dict]:
    rows = json.loads((FIXTURES / "aed_raw_sample.json").read_text(encoding="utf-8"))["rows"]
    return transform(rows, FIXED_INFO)[0]


if __name__ == "__main__":
    (FIXTURES / "aed_expected_points.json").write_text(
        json.dumps(build(), ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("wrote aed_expected_points.json")
