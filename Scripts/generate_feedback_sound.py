#!/usr/bin/env python3
"""Generate Codex Deck's original soft key tone (no third-party samples)."""
import math
from pathlib import Path
import struct
import wave

rate = 48000
duration = 0.18
samples = []
phase = 0.0
for index in range(round(rate * duration)):
    time = index / rate
    frequency = 520 * (0.85 ** min(time / 0.06, 1))
    phase += 2 * math.pi * frequency / rate
    attack = math.sin(min(time / 0.008, 1) * math.pi / 2) ** 2
    release = min((duration - time) / 0.025, 1) ** 2
    envelope = attack * math.exp(-time / 0.045) * release
    samples.append(envelope * (math.sin(phase) + 0.16 * math.sin(2 * phase)))

peak = max(abs(value) for value in samples)
pcm = b"".join(struct.pack("<h", round(value / peak * 0.62 * 32767)) for value in samples)
output = Path(__file__).resolve().parents[1] / "Sources/CodexUsageWeb/Resources/click.wav"
with wave.open(str(output), "wb") as sound:
    sound.setparams((1, 2, rate, 0, "NONE", "not compressed"))
    sound.writeframes(pcm)
print(f"Generated {output.name}: {duration:.2f}s, {rate}Hz, mono PCM")
