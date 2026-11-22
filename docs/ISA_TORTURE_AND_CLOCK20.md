# CTW RV32 MCU V10: ISA TORTURE + ASIC 20 MHz CANDIDATE

> **Revision notice (V10 GP/TP GPR FIX):** The expected strict-ID231 failure described below belongs to the previous CSR-IMMEDIATE-FIX/stock TinyQV RTL. In this new candidate, x3/x4 use the normal writable GPR logic, and strict PASS on newly compiled DE10 is a release gate. See `docs/GP_TP_GPR_ARCHITECTURE_FIX.md`. This has not yet been confirmed on FPGA.


## 0. Scope and exact validation claims

- Baseline from `CTW-RV32-MCU-V10-CPU-BOOT-FIX`: user verified 8-hour FPGA soak, 9,084,352 stress rounds, 100/100 reset cycles.
- DE10 FPGA still uses **50 MHz** (`CLOCK_50`, QSF/SDC period 20 ns). This candidate does NOT change the proven FPGA clock or pinout.
- Tiny Tapeout silicon clock **candidate** changed from 10 to **20 MHz** by editing `info.yaml`, `src/config.json`, and the ASIC wrapper parameter. This is only a timing target: **no synthesis, STA, timing closure, P&R, or silicon test** is claimed.
- ISA torture firmware and host script are new, compiled/checked statically here. **No new on-board PASS has been observed yet.**
- Do NOT claim full RISC-V compliance even if the new directed suite passes. TinyQV hardwires `gp=x3` and `tp=x4` (`src/register.v`). These are expected to fail standard RV32E GPR tests.

## 1. What gets exercised

| Class | Test coverage | Status |
| --- | --- | --- |
| RV32E R-type: `ADD SUB SLL SLT SLTU XOR SRL SRA OR AND` | 55+ generated tests + existing directed checks, corner and seeded pseudo-random operands | Firmware ready; DE10 run pending |
| RV32E I-type: `ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI` | 15 explicit boundary cases + existing tests | Firmware ready; DE10 run pending |
| `LUI AUIPC JAL JALR`, six branches | Original 40-check suite plus explicit compressed jumps | Firmware ready; DE10 run pending |
| `LB LBU LH LHU LW SB SH SW` | Original stack/byte-lane tests; V10 PSRAM stress remains separate | Previously passed with baseline, stronger memory compliance tests still needed |
| `FENCE` | 32-bit standard FENCE with original RTL decoder fix | Previously passed with baseline |
| `C.*` | Explicit c.nop, c.li, c.addi, c.addi4spn, c.swsp/c.lwsp, c.sw/c.lw, c.srai, c.srli, c.andi, c.sub, c.xor, c.or, c.and, c.slli, c.mv, c.add, c.lui, c.addi16sp, c.beqz/bnez, c.j, c.jal, c.jr, c.jalr | Compiled/inspected, DE10 pending |
| `CSR` | CSRRS/CSRRC/CSRRSI/CSRRCI cycle reads, CSRRW/CSRRWI mepc write/readback + restore | Compiled, DE10 pending |
| ECALL/EBREAK/MRET/IRQ | Original `v10_exceptions.bin` and `irq_demo.bin` regression | Previously passed with baseline |
| Strict x3/x4 (GP/TP) | Independent strict firmware `v10_isa_strict_gp_tp.bin` | Expected to FAIL: ID 231 or 232 on current RTL |
| Illegal opcode/trap, misaligned access, reserved RVC forms, full privileged ISA | Not exhaustively verified | Open / not signoff |

The generated 75 test vectors are mapped in `docs/ISA_TORTURE_VECTOR_MAP.csv`, with independent oracle results computed by `tools/generate_isa_torture.py` (fixed seed `0xC7A10`). The existing 40-check suite is also executed before each new suite run. It is **NOT** an exhaustive cross-product of encodings/registers/immediates; it is a harder directed pre-PD regression.

### Built images

- `firmware/v10_isa_torture.bin`: <=4 KiB, ordinary ISA torture; use first.
- `firmware/v10_isa_strict_gp_tp.bin`: <=4 KiB, strict GP/TP architectural conformance; expected to fail current design and must not be interpreted as a passing signoff.
- Original `firmware/v10_qualification.bin` remains unmodified (2136 bytes, CRC32 BBE53C4E) so the proven 8-hour test is reproducible.

