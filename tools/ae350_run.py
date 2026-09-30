#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Package, upload, and run AE350 programs on the AE350 + DDR3 image.

  pack <program.bin> -o <image.tpi> [--load ADDR] [--entry ADDR]
      Prefix a flat binary with the boot ROM's image header
      (software/ae350/include/ae350.h), padding it to whole words.
  upload <image.tpi>... [--dir DIR]
      Copy images to the SD card.  Tang-Control only accepts this from the
      TangCore main menu, before the AE350 image is loaded.
  run <remote> [--restart] [--timeout SECONDS]
      With the AE350 image running, optionally restart the CPU, stream the
      image from the SD card, wait for the program to return, and show the
      status.  Exits nonzero unless the program returned.
  status
      Show the image flags, loader state, stream counters, program results,
      RAM-bridge counters, and the log.
  restart
      Restart the AE350 (its boot ROM then waits for an image).
  trace
      Show the RAM bridge's state flags, its first ERROR address, and its
      trace of the last 16 accepted transfers.

Uses Tang-Control's tangctl.py (TANG_CONTROL_DIR, default ../Tang-Control).
The debug register map is documented in src/ae350/ae350_ddr3_top.sv and
src/ae350/ae350_exts_regs.sv.
"""

import argparse
import contextlib
import io
import os
import re
import struct
import sys
import time
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TANG_CONTROL = Path(os.environ.get("TANG_CONTROL_DIR", ROOT.parent / "Tang-Control"))
sys.path.insert(0, str(TANG_CONTROL / "scripts"))

IMAGE_MAGIC = 0x31495054
HEADER_SIZE = 32
DEFAULT_LOAD = 0x40000000
REMOTE_DIR = "ae350"
REGS_MAGIC = 0x54504133

STATE = 0x20
LOG_HEAD = 0x30
USER = 0x40
BRIDGE = 0xA0
LOG_RING = 0x100
LOG_BYTES = 512
STREAM = 0x3C0
FLAGS = 0x3E0
RESTART = 0x3F0
CORE_CLOCK_HZ = 750e6
BUS_CLOCK_HZ = 100e6

STATE_NAMES = {
    0x00: "boot", 0x01: "wait", 0x02: "receive", 0x03: "run", 0x04: "returned",
    0x81: "error: bad header", 0x82: "error: bad load range", 0x83: "error: truncated",
    0x84: "error: length mismatch", 0x85: "error: CRC mismatch", 0x86: "error: cancelled",
    0x87: "error: stream overflow", 0x88: "trap",
}
FLAG_NAMES = ["por", "ae350_pll", "ddr3_pll", "calibrated", "cpu_running"]
BRIDGE_STATE = 0xB8
BRIDGE_TRACE = 0x300
BRIDGE_STATE_NAMES = ["hready", "hresp", "c_valid", "c_eval", "c_merge", "rbuf_ok",
                      "rd_pend", "rd_wait", "wbuf_valid", "wbuf_open", "wr_wait",
                      "error_first", "rd_done", "cmd_ready", "wr_data_rdy", "hwrite"]
HTRANS_NAMES = ["IDLE", "BUSY", "NONSEQ", "SEQ"]
HBURST_NAMES = ["SINGLE", "INCR", "WRAP4", "INCR4", "WRAP8", "INCR8", "WRAP16", "INCR16"]


def pack(payload, load, entry):
    payload += b"\0" * (-len(payload) % 4)
    header = struct.pack("<8I", IMAGE_MAGIC, HEADER_SIZE, load, entry, len(payload),
                         zlib.crc32(payload), 0, 0)
    return header + payload


def tangctl():
    import tangctl as module  # noqa: E402
    return module


def quiet(port, command, timeout=5):
    with contextlib.redirect_stdout(io.StringIO()):
        return tangctl().run_command(port, command, timeout=timeout)


def peek(port, address, count=1):
    values = []
    while count > 0:
        chunk = min(count, 32)
        lines = quiet(port, f"peek 0x{address:08x} {chunk}")
        values += [int(line.split(":")[1], 16) for line in lines]
        address += 4 * chunk
        count -= chunk
    return values


def poke(port, address, value):
    quiet(port, f"poke 0x{address:08x} 0x{value:08x}")


def describe_state(value):
    return f"{STATE_NAMES.get(value & 0xff, hex(value & 0xff))} (runs {value >> 16})"


def read_log(port):
    head = peek(port, LOG_HEAD)[0]
    ring = b"".join(word.to_bytes(4, "little") for word in peek(port, LOG_RING, LOG_BYTES // 4))
    if head <= LOG_BYTES:
        text = ring[:head]
    else:
        start = head % LOG_BYTES
        text = ring[start:] + ring[:start]
    return text.decode("ascii", "replace")


def read_status(port):
    magic = peek(port, 0)[0]
    flags, calib, uptime = peek(port, FLAGS, 3)
    state, size, crc, result = peek(port, STATE, 4)
    return {
        "magic": magic, "flags": flags, "calib_ms": calib / 50e3, "uptime_s": uptime / 50e6,
        "state": state, "size": size, "crc": crc, "result": result,
        "stream": peek(port, STREAM, 5),
        "user": peek(port, USER, 16),
        "bridge": peek(port, BRIDGE, 6),
        "log": read_log(port),
    }


def print_status(port):
    status = read_status(port)
    flags = [name for bit, name in enumerate(FLAG_NAMES) if status["flags"] >> bit & 1]
    print(f"image      flags {' '.join(flags) or 'none'}; calibration "
          f"{status['calib_ms']:.1f} ms; uptime {status['uptime_s']:.1f} s; "
          f"registers {'ok' if status['magic'] == REGS_MAGIC else hex(status['magic'])}")
    print(f"loader     {describe_state(status['state'])}")
    print(f"image      {status['size']} bytes, crc32 {status['crc']:08x}, "
          f"result 0x{status['result']:08x}")
    sessions, stream_bytes, ends, cancels, overflow = status["stream"]
    print(f"stream     sessions {sessions}, bytes {stream_bytes}, ends {ends}, "
          f"cancels {cancels}, overflow {overflow}")
    print("user       " + " ".join(f"{value:08x}" for value in status["user"]))
    reads, writes, latency_sum, latency_max, hits, errors = status["bridge"]
    average = latency_sum / reads if reads else 0
    print(f"bridge     {reads} reads (latency average {average:.1f}, max {latency_max}"
          f" bus cycles), {writes} writes, {hits} buffer hits, {errors} errors")
    print("log        " + repr(status["log"]))
    return status


def print_trace(port):
    state, status, first_error = peek(port, BRIDGE_STATE, 3)
    addresses = peek(port, BRIDGE_TRACE, 16)
    infos = peek(port, BRIDGE_TRACE + 0x40, 16)
    flags = [name for bit, name in enumerate(BRIDGE_STATE_NAMES) if state >> bit & 1]
    print(f"bridge     {' '.join(flags)}; htrans {HTRANS_NAMES[state >> 16 & 3]}")
    print(f"trace      {'frozen' if status & 0x80 else 'running'}, next entry {status & 15}; "
          f"first ERROR at 0x{first_error:08x}")
    for step in range(16):
        index = (status + step) & 15
        info = infos[index]
        print(f"  {index:2d} 0x{addresses[index]:08x} {HTRANS_NAMES[info >> 7 & 3]:6s} "
              f"{'W' if info >> 6 & 1 else 'R'} size {8 << (info >> 3 & 7):3d} "
              f"{HBURST_NAMES[info & 7]:6s}{' predicted' if info >> 9 & 1 else ''}")


def wait_state(port, predicate, timeout):
    deadline = time.monotonic() + timeout
    while True:
        state = peek(port, STATE)[0]
        if predicate(state):
            return state
        if time.monotonic() > deadline:
            raise TimeoutError(f"loader state stayed {describe_state(state)}")
        time.sleep(0.05)


def command_pack(args):
    payload = Path(args.binary).read_bytes()
    entry = args.load if args.entry is None else args.entry
    image = pack(payload, args.load, entry)
    Path(args.output).write_bytes(image)
    print(f"{args.output}: {len(image) - HEADER_SIZE} payload bytes, load 0x{args.load:08x}, "
          f"entry 0x{entry:08x}, crc32 {zlib.crc32(image[HEADER_SIZE:]):08x}")
    return 0


def command_upload(args, port):
    with contextlib.suppress(RuntimeError):
        quiet(port, f"mkdir {args.dir}")
    for image in args.images:
        tangctl().run_put(port, image, f"{args.dir}/{Path(image).name}")
    return 0


def restart(port, timeout):
    poke(port, RESTART, 1)
    time.sleep(0.01)
    wait_state(port, lambda s: (s & 0xff) == 0x01, timeout)


def command_run(args, port):
    remote = args.remote if "/" in args.remote else f"{REMOTE_DIR}/{args.remote}"
    if args.restart or (peek(port, STATE)[0] & 0xff) != 0x01:
        restart(port, args.timeout)
    before = peek(port, STATE)[0]
    before_runs = before >> 16
    started = time.monotonic()
    for line in quiet(port, f"stream {remote}", timeout=600):
        match = re.search(r"STREAM bytes=(\d+) ms=(\d+) crc32=([0-9a-f]+)", line)
        if match:
            size, ms = int(match.group(1)), int(match.group(2))
            rate = size / (ms / 1000) / 1024 if ms else 0
            print(f"streamed   {remote}: {size} bytes in {ms} ms ({rate:.1f} KiB/s)")
    # A normal return bumps the completed-runs count (bits 31:16) and the
    # loader falls straight back to WAIT, so 'returned' is too transient to
    # poll.  An error or trap leaves the state byte at 0x81..0x88.
    state = wait_state(port,
        lambda s: (s >> 16) != before_runs or (s & 0xff) >= 0x81, args.timeout)
    print(f"finished   {time.monotonic() - started:.2f} s after stream start")
    print_status(port)
    return 0 if (state >> 16) != before_runs else 1


def main():
    parser = argparse.ArgumentParser(description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", help="serial device; auto-detected when omitted")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("pack")
    p.add_argument("binary")
    p.add_argument("-o", "--output", required=True)
    p.add_argument("--load", type=lambda v: int(v, 0), default=DEFAULT_LOAD)
    p.add_argument("--entry", type=lambda v: int(v, 0))
    p = sub.add_parser("upload")
    p.add_argument("images", nargs="+")
    p.add_argument("--dir", default=REMOTE_DIR, help=f"SD directory (default {REMOTE_DIR})")
    p = sub.add_parser("run")
    p.add_argument("remote", help=f"SD path, or a name under {REMOTE_DIR}/")
    p.add_argument("--restart", action="store_true", help="restart the AE350 first")
    p.add_argument("--timeout", type=float, default=60.0)
    sub.add_parser("status")
    sub.add_parser("trace")
    p = sub.add_parser("restart")
    p.add_argument("--timeout", type=float, default=5.0)
    args = parser.parse_args()

    if args.command == "pack":
        return command_pack(args)
    port = tangctl().open_port(args.port or tangctl().find_port())
    try:
        if args.command == "upload":
            return command_upload(args, port)
        if args.command == "run":
            return command_run(args, port)
        if args.command == "trace":
            print_trace(port)
            return 0
        if args.command == "restart":
            restart(port, args.timeout)
        print_status(port)
        return 0
    finally:
        port.close()


if __name__ == "__main__":
    sys.exit(main())
