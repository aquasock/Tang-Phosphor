#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Check O-Scope fixtures, queue health and shared native audio on TinyTang.

Generate/upload tools/make_scope_fixtures.py's WAV files and load oscope.tdsh
first. Visual geometry and sound still require observation on the hardware.
"""
import argparse
from pathlib import Path
import re
import sys
import time

import serial


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--port', default='/dev/ttyACM0')
    ap.add_argument('--tinytang-tools', type=Path,
                    default=Path(__file__).resolve().parents[2] / 'TinyTang/tools')
    ap.add_argument('--seconds', type=int, default=4,
                    help='must match the generated fixtures')
    args = ap.parse_args()
    if not 1 <= args.seconds <= 60:
        ap.error('duration must be 1 to 60 seconds')
    sys.path.insert(0, str(args.tinytang_tools))
    from phosphor_format_sweep import DONE, run
    from tinytang_console import require_shell

    def peek(port, address):
        out = run(port, f'phosphor peek {address:#x}', 5)
        match = re.search(r'0x[0-9a-f]+: 0x([0-9a-f]+) \(status 0\)', out)
        if not match:
            raise RuntimeError(f'register read failed: {out}')
        return int(match[1], 16)

    plan = [(shape, 48000) for shape in
            ('circle', 'diagonal', 'opposite', 'horizontal', 'vertical', 'lissajous')]
    plan += [('circle', 44100)]
    failures = 0
    with serial.Serial(args.port, 115200, timeout=.3, write_timeout=30) as port:
        require_shell(port)
        if peek(port, 4) != 0x1000a or not (peek(port, 0xac) & 1):
            raise RuntimeError('load oscope.tdsh first: requires ABI 1.10 and scope enabled')
        for shape, rate in plan:
            require_shell(port)
            drops_before, sweeps_before = peek(port, 0xb0), peek(port, 0xb8)
            out = run(port, f'phosphor play /music/scope-{shape}-{rate}.wav',
                      args.seconds + 30)
            match = DONE.search(out.encode())
            if not match:
                print(f'FAIL {shape}/{rate}: {out}', flush=True)
                failures += 1
                continue
            count, underruns, actual_rate = map(int, match.groups())
            status, drops, sweeps = (peek(port, address) for address in (0xb4, 0xb0, 0xb8))
            time.sleep(.2)
            clock_status, mclk = peek(port, 0xfc), peek(port, 0xf8)
            expected_mclk = 1228800 if rate == 48000 else 1128960
            ok = (count == args.seconds * rate and underruns == 0 and
                  actual_rate == rate and status & 3 == 3 and
                  drops == drops_before and sweeps != sweeps_before and
                  clock_status == (0x1f if rate == 48000 else 0x17) and
                  abs(mclk - expected_mclk) <= 4)
            failures += not ok
            print(f"{'PASS' if ok else 'FAIL'} {shape:10s} {rate}: "
                  f'{count} samples, {underruns} underruns, '
                  f'{(drops-drops_before) & 0xffffffff} visual drops, '
                  f'{(sweeps-sweeps_before) & 0xffffffff} sweeps, '
                  f'scope {status:#x}, clock {clock_status:#x}/{mclk}', flush=True)
    print('scope fixtures:', 'PASS' if failures == 0 else f'FAIL ({failures})')
    return int(failures != 0)


if __name__ == '__main__':
    sys.exit(main())
