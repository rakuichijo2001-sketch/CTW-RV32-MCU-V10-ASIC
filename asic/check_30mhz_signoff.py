#!/usr/bin/env python3
"""Fail-closed physical signoff for the 30 MHz / SKY130A / 4x2 MCU.

Reads all nine post-route STA corners plus final Magic DRC, KLayout DRC and LVS
reports. Also accepts an exported pnr_diagnostics ZIP for reproducibility.
"""
import argparse
import json
import os
from pathlib import Path
import re
import sys
import zipfile

CORNERS = (
    "nom_tt_025C_1v80", "nom_ss_100C_1v60", "nom_ff_n40C_1v95",
    "min_tt_025C_1v80", "min_ss_100C_1v60", "min_ff_n40C_1v95",
    "max_tt_025C_1v80", "max_ss_100C_1v60", "max_ff_n40C_1v95",
)

class Reports:
    def __init__(self, path):
        self.path = Path(path)
        self.zip = zipfile.ZipFile(path) if self.path.is_file() else None

    def read(self, rel):
        if self.zip:
            return self.zip.read(rel).decode("utf-8")
        return (self.path / rel).read_text(encoding="utf-8")

    def metrics(self, rel):
        data = json.loads(self.read(rel))
        if not isinstance(data.get("metrics"), dict):
            raise ValueError("missing metrics: " + rel)
        return data["metrics"]

def check(reports, config_path, info_path):
    problems, notes = [], []
    config = json.loads(Path(config_path).read_text(encoding="utf-8"))
    info = Path(info_path).read_text(encoding="utf-8")
    for key, expected in (
        ("CLOCK_PERIOD", 33.333),
        ("MAX_TRANSITION_CONSTRAINT", 1.5),
        ("MAX_FANOUT_CONSTRAINT", 6),
        ("PNR_SDC_FILE", "dir::project.sdc"),
        ("SIGNOFF_SDC_FILE", "dir::project.sdc"),
        ("RUN_KLAYOUT_DRC", 1),
    ):
        if config.get(key) != expected:
            problems.append(f"{key} changed: {config.get(key)!r}, expected {expected!r}")
    if not re.search(r"^\s*clock_hz:\s*30000000\s*$", info, re.M):
        problems.append("info.yaml clock_hz is not 30000000")
    if not re.search(r"""^\s*tiles:\s*["']?4x2["']?\s*$""", info, re.M):
        problems.append("info.yaml tiles are not 4x2")
    try:
        sta = reports.metrics("56-openroad-stapostpnr/state_out.json")
        drc = reports.metrics("66-checker-klayoutdrc/state_out.json")
        lvs = reports.metrics("70-checker-lvs/state_out.json")
    except (OSError, KeyError, ValueError) as exc:
        return problems + [f"Missing/invalid final physical report: {exc}"], notes, {}

    def zero(data, key, desc):
        if data.get(key) != 0:
            problems.append(f"{desc}: {key} = {data.get(key)!r}, expected 0")

    def positive(data, key, desc):
        val = data.get(key)
        if not isinstance(val, (int, float)) or val < 0:
            problems.append(f"{desc}: {key} = {val!r}, expected >= 0 ns")

    for corner in CORNERS:
        suffix = "__corner:" + corner
        for metric in (
            "design__max_slew_violation__count",
            "design__max_cap_violation__count",
            "timing__setup_vio__count", "timing__hold_vio__count",
            "timing__setup__tns", "timing__hold__tns",
        ):
            zero(sta, metric + suffix, corner)
        for metric in ("timing__setup__ws", "timing__hold__ws"):
            positive(sta, metric + suffix, corner)

    for data, key in (
        (drc, "magic__drc_error__count"),
        (drc, "klayout__drc_error__count"),
        (drc, "route__drc_errors"),
        (lvs, "design__lvs_error__count"),
        (lvs, "design__lvs_unmatched_device__count"),
        (lvs, "design__lvs_unmatched_net__count"),
        (lvs, "design__lvs_unmatched_pin__count"),
        (lvs, "design__power_grid_violation__count"),
        (lvs, "route__antenna_violation__count"),
    ):
        zero(data, key, "Final DRC/LVS/PDN/antenna")

    # Nine established max-fanout violations are CTS internal branches only.
    # Verify their exact names. A new violation on a data net is NOT waived.
    fcount = sta.get("design__max_fanout_violation__count")
    if fcount is None:
        problems.append("Max-fanout count missing")
    elif fcount:
        try:
            content = reports.read("56-openroad-stapostpnr/max_ss_100C_1v60/sta.log")
            section = re.search(r"\nmax fanout\n(.*?)\n\n\n", content, re.S)
            if section is None:
                raise ValueError("fanout pin table missing")
            pins = [line.strip().split()[0] for line in section.group(1).splitlines()
                    if "(VIOLATED)" in line]
            expected = {"clkbuf_0_clk/X"} | {f"clkbuf_3_{n}_0_clk/X" for n in range(8)}
            if set(pins) != expected or len(pins) != fcount:
                problems.append("Unapproved fanout violations: " + str(pins))
            else:
                for corner in CORNERS:
                    key = "design__max_fanout_violation__count__corner:" + corner
                    if sta.get(key) != len(expected):
                        problems.append(f"Fanout exception changed at {corner}: {sta.get(key)}")
                notes.append("CTS-only exception: 9 intermediate clock-buffer nets; no data-path fanout waived")
        except (OSError, KeyError, ValueError) as exc:
            problems.append("Cannot audit CTS exception: " + str(exc))

    summary = {
        "setup_ws_ns": sta.get("timing__setup__ws"),
        "hold_ws_ns": sta.get("timing__hold__ws"),
        "slew_violations": sta.get("design__max_slew_violation__count"),
        "cap_violations": sta.get("design__max_cap_violation__count"),
        "fanout_clock_exceptions": fcount,
        "magic_drc": drc.get("magic__drc_error__count"),
        "klayout_drc": drc.get("klayout__drc_error__count"),
        "lvs": lvs.get("design__lvs_error__count"),
    }
    return problems, notes, summary

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--reports", default="runs/wokwi")
    ap.add_argument("--config", default="src/config.json")
    ap.add_argument("--info", default="info.yaml")
    args = ap.parse_args()
    try:
        errors, notes, metrics = check(Reports(args.reports), args.config, args.info)
    except (OSError, KeyError, ValueError, json.JSONDecodeError) as exc:
        errors, notes, metrics = [str(exc)], [], {}
    status = "FAIL" if errors else "PASS"
    print("30 MHz SKY130 4x2 physical signoff:", status)
    for k, v in metrics.items():
        print(f"{k}: {v}")
    for n in notes:
        print("NOTE:", n)
    for e in errors:
        print("ERROR:", e)
    if path := os.getenv("GITHUB_STEP_SUMMARY"):
        with open(path, "a", encoding="utf-8") as fd:
            fd.write(f"\n### 30 MHz physical signoff: {status}\n")
            for k, v in metrics.items():
                fd.write(f"\n- {k}: {v}")
            for e in errors:
                fd.write(f"\n- FAIL: {e}")
            fd.write("\n")
    return 1 if errors else 0

if __name__ == "__main__":
    sys.exit(main())
