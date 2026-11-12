"""Opt-in real Valhalla comparison, public landmarks only. Never run in CI."""
import datetime
import json
from pathlib import Path
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
FOLDER = ROOT / 'test/fixtures/offline_route'


def main():
    output = {'endpoint': 'https://valhalla1.openstreetmap.de/route',
              'retrievedAt': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'pairs': []}
    for pair in json.loads((FOLDER / 'taipei_pairs.json').read_text())['pairs']:
        body = {'locations': [dict(lat=p[0], lon=p[1]) for p in [pair['origin'], pair['destination']]],
                'costing': 'pedestrian', 'directions_type': 'none', 'units': 'kilometers'}
        request = urllib.request.Request(output['endpoint'], json.dumps(body).encode(),
                                         {'Content-Type': 'application/json', 'User-Agent': 'TaipeiSafeWalk-offline-validation/1.0'})
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                trip = json.load(response)['trip']
            output['pairs'].append(dict(id=pair['id'], status='ok', distanceMeters=trip['summary']['length']*1000,
                                        shape=trip['legs'][0]['shape']))
        except Exception as error:
            output['pairs'].append(dict(id=pair['id'], status='unavailable', errorType=type(error).__name__))
        time.sleep(1.2)
    (FOLDER / 'valhalla_reference.json').write_text(json.dumps(output, indent=2) + '\n', encoding='utf-8')
    print([(p['id'], p['status']) for p in output['pairs']])


if __name__ == '__main__':
    main()
