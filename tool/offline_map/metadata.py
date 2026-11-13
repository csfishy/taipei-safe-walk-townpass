"""Write reproducible metadata, or verify committed files without network access."""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3

ASSETS = Path(__file__).resolve().parents[2] / 'assets/safe_walk/map'
PBF_SHA = '6d9b7a214e7617df8473e311466e0a2517209d937c579f6a2134a64421cc838d'


def digest(data):
    return hashlib.sha256(data).hexdigest()


def metadata(directory=ASSETS):
    archive = directory / 'taipei.mbtiles'
    data = archive.read_bytes()
    if data[:16] != b'SQLite format 3\x00':
        raise ValueError('Expected SQLite MBTiles archive')
    if not 0 < len(data) <= 50_000_000:
        raise ValueError('Map must be nonempty and at most 50 MB')
    with sqlite3.connect(archive.resolve().as_uri() + '?mode=ro', uri=True) as connection:
        tile_meta = dict(connection.execute('SELECT name,value FROM metadata'))
        count, min_zoom, max_zoom = connection.execute(
            'SELECT count(*),min(zoom_level),max(zoom_level) FROM tiles').fetchone()
    if tile_meta['format'] != 'pbf' or (min_zoom, max_zoom) != (12, 15):
        raise ValueError('Expected vector PBF tiles, zoom 12–15')
    return {
        'format': 'mbtiles-1.3', 'schema': 'protomaps-v4',
        'sourceUrl': 'https://download.geofabrik.de/asia/taiwan-261111.osm.pbf',
        'sourceFile': 'taiwan-261111.osm.pbf', 'sourceDate': '2026-11-11',
        'sourceSha256': PBF_SHA,
        'bbox': [24.95, 121.44, 25.22, 121.68],
        'minZoom': 12, 'maxZoom': 15, 'displayMaxZoom': 19,
        'tileEntries': count,
        'generator': {
            'planetiler': '0.10.2', 'java': '21',
            'protomapsCommit': '42ffaaa4a85a41bfcb23e43cc0f5b492a5eca123',
            'profile': 'tool/offline_map/TaipeiBasemap.java',
            'parameters': '--bounds=121.44,24.95,121.68,25.22 --minzoom=12 --maxzoom=15 --archive-version=1.3 --threads=4 --nodemap-type=sortedtable --storage=mmap',
        },
        'bytes': len(data), 'sha256': digest(data),
        'license': 'ODbL-1.0',
        'attribution': '© OpenStreetMap contributors · Protomaps',
        'style': {'file': 'style.json', 'sha256': digest((directory / 'style.json').read_bytes()),
                  'license': 'CC0-1.0 design; BSD-3-Clause style code',
                  'source': 'vector_map_tiles_pmtiles 1.5.2 Protomaps lightV4; Traditional Chinese labels'},
        'font': {'file': 'NotoSansCJKtc-Regular.otf',
                 'sha256': digest((directory / 'NotoSansCJKtc-Regular.otf').read_bytes()),
                 'license': 'OFL-1.1',
                 'source': 'https://github.com/notofonts/noto-cjk/tree/main/Sans/OTF/TraditionalChinese'},
        'limitations': [
            'Snapshot, not a guarantee of present access, lighting or safety.',
            'OSM-only inland Taipei profile; no global ocean or landcover datasets; unranked POIs.',
            'Native z16–z19 overzoom z15; outside coverage displays a grey background and warning.',
        ],
    }


def verify(directory=ASSETS):
    actual = metadata(directory)
    expected = json.loads((directory / 'taipei_basemap.meta.json').read_text(encoding='utf-8'))
    if expected != actual:
        raise ValueError('Offline basemap metadata/digest mismatch')
    for source_path in (directory.parent / 'route/taipei_walk_graph.meta.json',
                        directory.parent / 'osm_help_points_taipei.json'):
        source_meta = json.loads(source_path.read_text(encoding='utf-8'))
        if (source_meta.get('sourceDate'), source_meta.get('sourceSha256')) != (
                actual['sourceDate'], actual['sourceSha256']):
            raise ValueError('D4 map, routing and help-point snapshots must share one PBF')
    for file in directory.iterdir():
        if file.is_file() and file.stat().st_size > 50_000_000:
            raise ValueError('Offline map asset exceeds 50 MB')
    print(f"PASS: offline basemap metadata and SHA-256 ({actual['bytes']} bytes); D4 shared PBF")


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    if args.write:
        (ASSETS / 'taipei_basemap.meta.json').write_text(
            json.dumps(metadata(), ensure_ascii=False, indent=2) + '\n', encoding='utf-8', newline='\n')
    verify()
