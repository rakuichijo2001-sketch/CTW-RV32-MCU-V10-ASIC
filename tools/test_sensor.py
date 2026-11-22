#!/usr/bin/env python3
"""Upload the CTW sensor demo and check the ESP32-to-RV32 round trip."""
from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys
import time

from upload_esp32 import BAUD, upload, wait_line

SEQUENCE = (7, 0, 1, 6, 2, 5, 3, 4)
SAMPLE = re.compile(r"SAMPLE ([0-7]) (\d+)\Z")


def sensor_test(ser, report=print):
    ser.write(b"SENSOR\n")
    for expected in SEQUENCE:
        line = wait_line(ser, lambda s: SAMPLE.fullmatch(s) is not None
                         or s.startswith("SENSOR PASS "), 3)
        match = SAMPLE.fullmatch(line)
        if match is None:
            raise RuntimeError("Sensor test ended before all 8 samples")
        raw, result = map(int, match.groups())
        if (raw, result) != (expected, 3 * expected + 7):
            raise RuntimeError(f"Wrong sensor frame: expected {expected}, got {raw} -> {result}")
        report(f"  GPIO {raw:03b} ({raw}) -> CPU result {result}")
    wait_line(ser, lambda s: s == "SENSOR PASS 8", 2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", required=True, help="ESP32 USB COM port, e.g. COM12")
    parser.add_argument("--no-upload", action="store_true", help="Retest the sensor program already in Flash")
    args = parser.parse_args()
    try:
        import serial
    except ImportError:
        sys.exit("Install pyserial with: py -m pip install -r tools/requirements.txt")

    try:
        with serial.Serial(args.port, BAUD, timeout=0.1, write_timeout=5) as ser:
            ser.dtr = False
            ser.rts = False
            time.sleep(1.5)
            ser.reset_input_buffer()
            ser.write(b"PING\n")
            wait_line(ser, lambda s: s == "CTW3", 4)
            if not args.no_upload:
                data = (Path(__file__).resolve().parent.parent / "firmware/sensor_demo.bin").read_bytes()
                size, crc = upload(ser, data)
                print(f"Flash verified: {size} bytes, CRC32 {crc:08X}")
            sensor_test(ser)
        print("PASS: MCU read all 8 GPIO patterns, processed them and replied over UART.")
    except (OSError, RuntimeError, ValueError) as exc:
        sys.exit(f"Sensor test failed: {exc}")


if __name__ == "__main__":
    main()
