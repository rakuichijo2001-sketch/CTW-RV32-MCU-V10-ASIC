#!/usr/bin/env python3
"""Load V8 IRQ firmware; then test Timer, GPIO and UART interrupts via ESP32."""
import argparse
from pathlib import Path
import sys
import time
from upload_esp32 import BAUD, upload, wait_line

EVENTS = ('IRQ TIMER PASS', 'IRQ TX PASS') + tuple(
    event for n in range(4) for event in (f'IRQ GPIO {n} PASS', f'IRQ RX {n} PASS')
) + ('IRQ PASS ALL',)


def irq_test(ser, report=print):
    ser.write(b'IRQ\n')
    for expected in EVENTS:
        line = wait_line(ser, lambda s: s.startswith('IRQ '), 4)
        if line != expected:
            raise RuntimeError(f'Expected {expected}, got {line}')
        report(line)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--port', required=True)
    p.add_argument('--no-upload', action='store_true')
    a = p.parse_args()
    try:
        import serial
        with serial.Serial(a.port, BAUD, timeout=0.1, write_timeout=5) as ser:
            ser.dtr = False
            ser.rts = False
            time.sleep(1.5)
            ser.reset_input_buffer()
            ser.write(b'PING\n')
            wait_line(ser, lambda s: s == 'CTW3', 4)
            if not a.no_upload:
                data = (Path(__file__).resolve().parent.parent / 'firmware/irq_demo.bin').read_bytes()
                size, crc = upload(ser, data)
                print(f'Flash verified: {size} bytes, CRC32 {crc:08X}')
            irq_test(ser)
        print('PASS: timer, GPIO, UART RX/TX interrupts, ISR return and masked pending test.')
    except (OSError, RuntimeError, ValueError, ImportError) as e:
        sys.exit(f'IRQ test failed: {e}')

if __name__ == '__main__':
    main()
