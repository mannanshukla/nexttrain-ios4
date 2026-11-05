#!/usr/bin/env python3
# tick.py <out.wav> : one soft mechanical tick for the egg timer, 44.1 kHz 16-bit mono.
# Convert for the app with: afconvert -f caff -d LEI16 out.wav res/tick.caf
import math, random, struct, sys, wave
RATE = 44100; n = int(RATE * 0.045); random.seed(3); out = []
for i in range(n):
    t = i / RATE
    click = (random.random() * 2 - 1) * math.exp(-t / 0.0025)                              # the escapement's snap
    body = 0.6 * math.sin(2 * math.pi * 2900 * t) * math.exp(-t / 0.006) + 0.35 * math.sin(2 * math.pi * 1350 * t) * math.exp(-t / 0.01)   # the shell ringing a little
    out.append(click * 0.5 + body)
peak = max(abs(x) for x in out)
w = wave.open(sys.argv[1], 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(RATE)
w.writeframes(b''.join(struct.pack('<h', int(32767 * 0.35 * x / peak)) for x in out)); w.close()
