#!/usr/bin/env python3
"""Sequential prior-version regressions on the ONE V10 FPGA .sof + V10 ESP32 sketch.

Always reprogram firmware for each phase. Never resets/recompiles FPGA.
Does not substitute for HDL simulation or ASIC physical signoff.
"""
from __future__ import annotations
import argparse
from pathlib import Path
import sys
import time
from upload_esp32 import BAUD, upload, wait_line
from test_sensor import sensor_test
from test_irq import irq_test
from test_v9 import v9_test
from test_v10_edge import edge_test

ROOT=Path(__file__).resolve().parents[1]

def phase(ser,filename,callback):
    image=(ROOT/'firmware'/filename).read_bytes()
    length,crc=upload(ser,image)
    print(f'UPLOAD {filename}: {length} bytes CRC32 {crc:08X}',flush=True)
    callback(ser)
    print(f'REGRESSION {filename} PASS',flush=True)


def bidir_test(ser):
    ser.write(b'BIDIR\n')
    for direction in ('IN','OUT'):
        for bitpattern in range(4):
            expected=f'BIDIR {direction} {bitpattern}'
            result=wait_line(ser,lambda s:s.startswith('BIDIR '),8)
            if result!=expected:raise RuntimeError(f'{expected}: got {result}')
    wait_line(ser,lambda s:s=='BIDIR PASS IN=4 OUT=4 Z',3)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',required=True)
    args=parser.parse_args()
    try:
        import serial
        with serial.Serial(args.port,BAUD,timeout=0.1,write_timeout=5) as ser:
            ser.dtr=False;ser.rts=False
            time.sleep(1.5)
            ser.reset_input_buffer()
            ser.write(b'PING\n')
            wait_line(ser,lambda s:s=='CTW3',4)
            phase(ser,'sensor_demo.bin',lambda port:sensor_test(port,lambda line:None))
            phase(ser,'gpio_bidir_demo.bin',bidir_test)
            phase(ser,'irq_demo.bin',lambda port:irq_test(port,lambda line:None))
            phase(ser,'v9_peripherals.bin',lambda port:v9_test(port,lambda line:None))
            phase(ser,'v10_peripheral_edge.bin',edge_test)
            phase(ser,'v10_exceptions.bin',lambda port:(
                port.write(b'V10X\n'),
                wait_line(port,lambda line:line=='EXCEPTIONS PASS ECALL EBREAK MRET',5)
            ))
        print('PASS: sensor, bidirectional GPIO, IRQ, 100kHz I2C/PWM, I2C NACK/repeated START, PWM 0/50, ECALL/EBREAK/MRET.',flush=True)
        print('NEXT: py tools/test_v10.py --port COM12 --hours 8')
    except (OSError,RuntimeError,TimeoutError,ValueError,ImportError) as exc:
        sys.exit(f'VERSION REGRESSION FAILED: {exc}')
if __name__=='__main__':main()
