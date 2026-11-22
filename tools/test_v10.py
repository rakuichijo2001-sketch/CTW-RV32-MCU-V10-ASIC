#!/usr/bin/env python3
"""V10 final pre-PD test: directed ISA/memory, watchdog recovery, 8/24h soak.

Reports and CSV are produced on the USER PC; no background service.
All frames are checked against independent Python software arithmetic.
Run only against V10 FPGA SOF + V10 ESP32 sketch.
"""
from __future__ import annotations
import argparse
import csv
from datetime import datetime, timezone
from pathlib import Path
import re
import sys
import time
from upload_esp32 import BAUD, upload, wait_line
from v10_reference import advance, INITIAL_SIGNATURE

LINE = re.compile(r"V10 ([SHWQ]) seq=([0-9A-F]{8}) sig=([0-9A-F]{8}) wd=(\d+)\Z")


def request(ser, command: str, timeout=25):
    ser.write(f"V10{command}\n".encode("ascii"))
    reply = wait_line(ser, lambda s: s.startswith("V10 "), timeout)
    matched = LINE.fullmatch(reply)
    if not matched or matched[1] != command:
        raise RuntimeError(f"Unexpected V10 frame: {reply!r}")
    return int(matched[2], 16), int(matched[3], 16), int(matched[4])


def execute(ser, hours: float, interval: float, csv_path: Path, no_wdt: bool = False):
    seq, signature, wdt = request(ser, 'S')
    expected = advance(INITIAL_SIGNATURE, 0, 4)
    if seq != 4 or signature != expected:
        raise RuntimeError(f"Directed ISA/memory check incorrect seq={seq} signature={signature:08X}, expected {expected:08X}")
    print(f"V10 directed PASS: 4 rounds, sequence={seq}, signature={signature:08X}", flush=True)
    if not no_wdt:
        seq, signature, wdt = request(ser, 'W', timeout=25)
        expected = advance(INITIAL_SIGNATURE, 0, 16)
        if seq != 16 or signature != expected or wdt < 1:
            raise RuntimeError(f"WDT reboot validation failed seq={seq} sig={signature:08X} count={wdt}")
        print(f"V10 watchdog PASS: autonomous reboot, count={wdt}", flush=True)
    expected_seq = seq
    expected_sig = signature
    start = time.monotonic()
    deadline = start + hours * 3600
    last_report = start
    packets = 0
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.writer(file)
        writer.writerow(["utc", "elapsed_seconds", "sequence", "signature", "watchdog_resets", "latency_seconds"])
        file.flush()
        while time.monotonic() < deadline:
            then = time.monotonic()
            got_seq, got_sig, got_wdt = request(ser, 'H')
            next_sig = advance(expected_sig, expected_seq, 16)
            if got_seq != ((expected_seq + 16) & 0xFFFFFFFF) or got_sig != next_sig:
                raise RuntimeError(f"Mismatch after {packets} packets: got seq={got_seq} sig={got_sig:08X}, expected seq={expected_seq+16} sig={next_sig:08X}")
            if got_wdt != wdt:
                raise RuntimeError(f"Unexpected watchdog reset: old={wdt}, new={got_wdt}")
            expected_seq, expected_sig = got_seq, got_sig
            packets += 1
            now = time.monotonic()
            writer.writerow([datetime.now(timezone.utc).isoformat(), round(now-start,3),
                             got_seq, f"{got_sig:08X}", got_wdt, round(now-then,4)])
            if packets % 50 == 0: file.flush()
            if now - last_report > 60:
                print(f"V10 SOAK: {int(now-start)}s, packets={packets}, rounds={expected_seq}, sig={expected_sig:08X}, WDT={got_wdt}",flush=True)
                file.flush()
                last_report = now
            remaining = interval - (now-then)
            if remaining > 0: time.sleep(remaining)
        file.flush()
    if hours == 0:
        print(('V10 DIRECTED PASS (watchdog test skipped).' if no_wdt else 'V10 DIRECTED + WATCHDOG PASS.') + ' Long-duration soak was NOT performed.', flush=True)
    else:
        print(f"V10 LONG SOAK PASS: {hours}h requested, {packets} packets, {expected_seq} stress rounds. CSV: {csv_path}", flush=True)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--port', required=True, help='e.g. COM12')
    ap.add_argument('--hours',type=float,default=8.0,help='soak duration; 0 for directed-only')
    ap.add_argument('--interval',type=float,default=0.05,help='minimum seconds between health responses')
    ap.add_argument('--no-upload',action='store_true')
    ap.add_argument('--firmware',type=Path,default=None,
                    help='optional diagnostic firmware binary; normally use original V10 image')
    ap.add_argument('--no-watchdog-test',action='store_true')
    ap.add_argument('--csv',type=Path,default=Path('logs/v10_soak.csv'))
    args=ap.parse_args()
    if args.hours < 0 or args.interval < 0: ap.error('hours and interval must be nonnegative')
    try:
        import serial
        with serial.Serial(args.port,BAUD,timeout=0.1,write_timeout=5) as ser:
            ser.dtr=False;ser.rts=False
            time.sleep(1.5)
            ser.reset_input_buffer()
            ser.write(b'PING\n')
            wait_line(ser, lambda s:s=='CTW3',4)
            if not args.no_upload:
                firmware_path=args.firmware if args.firmware else (Path(__file__).resolve().parents[1]/'firmware/v10_qualification.bin')
                payload=firmware_path.read_bytes()
                length,crc=upload(ser,payload)
                print(f'Flash verified: {length} bytes, CRC32 {crc:08X}',flush=True)
            # The programming protocol acknowledges RUN immediately after
            # releasing target reset. Do not send the first UART byte yet:
            # the MCU must finish its 6 ms+ QSPI Flash/PSRAM boot sequence.
            # V10B provides an explicit reset/reboot barrier: the ESP32 waits
            # 30 ms after releasing reset before acknowledging readiness.
            ser.write(b'V10B\n')
            wait_line(ser, lambda s: s == 'V10 RESET OK', 4)
            execute(ser,args.hours,args.interval,args.csv,args.no_watchdog_test)
    except (OSError,RuntimeError,ValueError,TimeoutError,ImportError) as exc:
        sys.exit(f'V10 FAILURE (NOT signoff): {exc}')

if __name__=='__main__':
    main()
