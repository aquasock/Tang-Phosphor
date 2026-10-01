#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Single-cable (FT2232) UART liveness + contention probe.

Diagnoses why the merged core is silent on the direct FT2232-UART path while
the deployment core answers. Three observations, each capturing RAW bytes on
ttyUSB1 (the FPGA->BL616 direction, U15) and reporting a verdict:

  listen   Passive baseline. With the merged core flashed and the BL616
           running, watch U15 for a few seconds. If the FPGA's UART is alive
           and the BL616 is talking to it, we see 0xAA-framed traffic. This
           proves the merged core's UART RX+TX work at the BL616's baud --
           independent of our own injection, and independent of timing.

  inject   Send one peek-0 extended read, then capture the raw return line.
           Reports valid-response / garbage / silence.

  contend  Baseline 2s, then inject a peek every 100ms for 3s while capturing.
           If our TX genuinely collides with the BL616's TX on the shared
           RXD wire (V14), the FPGA->BL616 traffic we saw in the baseline
           should get corrupted or stop while we inject.

Because the deployment core answers `inject` and the merged core does not,
running the same probe against both bitstreams isolates the merged
bitstream's transport from the shared-wire contention.

Uses the TangCore UART framing (0xAA) + CRC-16/CCITT-FALSE extended command
set, mirroring Tang-Control utils/fpga_debug.cpp byte-for-byte.
"""
import argparse
import struct
import sys
import time

import serial

EXT_COMMAND = 0x10
EXT_VERSION = 0x01
EXT_READ32 = 0x01
EXT_WRITE32 = 0x02


def crc16(data):
    """CRC-16/CCITT-FALSE (poly 0x1021, init 0xffff, MSB-first)."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if (crc & 0x8000) else (crc << 1) & 0xFFFF
    return crc


def peek_frame(address, seq=1):
    payload = bytearray([EXT_VERSION, EXT_READ32])
    payload += struct.pack(">H", seq)
    payload += struct.pack(">I", address)
    payload += struct.pack(">I", 0)  # read has no write data
    crc = crc16(bytes([EXT_COMMAND]) + bytes(payload))
    payload += struct.pack(">H", crc)
    n = 1 + len(payload)
    return bytes([0xAA, (n >> 8) & 0xFF, n & 0xFF, EXT_COMMAND]) + bytes(payload)


def parse_frames(stream):
    """Yield (cmd, payload) for every well-formed 0xAA frame in `stream`.

    Returns (frames, leftovers) where leftovers are bytes that could not be
    folded into a frame (garbage / partial).
    """
    frames = []
    leftovers = bytearray()
    i = 0
    n = len(stream)
    while i < n:
        if stream[i] != 0xAA:
            leftovers.append(stream[i])
            i += 1
            continue
        if i + 3 >= n:
            leftovers += stream[i:]
            break
        frame_len = (stream[i + 1] << 8) | stream[i + 2]
        cmd = stream[i + 3]
        payload_len = frame_len - 1
        end = i + 4 + payload_len
        if end > n:
            leftovers += stream[i:]
            break
        frames.append((cmd, bytes(stream[i + 4:end])))
        i = end
    return frames, bytes(leftovers)


def open_port(path, baud):
    port = serial.Serial(path, baud, timeout=0.05)
    port.reset_input_buffer()
    port.reset_output_buffer()
    return port


def hexdump(data, max_bytes=256):
    if not data:
        return "  <none>"
    data = data[:max_bytes]
    out = []
    for i in range(0, len(data), 16):
        chunk = data[i:i + 16]
        hexs = " ".join(f"{b:02x}" for b in chunk)
        ascii_ = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        out.append(f"  {i:04x}  {hexs:<47}  {ascii_}")
    if len(data) > max_bytes:
        out.append(f"  ... ({len(data)} total bytes, truncated)")
    return "\n".join(out)


def capture(port, seconds):
    """Return the raw bytes received over `seconds`."""
    port.reset_input_buffer()
    deadline = time.monotonic() + seconds
    buf = bytearray()
    while time.monotonic() < deadline:
        chunk = port.read(port.in_waiting or 1)
        if chunk:
            buf += chunk
    return bytes(buf)


