#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Run an AE350 program on the merged image over the single FT2232 cable.

Thin driver around tools/fpga_uart.py: it routes stream/debug to the CPU,
restarts the loader, streams a packaged .tpi program, and polls for
completion. This is the same flow as `tools/ae350_run.py --direct --base
0x4000 --cpu run <tpi>`, kept as a small one-purpose command.

Usage:
  scripts/mp3_single_cable.py --tpi build/rbhost/bench/mp3play.tpi
"""
import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import fpga_uart

CPU_MODE = 0x00A8          # player debug register, bit 0 routes stream/debug to CPU
STATE = 0x4020             # AE350 loader state (BASE 0x4000 + 0x20)
RESTART = 0x43F0           # AE350 loader restart (BASE 0x4000 + 0x3f0)
STATE_WAIT = 0x01


def wait_state(port, pred, timeout, what):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        state = fpga_uart.peek(port, STATE)[1]
        if pred(state):
            return state
        time.sleep(0.05)
    raise TimeoutError(what)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--baud", type=int, default=2_000_000)
    ap.add_argument("--tpi", required=True)
    ap.add_argument("--timeout", type=float, default=120.0)
    args = ap.parse_args()

    port = fpga_uart.open_port(args.port, args.baud)
    print(f"tpi       {args.tpi} ({Path(args.tpi).stat().st_size} bytes)")

    fpga_uart.poke(port, CPU_MODE, 1)
    fpga_uart.poke(port, RESTART, 1)
    time.sleep(0.01)
    wait_state(port, lambda s: (s & 0xFF) == STATE_WAIT, args.timeout,
               "loader did not reach WAIT")

    before = fpga_uart.peek(port, STATE)[1]
    before_runs = before >> 16
    print(f"state     before run: 0x{before & 0xff:02x} (runs {before_runs})")

    t0 = time.monotonic()
    n = fpga_uart.stream_file(port, args.tpi, progress=lambda off, total, dt:
                              print(f"  streamed {off}/{total} bytes "
                                    f"({off / dt / 1024:.1f} KiB/s)"))
    print(f"streamed  {n} bytes in {time.monotonic() - t0:.1f} s")

    final = wait_state(port, lambda s: (s >> 16) != before_runs or (s & 0xFF) >= 0x81,
                       args.timeout, "program did not complete")
    print(f"finished  {time.monotonic() - t0:.1f} s after stream start")
    print(f"state     0x{final & 0xff:02x} (runs {final >> 16}, result 0x{final:08x})")

    fpga_uart.poke(port, CPU_MODE, 0)
    print("done      cpu_mode cleared")
    return 0


if __name__ == "__main__":
    sys.exit(main())
