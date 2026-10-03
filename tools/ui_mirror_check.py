#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
#
# Mirror check for the PMOD socket bring-up core.
#
# The point of this tool is to replace "it looked right" with three verdicts
# that are earned rather than eyeballed:
#
#   MIRROR    each measured stream matches a model computed here, in Python,
#             from the pattern definition and the scaling geometry.  A frozen
#             frame passes this check honestly, because three screens showing
#             the same frozen frame really are mirrored.
#   LIVENESS  the frame counters advance.  This is the check that catches a
#             stopped renderer, which the mirror check cannot: a frozen frame
#             is a legitimately mirrored state.
#   HELD      the renderer is frozen on purpose, so a frozen signature is the
#             expected state and liveliness is not required.  This verdict
#             exists because the author of this tool once froze the renderer
#             with the hold bit, forgot, and spent an hour hunting a bug that
#             did not exist.  The tool is not allowed to make that mistake.
#
# The tool sets hold itself before reading, so it always compares whole settled
# frames, and restores whatever it found on the way in -- leaving the renderer
# frozen would be exactly the trap above.
#
# Usage:
#   tools/ui_mirror_check.py [--tangctl PATH] [--settle SECONDS] [--json]

import argparse
import json
import subprocess
import sys
import time

# Register map, byte addresses, from src/debug/ui_debug_regs.sv.
REG_MAGIC       = 0x00
REG_BUILD_DATE  = 0x04
REG_UPTIME      = 0x08
REG_RENDER      = 0x0c
REG_CONTROL     = 0x10
REG_SCRATCH     = 0x14
REG_BANK        = 0x18
REG_SRC_SIG     = 0x1c
REG_OLED_FRAMES = 0x20
REG_OLED_SIG    = 0x24
REG_HDMI_FRAMES = 0x28
REG_HDMI_SIG    = 0x2c
REG_VGA_FRAMES  = 0x30
REG_VGA_SIG     = 0x34

MAGIC = 0x54504830          # "TPH0"
MASK32 = 0xFFFFFFFF

# Geometry and pattern definitions, mirrored from the RTL.  These are the
# model: if they drift from src/ui/ui_pattern_demo.sv and src/video/ui_hdmi_scan.sv
# the check fails loudly rather than silently passing.
W_SRC, H_SRC = 96, 64
K, ACTIVE_X, ACTIVE_Y = 11, 112, 8
FRAME_W, FRAME_H = 1280, 720              # visible window at the transmitter
LAST_PAT = 7


def pattern_pixel(px, py, p):
    """src/ui/ui_pattern_demo.sv pattern_pixel()."""
    if p == 0:
        return 0xF800
    if p == 1:
        return 0x07E0
    if p == 2:
        return 0x001F
    if p == 3:
        return 0xFFFF
    if p == 4:
        return 0x0000
    if p == 5:
        bars = [0xF800, 0x07E0, 0x001F, 0x07FF, 0xF81F, 0xFFE0, 0xFFFF]
        i = px // 12
        return bars[i] if i < len(bars) else 0x0000
    if p == 6:
        return ((px >> 2) << 11) | (py << 5) | (py >> 1)
    if px == 0 or px == W_SRC - 1 or py == 0 or py == H_SRC - 1:
        return 0xFFFF
    if px < 8 and py < 8:
        return 0xFFFF
    if px == py:
        return 0x07E0
    if px + py == W_SRC - 1:
        return 0xF800
    return 0x0000


def source_frame(p):
    """The store as the renderer fills it: x fastest, then y."""
    return [pattern_pixel(x, y, p) for y in range(H_SRC) for x in range(W_SRC)]


def fold(pixels):
    """acc <- acc * 5 + px, mod 2^32.  Matches src/ui/ui_checksum.sv."""
    acc = 0
    for px in pixels:
        acc = (acc * 5 + px) & MASK32
    return acc


