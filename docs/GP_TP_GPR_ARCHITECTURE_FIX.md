# V10 architectural GPR fix — strict RV32E ID=231 / LED E7

## Observed physical-board evidence, 22 November 2026

- V10 CSR-IMMEDIATE-FIX hardware, firmware 3928 B CRC32 `5052D8B0`: **ISA TORTURE 10000/10000 PASS**, `WDT=0` (user provided log).
- Strict image 4024 B CRC32 `194ADA6A` returned **FAIL ID=231, LED E7** on first iteration, which is the `gp/x3` GPR read-after-write check. The `tp/x4` check ID=232 was not reached.
- The result is expected on the original TinyQV source (`src/register.v`): `gen_reg_gp` and `gen_reg_tp` return fixed nibble constants instead of writable register contents. In RV32E both x3 and x4 must be ordinary writable GPRs. This prevents claiming RV32E compatibility, regardless of the 10,000-loop ordinary ISA suite.

## Exact RTL modification (one file)

`src/register.v`: delete the special `i==3` / `i==4` generate branches so x1–x15 all use the **existing**, verified nibble-serial `gen_reg_normal` logic. Preserve x0's hard-wired zero behavior. No changes to CPU decoder, CSR logic, interrupt, bus, SPI, PSRAM, WDT, MMIO, pinout, or physical clock.

**Cost:** 2 additional architectural 32-bit registers (64 storage bits plus read/write selection logic), not necessarily just 64 standard cells after synthesis. Re-run area and STA at ASIC 20-MHz target, 4×2 tile fit is unverified.

**Compatibility caveat:** Original TinyQV includes some nonstandard compressed instruction encodings that rely on x3/x4 containing fixed pointer-like values. This patch deliberately prioritizes standard writable RV32E GPR semantics; any firmware using these TinyQV-specific encodings must be audited/ported or independently tested. This is NOT a proof that every instruction encoding now meets the RV32EC specification. Illegal/reserved opcode behavior, exception semantics, and 100% encoding coverage remain open signoff items.

## Verification order (fresh FPGA compilation is mandatory)

1. Keep original `CTW-RV32-MCU-V10-CSR-IMMEDIATE-FIX` `.sof` and source as an immutable fallback. This is a **new RTL build**, not a firmware-only change.
2. Open the **new project's** `ctw_de10.qpf` in Quartus, run a full Compile, and program the NEW `.sof` to DE10-Nano. Keep the existing verified ESP32 sketch, wire map and 50-MHz FPGA clock.
3. Test the strict firmware **first** (it is intentionally the shortest discriminating test):

   ```powershell
   py tools/test_v10_isa_torture.py --port COM12 --firmware firmware/v10_isa_strict_gp_tp.bin --loops 1
   ```

   **Required:** `PASS: 1 ISA torture iterations ...` with firmware CRC32 `194ADA6A`. If still ID 231, verify the actual SOF was recompiled and programmed; if ID 232, x3 is fixed but x4 still fails.
4. Reflash ordinary ISA firmware and run 100 iterations, then 10,000 if 100 PASS:

   ```powershell
   py tools/test_v10_isa_torture.py --port COM12 --loops 100
   py tools/test_v10_isa_torture.py --port COM12 --loops 10000 --no-upload
   ```

   Ordinary image CRC32 `5052D8B0`; `--no-upload` tests the image already in Flash, not the strict test image.
5. Repeat full peripherals, watchdog, 100 resets and 8-hour soak **on this new SOF**:

   ```powershell
   py tools/run_v10_regression.py --port COM12
   py tools/test_v10.py --port COM12 --hours 0
   py tools/test_v10_reset.py --port COM12 --cycles 100
   py tools/test_v10.py --port COM12 --hours 8 --csv logs/v10_gp_tp_8h.csv
   ```

6. On a workstation with Icarus Verilog installed, the isolated GPR unit test is:

   ```bash
   make test-v10-gpr-rtl
   ```

   Run the remaining Icarus RTL suites too (`make test-v10-csr-rtl test-v10-fence test-v10-prepd`).
7. Before ASIC implementation: inspect RVC reserved/custom encodings, add independent reference-model/illegal-opcode tests, and check area/STA against 4×2 and 20 MHz targets.

## Validation boundary

This package contains a **proposed** RTL fix with accompanying HDL unit test and unchanged, previously proven firmware images. It has **not** been simulated or run on a real DE10 board in the packaging environment. Successful GCC/LLVM assembly or Python static checks are not hardware proofs. No ASIC timing/area or Tiny Tapeout signoff is claimed.
