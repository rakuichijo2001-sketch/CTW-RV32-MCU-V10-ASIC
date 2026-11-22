#!/usr/bin/env python3
"""Upload a RISC-V firmware binary via CTW3 on the ESP32's USB serial port."""
from __future__ import annotations

import argparse
import pathlib
import re
import sys
import time
import zlib

BINARY_LIMIT = 4096
BAUD = 115200
OK = re.compile(r"OK (\d+) ([0-9A-Fa-f]{8}) RUN\Z")


def wait_line(ser, expected, timeout):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        line = ser.readline().decode("ascii", errors="replace").strip()
        if line.startswith("ERR "):
            raise RuntimeError(line[4:])
        if expected(line):
            return line
    raise TimeoutError("No expected response from ESP32")


def upload(ser, data: bytes):
    crc = zlib.crc32(data) & 0xFFFFFFFF
    ser.write(f"CTW3 {len(data)} {crc:08X}\n".encode("ascii"))
    wait_line(ser, lambda s: s == "READY", 5)
    if ser.write(data) != len(data):
        raise IOError("Incomplete serial write")
    ser.flush()
    line = wait_line(ser, lambda s: OK.fullmatch(s) is not None, 45)
    match = OK.fullmatch(line)
    if int(match[1]) != len(data) or int(match[2], 16) != crc:
        raise RuntimeError("ESP32 reported a different size or CRC")
    return len(data), crc


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="ESP32 serial port, e.g. COM5")
    parser.add_argument("image", type=pathlib.Path)
    args = parser.parse_args()
    try:
        import serial
    except ImportError:
        sys.exit("Install pyserial with: python -m pip install pyserial")
    try:
        data = args.image.read_bytes()
        if not 0 < len(data) <= BINARY_LIMIT:
            raise ValueError("Firmware must be 1..4096 bytes")
        # Opening a USB-UART on a DevKit can reset ESP32 via DTR/RTS.
        with serial.Serial(args.port, BAUD, timeout=0.2, write_timeout=5) as ser:
            ser.dtr = False
            ser.rts = False
            time.sleep(1.5)
            ser.reset_input_buffer()
            ser.write(b"PING\n")
            wait_line(ser, lambda s: s == "CTW3", 4)
            n, crc = upload(ser, data)
        print(f"PASS {n} bytes, CRC32 {crc:08X}, ESP32 verified Flash, released the bus and requested MCU boot.")
    except (OSError, RuntimeError, ValueError) as exc:
        sys.exit(f"Upload failed: {exc}. Check wiring and retry. A Flash programming error holds target reset.")


if __name__ == "__main__":
    main()
