#!/usr/bin/env python3
"""Generate Pause's original, deterministic synthesized PCM sounds. No source recordings."""
import math, random, struct, wave
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1] / 'Pause/Resources/Audio'
ROOT.mkdir(parents=True, exist_ok=True)
RATE = 22050

def write(name, samples):
    peak = max(max(abs(x) for x in samples), 0.01)
    with wave.open(str(ROOT / (name + '.wav')), 'wb') as out:
        out.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        out.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, x / peak * .68)) * 32767)) for x in samples))

rng = random.Random(42)
for name in ['rain', 'ocean', 'ambient']:
    length = 16
    samples = []
    low = 0
    for i in range(RATE * length):
        t = i / RATE
        noise = rng.uniform(-1, 1)
        low = .985 * low + .015 * noise
        if name == 'rain':
            value = .24 * noise + 1.6 * low
        elif name == 'ocean':
            swell = .25 + .75 * (.5 + .5 * math.sin(2 * math.pi * t / 8)) ** 2
            value = (4 * low + .055 * noise) * swell
        else:
            value = sum(math.sin(2 * math.pi * f * t) * a for f, a in [(110, .3), (165, .13), (220, .07), (277.1875, .055), (330, .04)])
            value *= .85 + .15 * math.cos(2 * math.pi * t / 16)
        samples.append(value)
    # Wrap a filtered noise seam over 80 ms. Tone frequencies are periodic over 16 seconds.
    if name != 'ambient':
        n = int(RATE * .08)
        for i in range(n):
            a = i / n
            samples[-n + i] = samples[-n + i] * (1 - a) + samples[i] * a
        samples = samples[n:]
    write(name, samples)

for name, partials in {
    'bell': [(523.25, 1, 2.0), (1048.4, .22, 1.1), (1569.8, .07, .7)],
    'bowl': [(220, 1, 3.4), (441.1, .35, 2.6), (655, .16, 1.8)],
    'chime': [(659.25, .7, 1.9), (830.61, .4, 2.3), (987.77, .3, 2.8)]
}.items():
    samples = []
    for i in range(RATE * 9):
        t = i / RATE
        attack = min(1, t / .045)
        release = min(1, (9 - t) / .5)
        samples.append(attack * release * sum(a * math.exp(-t / decay) * math.sin(2 * math.pi * f * t) for f, a, decay in partials))
    write(name, samples)
print('Generated six original sounds in', ROOT)
