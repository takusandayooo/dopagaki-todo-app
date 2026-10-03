#!/usr/bin/env python3
"""Deterministic original impact tones: C5, E5, G5. No external samples."""
import math
from pathlib import Path
import struct
import wave

ROOT = Path(__file__).resolve().parents[1]
RATE = 48000
DEST = ROOT / 'App/Resources/RewardSounds'
DEST.mkdir(parents=True, exist_ok=True)
for index, (frequency, duration) in enumerate([(523.25, .26), (659.25, .33), (783.99, .46)], 1):
    samples = []
    for n in range(round(RATE * duration)):
        t = n / RATE
        attack = min(1, t / .002)
        tail = min(1, (duration - t) / .025)
        body = math.sin(2 * math.pi * frequency * t) * math.exp(-t / (.068 + index * .02))
        sparkle = .28 * math.sin(2 * math.pi * frequency * 2 * t) * math.exp(-t / .045)
        strike = .30 * math.sin(2 * math.pi * (150 * t + 1.7 * (1 - math.exp(-t / .012)))) * math.exp(-t / .022)
        shimmer = .12 * math.sin(2 * math.pi * frequency * 3 * t) * math.exp(-t / .12) if index == 3 else 0
        samples.append((body + sparkle + strike + shimmer) * attack * tail)
    peak = max(abs(x) for x in samples)
    samples = [x * (.55 + index * .07) / peak for x in samples]
    with wave.open(str(DEST / f'star-impact-{index}.wav'), 'wb') as output:
        output.setparams((1, 2, RATE, 0, 'NONE', 'not compressed'))
        output.writeframes(b''.join(struct.pack('<h', round(x * 32767)) for x in samples))
    print(f'star-impact-{index}.wav: {duration:.2f}s, {frequency} Hz, peak {max(abs(x) for x in samples):.2f}')
