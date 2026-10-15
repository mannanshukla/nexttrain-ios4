# Satellite backgrounds for the Caltrain and BART map boxes from Sentinel-2 cloudless 2016 by EOX
# (https://s2maps.eu, CC BY 4.0, contains modified Copernicus Sentinel data 2016). The USGS mosaic had
# no-data blocks and striped water over the Bay; this one is seamless. Web Mercator tiles are stitched and
# resampled into the app's equirectangular boxes (same bbox and size as fetch_imagery.sh).
# usage: python fetch_s2.py <tile cache dir> <out dir>
import math, os, sys, time, urllib.request
from PIL import Image, ImageEnhance
cache, out = sys.argv[1], sys.argv[2]
URL = "https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless_3857/default/g/{z}/{y}/{x}.jpg"
BOXES = {"caltrain": ((-122.56, 36.97, -121.52, 37.84), (1400, 1478)),
         "bart":     ((-122.56, 37.44, -121.66, 38.06), (1400, 1217))}
Z = 12
def gx(lon, z): return (lon + 180) / 360 * 256 * 2 ** z
def gy(lat, z): r = math.radians(lat); return (1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * 256 * 2 ** z
def tile(z, x, y):
    p = os.path.join(cache, f"{z}_{x}_{y}.jpg")
    if not os.path.exists(p):
        for attempt in range(4):
            try:
                req = urllib.request.Request(URL.format(z=z, x=x, y=y), headers={"User-Agent": "nexttrain-ios4 map build (one-time fetch)"})
                data = urllib.request.urlopen(req, timeout=30).read(); open(p, "wb").write(data); time.sleep(0.05); break
            except Exception as e:
                if attempt == 3: raise
                time.sleep(2)
    return Image.open(p).convert("RGB")
for name, ((W, S, E, N), (w, h)) in BOXES.items():
    x0, x1, y0, y1 = gx(W, Z), gx(E, Z), gy(N, Z), gy(S, Z)
    tx0, tx1, ty0, ty1 = int(x0 // 256), int(x1 // 256), int(y0 // 256), int(y1 // 256)
    mosaic = Image.new("RGB", ((tx1 - tx0 + 1) * 256, (ty1 - ty0 + 1) * 256))
    for ty in range(ty0, ty1 + 1):
        for tx in range(tx0, tx1 + 1): mosaic.paste(tile(Z, tx, ty), ((tx - tx0) * 256, (ty - ty0) * 256))
    ox, oy = tx0 * 256, ty0 * 256
    # shrink with a proper filter first so the warp below never skips pixels
    k = w / (x1 - x0); small = mosaic.resize((round(mosaic.width * k), round(mosaic.height * k)), Image.LANCZOS)
    mesh, strip = [], 4
    for j in range(0, h, strip):
        j1 = min(h, j + strip)
        la0, la1 = N - j / h * (N - S), N - j1 / h * (N - S)
        sx0, sx1 = (x0 - ox) * k, (x1 - ox) * k
        sy0, sy1 = (gy(la0, Z) - oy) * k, (gy(la1, Z) - oy) * k
        mesh.append(((0, j, w, j1), (sx0, sy0, sx0, sy1, sx1, sy1, sx1, sy0)))
    img = small.transform((w, h), Image.MESH, mesh, Image.BICUBIC)
    img = ImageEnhance.Color(img).enhance(0.78); img = ImageEnhance.Contrast(img).enhance(1.06)   # calm the orange summer hills toward tan
    img.save(os.path.join(out, f"sat-{name}.jpg"), quality=84, optimize=True, progressive=False)
    print(name, img.size, f"{(tx1 - tx0 + 1) * (ty1 - ty0 + 1)} tiles")
