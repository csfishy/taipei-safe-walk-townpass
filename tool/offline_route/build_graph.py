"""Deterministic OSM PBF -> bounded pedestrian CSR. Python stdlib only.

PBF parsing follows https://github.com/openstreetmap/OSM-binary (fileformat.proto,
osmformat.proto). Relations are deliberately not used; see README limitations.
"""
import argparse
import datetime
import hashlib
import json
import math
from pathlib import Path
import struct
import zlib

MAGIC = b'SWWALK01'
HEADER = struct.Struct('<8sIIII')
EDGE = struct.Struct('<IIIB3x')  # target, millimetres, name index, flags
RULES = json.loads(Path(__file__).with_name('rules.json').read_text())


def walkable(tags, rules=RULES):
    foot = tags.get('foot')
    explicit = foot in rules['explicitFoot']
    if foot in rules['deniedFoot']:
        return False
    if tags.get('highway') in ('construction', 'proposed') or tags.get('construction') not in (None, 'no'):
        return False
    if tags.get('access') in rules['deniedAccess'] and not explicit:
        return False
    if tags.get('area') == 'yes' or not tags.get('highway'):
        return False
    return explicit or tags['highway'] in rules['highways']


def varints(data):
    value = shift = 0
    for b in data:
        value |= (b & 127) << shift
        if b < 128:
            yield value
            value = shift = 0
        else:
            shift += 7
            if shift > 70:
                raise ValueError('Invalid protobuf varint')
    if shift:
        raise ValueError('Truncated varint')


def fields(data):
    pos = 0
    def take_varint():
        nonlocal pos
        start = pos
        while pos < len(data):
            pos += 1
            if data[pos - 1] < 128:
                return next(varints(data[start:pos]))
        raise ValueError('Truncated protobuf')
    while pos < len(data):
        tag = take_varint()
        kind = tag & 7
        if kind == 0:
            value = take_varint()
        elif kind == 2:
            size = take_varint()
            value = data[pos:pos + size]
            pos += size
            if pos > len(data):
                raise ValueError('Truncated protobuf field')
        else:
            raise ValueError(f'Unsupported protobuf wire type {kind}')
        yield tag >> 3, value


def unzig(n):
    return (n >> 1) ^ -(n & 1)


def deltas(data):
    total = 0
    for n in varints(data):
        total += unzig(n)
        yield total


def blocks(path):
    with path.open('rb') as stream:
        while prefix := stream.read(4):
            size, = struct.unpack('>I', prefix)
            if size > 65536:
                raise ValueError('Oversized PBF header')
            header = dict(fields(stream.read(size)))
            blob = dict(fields(stream.read(header[3])))
            if header[1] != b'OSMData':
                continue
            data = blob.get(1)
            if data is None:
                data = zlib.decompress(blob[3])
                if len(data) != blob[2]:
                    raise ValueError('PBF raw size mismatch')
            yield data


def primitives(path):
    for block in blocks(path):
        entries = list(fields(block))
        scalar = dict(entries)
        strings = [v.decode('utf-8') for k, v in fields(scalar[1]) if k == 1]
        granularity = scalar.get(17, 100)
        lat_offset = scalar.get(19, 0)
        lon_offset = scalar.get(20, 0)
        def coord(lat, lon):
            return (round((lat_offset + granularity * lat) / 100),
                    round((lon_offset + granularity * lon) / 100))
        def tags(keys, vals):
            return {strings[k]: strings[v] for k, v in zip(varints(keys), varints(vals))}
        for key, group in entries:
            if key != 2:
                continue
            for kind, message in fields(group):
                obj = dict(fields(message))
                if kind == 2:  # DenseNodes
                    kv = iter(varints(obj.get(10, b'')))
                    for ident, lat, lon in zip(deltas(obj[1]), deltas(obj[8]), deltas(obj[9])):
                        node_tags = {}
                        for k in kv:
                            if k == 0:
                                break
                            node_tags[strings[k]] = strings[next(kv)]
                        yield 'node', ident, coord(lat, lon), node_tags
                elif kind == 1:
                    yield 'node', unzig(obj[1]), coord(unzig(obj[8]), unzig(obj[9])), tags(obj.get(2, b''), obj.get(3, b''))
                elif kind == 3:
                    yield 'way', obj[1], list(deltas(obj[8])), tags(obj.get(2, b''), obj.get(3, b''))


def meters(a, b):
    lat1, lon1, lat2, lon2 = [math.radians(x / 1e7) for x in (*a, *b)]
    h = math.sin((lat2-lat1)/2)**2 + math.cos(lat1)*math.cos(lat2)*math.sin((lon2-lon1)/2)**2
    return 12742017.6 * math.asin(min(1, math.sqrt(h)))


def encode(nodes, edges, names):
    """nodes: E7 lat/lon; edges: (from,to,mm,name,flags), sorted deterministically."""
    edges = sorted(edges)
    strings = json.dumps(names, ensure_ascii=False, separators=(',', ':')).encode()
    out = bytearray(HEADER.pack(MAGIC, len(nodes), len(edges), len(names), len(strings)))
    for lat, lon in nodes:
        out.extend(struct.pack('<ii', lat, lon))
    offsets = [0] * (len(nodes) + 1)
    for source, *_ in edges:
        offsets[source + 1] += 1
    for i in range(len(nodes)):
        offsets[i + 1] += offsets[i]
    for offset in offsets:
        out.extend(struct.pack('<I', offset))
    for _, target, length, name, flags in edges:
        out.extend(EDGE.pack(target, length, name, flags))
    out.extend(strings)
    return out


