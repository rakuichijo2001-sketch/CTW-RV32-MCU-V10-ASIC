#!/usr/bin/env python3
"""Consistency check; does not claim ASIC timing closure."""
from pathlib import Path
import json,re
ROOT=Path(__file__).resolve().parents[1]
info=(ROOT/'info.yaml').read_text()
top=(ROOT/'src/tt_um_ctw_rv32_mcu.v').read_text()
fpga=(ROOT/'ctw_de10_top.sv').read_text()
config=json.loads((ROOT/'src/config.json').read_text())
get=lambda pattern,s: int(re.search(pattern,s).group(1))
hz=get(r'clock_hz:\s*(\d+)',info)
period=config['CLOCK_PERIOD']
asic_hz=get(r'CLK_HZ=(\d+)',top)
div=get(r'UART_DIV=(\d+)',top)
fpgahz=get(r'\.CLK_HZ\((\d+)\)',fpga)
assert hz==asic_hz and 1e9/period==hz,(hz,asic_hz,period)
assert fpgahz==50000000 and get(r'UART_DIV\((\d+)\)',fpga)==434
assert abs(hz/div-115200)/115200<0.02
assert hz%1000000==0
print(f'ASIC candidate: {hz/1e6:g} MHz, {period} ns; UART={hz/div:.1f} baud (div={div})')
print(f'FPGA actual: {fpgahz/1e6:g} MHz (unchanged, separate Quartus constraints)')
print(f'ASIC I2C 100kHz divider: {hz//200000 -1}')
print(f'ASIC watchdog tick: {(hz+999)//1000} clocks/ms')
print(f'PSRAM 6us CS guard: {6*(hz//1000000)} system clocks')
print(f'Boot QSPI SCK nominal: {hz/(2*((hz+4999999)//5000000)):.0f} Hz')
print('Clock metadata CONSISTENT; ASIC STA/P&R NOT RUN')