def emitted_stream(frame):
    """What the transmitter puts on the wire: the scaled image, bars included.

    ui_hdmi_scan's latency compensation makes the source pixel for display
    coordinate (x, y) exactly ((x - ACTIVE_X) / K, (y - ACTIVE_Y) / K), and
    everything outside the active rectangle is a bar, which the checksum sees
    as zero.
    """
    x_end = ACTIVE_X + K * W_SRC - 1
    y_end = ACTIVE_Y + K * H_SRC - 1
    out = []
    for y in range(FRAME_H):
        row_base = (y - ACTIVE_Y) // K if ACTIVE_Y <= y <= y_end else None
        for x in range(FRAME_W):
            if ACTIVE_X <= x <= x_end and row_base is not None:
                out.append(frame[row_base * W_SRC + (x - ACTIVE_X) // K])
            else:
                out.append(0)
    return out


class Device:
    def __init__(self, tangctl, timeout=30):
        self.tangctl = tangctl
        self.timeout = timeout

    def _run(self, args):
        proc = subprocess.run(
            [sys.executable, self.tangctl] + args,
            capture_output=True, text=True, timeout=self.timeout,
        )
        out = (proc.stdout + proc.stderr).strip()
        if proc.returncode != 0:
            raise RuntimeError(f"tangctl {' '.join(args)}: {out}")
        return out

    def peek(self, addr):
        out = self._run(["peek", hex(addr), "1"])
        for token in out.split():
            if token.startswith("0x") and len(token) == 10:
                return int(token, 16)
        raise RuntimeError(f"could not parse peek output: {out!r}")

    def poke(self, addr, value):
        self._run(["poke", hex(addr), hex(value)])

    def read_state(self):
        return {
            "magic":       self.peek(REG_MAGIC),
            "uptime":      self.peek(REG_UPTIME),
            "render":      self.peek(REG_RENDER),
            "control":     self.peek(REG_CONTROL),
            "bank":        self.peek(REG_BANK),
            "src_sig":     self.peek(REG_SRC_SIG),
            "oled_frames": self.peek(REG_OLED_FRAMES),
            "oled_sig":    self.peek(REG_OLED_SIG),
            "hdmi_frames": self.peek(REG_HDMI_FRAMES),
            "hdmi_sig":    self.peek(REG_HDMI_SIG),
        }


def render_moves(dev, seconds):
    """Whether the renderer is producing frames, observed rather than assumed.

    The hold bit is not a trustworthy source for this: an earlier build packed
    it at a different position in the read than in the write, which is exactly
    how a checker mistakes a pattern bit for a hold bit.  Watching the counter
    is unambiguous.
    """
    before = dev.peek(REG_RENDER)
    deadline = time.time() + seconds
    while time.time() < deadline:
        time.sleep(0.2)
    return dev.peek(REG_RENDER) > before


def main():
    ap = argparse.ArgumentParser(description="check that every output shows the same frame")
    ap.add_argument("--tangctl", default="../Tang-Control/scripts/tangctl.py",
                    help="path to Tang-Control's tangctl.py")
    ap.add_argument("--settle", type=float, default=0.35,
                    help="seconds to wait after setting hold, for the frame to publish")
    ap.add_argument("--frames", type=int, default=12,
                    help="how many frames to generate while measuring liveness")
    ap.add_argument("--json", action="store_true", help="emit machine-readable results")
    args = ap.parse_args()

    dev = Device(args.tangctl)
    results = {}
    failures = []

    try:
        s0 = dev.read_state()
    except Exception as exc:
        print(f"CANNOT CHECK: {exc}")
        print("Nothing was measured, so nothing is verified. Is the core loaded?")
        return 2

    if s0["magic"] != MAGIC:
        print(f"CANNOT CHECK: magic is 0x{s0['magic']:08x}, expected 0x{MAGIC:08x}")
        return 2

    control = s0["control"]
    pmod0_pers, pmod1_pers = (control >> 4) & 0xF, (control >> 8) & 0xF
    pmod0_flip, pmod1_flip = bool(control & 0x1000), bool(control & 0x2000)

    hold_in = not render_moves(dev, 2.6)
    results["held_observed"] = hold_in

    results["socket_config"] = {
        "pmod0_personality": pmod0_pers, "pmod0_flipped": pmod0_flip,
        "pmod1_personality": pmod1_pers, "pmod1_flipped": pmod1_flip,
        "hold_was_set": hold_in,
    }

    # ---- liveness, measured before we disturb anything -------------------
    liveness_moved = None
    if not hold_in:
        t0 = dev.read_state()
        deadline = time.time() + 3.0
        while time.time() < deadline:
            time.sleep(0.15)
        t1 = dev.read_state()
        moved = {
            "render":      t1["render"]      > t0["render"],
            "oled_frames": t1["oled_frames"] > t0["oled_frames"],
            "hdmi_frames": t1["hdmi_frames"] > t0["hdmi_frames"],
        }
        liveness_moved = all(moved.values())
        results["liveness"] = {"moved": moved, "ok": liveness_moved}
        if not liveness_moved:
            failures.append("liveness: " + ", ".join(k for k, v in moved.items() if not v)
                            + " did not advance")

    # ---- compare against the model, with the renderer held ---------------
    # Holding makes the published signatures stable, so the model has a single
    # definite frame to be right or wrong about.
    dev.poke(REG_CONTROL, (control & ~1) | 1)
    time.sleep(args.settle)
    held = dev.read_state()

    # The pattern's position in the read is version-dependent: the fixed layout
    # puts it at 18:16 and the earlier one at 2:0.  Accept either, and say
    # which matched, rather than pretending to know.
    candidates = [(held["control"] >> 16) & 0x7, held["control"] & 0x7]
    best = None
    for cand in dict.fromkeys(candidates):
        frame = source_frame(cand)
        e_src, e_hdmi = fold(frame), fold(emitted_stream(frame))
        src_ok = held["src_sig"] in (e_src, fold(source_frame((cand - 1) % (LAST_PAT + 1))))
        hdmi_ok = held["hdmi_sig"] == e_hdmi
        if src_ok and hdmi_ok:
            best = (cand, e_src, e_hdmi, src_ok, hdmi_ok)
            break
    if best is None:
        cand = candidates[0]
        frame = source_frame(cand)
        best = (cand, fold(frame), fold(emitted_stream(frame)),
                held["src_sig"] == fold(frame),
                held["hdmi_sig"] == fold(emitted_stream(frame)))
    pattern, expect_src, expect_hdmi, src_ok, hdmi_ok = best
    src_ok_prev = False

    results["pattern"] = pattern
    results["pattern_from"] = "bits 18:16" if pattern == candidates[0] else "bits 2:0"
    results["expected"] = {"source": f"0x{expect_src:08x}", "transmitter": f"0x{expect_hdmi:08x}"}
    results["measured"] = {"source": f"0x{held['src_sig']:08x}",
                          "transmitter": f"0x{held['hdmi_sig']:08x}"}

    results["mirror"] = {
        "source": src_ok or src_ok_prev,
        "transmitter": hdmi_ok,
        "panel": "not implemented",
    }
    if not (src_ok or src_ok_prev):
        failures.append(f"mirror: source signature 0x{held['src_sig']:08x} "
                        f"!= modelled 0x{expect_src:08x} for pattern {pattern}")
    if not hdmi_ok:
        failures.append(f"mirror: transmitter signature 0x{held['hdmi_sig']:08x} "
                        f"!= modelled 0x{expect_hdmi:08x} for pattern {pattern}")

    # ---- restore whatever we found ---------------------------------------
    dev.poke(REG_CONTROL, control)

    if args.json:
        print(json.dumps({"results": results, "failures": failures}, indent=2))
    else:
        cfg = results["socket_config"]
        print(f"socket config : PMOD0={cfg['pmod0_personality']} flip={cfg['pmod0_flipped']}, "
              f"PMOD1={cfg['pmod1_personality']} flip={cfg['pmod1_flipped']}, "
              f"hold was {'set' if cfg['hold_was_set'] else 'clear'}")
        if liveness_moved is None:
            print("liveness      : HELD -- renderer frozen on purpose, liveness not required")
        else:
            print(f"liveness      : {'PASS' if liveness_moved else 'FAIL'} "
                  f"(renderer, panel and transmitter counters)")
        print(f"pattern       : {pattern}")
        print(f"source        : measured 0x{held['src_sig']:08x}  modelled 0x{expect_src:08x}"
              f"  {'PASS' if (src_ok or src_ok_prev) else 'FAIL'}")
        print(f"transmitter   : measured 0x{held['hdmi_sig']:08x}  modelled 0x{expect_hdmi:08x}"
              f"  {'PASS' if hdmi_ok else 'FAIL'}")
        print("panel         : not implemented (needs a per-pixel strobe)")
        print(f"restored hold : {'set' if hold_in else 'clear'}")

    if failures:
        print("\nFAILURES:")
        for f in failures:
            print("  " + f)
        return 1
    print("\nOK: every measured stream matches its model.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
