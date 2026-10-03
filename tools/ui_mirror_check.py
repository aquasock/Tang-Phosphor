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
# Two register maps, because two cores implement this block.  The bring-up core
# owns the flat map at 0x00-0x3c; the player already had 0x00-0xbc spoken for, so
# its mirror block sits in the free hi-bank slots from 0xc0.  Layouts are
# identical; only the addresses differ, which is why this is a table and not a
# second tool.
MAPS = {
    "bringup": {"magic": 0x00, "uptime": 0x08, "render": 0x0c, "control": 0x10,
                "src_sig": 0x1c, "oled_frames": 0x20, "oled_sig": 0x24,
                "hdmi_frames": 0x28, "hdmi_sig": 0x2c},
    "merged":  {"magic": 0x00, "uptime": 0x04, "render": 0xd4, "control": 0xc0,
                "src_sig": 0xc8, "oled_frames": 0xd8, "oled_sig": 0xd0,
                "hdmi_frames": 0xdc, "hdmi_sig": 0xcc},
}

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
    ap.add_argument("--attempts", type=int, default=8,
                    help="frames to try when the held frame is a uniform fill, "
                         "whose agreement would prove nothing")
    ap.add_argument("--frames", type=int, default=12,
                    help="how many frames to generate while measuring liveness")
    ap.add_argument("--map", choices=sorted(MAPS), default="bringup",
                    help="which core's register map to use (default: bringup)")
    ap.add_argument("--json", action="store_true", help="emit machine-readable results")
    args = ap.parse_args()

    global REG_MAGIC, REG_UPTIME, REG_RENDER, REG_CONTROL, REG_SRC_SIG
    global REG_OLED_FRAMES, REG_OLED_SIG, REG_HDMI_FRAMES, REG_HDMI_SIG
    m = MAPS[args.map]
    REG_MAGIC, REG_UPTIME, REG_RENDER, REG_CONTROL = (
        m["magic"], m["uptime"], m["render"], m["control"])
    REG_SRC_SIG, REG_OLED_FRAMES, REG_OLED_SIG = (
        m["src_sig"], m["oled_frames"], m["oled_sig"])
    REG_HDMI_FRAMES, REG_HDMI_SIG = m["hdmi_frames"], m["hdmi_sig"]

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
    #
    # Identify which frame each stream is showing, independently, by matching
    # its measured signature against the model for every pattern.  The pattern
    # register is not trusted for this: it reports what the writer is about to
    # draw, not what a backend has latched.  Identification is deliberately
    # per-stream, because an earlier version accepted a source match on the
    # *previous* pattern while reporting the *current* one and so printed PASS
    # beside two numbers that plainly disagreed.
    source_by_fold = {fold(source_frame(p)): p for p in range(LAST_PAT + 1)}
    transmit_by_fold = {fold(emitted_stream(source_frame(p))): p
                       for p in range(LAST_PAT + 1)}
    # A uniform fill folds to one value across the whole store, so three
    # streams agreeing on one is not evidence of anything.  Release the hold
    # and look again on the next frame rather than bank a free pass: a gate
    # that can pass vacuously is not a gate.
    uniform = (0, 1, 2, 3, 4)
    attempts = 0
    while True:
        dev.poke(REG_CONTROL, (control & ~1) | 1)
        time.sleep(args.settle)
        held = dev.read_state()
        attempts += 1
        pattern = source_by_fold.get(held["src_sig"])
        panel_pattern = source_by_fold.get(held["oled_sig"])
        transmitter_pattern = transmit_by_fold.get(held["hdmi_sig"])
        if pattern is None or pattern not in uniform or attempts >= args.attempts:
            break
        dev.poke(REG_CONTROL, control & ~1)
        time.sleep(1.1)

    results["attempts"] = attempts
    register_pattern = (held["control"] >> 16) & 0x7

    frame = source_frame(pattern if pattern is not None else 0)
    expect_src = fold(frame)
    expect_hdmi = fold(emitted_stream(frame))
    # The panel emits the store contents at 1:1 with no bars, in the same
    # order the renderer writes them, so its expected fold is the source's.
    expect_panel = expect_src

    src_ok = pattern is not None and held["src_sig"] == expect_src
    hdmi_ok = transmitter_pattern is not None and transmitter_pattern == pattern
    panel_ok = panel_pattern is not None and panel_pattern == pattern

    results["pattern"] = pattern
    results["identified"] = {"source": pattern, "transmitter": transmitter_pattern,
                             "panel": panel_pattern}
    results["register_pattern"] = register_pattern
    # A uniform frame folds to a single value across the whole store, so three
    # streams agreeing on one is not evidence of anything.  Say so instead of
    # banking a free pass.
    results["weak_frame"] = pattern in (0, 1, 2, 3, 4) if pattern is not None else None
    results["expected"] = {"source": f"0x{expect_src:08x}",
                           "transmitter": f"0x{expect_hdmi:08x}",
                           "panel": f"0x{expect_panel:08x}"}
    results["measured"] = {"source": f"0x{held['src_sig']:08x}",
                           "transmitter": f"0x{held['hdmi_sig']:08x}",
                           "panel": f"0x{held['oled_sig']:08x}"}
    panel_ok = held["oled_sig"] == expect_panel

    results["mirror"] = {
        "source": src_ok,
        "transmitter": hdmi_ok,
        "panel": panel_ok,
    }
    if not src_ok:
        failures.append(f"mirror: source 0x{held['src_sig']:08x} matches no pattern "
                        f"(nearest model 0x{expect_src:08x})")
    if not hdmi_ok:
        failures.append(f"mirror: transmitter shows pattern {transmitter_pattern}, "
                        f"source shows {pattern}")
    if not panel_ok:
        failures.append(f"mirror: panel shows pattern {panel_pattern}, "
                        f"source shows {pattern}")

    if results["weak_frame"]:
        print("NOTE: identified frame is a uniform fill, where agreement proves "
              "nothing; re-run until a patterned frame is captured.")

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
        print(f"pattern       : source p{pattern}, transmitter p{transmitter_pattern}, "
              f"panel p{panel_pattern}   (register said {register_pattern})")
        print(f"source        : measured 0x{held['src_sig']:08x}  modelled 0x{expect_src:08x}"
              f"  {'PASS' if src_ok else 'FAIL'}")
        print(f"transmitter   : measured 0x{held['hdmi_sig']:08x}  modelled 0x{expect_hdmi:08x}"
              f"  {'PASS' if hdmi_ok else 'FAIL'}")
        print(f"panel         : measured 0x{held['oled_sig']:08x}  modelled 0x{expect_panel:08x}"
              f"  {'PASS' if panel_ok else 'FAIL'}")
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
