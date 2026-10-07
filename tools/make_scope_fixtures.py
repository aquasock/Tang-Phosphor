#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Generate deterministic stereo WAV fixtures for XY geometry qualification."""
import argparse
import math
from pathlib import Path
import struct
import wave


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output-dir", type=Path, default=Path("build/oscope-fixtures"))
    ap.add_argument("--rate", type=int, choices=(44100, 48000), default=48000)
    ap.add_argument("--seconds", type=int, default=4)
    args = ap.parse_args()
    if not 1 <= args.seconds <= 60:
        ap.error("duration must be 1 to 60 seconds")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for shape in ("circle", "diagonal", "opposite", "horizontal", "vertical", "lissajous"):
        path = args.output_dir / f"scope-{shape}-{args.rate}.wav"
        frames = bytearray()
        for n in range(args.rate * args.seconds):
            angle = math.tau * 500 * (n % args.rate) / args.rate
            a, b = math.sin(angle), math.cos(angle)
            left, right = {
                "circle": (a, b), "diagonal": (a, a), "opposite": (a, -a),
                "horizontal": (a, 0), "vertical": (0, a),
                "lissajous": (a, math.sin(2 * angle)),
            }[shape]
            frames += struct.pack("<hh", round(left * 24575), round(right * 24575))
        with wave.open(str(path), "wb") as wav:
            wav.setnchannels(2)
            wav.setsampwidth(2)
            wav.setframerate(args.rate)
            wav.writeframes(frames)
        print(path)


if __name__ == "__main__":
    main()
