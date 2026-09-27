#!/usr/bin/env python3
"""Generate Tang-Phosphor's deterministic 48 kHz stereo WAV test."""

from __future__ import annotations

import argparse
import hashlib
import struct
import wave
import zlib
from pathlib import Path


SAMPLE_RATE = 48_000
DURATION_SECONDS = 6
AMPLITUDE = 8_192


def square_sample(phase: int) -> int:
    return AMPLITUDE if phase < SAMPLE_RATE // 2 else -AMPLITUDE


def advance_phase(phase: int, frequency: int) -> int:
    return (phase + frequency) % SAMPLE_RATE


def generate(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    left_phase = 0
    right_phase = 0

    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)

        for index in range(SAMPLE_RATE * DURATION_SECONDS):
            second = index // SAMPLE_RATE
            left = square_sample(left_phase) if second < 2 or second >= 4 else 0
            right = square_sample(right_phase) if 2 <= second else 0
            output.writeframesraw(struct.pack("<hh", left, right))
            left_phase = advance_phase(left_phase, 440)
            right_phase = advance_phase(right_phase, 880)

    payload = path.read_bytes()
    print(f"path={path}")
    print(f"bytes={len(payload)}")
    print(f"crc32={zlib.crc32(payload) & 0xffffffff:08x}")
    print(f"sha256={hashlib.sha256(payload).hexdigest()}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "output",
        nargs="?",
        type=Path,
        default=Path("build/phosphor-wav-test-48k.wav"),
    )
    args = parser.parse_args()
    generate(args.output)


if __name__ == "__main__":
    main()
