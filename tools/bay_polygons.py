import json, sys, math
src, out, svg = sys.argv[1], sys.argv[2], sys.argv[3]
W, E, Sb, N = -122.60, -121.70, 36.92, 38.10
d = json.load(open(src)); ways = d["elements"]
# --- chain ways by shared end nodes (OSM coastline: land on left, water on right)
byfirst = {}
for w in ways: byfirst.setdefault(w["nodes"][0], []).append(w)
used = set(); chains = []
for w in ways:
    if w["id"] in used: continue
    # walk backwards to find a chain start
    cur = w
    seen = {w["id"]}
    while True:
        prev = [p for p in ways if p["nodes"][-1] == cur["nodes"][0] and p["id"] not in seen]
        if not prev: break
        cur = prev[0]; seen.add(cur["id"])
        if cur["id"] == w["id"]: break
    pts = []; cur_ids = []
    while cur and cur["id"] not in used:
        used.add(cur["id"]); cur_ids.append(cur["id"])
        g = [(p["lon"], p["lat"]) for p in cur["geometry"]]
        pts += g if not pts else g[1:]
        nxt = byfirst.get(cur["nodes"][-1], [])
        cur = next((n for n in nxt if n["id"] not in used), None)
    chains.append(pts)
print(len(chains), "chains", file=sys.stderr)
# --- clip a polyline to the box -> list of segments (each a list of points; endpoints on boundary or chain ends)
def inside(p): return W <= p[0] <= E and Sb <= p[1] <= N
def clip_seg(a, b):
    # Liang-Barsky; returns clipped (a', b') or None
    t0, t1 = 0.0, 1.0; dx, dy = b[0]-a[0], b[1]-a[1]
    for p, q in ((-dx, a[0]-W), (dx, E-a[0]), (-dy, a[1]-Sb), (dy, N-a[1])):
        if p == 0:
            if q < 0: return None
        else:
            r = q / p
            if p < 0: t0 = max(t0, r)
            else: t1 = min(t1, r)
    if t0 > t1: return None
    return ((a[0]+t0*dx, a[1]+t0*dy), (a[0]+t1*dx, a[1]+t1*dy))
segs = []; rings = []
for ch in chains:
    closed = len(ch) > 3 and ch[0] == ch[-1]
    if closed and all(inside(p) for p in ch): rings.append(ch); continue
    def to_edge(p):   # nearest box edge point
        c = [(abs(p[0]-W), (W, p[1])), (abs(p[0]-E), (E, p[1])), (abs(p[1]-Sb), (p[0], Sb)), (abs(p[1]-N), (p[0], N))]
        return min(c)[1]
    if inside(ch[0]): ch = [to_edge(ch[0])] + ch
    if inside(ch[-1]): ch = ch + [to_edge(ch[-1])]
    cur = []
    for a, b in zip(ch, ch[1:]):
        c = clip_seg(a, b)
        if c is None:
            if cur: segs.append(cur); cur = []
            continue
        if not cur or cur[-1] != c[0]: 
            if cur: segs.append(cur)
            cur = [c[0]]
        cur.append(c[1])
    if cur: segs.append(cur)
def onb(p): return abs(p[0]-W) < 1e-9 or abs(p[0]-E) < 1e-9 or abs(p[1]-Sb) < 1e-9 or abs(p[1]-N) < 1e-9
# boundary parameter, clockwise in a north-up frame starting at NW corner: N edge W->E, E edge N->S, S edge E->W, W edge S->N
pw, ph = E - W, N - Sb
def tparam(p):
    x, y = p
    if abs(y - N) < 1e-9: return x - W
    if abs(x - E) < 1e-9: return pw + (N - y)
    if abs(y - Sb) < 1e-9: return pw + ph + (E - x)
    return 2*pw + ph + (y - Sb)
P = 2*(pw+ph)
def pt_at(t):
    t %= P
    if t < pw: return (W + t, N)
    t -= pw
    if t < ph: return (E, N - t)
    t -= ph
    if t < pw: return (E - t, Sb)
    t -= pw
    return (W, Sb + t)
open_segs = [s for s in segs if len(s) > 1 and onb(s[0]) and onb(s[-1])]
dropped = len(segs) - len(open_segs)
print(len(open_segs), "boundary-to-boundary segments,", dropped, "dangling dropped", file=sys.stderr)
entries = sorted(((tparam(s[0]), i) for i, s in enumerate(open_segs)))
water = []; used = set()
for i0 in range(len(open_segs)):
    if i0 in used: continue
    poly = []; i = i0
    while i not in used:
        used.add(i); s = open_segs[i]; poly += s
        tb = tparam(s[-1])
        # next entry clockwise after tb
        nxt = next(((t, j) for t, j in entries if t > tb + 1e-12), entries[0])
        t_end = nxt[0] if nxt[0] > tb else nxt[0] + P
        # add corners between tb and t_end
        for ck in (pw, pw+ph, 2*pw+ph, P):
            for base in (0, P):
                c = ck + base
                if tb < c < t_end: poly.append(pt_at(c))
        i = nxt[1]
    water.append(poly)
print(len(water), "water polygons,", len(rings), "islands", file=sys.stderr)
# --- simplify (Douglas-Peucker)
def dp(pts, tol):
    if len(pts) < 3: return pts
    a, b = pts[0], pts[-1]; dx, dy = b[0]-a[0], b[1]-a[1]; L = math.hypot(dx, dy) or 1e-12
    best, bi = 0, 0
    for i in range(1, len(pts)-1):
        p = pts[i]; dist = abs(dy*(p[0]-a[0]) - dx*(p[1]-a[1])) / L
        if dist > best: best, bi = dist, i
    if best > tol: return dp(pts[:bi+1], tol)[:-1] + dp(pts[bi:], tol)
    return [a, b]
TOL = 0.0003
water = [dp(p, TOL) for p in water]
def dp_ring(r, tol):
    h = len(r) // 2
    return dp(r[:h+1], tol)[:-1] + dp(r[h:], tol)
rings = [dp_ring(r, TOL) for r in rings]
rings = [r for r in rings if len(r) >= 4]
water = [p for p in water if len(p) >= 4]
def area(p): return abs(sum(p[i][0]*p[(i+1)%len(p)][1] - p[(i+1)%len(p)][0]*p[i][1] for i in range(len(p))))/2
rings = [r for r in rings if area(r) > 1.5e-5]
print("after simplify:", sum(len(p) for p in water), "water pts,", len(rings), "islands", sum(len(r) for r in rings), "pts", file=sys.stderr)
rnd = lambda poly: [[round(x, 4), round(y, 4)] for x, y in poly]
json.dump({"box": [W, Sb, E, N], "water": [rnd(p) for p in water], "land": [rnd(r) for r in rings]}, open(out, "w"), separators=(",", ":"))
# --- SVG preview
sw = 600; sh = int(sw * ph / pw * 1.26)
def X(x): return (x - W) / pw * sw
def Y(y): return (N - y) / ph * sh
f = open(svg, "w"); f.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{sw}" height="{sh}"><rect width="{sw}" height="{sh}" fill="#e8e3d9"/>')
for p in water: f.write('<polygon fill="#a9c8e6" stroke="#6f9fcc" stroke-width="1" points="' + " ".join(f"{X(x):.1f},{Y(y):.1f}" for x, y in p) + '"/>')
for r in rings: f.write('<polygon fill="#e8e3d9" stroke="#6f9fcc" stroke-width="1" points="' + " ".join(f"{X(x):.1f},{Y(y):.1f}" for x, y in r) + '"/>')
f.write('</svg>'); f.close()
