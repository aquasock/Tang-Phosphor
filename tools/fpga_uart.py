#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-only
"""Direct FPGA transport over the FT2232 UART (single-cable JTAG+UART mode).

Speaks the TangCore UART protocol (0xAA framing) plus the CRC-16/CCITT-FALSE
extended command set and the versioned stream command, talking straight to the
FPGA's transport pins and bypassing the BL616/CDC path. Mirrors Tang-Control's
utils/fpga_debug.cpp, utils/fpga_stream.cpp and utils/fpga_ext_frame.h
byte-for-byte.

This is the shared transport used by scripts/mp3_single_cable.py and
tools/ae350_run.py --direct.
"""
import struct
import time

import serial

EXT_COMMAND = 0x10
EXT_VERSION = 0x01
EXT_READ32 = 0x01
EXT_WRITE32 = 0x02

STREAM_COMMAND = 0x11
STREAM_VERSION = 0x01
STREAM_START = 0x01
STREAM_DATA = 0x02
STREAM_END = 0x04
STREAM_CANCEL = 0x08
STREAM_MAX_DATA = 1024


def crc16(data):
    """CRC-16/CCITT-FALSE (poly 0x1021, init 0xffff, MSB-first)."""
    crc = 0xFFFF
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            crc = ((crc << 1) ^ 0x1021) & 0xFFFF if (crc & 0x8000) else (crc << 1) & 0xFFFF
    return crc


def open_port(path, baud=2_000_000):
    port = serial.Serial(path, baud, timeout=0.05)
    port.reset_input_buffer()
    port.reset_output_buffer()
    return port


def send_frame(port, cmd, payload):
    n = 1 + len(payload)
    port.write(bytes([0xAA, (n >> 8) & 0xFF, n & 0xFF, cmd]) + bytes(payload))


def recv_frame(port, timeout=2.0):
    """Return (cmd, payload) for the next complete 0xAA frame."""
    deadline = time.monotonic() + timeout
    buf = bytearray()
    while time.monotonic() < deadline:
        b = port.read(1)
        if not b:
            continue
        if b[0] == 0xAA:
            buf = bytearray([0xAA])
            break
    else:
        raise TimeoutError("no 0xAA frame")
    for _ in range(3):
        b = port.read(1)
        if not b:
            raise TimeoutError("truncated header")
        buf += b
    frame_len = (buf[1] << 8) | buf[2]
    cmd = buf[3]
    payload_len = frame_len - 1
    while len(buf) < 4 + payload_len:
        b = port.read(1)
        if not b:
            raise TimeoutError("truncated payload")
        buf += b
    return cmd, bytes(buf[4:])


def peek(port, address, timeout=2.0):
    """Extended read of one 32-bit register; returns (status, value)."""
    payload = bytearray([EXT_VERSION, EXT_READ32])
    payload += b"\x00\x00"
    payload += struct.pack(">I", address)
    payload += struct.pack(">I", 0)
    seq = 1
    payload[2] = (seq >> 8) & 0xFF
    payload[3] = seq & 0xFF
    payload += struct.pack(">H", crc16(bytes([EXT_COMMAND]) + bytes(payload)))
    send_frame(port, EXT_COMMAND, payload)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        cmd, p = recv_frame(port, timeout=deadline - time.monotonic())
        if cmd != EXT_COMMAND or len(p) != 15 or p[0] != EXT_VERSION:
            continue
        if p[1] != EXT_READ32 | 0x80:
            continue
        if struct.unpack(">H", p[3:5])[0] != seq:
            continue
        return p[2], struct.unpack(">I", p[9:13])[0]
    raise TimeoutError("no matching peek response")


def poke(port, address, value, timeout=2.0):
    """Extended write of one 32-bit register; returns status."""
    payload = bytearray([EXT_VERSION, EXT_WRITE32])
    payload += b"\x00\x00"
    payload += struct.pack(">I", address)
    payload += struct.pack(">I", value)
    seq = 1
    payload[2] = (seq >> 8) & 0xFF
    payload[3] = seq & 0xFF
    payload += struct.pack(">H", crc16(bytes([EXT_COMMAND]) + bytes(payload)))
    send_frame(port, EXT_COMMAND, payload)
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        cmd, p = recv_frame(port, timeout=deadline - time.monotonic())
        if cmd != EXT_COMMAND or len(p) != 15 or p[0] != EXT_VERSION:
            continue
        if p[1] != EXT_WRITE32 | 0x80:
            continue
        if struct.unpack(">H", p[3:5])[0] != seq:
            continue
        return p[2]
    raise TimeoutError("no matching poke response")


def _stream_frame(port, flags, stream_id, offset, data):
    payload = bytearray([STREAM_VERSION, flags])
    payload += struct.pack(">H", stream_id)
    payload += struct.pack(">I", offset)
    payload += struct.pack(">H", len(data))
    payload += data
    payload += struct.pack(">H", crc16(bytes([STREAM_COMMAND]) + bytes(payload)))
    send_frame(port, STREAM_COMMAND, payload)


def _stream_ack(port, stream_id, timeout=3.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        cmd, p = recv_frame(port, timeout=deadline - time.monotonic())
        if cmd != STREAM_COMMAND or len(p) != 13 or p[0] != STREAM_VERSION:
            continue
        if crc16(bytes([STREAM_COMMAND]) + p[:11]) != struct.unpack(">H", p[11:13])[0]:
            continue
        if struct.unpack(">H", p[3:5])[0] != stream_id:
            continue
        return p[1], p[2], struct.unpack(">I", p[5:9])[0], struct.unpack(">H", p[9:11])[0]
    raise TimeoutError("no stream ack")


def stream_file(port, path, progress=None):
    """Stream a local file to the FPGA over the versioned stream command.

    Returns the number of bytes streamed. `progress` (optional) is called with
    (offset, total) after each 256 KiB boundary.
    """
    data = open(path, "rb").read()
    stream_id = 1
    offset = 0
    t0 = time.monotonic()
    _stream_frame(port, STREAM_START, stream_id, 0, b"")
    _stream_ack(port, stream_id)
    while offset < len(data):
        chunk = data[offset:offset + STREAM_MAX_DATA]
        _stream_frame(port, STREAM_DATA, stream_id, offset, chunk)
        _stream_ack(port, stream_id)
        offset += len(chunk)
        if progress and (offset % (256 * 1024) == 0 or offset == len(data)):
            progress(offset, len(data), time.monotonic() - t0)
    _stream_frame(port, STREAM_END, stream_id, offset, b"")
    _stream_ack(port, stream_id)
    return len(data)
