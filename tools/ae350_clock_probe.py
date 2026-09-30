#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Measure the AE350 A25 core clock on the running AE350 smoke image.

The smoke firmware continuously stores its mcycle count to the fabric, which
pairs each value with a count of the 50 MHz board oscillator.  This tool
freezes a pair (debug write 0x10), reads it back (0x04 and 0x08), and derives
the core frequency from consecutive pairs.  The oscillator is independent of
the AE350 PLL, so the result does not depend on the PLL configuration being
what the netlist claims.

Uses Tang-Control's tangctl.py from the sibling repository by default.
"""

import argparse
import contextlib
import io
import os
import sys
import time
from pathlib import Path

REF_HZ = 50_000_000
MASK = 0xFFFF_FFFF


def load_tangctl(path):
    sys.path.insert(0, str(Path(path).resolve()))
    import tangctl  # noqa: E402
    return tangctl


def command(tangctl, port, text):
    with contextlib.redirect_stdout(io.StringIO()):
        return tangctl.run_command(port, text)


def sample(tangctl, port):
    command(tangctl, port, "poke 0x00000010 0x00000000")
    host_time = time.monotonic()
    words = {}
    for line in command(tangctl, port, "peek 0x00000000 4"):
        address, value = line.split(":")
        words[int(address, 16)] = int(value, 16)
    return host_time, words[0x0], words[0x4], words[0x8], words[0xC]


def main():
    default_tangctl = Path(__file__).resolve().parents[2] / "Tang-Control" / "scripts"
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", help="Tang-Control serial device; auto-detected when omitted")
    parser.add_argument("--tangctl-dir", default=os.environ.get("TANGCTL_DIR", default_tangctl))
    parser.add_argument("--samples", type=int, default=6)
    parser.add_argument("--interval", type=float, default=2.0,
                        help="seconds between pairs; keep below 2^32 / f_cpu (5.7 s at 750 MHz)")
    args = parser.parse_args()

    tangctl = load_tangctl(args.tangctl_dir)
    port_path = args.port or tangctl.find_port()
    if port_path is None:
        raise SystemExit("Tang-Control serial device not found")

    results = []
    with tangctl.open_port(port_path) as port:
        previous = sample(tangctl, port)
        if previous[1] & 1 == 0:
            raise SystemExit("AE350 has not reported start (debug word 0 is 0)")
        for _ in range(args.samples):
            time.sleep(args.interval)
            current = sample(tangctl, port)
            host_dt = current[0] - previous[0]
            cpu_delta = (current[2] - previous[2]) & MASK
            ref_delta = (current[3] - previous[3]) & MASK
            writes = (current[4] - previous[4]) & MASK
            if ref_delta == 0 or writes == 0:
                raise SystemExit("cycle-count pair did not advance; firmware is not running its loop")
            cpu_hz = cpu_delta * REF_HZ / ref_delta
            ref_dt = ref_delta / REF_HZ
            # A wrapped mcycle delta would disagree with the host's own clock.
            host_hz = cpu_delta / host_dt
            results.append(cpu_hz)
            print(f"ref {ref_dt:.4f} s  core cycles {cpu_delta:10d}  writes {writes:9d}  "
                  f"f_cpu {cpu_hz / 1e6:9.4f} MHz  (host-timed {host_hz / 1e6:8.2f} MHz)")
            previous = current

    mean = sum(results) / len(results)
    spread = max(results) - min(results)
    print(f"mean f_cpu {mean / 1e6:.4f} MHz over {len(results)} intervals, "
          f"spread {spread / 1e3:.3f} kHz, reference {REF_HZ / 1e6:.0f} MHz board oscillator")


if __name__ == "__main__":
    main()
