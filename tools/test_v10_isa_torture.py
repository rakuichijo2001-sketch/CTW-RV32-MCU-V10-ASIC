#!/usr/bin/env python3
"""Physical DE10+ESP32 ISA torture; fails with reproducible test ID."""
from __future__ import annotations
import argparse, pathlib, sys, time
from upload_esp32 import BAUD, upload, wait_line
from test_v10 import request
ROOT=pathlib.Path(__file__).resolve().parents[1]

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--port',required=True)
    ap.add_argument('--loops',type=int,default=100)
    ap.add_argument('--no-upload',action='store_true')
    ap.add_argument('--firmware',type=pathlib.Path,default=ROOT/'firmware/v10_isa_torture.bin')
    args=ap.parse_args()
    if args.loops<1: ap.error('--loops must be positive')
    try:
        import serial
        with serial.Serial(args.port,BAUD,timeout=0.1,write_timeout=5) as ser:
            ser.dtr=False;ser.rts=False
            time.sleep(1.5);ser.reset_input_buffer();ser.write(b'PING\n')
            wait_line(ser,lambda s:s=='CTW3',4)
            if not args.no_upload:
                size,crc=upload(ser,args.firmware.read_bytes())
                print(f'ISA image verified: {size} bytes, CRC32 {crc:08X}',flush=True)
            ser.write(b'V10B\n')
            wait_line(ser,lambda s:s=='V10 RESET OK',4)
            baseline_wdt=None
            for i in range(1,args.loops+1):
                seq,sig,wdt=request(ser,'S',timeout=25)
                if seq!=i or sig!=(0xc7c7e00d^i):
                    if seq & 0xf0000000==0xe0000000:
                        raise RuntimeError(f'ISA TEST FAIL ID={seq&0x0fffffff} (LED {0xe0|((seq&31)):02X}); signature={sig:08X}')
                    raise RuntimeError(f'ISA mismatch loop={i} seq={seq:08X} sig={sig:08X}')
                if baseline_wdt is None: baseline_wdt=wdt
                if wdt!=baseline_wdt: raise RuntimeError(f'watchdog reset unexpectedly: {baseline_wdt}->{wdt}')
                if i%10==0 or i==args.loops:
                    print(f'ISA TORTURE {i}/{args.loops} PASS, sig={sig:08X}, WDT={wdt}',flush=True)
            print(f'PASS: {args.loops} ISA torture iterations on RV32EC core',flush=True)
    except (OSError,RuntimeError,ValueError,TimeoutError,ImportError) as exc:
        sys.exit(f'ISA TORTURE FAILURE (NOT signoff): {exc}')
if __name__=='__main__': main()
