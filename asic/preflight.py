#!/usr/bin/env python3
"""Read-only RTL freeze and Tiny Tapeout submission preflight (stdlib only).
Does not synthesize RTL, calculate area, perform STA, or approve signoff.
"""
from pathlib import Path
import json, hashlib, re, sys

ROOT=Path(__file__).resolve().parent.parent
A=ROOT/'asic'

def get_info_field(txt,key):
    m=re.search(r'^\s*'+re.escape(key)+r':\s*["\']?([^"\'\n#]+)',txt,re.M)
    if not m: raise ValueError('info.yaml missing '+key)
    return m.group(1).strip()

def sources(txt):
    match=re.search(r'^  source_files:\s*\n((?:    - [^\n]+\n)+)',txt,re.M)
    if not match: raise ValueError('info.yaml source_files list missing or empty')
    return [s.strip().strip('"\'') for s in re.findall(r'^    - (.*)$',match.group(1),re.M)]

def main():
    errs=[]; notes=[]
    info=(ROOT/'info.yaml').read_text(encoding='utf8')
    config=json.loads((ROOT/'src/config.json').read_text(encoding='utf8'))
    manifest=json.loads((A/'rtl_freeze_manifest.json').read_text(encoding='utf8'))
    for r,h in manifest['sha256'].items():
        p=ROOT/r
        if not p.is_file(): errs.append('MISSING freeze file: '+r);continue
        raw=p.read_bytes()
        calc=hashlib.sha256(raw).hexdigest()
        if calc!=h:
            # Git normalizes text to LF, while Windows may check out CRLF.
            # Accept only that byte-for-byte line-ending conversion; do not
            # suppress real RTL/source modifications or regenerate the manifest.
            normalized=raw.replace(b'\r\n',b'\n')
            if normalized!=raw and hashlib.sha256(normalized).hexdigest()==h:
                notes.append('CRLF checkout matches frozen LF content: '+r)
            else:
                errs.append('CHANGED since freeze: '+r)
    if get_info_field(info,'top_module')!='tt_um_ctw_rv32_mcu': errs.append('Top mismatch')
    if get_info_field(info,'tiles')!='4x2': errs.append('Tile setting changed')
    if get_info_field(info,'clock_hz')!='20000000': errs.append('ASIC clock_hz mismatch')
    if get_info_field(info,'yaml_version')!='6': errs.append('Unexpected YAML version')
    if config.get('CLOCK_PERIOD')!=50: errs.append('CLOCK_PERIOD not 50ns')
    if config.get('CLOCK_PORT')!='clk': errs.append('CLOCK_PORT not clk')
    sl=sources(info)
    if len(sl)!=len(set(sl)): errs.append('Duplicate RTL source in info.yaml')
    if len(sl)!=17: notes.append('Expected 17 sources, found '+str(len(sl)))
    all_modules=[]
    for src in sl:
        p=ROOT/'src'/src
        if not p.is_file(): errs.append('Missing declared source '+src);continue
        txt=p.read_text(encoding='utf8')
        # Strip comments for gross HDL hygiene checks. Not a Verilog parser.
        code=re.sub(r'/\*.*?\*/|//[^\n]*','',txt,flags=re.S)
        all_modules+=re.findall(r'^\s*module\s+(\w+)',code,re.M)
        for name,pattern in [('$readmem',r'\$readmem[bh]\b'),('initial',r'\binitial\b'),('simulation termination',r'\$(?:finish|stop|fatal)\b')]:
            if re.search(pattern,code): notes.append(f'REVIEW: {name} found in {src}')
    if 'tt_um_ctw_rv32_mcu' not in all_modules: errs.append('Top module not found')
    if len(all_modules)!=len(set(all_modules)): errs.append('Repeated module declaration')
    top=(ROOT/'src/tt_um_ctw_rv32_mcu.v').read_text()
    for p in ['ui_in','uio_in','uo_out','uio_out','uio_oe','ena','clk','rst_n']:
        if not re.search(r'\b'+p+r'\b',top):errs.append('Top port missing '+p)
    gds=(ROOT/'.github/workflows/gds.yaml').read_text()
    if 'ttsky26d' not in gds:errs.append('Workflow missing SKY26d release tag')
    if 'sky130A' not in gds:errs.append('Workflow not targeting sky130A')
    if config.get('RUN_KLAYOUT_DRC')==0:notes.append('KLayout DRC disabled in project config; require official precheck/full signoff')
    if config.get('RUN_KLAYOUT_XOR')==0:notes.append('KLayout XOR disabled in config; do not claim XOR signoff')
    print('CTW V10 ASIC STAGE-1 PREFLIGHT (offline, no PDK/STA)')
    print('Baseline: V10-GP-TP-GPR-FIX  |  TT SKY26d/sky130A')
    print('Top:',get_info_field(info,'top_module'))
    print('RTL files:',len(sl),'| modules found:',len(all_modules),'| tiles:',get_info_field(info,'tiles'))
    print('ASIC clock target: 20 MHz (50 ns) | manifest files:',len(manifest['sha256']))
    for n in notes:print('NOTE:',n)
    for e in errs:print('ERROR:',e)
    if errs:print('PREFLIGHT FAIL — do not run hardening');return 1
    print('PREFLIGHT PASS — source/config manifest only; area, timing, physical signoff UNVERIFIED')
    return 0
if __name__=='__main__':sys.exit(main())
