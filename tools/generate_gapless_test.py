#!/usr/bin/env python3
"""Generate Tang-Phosphor's deterministic gapless playlist test.

One continuous stereo tone (440 Hz left, 660 Hz right) is split into six
tracks at sample counts that are not multiples of the 4,096-sample FLAC block
size. Track 3 is a WAV, so the seams cover FLAC->WAV and WAV->FLAC as well as
FLAC->FLAC. Every FLAC carries a distinct baseline-JPEG cover and 256 KiB of
PADDING, standing in for large embedded artwork that Tang-Control must not
send over the FPGA UART. Any inserted silence or discontinuity is audible as a
click in the otherwise steady tone.

Requires the `flac` and `metaflac` command-line tools and Pillow.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import math
import struct
import subprocess
import tempfile
import wave
from pathlib import Path

from PIL import Image, ImageDraw

SAMPLE_RATE = 44_100
AMPLITUDE = 8_192
TRACK_SAMPLES = [220_501, 187_003, 251_117, 199_999, 230_411, 176_437]
WAV_TRACK = 3
PADDING_BYTES = 256 * 1024
ALBUM = "Phosphor Gapless Test"
ARTIST = "Tang-Phosphor"
COVER_COLOURS = ["#c03030", "#c08030", "#30a040", "#3080c0", "#6040c0", "#c040a0"]


def tone(start: int, count: int) -> bytes:
    frames = bytearray()
    for index in range(start, start + count):
        left = round(AMPLITUDE * math.sin(2 * math.pi * 440 * index / SAMPLE_RATE))
        right = round(AMPLITUDE * math.sin(2 * math.pi * 660 * index / SAMPLE_RATE))
        frames += struct.pack("<hh", left, right)
    return bytes(frames)


def write_wav(path: Path, frames: bytes) -> None:
    with wave.open(str(path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(frames)


def write_cover(path: Path, number: int) -> None:
    image = Image.new("RGB", (240, 240), COVER_COLOURS[number - 1])
    draw = ImageDraw.Draw(image)
    draw.rectangle((70, 70, 170, 170), fill="#f0f0f0")
    draw.text((112, 112), str(number), fill="#000000")
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90, progressive=False)
    path.write_bytes(buffer.getvalue())


def encode_flac(source: Path, target: Path, cover: Path, number: int) -> None:
    subprocess.run(
        [
            "flac", "--silent", "--force", "--verify", "-5", "--no-seektable",
            f"--padding={PADDING_BYTES}",
            f"--tag=ALBUM={ALBUM}", f"--tag=ARTIST={ARTIST}",
            f"--tag=TITLE=Segment {number}", f"--tag=TRACKNUMBER={number}",
            f"--output-name={target}", str(source),
        ],
        check=True,
    )
    subprocess.run(
        ["metaflac", "--dont-use-padding", f"--import-picture-from=3||Cover {number}||{cover}",
         str(target)],
        check=True,
    )


def decoded_frames(path: Path, scratch: Path) -> bytes:
    if path.suffix == ".wav":
        with wave.open(str(path), "rb") as source:
            return source.readframes(source.getnframes())
    decoded = scratch / f"{path.stem}-decoded.wav"
    subprocess.run(["flac", "--silent", "--force", "--decode",
                    f"--output-name={decoded}", str(path)], check=True)
    with wave.open(str(decoded), "rb") as source:
        return source.readframes(source.getnframes())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("output_dir", type=Path,
                        help="directory to receive the tracks and playlist")
    args = parser.parse_args()
    output_dir: Path = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    names: list[str] = []
    reference = bytearray()
    start = 0
    with tempfile.TemporaryDirectory() as scratch_name:
        scratch = Path(scratch_name)
        for number, count in enumerate(TRACK_SAMPLES, start=1):
            frames = tone(start, count)
            reference += frames
            start += count
            if number == WAV_TRACK:
                name = f"gapless-{number:02d}.wav"
                write_wav(output_dir / name, frames)
            else:
                name = f"gapless-{number:02d}.flac"
                source = scratch / f"{number}.wav"
                cover = scratch / f"{number}.jpg"
                write_wav(source, frames)
                write_cover(cover, number)
                encode_flac(source, output_dir / name, cover, number)
            names.append(name)

        # The concatenated decode must be the uninterrupted source signal.
        joined = b"".join(decoded_frames(output_dir / name, scratch) for name in names)
        if joined != bytes(reference):
            raise SystemExit("decoded tracks do not reproduce the continuous source")

    write_wav(output_dir / "gapless-reference.wav", bytes(reference))
    playlist = ["#EXTM3U"]
    for number, (name, count) in enumerate(zip(names, TRACK_SAMPLES), start=1):
        playlist.append(f"#EXTINF:{count // SAMPLE_RATE},{ARTIST} - Segment {number}")
        playlist.append(name)
    (output_dir / "gapless.m3u8").write_text("\n".join(playlist) + "\n", encoding="utf-8")

    for name in [*names, "gapless.m3u8", "gapless-reference.wav"]:
        data = (output_dir / name).read_bytes()
        print(f"{hashlib.sha256(data).hexdigest()}  {len(data):>8}  {name}")


if __name__ == "__main__":
    main()
