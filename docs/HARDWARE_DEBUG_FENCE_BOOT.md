# V10 field finding and recovery: FENCE decode + boot synchronization

## Observed on user's actual DE10-Nano / ESP32

- V10 peripheral regression passed all groups.
- `v10_qualification_fence_nop.bin` (CRC32 `45E57C9C`) timed out immediately after upload, but **passed after `--no-upload --no-watchdog-test`**: 4 stress rounds and signature `25261684`.
- Original `v10_qualification.bin` (CRC32 `BBE53C4E`) timed out immediately after upload and **still timed out after `--no-upload --no-watchdog-test`**.
- These tests ran on the **existing bitstream** and did not establish that a newly compiled bitstream containing the FENCE decoder fix works.

## Changes in this consolidated project

1. `src/decode.v`: base `FENCE` (opcode 0x0F, funct3=000) retires as an architectural no-op for this blocking, in-order CPU. **FENCE.I remains unsupported**.
2. `tools/test_v10.py`: after programming **or** when `--no-upload`, send `V10B` to ESP32, which resets target and waits 30 ms before replying `V10 RESET OK`. Then begin UART testing. Fixes race with QSPI power-up/boot.
3. Correct reporting when `--no-watchdog-test` is used: a directed PASS is not mislabeled as watchdog PASS.

## Steps on the DE10

1. **Important:** open `ctw_de10.qpf` from THIS directory, run Quartus full compile, confirm new output `.sof` timestamp, program the new `.sof` into DE10. Merely changing source files does not modify the current FPGA fabric.
2. Keep all current wiring. Keep the working V10 ESP32 sketch; no changes needed there.
3. Close ESP32 Serial Monitor. At the project root run:
   `py tools/test_v10.py --port COM12 --hours 0 --no-watchdog-test`
   This uploads original FENCE firmware (CRC32 `BBE53C4E`), waits for boot, and exercises directed ISA/PSRAM. Expected: directed PASS, seq=4, signature=25261684.
4. If directed test passes, run watchdog separately:
   `py tools/test_v10.py --port COM12 --hours 0`
   Expected: directed PASS + watchdog PASS after autonomous reboot.
5. If both pass, run regression, reset cycling, then 8-hour soak.

If either firmware fails on the newly compiled SOF, record LED immediately after failure and the complete PowerShell output. Do not proceed to soak/signoff.

## Verification limitations

- These changes were verified by static inspection of supplied RTL and the exact host scripts, plus host Python unit tests.
- No Quartus, Icarus, ESP32, or physical hardware was available during repackaging: **not a hardware PASS or a signoff claim**.
- Original Flash/PSRAM are still FPGA models, not physical memory ICs.
