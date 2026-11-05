#!/usr/bin/env python3
# ring.py <out.wav> : synthesizes the timer bell (a small bell rattled by a clapper, two bursts), 44.1 kHz 16-bit mono.
# Convert for the app with: afconvert -f caff -d LEI16 out.wav res/ring.caf
import math, random, struct, sys, wave
RATE, DUR = 44100, 2.9
random.seed(7)
modes = [(1568.0, 1.0, 1.4), (1568.0 * 2.0, 0.5, 0.9), (1568.0 * 2.76, 0.35, 0.6), (1568.0 * 5.4, 0.12, 0.25)]   # (Hz, level, decay s)
strikes, t = [], 0.0
for start, end in ((0.0, 1.05), (1.35, 2.15)):   # brrring ... brrring
    t = start
    while t < end:
        strikes.append((t, 0.7 + 0.3 * random.random())); t += 1 / 14.0 * (0.92 + 0.16 * random.random())
n = int(RATE * DUR); out = [0.0] * n
for (st, vel) in strikes:
    i0 = int(st * RATE)
    for f, lvl, dec in modes:
        ph = random.random() * 2 * math.pi; w = 2 * math.pi * f / RATE; k = math.exp(-1 / (dec * RATE)); a = lvl * vel
        for i in range(i0, n):
            out[i] += a * math.sin(w * (i - i0) + ph); a *= k
            if a < 1e-4: break
peak = max(abs(x) for x in out) or 1
fade = int(0.05 * RATE)
frames = b''.join(struct.pack('<h', int(32767 * 0.8 * x / peak * (min(1, (n - i) / fade)))) for i, x in enumerate(out))
w = wave.open(sys.argv[1], 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE); w.writeframes(frames); w.close()
