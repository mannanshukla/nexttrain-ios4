import csv, json, sys, math
from collections import Counter, defaultdict
src, out = sys.argv[1], sys.argv[2]
LINES = ["J","K","L","M","N","T"]
routes = {r["route_id"]: r for r in csv.DictReader(open(f"{src}/routes.txt")) if r["route_short_name"] in LINES}
trips = {t["trip_id"]: t for t in csv.DictReader(open(f"{src}/trips.txt")) if t["route_id"] in routes}
stops = {s["stop_id"]: s for s in csv.DictReader(open(f"{src}/stops.txt"))}
seqs = defaultdict(list)
for r in csv.DictReader(open(f"{src}/stop_times.txt")):
    if r["trip_id"] in trips: seqs[r["trip_id"]].append((int(r["stop_sequence"]), r["stop_id"]))
# per route+direction: most common stop sequence (by trip count), and most common shape
def dp(pts, tol):
    if len(pts) < 3: return pts
    a, b = pts[0], pts[-1]; dx, dy = b[0]-a[0], b[1]-a[1]; L = math.hypot(dx, dy) or 1e-12
    best, bi = 0, 0
    for i in range(1, len(pts)-1):
        p = pts[i]; dist = abs(dy*(p[0]-a[0]) - dx*(p[1]-a[1])) / L
        if dist > best: best, bi = dist, i
    if best > tol: return dp(pts[:bi+1], tol)[:-1] + dp(pts[bi:], tol)
    return [a, b]
shapes = defaultdict(list)
for r in csv.DictReader(open(f"{src}/shapes.txt")): shapes[r["shape_id"]].append((int(r["shape_pt_sequence"]), float(r["shape_pt_lon"]), float(r["shape_pt_lat"])))
import re
def tc(t):
    t = re.sub(r"[\s/]+(outbound|inbound|outbd|inbd|northbound|southbound|ob|ib)\s*$", "", t, flags=re.I)   # platform direction suffixes
    t = re.sub(r"^metro\s+", "", t, flags=re.I)
    t = t.replace(" St & ", " & ")
    def cap(w):
        if w[:1].isdigit() or w == "&": return w
        if w.lower() in ("sf", "bart", "ucsf", "sfsu", "jfk"): return w.upper()
        return w[:1].upper() + w[1:].lower()
    t = " ".join(cap(w) for w in t.split(" "))
    t = re.sub(r"/(\w)", lambda m: "/" + m.group(1).upper(), t)           # capitalize after slashes
    t = t.replace("S.f.", "SF").replace("Bart/mezzanine Level", "BART").replace("Bart/Mezzanine Level", "BART")
    return t
outlines = []
for rid, r in sorted(routes.items(), key=lambda x: LINES.index(x[1]["route_short_name"])):
    line = {"id": r["route_short_name"], "name": tc(r["route_long_name"]), "color": r["route_color"], "dirs": [], "shape": []}
    for d in ("0", "1"):
        tids = [t for t, tr in trips.items() if tr["route_id"] == rid and tr["direction_id"] == d]
        if not tids: continue
        seqc = Counter(tuple(s for _, s in sorted(seqs[t])) for t in tids if seqs[t])
        best = seqc.most_common(1)[0][0]
        heads = Counter(trips[t]["trip_headsign"] for t in tids).most_common(1)[0][0]
        line["dirs"].append({"head": tc(heads), "stops": [{"code": stops[s]["stop_code"], "name": tc(stops[s]["stop_name"]), "lat": round(float(stops[s]["stop_lat"]), 5), "lon": round(float(stops[s]["stop_lon"]), 5)} for s in best]})
        shc = Counter(trips[t]["shape_id"] for t in tids).most_common(1)[0][0]
        if not line["shape"]:
            pts = [(x, y) for _, x, y in sorted(shapes[shc])]
            line["shape"] = [[round(x, 5), round(y, 5)] for x, y in dp(pts, 0.00015)]
    outlines.append(line)
    print(line["id"], line["name"], [(d["head"], len(d["stops"])) for d in line["dirs"]], len(line["shape"]), "shape pts", file=sys.stderr)
json.dump({"lines": outlines}, open(out, "w"), separators=(",", ":"))
