"""Run the same QSPI and firmware test against the TT standard-cell netlist."""
import os
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
test = root / "test"
log = test / "output" / "gl.log"
log.parent.mkdir(exist_ok=True)
suite = ET.Element("testsuite", name="CTW RV32 MCU", tests="1", failures="0")
case = ET.SubElement(suite, "testcase", name="QSPI boot and MCU functions")
pdk = Path(os.environ.get("PDK_ROOT", "/home/runner/pdk")) / "sky130A"
cells = pdk / "libs.ref" / "sky130_fd_sc_hd" / "verilog"
tb_sources = [*sorted((root / "fpga").glob("*.sv")), test / "tb_v3.sv"]
cmd = [
    "iverilog", "-g2012", "-DFUNCTIONAL", "-DUSE_POWER_PINS", "-DGL_TEST", "-DASIC", "-DGATE_SMOKE",
    "-s", "tb_v3", "-o", str(test / "tt-gl.vvp"),
    str(cells / "primitives.v"), str(cells / "sky130_fd_sc_hd.v"),
    str(test / "gate_level_netlist.v"), *map(str, tb_sources)
]
error = None
with log.open("w") as f:
    try:
        subprocess.run(cmd, cwd=root, stdout=f, stderr=subprocess.STDOUT, check=True)
        subprocess.run(["vvp", str(test / "tt-gl.vvp")], cwd=root, stdout=f,
                       stderr=subprocess.STDOUT, check=True, timeout=900)
    except (OSError, subprocess.SubprocessError) as exc:
        error = str(exc)
report = log.read_text()
print(report)
if error is not None or "PASS V6 gate" not in report:
    suite.set("failures", "1")
    ET.SubElement(case, "failure", message=error or "Missing completion marker").text = report
ET.ElementTree(suite).write(test / "results.xml", encoding="UTF-8", xml_declaration=True)

if suite.get("failures") != "0":
    raise SystemExit(1)
