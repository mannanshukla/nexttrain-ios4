# Track shapes for the map: Caltrain main line + Gilroy extension from the Caltrain GTFS, and one shape per BART color.
# usage: compact_shapes.py <caltrain gtfs dir> <bart gtfs dir> <res dir>
import csv, json, math, sys
from collections import defaultdict
ct, bart, res = sys.argv[1], sys.argv[2], sys.argv[3]
def dp(pts, tol):
    if len(pts) < 3: return pts
    a, b = pts[0], pts[-1]; dx, dy = b[0]-a[0], b[1]-a[1]; L = math.hypot(dx, dy) or 1e-12
    best, bi = 0, 0
    for i in range(1, len(pts)-1):
        p = pts[i]; dist = abs(dy*(p[0]-a[0]) - dx*(p[1]-a[1])) / L
        if dist > best: best, bi = dist, i
    if best > tol: return dp(pts[:bi+1], tol)[:-1] + dp(pts[bi:], tol)
    return [a, b]
def shapes(d):
    out = defaultdict(list)
    for r in csv.DictReader(open(f"{d}/shapes.txt")): out[r["shape_id"]].append((int(r["shape_pt_sequence"]), float(r["shape_pt_lon"]), float(r["shape_pt_lat"])))
    return {k: [(x, y) for _, x, y in sorted(v)] for k, v in out.items()}
rnd = lambda pts: [[round(x, 4), round(y, 4)] for x, y in pts]
cs = shapes(ct)
longest = max(cs.values(), key=len)                      # SF <-> San Jose
south = max((v for v in cs.values() if min(y for _, y in v) < 37.1), key=len)   # reaches Gilroy
json.dump({"main": rnd(dp(longest, 0.0004)), "south": rnd(dp(south, 0.0004))}, open(f"{res}/track.json", "w"), separators=(",", ":"))
bs = shapes(bart); trips = list(csv.DictReader(open(f"{bart}/trips.txt"))); routes = {r["route_id"]: r for r in csv.DictReader(open(f"{bart}/routes.txt"))}
best = {}   # color -> longest shape used by a trip of that color
for t in trips:
    r = routes.get(t["route_id"]);
    if not r or not t["shape_id"]: continue
    c = r["route_color"].upper(); s = bs.get(t["shape_id"], [])
    if len(s) > len(best.get(c, (None, []))[1]): best[c] = (r["route_short_name"].split("-")[0], s)
lines = [{"name": n, "color": c, "pts": rnd(dp(s, 0.0004))} for c, (n, s) in best.items()]
json.dump({"lines": lines}, open(f"{res}/bart_map.json", "w"), separators=(",", ":"))
print("track", len(longest), "+", len(south), "pts;", [(l["name"], len(l["pts"])) for l in lines])