def build(pbf, output, source_date, help_points=None):
    south, west, north, east = RULES['bbox']
    nodes, blocked, ways, poi_nodes, poi_ways = {}, set(), [], [], []
    def poi(tags):
        return tags.get('shop') == 'convenience' or tags.get('amenity') == 'police'
    def row(kind, ident, lat, lon, tags):
        return ['p' if tags.get('amenity') == 'police' else 's', f'{kind}/{ident}',
                lat / 1e7, lon / 1e7, tags.get('name:zh') or tags.get('name', ''), tags.get('opening_hours')]
    for kind, ident, value, tags in primitives(pbf):
        if kind == 'node':
            lat, lon = value
            if south*1e7 <= lat <= north*1e7 and west*1e7 <= lon <= east*1e7:
                nodes[ident] = value
                if poi(tags):
                    poi_nodes.append(row('node', ident, lat, lon, tags))
                if (tags.get('foot') in RULES['deniedFoot'] or
                    (tags.get('foot') not in RULES['explicitFoot'] and
                     (tags.get('barrier') in RULES['blockedBarriers'] or tags.get('access') in RULES['deniedAccess']))):
                    blocked.add(ident)
        else:
            if walkable(tags):
                ways.append((value, tags))
            if poi(tags):
                poi_ways.append((ident, value, tags))
    segments, used, names = [], set(), {''}
    for refs, tags in ways:
        name = tags.get('name:zh') or tags.get('name') or ''
        direction = tags.get('oneway:foot', 'no')
        for a, b in zip(refs, refs[1:]):
            if a not in nodes or b not in nodes or a in blocked or b in blocked or a == b:
                continue
            length = max(1, math.ceil(meters(nodes[a], nodes[b])*1000))
            if length <= 1:
                continue
            used.update((a, b))
            names.add(name)
            segments.append((a, b, length, name, tags.get('highway') == 'steps', direction))
    ids = {ident: i for i, ident in enumerate(sorted(used))}
    names = sorted(names)
    name_ids = {name: i for i, name in enumerate(names)}
    edges = set()
    for a, b, length, name, steps, direction in segments:
        if direction != '-1':
            edges.add((ids[a], ids[b], length, name_ids[name], int(steps)))
        if direction not in ('yes', '1', 'true'):
            edges.add((ids[b], ids[a], length, name_ids[name], int(steps)))
    data = encode([nodes[i] for i in sorted(used)], edges, names)
    if not edges or len(data) > 50_000_000:
        raise ValueError('Empty graph or asset exceeds 50 MB')
    output.mkdir(parents=True, exist_ok=True)
    (output / 'taipei_walk_graph.bin').write_bytes(data)
    with pbf.open('rb') as source:
        source_sha256 = hashlib.file_digest(source, 'sha256').hexdigest()
    meta = dict(format='SWWALK01', sourceUrl='https://download.geofabrik.de/asia/' + pbf.name,
                sourceDate=source_date, sourceFile=pbf.name, sourceSha256=source_sha256,
                bbox=RULES['bbox'], nodes=len(ids), edges=len(edges), bytes=len(data),
                sha256=hashlib.sha256(data).hexdigest(), rulesVersion=RULES['version'],
                rulesSha256=hashlib.sha256(Path(__file__).with_name('rules.json').read_bytes()).hexdigest(),
                license='ODbL-1.0', attribution='© OpenStreetMap contributors',
                generator='tool/offline_route/build_graph.py v1 (Python stdlib)')
    if help_points is not None:
        rows = poi_nodes
        for ident, refs, tags in poi_ways:
            positions = [nodes[n] for n in refs if n in nodes]
            if len(positions) != len(refs) or not positions:
                continue
            # Same representative bounding-box centre semantics as Overpass
            # `out center`; not a claimed entrance or an exact address.
            lat = (min(p[0] for p in positions) + max(p[0] for p in positions)) / 2
            lon = (min(p[1] for p in positions) + max(p[1] for p in positions)) / 2
            rows.append(row('way', ident, lat, lon, tags))
        snapshot = dict(source='OpenStreetMap (Geofabrik Taiwan PBF)', sourceDate=source_date,
                        sourceSha256=meta['sourceSha256'], sourceUrl=meta['sourceUrl'],
                        license='ODbL 1.0 — © OpenStreetMap contributors',
                        retrievedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                        bbox=RULES['bbox'], fields=['kind','osm','lat','lng','name','opening_hours'],
                        limitations=['Nodes and ways only; relations omitted. Way coordinates are representative bounding-box centres, not entrances.'],
                        rows=sorted(rows, key=lambda r: r[1]))
        help_points.write_text(json.dumps(snapshot, ensure_ascii=False, separators=(',', ':'))+'\n', encoding='utf-8', newline='\n')
        meta['helpPointsSha256'] = hashlib.sha256(help_points.read_bytes()).hexdigest()
        meta['helpPointsCount'] = len(rows)
    (output / 'taipei_walk_graph.meta.json').write_text(json.dumps(meta, ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    print(json.dumps(meta))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--pbf', type=Path, required=True)
    parser.add_argument('--source-date', required=True)
    parser.add_argument('--output', type=Path, default=Path('assets/safe_walk/route'))
    parser.add_argument('--help-points', type=Path, help='Regenerate the bundled help-point snapshot from this exact PBF (D4)')
    args = parser.parse_args()
    build(args.pbf, args.output, args.source_date, args.help_points)
