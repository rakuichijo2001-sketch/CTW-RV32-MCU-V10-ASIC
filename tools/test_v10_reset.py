#!/usr/bin/env python3
"""Repeated external rst_n assertion/release with a full ISA+PSRAM check per cycle.

ESP32 owns only target reset; never recompiles .sof or erases Flash.
"""
import argparse
import sys
import time
from upload_esp32 import BAUD,wait_line
from test_v10 import request
from v10_reference import INITIAL_SIGNATURE,advance

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--port',required=True)
    ap.add_argument('--cycles',type=int,default=100)
    args=ap.parse_args()
    if args.cycles < 1:ap.error('cycles >= 1')
    try:
        import serial
        with serial.Serial(args.port,BAUD,timeout=.1,write_timeout=5) as ser:
            ser.dtr=False;ser.rts=False;time.sleep(1.5);ser.reset_input_buffer()
            ser.write(b'PING\n');wait_line(ser,lambda s:s=='CTW3',4)
            for i in range(args.cycles):
                ser.write(b'V10B\n')
                wait_line(ser,lambda s:s=='V10 RESET OK',5)
                seq,sig,wdt=request(ser,'S')
                if seq!=4 or sig!=advance(INITIAL_SIGNATURE,0,4) or wdt!=0:
                    raise RuntimeError(f'Reset cycle {i+1}: seq={seq} sig={sig:08X} wd={wdt}')
                if (i+1)%10==0:print(f'RESET {i+1}/{args.cycles} PASS',flush=True)
        print(f'PASS: {args.cycles} external CPU reset/boot/ISA/PSRAM cycles')
    except (RuntimeError,TimeoutError,OSError,ValueError,ImportError) as exc:
        sys.exit(f'RESET STRESS FAILED: {exc}')
if __name__=='__main__':main()
