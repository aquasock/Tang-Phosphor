#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Check Rockbox codecs on RV32 and estimate their AE350 CPU load.

For each format, an excerpt of SOURCE is encoded with FFmpeg and decoded by
the RV32 rbhost under qemu-riscv32.  Correctness: the raw codec output (-r)
must equal x86 warble's, and for lossless formats the 16-bit DSP output must
equal FFmpeg's decode.  Performance: QEMU's contrib cache plugin models the
A25's 32 KiB 4-way 32-byte-line L1 caches (.ai/core-reference.md, Tang-PSX
AE350-004) and a 128 KiB direct-mapped L2 like Tang-PSX's fabric L2; the
instruction and miss counts are turned into a CPU-load range at 750 MHz for
each memory option.

A codec's end-of-stream status is recorded, and the RV32 and x86 decoders
must agree on it.  Opus is deferred: its RV32 output is not bit-identical to
x86 warble (see .ai/core-log.md).

The range brackets what the model cannot see: the best case assumes one
cycle per instruction and no dirty-line write-backs, the worst case 1.5
cycles per instruction and a write-back of equal cost for every data miss.
Miss costs are Tang-PSX hardware measurements (AE350-009/010) except the
SDRAM figure, which is an unmeasured estimate for a burst controller on the
16-bit Tang SDRAM module.

