# Compacts the Caltrain GTFS feed into res/caltrain.json for the iPod app. Usage: python3 -I compact_gtfs.py <gtfs dir> <out.json>
import csv, json, sys, os, re
g, out = sys.argv[1], sys.argv[2]
def rd(n): return list(csv.DictReader(open(os.path.join(g, n), encoding='utf-8-sig')))
stops = rd('stops.txt'); routes = {r['route_id']: r for r in rd('routes.txt')}
parents = [s for s in stops if s.get('location_type') == '1']
plats = [s for s in stops if s.get('location_type') in ('', '0') and s.get('parent_station')]
parents.sort(key=lambda s: -float(s['stop_lat']))   # north to south
def clean(n): return re.sub(r'\s*(Caltrain\s*)?Station$', '', n).replace(' Caltrain', '').strip()
sidx = {p['stop_id']: i for i, p in enumerate(parents)}
stations = []
for p in parents:
    st = {'id': p['stop_id'], 'name': clean(p['stop_name']), 'lat': round(float(p['stop_lat']), 5), 'lon': round(float(p['stop_lon']), 5), 'codes': {}, 'zone': ''}
    for pl in plats:
        if pl['parent_station'] == p['stop_id']:
            d = 'N' if 'north' in pl['stop_name'].lower() or pl.get('direction','').lower().startswith('n') else 'S'
            st['codes'][d] = pl.get('stop_code') or pl['stop_id']; st['zone'] = pl.get('zone_id') or st['zone']
    stations.append(st)
plat2st = {pl['stop_id']: sidx[pl['parent_station']] for pl in plats}
def mins(t): h, m, s = t.split(':'); return int(h) * 60 + int(m)
times = {}
for r in rd('stop_times.txt'):
    if r['stop_id'] not in plat2st: continue
    times.setdefault(r['trip_id'], []).append((int(r['stop_sequence']), plat2st[r['stop_id']], mins(r['departure_time']), mins(r['arrival_time'])))
trips = []
for t in rd('trips.txt'):
    sts = sorted(times.get(t['trip_id'], []))
    if not sts: continue
    name = routes[t['route_id']]['route_short_name']
    kind = 'Local' if name.startswith('Local') else name
    trips.append({'n': t.get('trip_short_name') or t['trip_id'], 'type': kind, 'dir': int(t['direction_id']), 'svc': t['service_id'], 'head': t.get('trip_headsign', ''), 'stops': [[s[1], s[2], s[3]] for s in sts]})
trips.sort(key=lambda t: t['stops'][0][1])
services = {c['service_id']: {'days': [int(c[d]) for d in ('monday','tuesday','wednesday','thursday','friday','saturday','sunday')], 'start': c['start_date'], 'end': c['end_date']} for c in rd('calendar.txt')}
exceptions = [{'svc': e['service_id'], 'date': e['date'], 'type': int(e['exception_type']), 'name': e.get('holiday_name', '')} for e in rd('calendar_dates.txt')]
fares = {}
price = {f['fare_id']: float(f['price']) for f in rd('fare_attributes.txt')}
for r in rd('fare_rules.txt'):
    if r['origin_id'] and r['destination_id']: fares[r['origin_id'] + '-' + r['destination_id']] = price[r['fare_id']]
fi = rd('feed_info.txt')[0]
json.dump({'version': fi['feed_version'], 'start': fi['feed_start_date'], 'end': fi['feed_end_date'], 'stations': stations, 'services': services, 'exceptions': exceptions, 'trips': trips, 'fares': fares}, open(out, 'w'), separators=(',', ':'))
used = set(t['svc'] for t in trips)
print(len(stations), 'stations', len(trips), 'trips', len(services), 'services', len([s for s in services if s in used]), 'used', len(exceptions), 'exceptions', len(fares), 'fares', os.path.getsize(out) // 1024, 'KB')
for s in stations[:3] + stations[-2:]: print(' ', s['name'], s['codes'], s['zone'])
print(' types:', sorted(set(t['type'] for t in trips)), 'heads:', sorted(set(t['head'] for t in trips))[:8])
