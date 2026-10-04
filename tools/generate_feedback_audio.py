"""Generate the game's original, compact mono feedback sounds (standard library only).

Run from any directory. The deterministic sounds use additive synthesis, filtered
noise and short envelopes, with 28% peak headroom and fade-outs to avoid clicks.
These are original project assets, not samples taken from the supplied libraries.
"""
from __future__ import annotations

import math
from pathlib import Path
import random
import struct
import wave

RATE = 24000
OUT = Path(__file__).resolve().parents[1] / "art" / "audio" / "feedback"
TAU = math.tau


def tone(t: float, start: float, duration: float, frequency: float,
         gain: float = 1, decay: float = 5, harmonics: float = .15) -> float:
    elapsed = t - start
    if not 0 <= elapsed < duration:
        return 0
    phase = elapsed * TAU * frequency
    envelope = min(1., elapsed / .008) * math.exp(-decay * elapsed / duration)
    envelope *= min(1., (duration - elapsed) / .015)
    return gain * envelope * (math.sin(phase) + harmonics * math.sin(phase * 2))


def generate(kind: str, duration: float, seed: int) -> None:
    rng = random.Random(seed)
    signal: list[float] = []
    filtered = 0.
    for sample in range(round(duration * RATE)):
        t = sample / RATE
        noise = rng.uniform(-1, 1)
        filtered += (noise - filtered) * .15
        value = 0.
        if kind == "pack":
            # Dry paper crinkles, then a soft zipper-like sweep.
            for start in [0., .105, .215]:
                age = t - start
                if 0 <= age < .085:
                    value += (noise * .28 + filtered * .4) * math.sin(age / .085 * math.pi)
            if .34 <= t < .57:
                age = (t - .34) / .23
                value += (noise - filtered) * .16 * math.sin(age * math.pi)
                value += tone(t, .34, .23, 430, .08, 3)
        elif kind == "sale":
            value = (tone(t, 0., .26, 784, .30)
                     + tone(t, .09, .33, 1175, .38)
                     + tone(t, .19, .39, 1568, .38, 6)
                     + tone(t, .19, .39, 784, .18, 6))
        elif kind == "purchase":
            value = (tone(t, 0., .20, 880, .30, 6)
                     + tone(t, .11, .28, 659, .38, 6)
                     + tone(t, .11, .28, 330, .16, 6))
        elif kind == "text":
            value = (tone(t, 0., .16, 740, .3, 4)
                     + tone(t, .18, .28, 988, .31, 4)
                     + tone(t, .18, .28, 1482, .1, 5))
        elif kind == "detected":
            value = (tone(t, 0., .22, 392, .3, 2, .3)
                     + tone(t, .22, .35, 587, .36, 3, .3))
        elif kind == "caught":
            value = (tone(t, 0., .55, 196, .32, 2, .4)
                     + tone(t, .17, .67, 147, .42, 3, .35)
                     + tone(t, .17, .67, 155.56, .18, 3, .2))
            if t < .05:
                value += filtered * .3 * (1 - t / .05)
        elif kind == "impact":
            value = tone(t, 0., .34, 78, .45, 6, .2)
            if t < .33:
                value += (filtered * .45 + noise * .08) * math.exp(-t * 11)
        elif kind == "police_shot":
            # A short dry crack with a low body and a restrained outdoor tail.
            attack = min(1., t / .0015)
            value = attack * (noise * .7 * math.exp(-t * 65)
                              + filtered * .55 * math.exp(-t * 15))
            value += tone(t, 0., .18, 105, .25, 9, .08)
        elif kind == "consume":
            value = tone(t, .16, .36, 523, .16, 4)
            if t < .14:
                value += (filtered + noise * .12) * .30 * math.sin(t / .14 * math.pi)
        elif kind == "tuition":
            for start, frequency in [(0., 523.25), (.12, 659.25), (.24, 783.99), (.36, 1046.5)]:
                value += tone(t, start, .52, frequency, .26, 5)
        elif kind == "class":
            value = (tone(t, 0., .40, 659, .25, 4)
                     + tone(t, .22, .55, 523, .30, 4)
                     + tone(t, .22, .55, 1046, .10, 5))
        elif kind == "party":
            for start, frequency in [(0., 392), (.10, 494), (.20, 587), (.35, 784)]:
                value += tone(t, start, .43, frequency, .3, 4, .25)
        signal.append(value)
    peak = max(abs(value) for value in signal)
    scale = .72 / peak if peak else 0.
    data = b"".join(struct.pack("<h", round(value * scale * 32767)) for value in signal)
    with wave.open(str(OUT / f"{kind}.wav"), "wb") as target:
        target.setnchannels(1)
        target.setsampwidth(2)
        target.setframerate(RATE)
        target.writeframes(data)
    print(f"{kind:10}  {duration:.2f}s  {len(data):6,} bytes  peak .72")


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    durations = {"pack": .64, "sale": .65, "purchase": .45, "text": .52,
                 "detected": .63, "caught": .92, "consume": .58,
                 "tuition": .95, "class": .84, "party": .85, "impact": .42,
                 "police_shot": .28}
    for seed, (kind, duration) in enumerate(durations.items(), start=801):
        generate(kind, duration, seed)


if __name__ == "__main__":
    main()
