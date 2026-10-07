#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Qualify PCM counts, underruns and measured I2S2 clocks on the board.

Load tools/i2s2-play.tdsh first. Requires pyserial and the sibling TinyTang
checkout's tools (override with --tinytang-tools). Its console guard confirms
a shell prompt before any command is sent. Listen to Line Out during the run.
"""
import argparse
from pathlib import Path
import re
import sys
import time

import serial


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", default="/dev/ttyACM0")
    ap.add_argument("--tinytang-tools", type=Path,
                    default=Path(__file__).resolve().parents[2] / "TinyTang/tools")
    ap.add_argument("--only", help="comma-separated formats in playback order")
    args = ap.parse_args()
    sys.path.insert(0, str(args.tinytang_tools))
    from phosphor_format_sweep import DONE, EXPECTED, run
    from tinytang_console import require_shell

    expected = {ext: (441000 if ext == "flac" else count, rate)
                for ext, count, rate in EXPECTED}
    plan = args.only.split(",") if args.only else list(expected) + ["wav"]
    if any(ext not in expected for ext in plan):
        ap.error("unknown corpus format")

    def peek(port, address):
        out = run(port, f"phosphor peek {address:#x}", 5)
        match = re.search(r"0x[0-9a-f]+: 0x([0-9a-f]+) \(status 0\)", out)
        if not match:
            raise RuntimeError(f"register read failed: {out}")
        return int(match[1], 16)

    failures = 0
    with serial.Serial(args.port, 115200, timeout=.3, write_timeout=30) as port:
        require_shell(port)
        if peek(port, 4) not in (0x10009, 0x1000a):
            raise RuntimeError("requires the I2S2 PCM playback image, ABI 1.9/1.10")
        for ext in plan:
            require_shell(port)
            out = run(port, f"phosphor play /music/test.{ext}", 60)
            match = DONE.search(out.encode())
            if not match:
                print(f"FAIL {ext}: {out}", flush=True)
                failures += 1
                continue
            count, underruns, rate = map(int, match.groups())
            # Wait for a complete 100 ms MCLK measurement after any switch.
            time.sleep(.2)
            status, mclk = peek(port, 0xfc), peek(port, 0xf8)
            expected_status = 0x1f if rate == 48000 else 0x17
            expected_mclk = 1228800 if rate == 48000 else 1128960
            ok = ((count, rate) == expected[ext] and underruns == 0 and
                  status == expected_status and abs(mclk - expected_mclk) <= 4)
            failures += not ok
            print(f"{'PASS' if ok else 'FAIL'} {ext:5s}: {count} samples, "
                  f"{underruns} underruns, {rate} Hz, "
                  f"MCLK count {mclk}, status {status:#x}", flush=True)
    print("sweep:", "PASS" if failures == 0 else f"FAIL ({failures})")
    return int(failures != 0)


if __name__ == "__main__":
    sys.exit(main())
