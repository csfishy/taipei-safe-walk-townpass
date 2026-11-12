import hashlib
import json
from pathlib import Path
import struct
import tempfile
import unittest

from build_graph import EDGE, HEADER, MAGIC, RULES, build, deltas, encode, fields, walkable


def vi(n):
    out = bytearray()
    while n > 127:
        out.append((n & 127) | 128)
        n >>= 7
    return bytes(out + bytes([n]))


def pb(k, value):
    return vi(k*8 + (2 if isinstance(value, bytes) else 0)) + (vi(len(value)) + value if isinstance(value, bytes) else vi(value))


class GraphToolTest(unittest.TestCase):
    def test_walk_rules(self):
        for highway in RULES['highways']:
            self.assertTrue(walkable({'highway': highway}), highway)
        for highway in ['motorway', 'motorway_link', 'trunk', 'trunk_link', 'cycleway']:
            self.assertFalse(walkable({'highway': highway}))
            self.assertTrue(walkable({'highway': highway, 'foot': 'yes'}))
        for tags in [dict(foot='no'), dict(foot='private'), dict(foot='use_sidepath'),
                     dict(access='no'), dict(access='private'), dict(construction='yes'), dict(area='yes')]:
            self.assertFalse(walkable({'highway': 'footway', **tags}))
        for foot in RULES['explicitFoot']:
            self.assertTrue(walkable(dict(highway='residential', access='private', foot=foot)))
        self.assertFalse(walkable(dict(highway='construction', foot='yes')))
        self.assertFalse(walkable(dict(foot='yes')))

    def test_protobuf(self):
        self.assertEqual(list(fields(pb(1, 42) + pb(2, b'ab'))), [(1, 42), (2, b'ab')])
        self.assertEqual(list(deltas(vi(2) + vi(3) + vi(8))), [1, -1, 3])
        with self.assertRaises(ValueError): list(fields(b'\x0a\x05a'))

    def test_binary_round_trip_deterministic(self):
        nodes = [(250000000, 1215000000), (250001000, 1215000000)]
        edges = [(1, 0, 12000, 0, 1), (0, 1, 12000, 0, 1)]
        data = encode(nodes, edges, ['步道'])
        magic, n, e, count, names_size = HEADER.unpack_from(data)
        self.assertEqual((magic, n, e, count), (MAGIC, 2, 2, 1))
        self.assertEqual(struct.unpack_from('<3I', data, 40), (0, 1, 2))
        self.assertEqual(EDGE.unpack_from(data, 52), (1, 12000, 0, 1))
        self.assertEqual(json.loads(data[-names_size:]), ['步道'])
        self.assertEqual(data, encode(nodes, list(reversed(edges)), ['步道']))

    def test_raw_pbf_extraction_bbox_access_direction_and_metadata(self):
        # Entire synthetic PBF is a unit fixture, never shipped in assets.
        strings = ['', 'highway', 'footway', 'name', '測試步道', 'oneway:foot', 'yes']
        table = b''.join(pb(1, s.encode()) for s in strings)
        def node(ident, lat, lon):
            return pb(1, ident*2) + pb(8, lat*2) + pb(9, lon*2)
        nodes = b''.join(pb(1, node(i, 250000000 + i*1000, 1215000000)) for i in range(1, 4))
        way = pb(1, 100) + pb(2, bytes([1,3,5])) + pb(3, bytes([2,4,6])) + pb(8, bytes([2,2,2]))
        block = pb(1, table) + pb(2, nodes) + pb(2, pb(3, way))
        blob = pb(1, block)
        header = pb(1, b'OSMData') + pb(3, len(blob))
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            pbf = folder / 'synthetic.osm.pbf'
            pbf.write_bytes(struct.pack('>I', len(header)) + header + blob)
            build(pbf, folder / 'out', '2026-01-01')
            meta = json.loads((folder / 'out/taipei_walk_graph.meta.json').read_text(encoding='utf-8'))
            self.assertEqual((meta['nodes'], meta['edges']), (3, 2))
            binary = (folder / 'out/taipei_walk_graph.bin').read_bytes()
            self.assertEqual(meta['sha256'], hashlib.sha256(binary).hexdigest())

    def test_committed_real_asset_hash_and_limits(self):
        asset = Path(__file__).resolve().parents[2] / 'assets/safe_walk/route'
        meta = json.loads((asset / 'taipei_walk_graph.meta.json').read_text(encoding='utf-8'))
        data = (asset / 'taipei_walk_graph.bin').read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(), meta['sha256'])
        self.assertEqual(meta['bbox'], RULES['bbox'])
        self.assertEqual(meta['rulesVersion'], RULES['version'])
        self.assertEqual(meta['rulesSha256'], hashlib.sha256(Path(__file__).with_name('rules.json').read_bytes()).hexdigest())
        self.assertLessEqual(len(data), 50_000_000)
        self.assertGreater(meta['nodes'], 100_000)
        help_path = asset.parent / 'osm_help_points_taipei.json'
        snapshot = json.loads(help_path.read_text(encoding='utf-8'))
        self.assertEqual(meta['helpPointsSha256'], hashlib.sha256(help_path.read_bytes()).hexdigest())
        self.assertEqual(snapshot['sourceSha256'], meta['sourceSha256'])
        self.assertEqual(snapshot['sourceDate'], meta['sourceDate'])


if __name__ == '__main__':
    unittest.main()
