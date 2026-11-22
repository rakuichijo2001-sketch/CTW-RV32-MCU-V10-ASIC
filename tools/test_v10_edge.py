#!/usr/bin/env python3
"""Additional V10 boundary peripheral test: PWM0=0%, PWM1=50%, I2C NACK and repeated START."""
import argparse
import sys
import time
from pathlib import Path
from upload_esp32 import BAUD,upload,wait_line

def edge_test(ser):
    ser.write(b'V10EDGE\n')
    for expected in ('V10EDGE PWM PASS', 'V10EDGE NACK PASS address=0x43',
                     'V10EDGE I2C REPEATED PASS 0xC3', 'V10EDGE PASS ALL'):
        line=wait_line(ser,lambda s:s.startswith('V10EDGE ') or s.startswith('ERR V10EDGE'),15)
        if not line.startswith(expected):raise RuntimeError(f'Expected {expected!r}, got {line!r}')
        print(line,flush=True)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',required=True)
    parser.add_argument('--no-upload',action='store_true')
    args=parser.parse_args()
    try:
        import serial
        with serial.Serial(args.port,BAUD,timeout=.1,write_timeout=5) as ser:
            ser.dtr=False;ser.rts=False;time.sleep(1.5);ser.reset_input_buffer()
            ser.write(b'PING\n');wait_line(ser,lambda s:s=='CTW3',4)
            if not args.no_upload:
                n,crc=upload(ser,(Path(__file__).resolve().parents[1]/'firmware/v10_peripheral_edge.bin').read_bytes())
                print(f'Flash verified: {n} bytes CRC32 {crc:08X}')
            edge_test(ser)
        print('PASS V10 boundary peripherals')
    except (RuntimeError,TimeoutError,OSError,ValueError,ImportError) as exc:
        sys.exit(f'V10EDGE FAILED: {exc}')
if __name__=='__main__':main()
