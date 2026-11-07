"""Offline tests: python3 -m unittest discover -s lib/features/safe_walk/safety_data/aed/tool"""
from __future__ import annotations

import json
import unittest
from dataclasses import replace
from datetime import datetime, timezone

from aed_transform import format_taipei_time, make_address, normalize_license, platform_time_to_iso, transform
from make_fixtures import FIXED_INFO, FIXTURES, build


def raw() -> list[dict]:
    return json.loads((FIXTURES / "aed_raw_sample.json").read_text(encoding="utf-8"))["rows"]


class TransformTests(unittest.TestCase):
    def test_expected_fixture_is_up_to_date(self):
        committed = json.loads((FIXTURES / "aed_expected_points.json").read_text(encoding="utf-8"))
        self.assertEqual(committed, build(), "run: python3 make_fixtures.py")

    def test_every_real_sample_row_converts(self):
        points, rejected = transform(raw(), FIXED_INFO)
        self.assertEqual(rejected, [])
        self.assertEqual(len(points), len(raw()))

    def test_ids_unique_readable_and_input_order_independent(self):
        ids = [p["id"] for p in transform(raw(), FIXED_INFO)[0]]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertIn("tpe-aed-63000110-25.10235-121.548432-2", ids)  # 故宮: two AEDs, one coordinate
        self.assertEqual(ids, [p["id"] for p in transform(list(reversed(raw())), FIXED_INFO)[0]])

    def test_honest_defaults(self):
        p = transform(raw(), FIXED_INFO)[0][0]
        self.assertEqual(p["kind"], "public_facility")
        self.assertEqual(p["recognition"], {"status": "not_applicable", "evidenceUrl": None, "checkedAt": None})
        self.assertEqual((p["availability"], p["availabilityCheckedAt"], p["capabilities"]), ("unknown", None, ["unknown"]))
        self.assertEqual(p["source"]["dataMode"], "live")
        self.assertNotEqual(p["source"]["retrievedAt"], p["source"]["dataUpdatedAt"])

    def test_address_rules(self):
        self.assertEqual(make_address("忠孝東路五段六號", "信義區"), "臺北市信義區忠孝東路五段六號")
        self.assertEqual(make_address("台北市松山區健康路227號", "松山區"), "臺北市松山區健康路227號")
        self.assertEqual(make_address("大安區臨江街", "大安區"), "臺北市大安區臨江街")
        self.assertIsNone(make_address("   ", "中正區"))

    def test_bad_coordinates_are_rejected_not_guessed(self):
        base = raw()[0]
        rows = [{**base, "_id": 9001, "緯度": "", "經度": "121.5"},
                {**base, "_id": 9002, "緯度": "121.528283", "經度": "25.02603"},
                {**base, "_id": 9003, "緯度": "22.6", "經度": "120.3"},
                {**base, "_id": 9004, "緯度": "nan", "經度": "121.5"}]
        points, rejected = transform(rows, FIXED_INFO)
        self.assertEqual(points, [])
        self.assertEqual([r["rowId"] for r in rejected], [9001, 9002, 9003, 9004])

    def test_unknown_licence_and_time_stay_null(self):
        info = replace(FIXED_INFO, license_name="依菸酒管理法相關規定", resource_last_modified=None)
        s = transform(raw(), info)[0][0]["source"]
        self.assertIsNone(s["license"])
        self.assertIsNone(s["dataUpdatedAt"])
        self.assertEqual(normalize_license("依政府資料開放授權條款-第1版"), "政府資料開放授權條款-第1版")
        self.assertEqual(platform_time_to_iso("2026-09-04 18:15:48"), "2026-09-04T18:15:48+08:00")

    def test_taipei_time_format(self):
        self.assertEqual(format_taipei_time(datetime(2026, 11, 7, 6, 44, 57, 123, tzinfo=timezone.utc)),
                         "2026-11-07T14:44:57+08:00")
        with self.assertRaises(ValueError):
            format_taipei_time(datetime(2026, 11, 7, 14, 0))


if __name__ == "__main__":
    unittest.main()
