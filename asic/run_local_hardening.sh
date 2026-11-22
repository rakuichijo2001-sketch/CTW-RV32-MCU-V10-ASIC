#!/usr/bin/env bash
set -euo pipefail
# Run from Linux/WSL with Python 3.11+, Docker, LibreLane, sky130A PDK installed.
cd "$(dirname "$0")/.."
python3 asic/preflight.py
: "${PDK_ROOT:?Set PDK_ROOT to the matching sky130A PDK root}"
: "${PDK:?Set PDK=sky130A}"
if [[ "$PDK" != "sky130A" ]]; then echo 'Wrong PDK; expected sky130A' >&2; exit 2; fi
if [[ ! -f tt/tt_tool.py ]]; then echo 'Missing tt/tt_tool.py. Follow official setup: git clone https://github.com/TinyTapeout/tt-support-tools tt' >&2; exit 2; fi
if ! command -v docker >/dev/null; then echo 'Docker not installed' >&2; exit 2; fi
if ! docker info >/dev/null 2>&1; then echo 'Docker daemon not running' >&2; exit 2; fi
mkdir -p asic/reports
./tt/tt_tool.py --create-user-config 2>&1 | tee asic/reports/00_create_user_config.log
set -o pipefail
./tt/tt_tool.py --harden 2>&1 | tee asic/reports/01_harden.log
./tt/tt_tool.py --print-warnings 2>&1 | tee asic/reports/02_warnings.log
printf '\nHardening command completed. Inspect cell area, setup/hold slack, DRC/LVS and official precheck before PASS.\n'