## 2. Run on the existing FPGA `.sof`

No Quartus rebuild, no rewiring, and no ESP32 sketch reupload are needed for the ISA torture because the FPGA 50 MHz hardware and UART `V10S` protocol are unchanged. Use the **ESP32 V10 CPU-BOOT-FIX sketch** already validated.

From the new project root in Windows PowerShell:

```powershell
py tools/test_v10_isa_torture.py --port COM12 --loops 100
```

The host verifies firmware upload/CRC, requests a clean boot, and runs both ISA suites on every iteration. Success is `PASS: 100 ISA torture iterations on RV32EC core`. `seq=0xE0000000|ID` from the firmware reports a specific failure ID; for IDs 41..115, locate the row in `docs/ISA_TORTURE_VECTOR_MAP.csv`; for 200..225 inspect `firmware/v10_isa_torture.S`. An unexpected timeout requires inspecting the DE10 LED (32=ready, 35=running ISA, E0..FF=failure modulo 32, 36=last ISA PASS).

After passing 100 loops, try 10,000 loops without reflashing:

```powershell
py tools/test_v10_isa_torture.py --port COM12 --loops 10000 --no-upload
```

Optional **strict conformance probe**, expected to demonstrate the `gp/tp` limitation:

```powershell
py tools/test_v10_isa_torture.py --port COM12 --firmware firmware/v10_isa_strict_gp_tp.bin --loops 1
```

This strict image intentionally causes the script to print `ISA TEST FAIL ID=231` on the stock TinyQV design. It is a legitimate hardware issue rather than a software build problem. Do not claim full RV32EC compliance until GP/TP and missing trap/legal-instruction behavior are addressed.

## 3. ASIC clock changes

| Item | Frozen FPGA validated version | New ASIC candidate |
| --- | --- | --- |
| System clock | 50 MHz, Quartus `CLOCK_50` | 20 MHz target **pending STA** |
| Period | 20 ns DE10 `.sdc` | 50 ns `src/config.json` |
| UART | 434 at 50 MHz -> approx 115207 baud | 174 at 20 MHz -> approx 114943 baud |
| I2C 100 kHz divider | 249 | 99 |
| Watchdog ms tick | 50,000 clocks | 20,000 clocks |
| PSRAM CS guard | 300 clocks -> 6 us | 120 clocks -> 6 us |
| Boot QSPI SCK nominal | 2.5 MHz | 2.5 MHz |

All timing derived from the same `CLK_HZ` parameter in the ASIC pad wrapper. A user application for ASIC must compile with `CTW_CLK_HZ=20000000` (if it uses firmware/ctw_clock_config.h) or program the appropriate I2C divider dynamically. A fixed 249 divider intended for 50 MHz produces a slower I2C clock on a 20-MHz ASIC.

**Tiny Tapeout's `clk` is an input**; this project does not instantiate a PLL. Changing `info.yaml` or `CLOCK_PERIOD` does not magically increase a fabricated chip's maximum frequency. A physical clock source must drive the chip and the P&R/STA must close at the chosen period. Check `docs/evidence/*` for old historical estimates only; they are NOT V10 20 MHz timing signoff.

### Required ASIC clock signoff gates

1. Run RTL lint and simulation against the chosen shuttle PDK; no unexpected latches, CDC or asynchronous-reset issues.
2. Run synthesis, check standard-cell area and tile 4x2 fit; compare 10 MHz 100 ns and 20 MHz 50 ns.
3. Run P&R/CTS and signoff STA (including derived output-port loads, I/O delays, pad paths, QSPI return timing); record WNS/TNS and critical paths for process corners.
4. Validate QSPI Flash / dual PSRAM physical setup/hold, turnaround, initialization and tCEM, plus I2C pull-ups. FPGA simulation memory models are insufficient evidence here.
5. If 20 MHz fails, reduce frequency or repair real timing violation **without deleting correctness checks**. Only consider 25 MHz (40 ns) after 20 MHz closes with margin.
6. Re-run gate-level or post-layout regressions and all TT precheck, LVS, DRC before tapeout.

Use `py tools/clock_audit.py` to check clock values in metadata/top. It does not perform STA.
