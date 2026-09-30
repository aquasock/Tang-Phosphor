#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Run Rockbox codecs on the AE350 and compare them with QEMU and the model.

  prepare SOURCE [--start S] [--duration S] [--formats a,b]
      Encode an excerpt of SOURCE in each format of tools/rbhost_profile.py,
      build one benchmark image per format (`make -C software/rbhost bench`:
      rbhost with that codec and input embedded, decoding through the DSP to
      a RAM buffer), and run the same program under qemu-riscv32 for its
      reference exit status, output size and CRC-32, and the Linux build of
      rbhost on the same file under the cache model for the instruction count
      and estimated load.  Writes build/rbbench/manifest.json.
  upload
      Copy the images to the SD card (TangCore main menu only).
  run [--formats a,b]
      With the AE350 + DDR3 image running, run each image, require the same
      exit status, output size and CRC-32 as QEMU, and report the measured
      A25 load at 750 MHz against the model's range.  Writes
      build/rbbench/results.json.

Prerequisites: `make -C software/rbhost`, tools/build-qemu-cache-model.sh,
and tools/ae350_run.py's Tang-Control setup for upload and run.
"""

import argparse
import contextlib
import io
import json
import re
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import ae350_run  # noqa: E402
import rbhost_profile  # noqa: E402

OUT = ROOT / "build/rbbench"
BUILD = ROOT / "build/rbhost"
TOOLCHAIN = Path("/home/vash/.cache/tangcore-dev/toolchain/bin")
CPU_HZ = 750e6

# Rockbox codec (codec_root_fn) for each format.
CODECS = {
    "flac": "flac", "alac": "alac", "wavpack": "wavpack", "tta": "tta",
    "mp3-320": "mpa", "mp3-v2": "mpa", "mp2-256": "mpa", "vorbis-q6": "vorbis",
    "aac-256": "aac", "wma-192": "wma", "ac3-448": "a52",
}


def run(command, **kwargs):
    return subprocess.run(command, check=True, capture_output=True, **kwargs)


def parse_harness(text):
    """Log and result registers printed by software/rbhost/host/bench_qemu.c."""
    log = text.split("log:\n", 1)[1].split("result ", 1)[0]
    user = [int(v, 16) for v in re.findall(r"^user   ([0-9a-f]{8})$", text, re.M)]
    return log, user


def log_info(log):
    frequency = re.search(r"Frequency: (\d+)", log)
    samples = re.search(r"Samples: (\d+)", log)
    return (int(frequency.group(1)) if frequency else 0,
            int(samples.group(1)) if samples else 0)


def command_prepare(args):
    OUT.mkdir(parents=True, exist_ok=True)
    source = args.source.resolve()
    selected = set(args.formats.split(",")) if args.formats else None
    env = {"PATH": f"{TOOLCHAIN}:" + __import__("os").environ["PATH"]}
    env = {**__import__("os").environ, **env}
    manifest = {"source": str(source), "start": args.start, "duration": args.duration,
                "formats": {}}
    with tempfile.TemporaryDirectory(prefix="rbbench-") as temporary:
        work = Path(temporary)
        pcm = work / "excerpt.pcm"
        run(["ffmpeg", "-v", "error", "-ss", str(args.start), "-t", str(args.duration),
             "-i", str(source), "-ac", "2", "-ar", "44100", "-f", "s16le", str(pcm)])
        wav = work / "excerpt.wav"
        run(["ffmpeg", "-v", "error", "-f", "s16le", "-ar", "44100", "-ac", "2",
             "-i", str(pcm), str(wav)])
        for name, suffix, encoder, _lossless in rbhost_profile.FORMATS:
            if selected and name not in selected:
                continue
            encoded = OUT / f"{name}.{suffix}"
            run(["ffmpeg", "-v", "error", "-y", "-i", str(wav), *encoder,
                 "-map_metadata", "-1", str(encoded)])
            run(["make", "-C", str(ROOT / "software/rbhost"), "bench",
                 f"BENCH_NAME={name}", f"BENCH_CODEC={CODECS[name]}",
                 f"BENCH_INPUT={encoded}"], env=env)
            harness = BUILD / "bench" / f"{name}-qemu.elf"
            log, user = parse_harness(run(["qemu-riscv32", str(harness)]).stdout.decode())
            frequency, samples = log_info(log)
            # The model runs the Linux build of rbhost on the same file: like
            # the hardware measurement it covers main() only, without the
            # harness's output CRC.
            cache_log = work / f"{name}.cache.log"
            run([str(rbhost_profile.DEV / "qemu-riscv32"), "-plugin",
                 f"{rbhost_profile.DEV / 'contrib/plugins/libcache.so'},"
                 f"{rbhost_profile.CACHE_ARGS}", "-d", "plugin", "-D", str(cache_log),
                 str(BUILD / "rbhost-qemu"), str(BUILD / "codecs"), str(encoded),
                 str(work / f"{name}.wav")])
            summary = rbhost_profile.cache_summary(cache_log)
            seconds = samples / frequency if frequency else 0
            image = BUILD / "bench" / f"{name}.tpi"
            (OUT / image.name).write_bytes(image.read_bytes())
            manifest["formats"][name] = {
                "image": image.name, "input_bytes": encoded.stat().st_size,
                "status": user[0], "output_bytes": user[5], "output_crc": user[6],
                "qemu_instructions": summary["instructions"],
                "frequency": frequency, "samples": samples, "seconds": seconds,
                "cache": summary,
                "model_load_percent": rbhost_profile.estimate(summary, seconds) if seconds else {},
            }
            ddr3 = manifest["formats"][name]["model_load_percent"].get("DDR3", (0, 0))
            print(f"{name:10s} {image.stat().st_size:9d} bytes  status {user[0]}  "
                  f"out {user[5]} crc {user[6]:08x}  model DDR3 {ddr3[0]:.1f}-{ddr3[1]:.1f}%",
                  flush=True)
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return 0


def command_upload(args):
    manifest = json.loads((OUT / "manifest.json").read_text())
    images = [str(OUT / entry["image"]) for entry in manifest["formats"].values()]
    port = ae350_run.tangctl().open_port(args.port or ae350_run.tangctl().find_port())
    try:
        with contextlib.suppress(RuntimeError):
            ae350_run.quiet(port, f"mkdir {ae350_run.REMOTE_DIR}")
        for image in images:
            ae350_run.tangctl().run_put(port, image, f"{ae350_run.REMOTE_DIR}/{Path(image).name}")
    finally:
        port.close()
    return 0


def command_run(args):
    manifest = json.loads((OUT / "manifest.json").read_text())
    selected = set(args.formats.split(",")) if args.formats else None
    port = ae350_run.tangctl().open_port(args.port or ae350_run.tangctl().find_port())
    results = {"manifest": manifest, "formats": {}}
    failures = 0
    try:
        for name, entry in manifest["formats"].items():
            if selected and name not in selected:
                continue
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    args.remote, args.restart = entry["image"], True
                    code = ae350_run.command_run(args, port)
            except TimeoutError:
                code = 1
            status = ae350_run.read_status(port)
            user = status["user"]
            cycles = user[1] | user[2] << 32
            instructions = user[3] | user[4] << 32
            wall = (user[8] | user[9] << 32) / ae350_run.BUS_CLOCK_HZ
            reads, latency_sum, writes = user[10], user[11], user[12]
            ok = (code == 0 and user[0] == entry["status"] and
                  user[5] == entry["output_bytes"] and user[6] == entry["output_crc"])
            failures += not ok
            load = 100 * cycles / (entry["seconds"] * CPU_HZ) if entry["seconds"] else 0
            model = entry["model_load_percent"].get("DDR3", (0, 0))
            results["formats"][name] = {
                "ok": ok, "status": user[0], "output_bytes": user[5], "output_crc": user[6],
                "cycles": cycles, "instructions": instructions, "wall_seconds": wall,
                "bridge_reads": reads, "bridge_latency_sum": latency_sum,
                "bridge_writes": writes, "load_percent": load, "log": status["log"],
            }
            print(f"{name:10s} {'PASS' if ok else 'FAIL'}  load {load:5.2f}% "
                  f"(model DDR3 {model[0]:.1f}-{model[1]:.1f}%)  "
                  f"insn {instructions} (qemu {entry['qemu_instructions']})  "
                  f"CPI {cycles / instructions if instructions else 0:.3f}  "
                  f"reads {reads} (latency {latency_sum / reads if reads else 0:.1f} bus cycles)  "
                  f"writes {writes}", flush=True)
    finally:
        port.close()
    (OUT / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    return 1 if failures else 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0],
        epilog=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", help="serial device; auto-detected when omitted")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("prepare")
    p.add_argument("source", type=Path)
    p.add_argument("--start", type=float, default=60.0)
    p.add_argument("--duration", type=float, default=10.0)
    p.add_argument("--formats", help="comma-separated subset")
    sub.add_parser("upload")
    p = sub.add_parser("run")
    p.add_argument("--formats", help="comma-separated subset")
    p.add_argument("--timeout", type=float, default=120.0)
    args = parser.parse_args()
    if args.command == "prepare":
        return command_prepare(args)
    if args.command == "upload":
        return command_upload(args)
    return command_run(args)


if __name__ == "__main__":
    sys.exit(main())
