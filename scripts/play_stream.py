#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Play an audio file through the resident AE350 player over one wire.

Streams the resident player .tpi (codec embedded, input received by stream),
then the raw audio file, then polls for the AE350 to finish decode+play.
"""
import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import fpga_uart

CPU_MODE = 0x00C0
STATE = 0x4020
RESTART = 0x43F0
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
    ap.add_argument("--tpi", required=True, help="resident player program")
    ap.add_argument("--input", required=True, help="audio file to stream")
    ap.add_argument("--timeout", type=float, default=300.0)
    args = ap.parse_args()

    port = fpga_uart.open_port(args.port, args.baud)
    print(f"player    {args.tpi} ({Path(args.tpi).stat().st_size} bytes)")
    print(f"audio     {args.input} ({Path(args.input).stat().st_size} bytes)")

    fpga_uart.poke(port, CPU_MODE, 1)
    fpga_uart.poke(port, RESTART, 1)
    time.sleep(0.01)
    wait_state(port, lambda s: (s & 0xFF) == STATE_WAIT, args.timeout,
               "loader did not reach WAIT")

    before = fpga_uart.peek(port, STATE)[1]
    before_runs = before >> 16

    t0 = time.monotonic()
    n = fpga_uart.stream_file(port, args.tpi,
                              progress=lambda o, t, d: print(
                                  f"  program {o}/{t} bytes ({o/(d or 1)/1024:.1f} KiB/s)",
                                  end="\r", flush=True))
    print(f"\nprogram   {n} bytes in {time.monotonic() - t0:.1f} s")

    # The resident player now blocks waiting for the audio stream.
    t1 = time.monotonic()
    n2 = fpga_uart.stream_file(port, args.input,
                               progress=lambda o, t, d: print(
                                   f"  audio {o}/{t} bytes ({o/(d or 1)/1024:.1f} KiB/s)",
                                   end="\r", flush=True))
    print(f"\naudio     {n2} bytes in {time.monotonic() - t1:.1f} s")

    final = wait_state(port, lambda s: (s >> 16) != before_runs or (s & 0xFF) >= 0x81,
                       args.timeout, "program did not complete")
    print(f"finished  {time.monotonic() - t0:.1f} s after program stream start")
    print(f"state     0x{final & 0xff:02x} (runs {final >> 16}, result 0x{final:08x})")

    fpga_uart.poke(port, CPU_MODE, 0)
    print("done      cpu_mode cleared")
    return 0


if __name__ == "__main__":
    sys.exit(main())
