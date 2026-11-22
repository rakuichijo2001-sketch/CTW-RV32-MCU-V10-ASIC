#!/usr/bin/env python3
"""Upload V7 firmware, then drive and sample both reconfigurable GPIO pads."""
from __future__ import annotations
import argparse
from pathlib import Path
import re
import sys
import time
from upload_esp32 import BAUD, upload, wait_line


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--port', required=True, help='ESP32 serial port, e.g. COM12')
    p.add_argument('--no-upload', action='store_true')
    args=p.parse_args()
    try:
        import serial
        with serial.Serial(args.port, BAUD, timeout=0.1, write_timeout=5) as ser:
            ser.dtr=False; ser.rts=False
            time.sleep(1.5)
            ser.reset_input_buffer()
            ser.write(b'PING\n')
            wait_line(ser,lambda s:s=='CTW3',4)
            if not args.no_upload:
                image=(Path(__file__).resolve().parent.parent/'firmware/gpio_bidir_demo.bin').read_bytes()
                size,crc=upload(ser,image)
                print(f'Flash verified: {size} bytes, CRC32 {crc:08X}')
            ser.write(b'BIDIR\n')
            for direction in ('IN','OUT'):
                for expected in range(4):
                    line=wait_line(ser, lambda s:re.fullmatch(r'BIDIR (?:IN|OUT) [0-3]',s) is not None or s.startswith('ERR BIDIR'), 5)
                    if line!=f'BIDIR {direction} {expected}':
                        raise RuntimeError(f'expected BIDIR {direction} {expected}, got {line}')
                    print(f'  {direction}: pattern {expected:02b} PASS')
            wait_line(ser,lambda s:s=='BIDIR PASS IN=4 OUT=4 Z' or s.startswith('ERR BIDIR'),3)
            print('PASS: uio[6] and uio[7] read, drove and returned to high-Z.')
    except (OSError,RuntimeError,ValueError) as exc:
        sys.exit(f'GPIO bidirectional test failed: {exc}')
if __name__=='__main__': main()