def summarize(tag, raw):
    frames, leftovers = parse_frames(raw)
    print(f"\n[{tag}] {len(raw)} raw bytes")
    if frames:
        print(f"  valid 0xAA frames: {len(frames)}")
        kinds = {}
        for cmd, _ in frames:
            kinds[cmd] = kinds.get(cmd, 0) + 1
        for cmd, count in sorted(kinds.items()):
            print(f"    cmd 0x{cmd:02x}: {count}")
    else:
        print("  valid 0xAA frames: 0")
    if leftovers:
        print(f"  non-frame bytes: {len(leftovers)}")
        print(hexdump(leftovers))
    return frames, leftovers


def verdict_listen(raw):
    frames, leftovers = parse_frames(raw)
    if not raw:
        print("\nVERDICT: U15 silent -- FPGA is not transmitting at all.")
        print("         (BL616 not sending commands, or FPGA UART TX dead, or wrong baud)")
    elif frames and len(leftovers) <= len(raw) // 4:
        print("\nVERDICT: clean 0xAA traffic -- merged core UART is ALIVE and")
        print("         talking to the BL616 at this baud. Timing and responder are fine.")
    else:
        print("\nVERDICT: bytes present but not clean frames -- wrong baud or a")
        print("         contended/corrupted line.")


def verdict_inject(raw):
    frames, leftovers = parse_frames(raw)
    if not raw:
        print("\nVERDICT: silence after inject -- frame not received or response not driven.")
    elif any(cmd == EXT_COMMAND for cmd, _ in frames):
        print("\nVERDICT: got an extended-command response -- direct injection WORKS.")
    else:
        print("\nVERDICT: garbage only after inject -- line contended / partial frame.")


def mode_listen(args):
    port = open_port(args.port, args.baud)
    print(f"listening on {args.port} @ {args.baud} for {args.seconds}s ...")
    raw = capture(port, args.seconds)
    summarize("listen", raw)
    verdict_listen(raw)


def mode_inject(args):
    port = open_port(args.port, args.baud)
    frame = peek_frame(args.address)
    print(f"injecting peek 0x{args.address:08x} on {args.port} @ {args.baud} ...")
    port.write(frame)
    raw = capture(port, args.seconds)
    summarize("inject", raw)
    verdict_inject(raw)


def mode_contend(args):
    port = open_port(args.port, args.baud)
    print(f"baseline {args.seconds}s ...")
    base = capture(port, args.seconds)
    summarize("baseline", base)
    print(f"\ninjecting peek every 100ms for {args.seconds}s while capturing ...")
    deadline = time.monotonic() + args.seconds
    buf = bytearray()
    seq = 0
    while time.monotonic() < deadline:
        seq += 1
        port.write(peek_frame(args.address, seq))
        time.sleep(0.1)
        chunk = port.read(port.in_waiting or 1)
        if chunk:
            buf += chunk
    raw = bytes(buf)
    summarize("during-inject", raw)
    frames, leftovers = parse_frames(raw)
    if not raw:
        print("\nVERDICT: no traffic while injecting -- our TX is colliding with")
        print("         the BL616's TX on V14, starving the FPGA->BL616 link.")
    elif frames and not leftovers:
        print("\nVERDICT: clean responses while injecting -- no contention; direct")
        print("         injection works. Silence in `inject` mode is elsewhere.")
    else:
        print("\nVERDICT: mixed/garbage while injecting -- partial contention.")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--baud", type=int, default=2_000_000)
    ap.add_argument("--seconds", type=float, default=3.0)
    ap.add_argument("--address", type=lambda s: int(s, 0), default=0)
    ap.add_argument("mode", choices=["listen", "inject", "contend"])
    args = ap.parse_args()

    try:
        if args.mode == "listen":
            mode_listen(args)
        elif args.mode == "inject":
            mode_inject(args)
        else:
            mode_contend(args)
    except serial.SerialException as e:
        print(f"serial error: {e}", file=sys.stderr)
        sys.exit(2)


if __name__ == "__main__":
    main()
