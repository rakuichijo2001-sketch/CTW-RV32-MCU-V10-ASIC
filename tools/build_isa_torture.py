#!/usr/bin/env python3
"""Compile V10 ISA torture image with LLVM/Clang (RV32EC/Zicsr)."""
import argparse, subprocess, pathlib, zlib, sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
SOURCES=['firmware/startup.S','firmware/v10_isa.S','firmware/v10_isa_torture.S','firmware/v10_isa_torture.c']

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--strict-gp-tp',action='store_true',help='Build expected-failure architectural conformance image')
    ap.add_argument('--clang',default='clang')
    ap.add_argument('--objcopy',default='llvm-objcopy')
    args=ap.parse_args()
    stem='v10_isa_strict_gp_tp' if args.strict_gp_tp else 'v10_isa_torture'
    elf=ROOT/f'firmware/{stem}.elf'
    img=ROOT/f'firmware/{stem}.bin'
    cmd=[args.clang,'--target=riscv32-unknown-elf','-march=rv32ec_zicsr',
         '-mabi=ilp32e','-Os','-ffreestanding','-fno-builtin','-nostdlib',
         '-fdata-sections','-ffunction-sections','-msmall-data-limit=0',
         '-Wl,-T,'+str(ROOT/'firmware/link_v10.ld'),
         '-Wl,--no-relax','-Wl,--gc-sections',
         *(['-DCTW_STRICT_GP_TP'] if args.strict_gp_tp else []),
         *(str(ROOT/p) for p in SOURCES),
         *([str(ROOT/'firmware/v10_isa_strict_gp_tp.S')] if args.strict_gp_tp else []),
         '-o',str(elf)]
    subprocess.run(cmd,check=True)
    subprocess.run([args.objcopy,'-O','binary',str(elf),str(img)],check=True)
    blob=img.read_bytes()
    if len(blob)>4096: raise SystemExit(f'EXCEEDS 4KiB linker limit: {len(blob)}')
    print(f'RV32EC ISA torture: {len(blob)} bytes, CRC32 {zlib.crc32(blob):08X}')
if __name__=='__main__': main()
