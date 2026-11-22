#!/usr/bin/env python3
"""Upload V9 firmware and exercise PWM+I2C using ESP32 as 7-bit slave."""
import argparse
from pathlib import Path
import sys
import time
from upload_esp32 import BAUD, upload, wait_line


def v9_test(ser, report=print):
    ser.write(b'V9\n')
    for expected_prefix in ('V9 PWM PASS', 'V9 I2C WRITE PASS 0x5A',
                            'V9 I2C READ PASS 0xC3', 'V9 PASS ALL'):
        line = wait_line(ser, lambda s: s.startswith('V9 '), 10)
        if not line.startswith(expected_prefix):
            raise RuntimeError(f'Expected {expected_prefix!r}, got {line!r}')
        report(line)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--port', required=True)
    p.add_argument('--no-upload', action='store_true')
    args = p.parse_args()
    try:
        import serial
        with serial.Serial(args.port, BAUD, timeout=0.1, write_timeout=5) as ser:
            ser.dtr = False
            ser.rts = False
            time.sleep(1.5)
            ser.reset_input_buffer()
            ser.write(b'PING\n')
            wait_line(ser, lambda s: s == 'CTW3', 4)
            if not args.no_upload:
                blob = (Path(__file__).resolve().parent.parent /
                        'firmware/v9_peripherals.bin').read_bytes()
                n, crc = upload(ser, blob)
                print(f'Flash verified: {n} bytes, CRC32 {crc:08X}')
            v9_test(ser)
        print('PASS: programmable PWM, I2C write/read, restored GPIO pinmux.')
    except (OSError, RuntimeError, ValueError, ImportError) as exc:
        sys.exit(f'V9 test failed: {exc}')


if __name__ == '__main__':
    main()
