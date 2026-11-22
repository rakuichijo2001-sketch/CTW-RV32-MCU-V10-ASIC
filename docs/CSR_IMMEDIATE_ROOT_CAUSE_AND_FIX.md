# V10 ISA Torture: ID 225 / DE10 LED E1

> **Revision notice (V10 GP/TP GPR FIX):** The expected strict-ID231 failure described below belongs to the previous CSR-IMMEDIATE-FIX/stock TinyQV RTL. In this new candidate, x3/x4 use the normal writable GPR logic, and strict PASS on newly compiled DE10 is a release gate. See `docs/GP_TP_GPR_ARCHITECTURE_FIX.md`. This has not yet been confirmed on FPGA.


## Observation on physical DE10 + ESP32

`py tools/test_v10_isa_torture.py --port COM12 --loops 100` uploaded the **original**, unpatched 3828-byte image, CRC32 `0237D352`, then returned `ISA TEST FAIL ID=225 (LED E1); signature=BAD000E1` on the first requested run.

This is **not** a host UART problem or Flash corruption: the firmware boots, executes the earlier checks, and returns the exact failure ID. The host does not show actual `mepc`; it only reports the failed equality. Diagnosis below is based on direct RTL inspection and the failing instruction.

## Root cause

ID 224 tests register-form `CSRRW mepc, t0` and passed; ID 225 executes:

```asm
csrrwi t2, 0x341, 16
csrrs  t2, 0x341, zero
li a0, 225
li a5, 0x10
bne t2, a5, .Lrestore_mepc
```

In RISC-V `CSRRWI`, `CSRRSI`, `CSRRCI`, bits `[19:15]` encode a **5-bit zero-extended immediate (zimm)**, *not* GPR `rs1`. In the V10 baseline, `src/core.v` always supplied GPR `data_rs1` to CSR writes; `src/cpu.v`/`decode.v` truncated instruction bits `[19:15]` to a four-bit architectural register index. With `zimm=16`, that selects `x0` instead of `16` on a 16-register RV32E core, explaining the failure.

The `mepc` register also only implemented CSR write/replacement but not CSR set/clear. This gap is exposed by new directed tests of `CSRRSI` and `CSRRCI`.

## RTL changes (same memory map and pinout)

- `src/cpu.v`: latch `instr[19:15]` as `csr_zimm[4:0]` alongside decoded operands and provide it to the core.
- `src/core.v`: for `funct3[2]=1` CSR operations, use `csr_zimm` as the CSR source operand, sliced into 4-bit nibbles for the serial datapath. Register-form CSR instructions retain the existing GPR path.
- `src/core.v`: add `mepc` bitwise set/clear behavior for CSRR[S/C] and CSRR[S/C]I, using the old nibble when doing a read-modify-write.
- No change to the external buses, QSPI, PSRAM, interrupts, clock configuration, or ESP32 code.

## Added physical tests

- 225: CSRRWI `zimm=16`, expected MEPC `0x10`.
- 226: CSRRWI `zimm=30`, expected `0x1E`.
- 227: CSRRCI `zimm=16`, expected `0x0E`.
- 228: CSRRSI `zimm=16`, expected `0x1E`.
- 229: CSRRSI `zimm=0`, expected unchanged `0x1E`.
- 230: CSRRCI `zimm=0`, expected unchanged `0x1E`.

The test intentionally stays with even `mepc` values because RISC-V requires instruction addresses to be aligned. All earlier IDs remain enabled; no test is skipped.

## Builds and limitations

- `firmware/v10_isa_torture.bin`: 3928 bytes, CRC32 `5052D8B0`.
- `firmware/v10_isa_strict_gp_tp.bin`: 4024 bytes, CRC32 `194ADA6A`.
- Both compile for `rv32ec_zicsr / ilp32e` and are <= 4096 bytes.
- Python unit tests include targeted assertions for the new CSR path, but there is **no simulator or Quartus available** in this environment; the new RTL and firmware have NOT been verified on the actual DE10 or with ASIC STA. The `test/tb_v10_csr_immediate.sv` testbench is supplied for `make test-v10-csr-rtl` with Icarus Verilog on the engineer's machine.
- The stock `gp` and `tp` limitations remain. The strict architecture suite is expected to return FAIL ID 231, even after this CSR fix; that issue needs a separate architectural decision before an RV32EC compliance claim.

## Required physical verification

1. **Stop using the old `.sof`.** Open `ctw_de10.qpf` from this fixed project directory, do a **full Quartus compilation**, verify the `.sof` timestamp, and program DE10.
2. Keep the **working ESP32 V10 sketch and wiring** unchanged.
3. Run `py tools/test_v10_isa_torture.py --port COM12 --loops 1`. Expected upload: **3928 bytes CRC32 5052D8B0**.
4. Once one loop passes, run `py tools/test_v10_isa_torture.py --port COM12 --loops 100 --no-upload`, then 10000 loops if desired.
5. Run `py tools/run_v10_regression.py --port COM12`; the regression overwrites the Flash with other images.
6. Run `py tools/test_v10.py --port COM12 --hours 0` to recheck ISA/PSRAM and watchdog. The full eight-hour soak must be repeated after the RTL change before qualification signoff.
7. The **strict** RV32E check (`--firmware firmware/v10_isa_strict_gp_tp.bin --loops 1`) is an intentional expected-FAIL probe for x3/x4, and should not be run as a passing release gate.

Do not move to ASIC physical signoff until RTL functionality, ISA compliance gaps, timing and area have been explicitly reviewed.
