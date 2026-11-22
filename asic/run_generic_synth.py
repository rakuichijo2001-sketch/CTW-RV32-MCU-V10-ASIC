#!/usr/bin/env python3
"""Optional Yosys generic synthesis smoke-test. NOT SKY130 cell area or timing."""
import subprocess,shutil,sys,re
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT/'asic'))
from preflight import sources

def main():
    if subprocess.call([sys.executable,str(ROOT/'asic/preflight.py')])!=0:return 1
    exe=shutil.which('yosys')
    if not exe:
        print('NOT RUN: yosys is not installed. Use official Tiny Tapeout GDS workflow.');return 2
    info=(ROOT/'info.yaml').read_text()
    src=[str(ROOT/'src'/s) for s in sources(info)]
    out=ROOT/'asic/reports';out.mkdir(exist_ok=True,parents=True)
    script='read_verilog -sv '+' '.join('"'+s+'"' for s in src)+'; hierarchy -check -top tt_um_ctw_rv32_mcu; proc; opt; check -assert; synth -top tt_um_ctw_rv32_mcu; check -assert; stat'
    print('YOSYS generic synth: NOT technology-mapped Sky130')
    p=subprocess.run([exe,'-Q','-l',str(out/'yosys_generic.log'),'-p',script],cwd=ROOT)
    if p.returncode==0: print('GENERIC SYNTH PASS — area (um^2) & STA still unknown')
    else:print('GENERIC SYNTH FAIL; see asic/reports/yosys_generic.log')
    return p.returncode
if __name__=='__main__':sys.exit(main())
