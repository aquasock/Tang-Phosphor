#!/usr/bin/env python3
"""Generate Tang-Phosphor's deterministic native-rate stereo WAV test."""

from __future__ import annotations

import argparse
import hashlib
import struct
import wave
import zlib
from pathlib import Path


DURATION_SECONDS = 6
AMPLITUDE = 8_192


def square_sample(phase: int, sample_rate: int) -> int:
    return AMPLITUDE if phase < sample_rate // 2 else -AMPLITUDE


def advance_phase(phase: int, frequency: int, sample_rate: int) -> int:
    return (phase + frequency) % sample_rate


def generate(path: Path, sample_rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    left_phase = 0
    right_phase = 0

    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(sample_rate)

        for index in range(sample_rate * DURATION_SECONDS):
            second = index // sample_rate
            left = square_sample(left_phase, sample_rate) if second < 2 or second >= 4 else 0
            right = square_sample(right_phase, sample_rate) if 2 <= second else 0
            output.writeframesraw(struct.pack("<hh", left, right))
            left_phase = advance_phase(left_phase, 440, sample_rate)
            right_phase = advance_phase(right_phase, 880, sample_rate)

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
    )
    parser.add_argument(
        "--sample-rate",
        type=int,
        choices=(44_100, 48_000),
        default=48_000,
    )
    args = parser.parse_args()
    rate_name = "48k" if args.sample_rate == 48_000 else "44k1"
    output = args.output or Path(f"build/phosphor-wav-test-{rate_name}.wav")
    generate(output, args.sample_rate)


if __name__ == "__main__":
    main()