Prerequisites: `make -C software/rbhost`, tools/build-qemu-cache-model.sh,
and an x86 warble build of the same Rockbox revision (--warble).
"""

import argparse
import hashlib
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEV = Path.home() / ".cache" / "tang-phosphor-dev" / "qemu-10.2.1" / "build"
CPU_HZ = 750e6

# name, container suffix, FFmpeg encoder arguments, lossless
FORMATS = [
    ("flac",    "flac", ["-c:a", "flac"], True),
    ("alac",    "m4a",  ["-c:a", "alac"], True),
    ("wavpack", "wv",   ["-c:a", "wavpack"], True),
    ("tta",     "tta",  ["-c:a", "tta"], True),
    ("mp3-320", "mp3",  ["-c:a", "libmp3lame", "-b:a", "320k"], False),
    ("mp3-v2",  "mp3",  ["-c:a", "libmp3lame", "-q:a", "2"], False),
    ("mp2-256", "mp2",  ["-c:a", "mp2", "-b:a", "256k"], False),
    ("vorbis-q6", "ogg", ["-c:a", "libvorbis", "-q:a", "6"], False),
    ("aac-256", "m4a",  ["-c:a", "aac", "-b:a", "256k"], False),
    ("wma-192", "wma",  ["-c:a", "wmav2", "-b:a", "192k"], False),
    ("ac3-448", "ac3",  ["-c:a", "ac3", "-b:a", "448k"], False),
]

# option name: (L1 miss cost served by L2, L1+L2 miss cost), in core cycles
MEMORY = {
    "DDR3":        (570, 570),
    "SDRAM (est)": (425, 425),
    "L2+DDR3":     (240, 570),
    "L2+SDRAM":    (240, 425),
}

CACHE_ARGS = ("dcachesize=32768,dassoc=4,dblksize=32,"
              "icachesize=32768,iassoc=4,iblksize=32,evict=lru,"
              "l2=on,l2cachesize=131072,l2assoc=1,l2blksize=32,limit=16")


def run(command, check=True, **kwargs):
    return subprocess.run(command, check=check, capture_output=True, **kwargs)


def rbhost(args, qemu, extra=()):
    build = args.build
    return run([str(qemu), *extra, str(build / "rbhost-qemu"), *args.raw_flag,
                str(build / "codecs"), *args.io], check=False)


def codec_error(completed):
    return b"error: codec error" in completed.stderr


def decode_info(stderr):
    text = stderr.decode("ascii", "replace")
    frequency = int(re.search(r"Frequency: (\d+)", text).group(1))
    samples = int(re.search(r"Samples: (\d+)", text).group(1))
    return frequency, samples


def cache_summary(log):
    lines = log.read_text().splitlines()
    values = lines[1].split()
    return {
        "instructions": int(values[4]),
        "data_accesses": int(values[1]),
        "data_misses": int(values[2]),
        "instruction_misses": int(values[5]),
        "l2_accesses": int(values[7]),
        "l2_misses": int(values[8]),
        "top_misses": [line for line in lines[3:3 + 8]],
    }


def estimate(summary, seconds):
    l1 = summary["data_misses"] + summary["instruction_misses"]
    l2 = summary["l2_misses"]
    loads = {}
    for name, (l2_hit, l2_miss) in MEMORY.items():
        miss_cycles = (l1 - l2) * l2_hit + l2 * l2_miss if "L2" in name \
            else l1 * l2_miss
        data_cycles = (summary["data_misses"] / l1) * miss_cycles if l1 else 0
        best = summary["instructions"] * 1.0 + miss_cycles
        worst = summary["instructions"] * 1.5 + miss_cycles + data_cycles
        loads[name] = (100 * best / (seconds * CPU_HZ),
                       100 * worst / (seconds * CPU_HZ))
    return loads


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", type=Path, help="audio file FFmpeg can read")
    parser.add_argument("--start", type=float, default=60.0)
    parser.add_argument("--duration", type=float, default=60.0)
    parser.add_argument("--formats", help="comma-separated subset")
    parser.add_argument("--build", type=Path, default=ROOT / "build/rbhost")
    parser.add_argument("--warble", type=Path, required=True,
                        help="x86 warble binary built from third_party/rockbox")
    parser.add_argument("--qemu", type=Path, default=Path("qemu-riscv32"))
    parser.add_argument("--plugin-qemu", type=Path, default=DEV / "qemu-riscv32")
    parser.add_argument("--plugin", type=Path,
                        default=DEV / "contrib/plugins/libcache.so")
    parser.add_argument("--json", type=Path, help="write results here")
    args = parser.parse_args()
    args.warble = args.warble.resolve()
    args.build = args.build.resolve()
    args.source = args.source.resolve()

    selected = set(args.formats.split(",")) if args.formats else None
    source_sha = hashlib.sha256(args.source.read_bytes()).hexdigest()
    results = {"source": str(args.source), "source_sha256": source_sha,
               "start": args.start, "duration": args.duration, "formats": {}}
    failures = 0

    with tempfile.TemporaryDirectory(prefix="rbhost-profile-") as temporary:
        work = Path(temporary)
        reference = work / "reference.pcm"
        run(["ffmpeg", "-v", "error", "-ss", str(args.start), "-t",
             str(args.duration), "-i", str(args.source), "-ac", "2",
             "-f", "s16le", str(reference)])
        wav = work / "excerpt.wav"
        run(["ffmpeg", "-v", "error", "-f", "s16le", "-ar",
             "44100", "-ac", "2", "-i", str(reference), str(wav)])

        for name, suffix, encoder, lossless in FORMATS:
            if selected and name not in selected:
                continue
            encoded = work / f"{name}.{suffix}"
            run(["ffmpeg", "-v", "error", "-i", str(wav), *encoder,
                 "-map_metadata", "-1", str(encoded)])
            entry = {"bytes": encoded.stat().st_size}

            rv32_raw, x86_raw = work / f"{name}.rv32.r32", work / f"{name}.x86.r32"
            args.raw_flag, args.io = ["-r"], [str(encoded), str(rv32_raw)]
            completed = rbhost(args, args.qemu)
            frequency, samples = decode_info(completed.stderr)
            x86 = run([str(args.warble), "-r", str(encoded), str(x86_raw)],
                      check=False, cwd=args.warble.parent)
            entry["codec_error"] = codec_error(completed)
            entry["status_matches_warble"] = codec_error(completed) == codec_error(x86)
            entry["raw_matches_warble"] = rv32_raw.read_bytes() == x86_raw.read_bytes()

            dsp = work / f"{name}.rv32.wav"
            args.raw_flag, args.io = [], [str(encoded), str(dsp)]
            log = work / f"{name}.cache.log"
            rbhost(args, args.plugin_qemu,
                   ["-plugin", f"{args.plugin},{CACHE_ARGS}", "-d", "plugin",
                    "-D", str(log)])
            if lossless:
                entry["pcm_matches_source"] = \
                    dsp.read_bytes()[0x2e:] == reference.read_bytes()

            seconds = samples / frequency
            summary = cache_summary(log)
            entry.update(frequency=frequency, samples=samples, seconds=seconds,
                         cache=summary, load_percent=estimate(summary, seconds))
            results["formats"][name] = entry
            ok = entry["raw_matches_warble"] and entry["status_matches_warble"] \
                and entry.get("pcm_matches_source", True)
            failures += not ok
            loads = entry["load_percent"]
            print(f"{name:10s} {'PASS' if ok else 'FAIL'} "
                  f"{summary['instructions'] / seconds / 1e6:6.1f} Minsn/s "
                  f"{summary['data_misses'] / seconds / 1e3:6.1f} kDmiss/s "
                  f"{summary['instruction_misses'] / seconds / 1e3:6.1f} kImiss/s "
                  f"L2miss {100 * summary['l2_misses'] / max(1, summary['l2_accesses']):4.1f}% | " +
                  "  ".join(f"{option} {low:4.1f}-{high:4.1f}%"
                            for option, (low, high) in loads.items()),
                  flush=True)

    if args.json:
        args.json.write_text(json.dumps(results, indent=2) + "\n")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
