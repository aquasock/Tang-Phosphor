#!/usr/bin/env python3
"""Generate deterministic FLAC and reference PCM vectors for RTL tests."""

from __future__ import annotations

import argparse
import math
import random
import struct
import subprocess
import wave
from pathlib import Path


def write_vector(
    output_dir: Path,
    name: str,
    sample_rate: int,
    samples: list[tuple[int, int]],
    encoder_options: list[str],
) -> None:
    wav_path = output_dir / f"{name}.wav"
    raw_path = output_dir / f"{name}.raw"
    flac_path = output_dir / f"{name}.flac"
    payload = b"".join(struct.pack("<hh", left, right) for left, right in samples)

    raw_path.write_bytes(payload)
    with wave.open(str(wav_path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(sample_rate)
        output.writeframes(payload)

    subprocess.run(
        [
            "flac",
            "--silent",
            "--verify",
            "--force",
            "--no-seektable",
            "--no-padding",
            *encoder_options,
            f"--output-name={flac_path}",
            str(wav_path),
        ],
        check=True,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    correlated: list[tuple[int, int]] = []
    for index in range(5000):
        ramp = ((index * 197) & 0x7FFF) - 0x4000
        left = max(-32768, min(32767, ramp + (3000 if index & 32 else -3000)))
        right = max(-32768, min(32767, left - ((index % 17) - 8) * 11))
        correlated.append((left, right))
    write_vector(args.output_dir, "lpc44", 44_100, correlated, ["-8", "-b", "4096", "-m"])

    generator = random.Random(0x50484F53)
    noisy = [
        (generator.randrange(-32768, 32768), generator.randrange(-32768, 32768))
        for _ in range(1152)
    ]
    write_vector(args.output_dir, "fixed48", 48_000, noisy,
                 ["-0", "-b", "192", "--no-mid-side"])

    constant = [(0x1234, -0x2345)] * 192
    write_vector(args.output_dir, "constant44", 44_100, constant,
                 ["-0", "-b", "192", "--no-mid-side"])

    # One continuous signal split between two files at a sample that is not a
    # frame boundary. Gapless playback must reproduce it without a seam.
    continuous = [
        (round(12000 * math.sin(index * 0.031)),
         round(9000 * math.sin(index * 0.047 + 1.0)))
        for index in range(700)
    ]
    write_vector(args.output_dir, "gapless_a44", 44_100, continuous[:333],
                 ["-5", "-b", "192"])
    write_vector(args.output_dir, "gapless_b44", 44_100, continuous[333:],
                 ["-5", "-b", "192"])

    rejected = [(index - 96, 96 - index) for index in range(192)]
    write_vector(args.output_dir, "profile96", 96_000, rejected,
                 ["-0", "-b", "192", "--no-mid-side"])

    corrupt = bytearray((args.output_dir / "lpc44.flac").read_bytes())
    corrupt[-1] ^= 0x01
    (args.output_dir / "crc-corrupt.flac").write_bytes(corrupt)


if __name__ == "__main__":
    main()
