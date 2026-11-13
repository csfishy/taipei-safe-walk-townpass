"""Adapt the CC0 Protomaps lightV4 design to bundled Noto Traditional Chinese.

Input: extracted pub archive vector_map_tiles_pmtiles-1.5.2 (MIT adapter;
the embedded Protomaps style design is CC0, style software BSD-3-Clause).
No glyph/sprite URL is included: Flutter renders text from the bundled font.
"""
import argparse
import json
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('package', type=Path)
args = parser.parse_args()
source = (args.package / 'lib/src/themes/v4/light.dart').read_text(encoding='utf-8')
layers = json.loads(source[source.index('['):].strip().removesuffix(';'))
for layer in layers:
    layout = layer.get('layout', {})
    if layer.get('type') == 'symbol' and 'text-field' in layout:
        layout['text-font'] = ['SafeWalkNotoTC']
        layout['text-field'] = ['coalesce', ['get', 'name:zh-Hant'], ['get', 'name:zh'],
                                ['get', 'name'], ['get', 'name:en']]
        layout['text-allow-overlap'] = False
    if layer['id'] == 'roads_labels_minor':
        # Dense Taipei alleys overlap badly at z15; reveal their names at z17.
        layer['minzoom'] = 17
layers.append({
    'id': 'taipei_station_labels', 'type': 'symbol', 'source': 'protomaps',
    'source-layer': 'pois', 'minzoom': 13,
    'filter': ['==', 'kind', 'station'],
    'layout': {'text-field': ['coalesce', ['get', 'name:zh-Hant'], ['get', 'name:zh'],
                              ['get', 'name'], ['get', 'name:en']],
               'text-font': ['SafeWalkNotoTC'], 'text-size': 13,
               'text-allow-overlap': False},
    'paint': {'text-color': '#1565a0', 'text-halo-color': '#ffffff', 'text-halo-width': 2},
})
output = Path(__file__).resolve().parents[2] / 'assets/safe_walk/map/style.json'
output.write_text(json.dumps({'version': 8, 'name': 'Taipei Safe Walk',
    'sources': {'protomaps': {'type': 'vector'}}, 'layers': layers},
    ensure_ascii=False, indent=2), encoding='utf-8', newline='\n')
