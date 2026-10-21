"""Synthesizes Shui's original UI sounds — pure stdlib, deterministic.

Regenerates Shui/Resources/Sounds/Library/*.wav (see that folder's README).

Usage: python3 -I scripts/synth_sounds.py Shui/Resources/Sounds/Library
"""
import math
import random
import struct
import sys
import wave
from pathlib import Path

RATE = 44100


def render(duration, voices, noise=None, peak=0.35, seed=7):
    n = int(duration * RATE)
    left = [0.0] * n
    right = [0.0] * n

    for v in voices:
        start = int(v["onset"] * RATE)
        phase = 0.0
        pan = v.get("pan", 0.5) * math.pi / 2
        gl, gr = math.cos(pan), math.sin(pan)
        for i in range(start, n):
            t = (i - start) / RATE
            glide = 1 + v.get("glide", 0.0) * (1 - math.exp(-t / v.get("glide_time", 0.08)))
            phase += 2 * math.pi * v["freq"] * glide / RATE
            attack = v.get("attack", 0.012)
            env = 0.5 - 0.5 * math.cos(math.pi * t / attack) if t < attack else 1.0
            env *= math.exp(-t / v["decay"])
            if env < 1e-5 and t > attack:
                break
            s = v["amp"] * env * math.sin(phase)
            left[i] += s * gl
            right[i] += s * gr

    if noise:
        rng = random.Random(seed)
        lp_fast = lp_slow = 0.0
        for i in range(n):
            t = i / RATE
            # Swells in, then fades: an airy breath under the tones.
            if t < noise["rise"]:
                env = math.sin(0.5 * math.pi * t / noise["rise"]) ** 2
            else:
                env = math.exp(-(t - noise["rise"]) / noise["fade"])
            cutoff = noise["cutoff_start"] + (noise["cutoff_end"] - noise["cutoff_start"]) * min(1.0, t / duration)
            a_fast = 1 - math.exp(-2 * math.pi * cutoff / RATE)
            a_slow = 1 - math.exp(-2 * math.pi * (cutoff * 0.25) / RATE)
            x = rng.uniform(-1, 1)
            lp_fast += a_fast * (x - lp_fast)
            lp_slow += a_slow * (x - lp_slow)
            s = (lp_fast - lp_slow) * noise["amp"] * env
            left[i] += s * 0.9
            right[i] += s * 1.0

    fade = int(0.06 * RATE)
    for i in range(fade):
        g = 0.5 - 0.5 * math.cos(math.pi * i / fade)
        left[n - 1 - i] *= g
        right[n - 1 - i] *= g

    loudest = max(max(abs(x) for x in left), max(abs(x) for x in right)) or 1.0
    scale = peak / loudest
    return [x * scale for x in left], [x * scale for x in right]


def write_wav(path, left, right):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        frames = bytearray()
        for l, r in zip(left, right):
            frames += struct.pack("<hh", int(max(-1, min(1, l)) * 32767), int(max(-1, min(1, r)) * 32767))
        w.writeframes(bytes(frames))


def shimmer():
    """A soft glass arpeggio rising over an airy breath — the default."""
    base = 587.33  # D5
    ratios = [1.0, 1.25, 1.5, 2.0, 2.5]
    voices = []
    for k, ratio in enumerate(ratios):
        onset = 0.055 * k
        pan = 0.3 + 0.1 * k
        amp = 0.55 * (0.82 ** k)
        f = base * ratio
        voices.append(dict(freq=f, onset=onset, amp=amp, decay=0.42, glide=0.015, pan=pan))
        voices.append(dict(freq=f + 2.7, onset=onset + 0.004, amp=amp * 0.6, decay=0.38, glide=0.015, pan=1 - pan))
        # A faint inharmonic overtone, gone almost instantly — the "glass" in it.
        voices.append(dict(freq=f * 2.76, onset=onset, amp=amp * 0.12, decay=0.06, pan=pan))
    noise = dict(amp=0.5, rise=0.3, fade=0.28, cutoff_start=1800, cutoff_end=7000)
    return render(1.4, voices, noise)


def bloom():
    """A warm low swell that opens into one soft bell."""
    voices = [
        dict(freq=196.0, onset=0.0, amp=0.5, decay=0.55, attack=0.18, glide=0.5, glide_time=0.25, pan=0.45),
        dict(freq=294.0, onset=0.0, amp=0.3, decay=0.5, attack=0.2, glide=0.5, glide_time=0.25, pan=0.55),
        dict(freq=880.0, onset=0.26, amp=0.32, decay=0.5, pan=0.5),
        dict(freq=883.0, onset=0.262, amp=0.2, decay=0.45, pan=0.6),
        dict(freq=880.0 * 2.76, onset=0.26, amp=0.05, decay=0.07, pan=0.5),
    ]
    noise = dict(amp=0.3, rise=0.25, fade=0.3, cutoff_start=600, cutoff_end=3000)
    return render(1.3, voices, noise, seed=11)


def droplet():
    """A single water-drop pop with a short sparkle tail."""
    voices = [
        dict(freq=620.0, onset=0.0, amp=0.6, decay=0.09, attack=0.003, glide=1.2, glide_time=0.02, pan=0.5),
        dict(freq=1568.0, onset=0.07, amp=0.18, decay=0.25, pan=0.35),
        dict(freq=1975.5, onset=0.11, amp=0.14, decay=0.25, pan=0.65),
        dict(freq=2349.3, onset=0.15, amp=0.1, decay=0.22, pan=0.5),
    ]
    return render(0.9, voices, None, peak=0.33)


if __name__ == "__main__":
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, fn in [("shimmer", shimmer), ("bloom", bloom), ("droplet", droplet)]:
        left, right = fn()
        write_wav(out / f"{name}.wav", left, right)
        print(f"wrote {name}.wav ({len(left) / RATE:.2f}s)")
