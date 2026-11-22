# V10 GP/TP GPR ARCHITECTURE FIX — STRICT ID231 / LED E7

**Status: RTL candidate, not board-validated or ASIC signoff.**

User's prior revision passed 10,000/10,000 ISA-Torture iterations, but strict
RV32E read-after-write failed at `x3/gp` (ID231). The `src/register.v` fix
converts **both** `x3/gp` and `x4/tp` from TinyQV fixed constants into
ordinary, independently writable 32-bit architectural registers. The existing
ISA firmware images and `20-MHz` **ASIC timing target** are unchanged.

**A full new Quartus compilation and `.sof` upload are mandatory.**
Do not repeat `--no-upload` with the old SOF. With the new SOF first run:

```powershell
py tools/test_v10_isa_torture.py --port COM12 --firmware firmware/v10_isa_strict_gp_tp.bin --loops 1
```

Expected upload: 4024 bytes CRC32 `194ADA6A`. Then reflash the ordinary ISA
image using `--loops 100` without `--no-upload`. After both PASS, rerun
peripheral regression, watchdog, reset, and 8-hour soak on the NEW hardware.

**Important compatibility warning:** the source TinyQV core has some custom
compressed instruction encodings that assumed x3/x4 held fixed constants.
Those may need separate migration. Do not equate this patch with complete
RV32EC compliance. See `docs/GP_TP_GPR_ARCHITECTURE_FIX.md`.

---

# V10 CSR IMMEDIATE FIX — ISA Torture E1 / ID225

**Bug diagnosed on physical FPGA:** ID225 (`CSRRWI mepc, 16`) fails because CSR immediate operations used register-file `rs1` instead of instruction `zimm[4:0]`. Also corrected `mepc` set/clear semantics. **This RTL patch has not yet been tested on DE10 or in ASIC implementation.**

## Important: build FPGA again

1. Open **this directory's** `ctw_de10.qpf` in Quartus, full compile, upload its newly produced `.sof` to DE10. Do not reuse the old `.sof`.
2. Keep ESP32 sketch + wiring from the last PASS build.
3. Run from this directory:

```powershell
py tools/test_v10_isa_torture.py --port COM12 --loops 1
py tools/test_v10_isa_torture.py --port COM12 --loops 100 --no-upload
```

Expect new firmware: **3928 bytes, CRC32 `5052D8B0`**. If this fails, record full output and LED value.

Optional local RTL unit test (if Icarus installed): `make test-v10-csr-rtl`.

Full explanation and release gates: `docs/CSR_IMMEDIATE_ROOT_CAUSE_AND_FIX.md`.

---

# V10 RV32EC ISA Torture + ASIC 20 MHz Candidate (NOT signoff)

**Starting point:** the V10 CPU-BOOT-FIX design verified on DE10+ESP32 for 8 hours / 100 resets. The DE10 `ctw_de10.qpf` and FPGA 50 MHz path are unchanged. The ASIC clock target in `info.yaml` and `src/config.json` is now **20 MHz (50 ns), pending synthesis + STA**.

**New test (no FPGA rebuild required):** `py tools/test_v10_isa_torture.py --port COM12 --loops 100`

**Full technical coverage, limitations and exact run commands:** `docs/ISA_TORTURE_AND_CLOCK20.md`.

**Known limitation:** TinyQV hardwires `x3/gp` and `x4/tp`; stock CPU is not yet full standard RV32E compliant. The optional strict binary intentionally detects this. Do not call passing the default torture suite full ISA certification.

---

**Important V10 repair:** [docs/HARDWARE_DEBUG_FENCE_BOOT.md](docs/HARDWARE_DEBUG_FENCE_BOOT.md) — requires a NEW Quartus SOF; both decoder and upload→boot synchronization fixed.

# CTW-RV32-MCU V10 — FINAL FEATURE SET / PRE-PD QUALIFICATION

**Target:** Tiny Tapeout SKY130, CPU TinyQV RV32EC (16 architectural GPRs),
1 × W25Q128JVSIM QSPI NOR Flash and 2 × APS6404L-3SQR-SN QSPI PSRAM (external).
**Prototype:** DE10-Nano Cyclone V + ESP32-WROOM-32/32E on JP1, memory-chip
protocol models inside FPGA. **One Quartus project only:** `ctw_de10.qpf`
(top `ctw_de10_top`). V9 100-kHz I²C firmware and the ESP32 sketch with
`Wire.slaveWrite` + internal pull-ups are retained.

## V10 design additions

- **Autonomous hardware watchdog** (`src/ctw_sys_watchdog.v`), separate from
  the reset domain of the CPU/boot sequencer. When the enabled CPU stops
  feeding it, watchdog forces a safe boot+CPU reset, remembers the cause,
  increments an 8-bit saturating event counter, and reboots from Flash.
  External `rst_n` clears its history. Default after reset: disabled.
- **New MMIO, existing addresses unchanged:**
  - `0x08000068` WDT_CFG: bit 0 enable, bits [31:16] timeout (ms, >=10).
  - `0x0800006C` WDT_FEED: write exact magic `0xA55A5AA5`.
  - `0x08000070` WDT_STATUS: bit 0 WDT-last-reset; bits [15:8] count.
  - `0x08000074` WDT_ELAPSED: milliseconds since feed (16 bits).
- **V10 firmware** with explicit RV32E/RVC directed instruction vectors,
  pseudo-random read/write and subword tests for *both* PSRAM banks, 1 KiB
  boundary checks, stack, `.data`, `.bss`, timer, UART, watchdog, software
  signature and UART health frames.
- **Long-duration monitor:** `tools/test_v10.py` requests stress rounds,
  independently verifies all software signatures and sequences, checks for
  unexpected reboot, logs CSV, and stops on the first error.
- **Regression:** `tools/run_v10_regression.py` re-runs the already exercised
  sensor, bidirectional GPIO, UART/GPIO/timer interrupts, PWM and 100-kHz I²C
  and additionally runs I²C NACK/repeated START, PWM 0/50%, and
  ECALL/EBREAK/MRET exception vectors.
- **Reset cycling:** `tools/test_v10_reset.py`, default 100 resets and complete
  firmware/PSRAM check each time, without reflashing `.sof` or Flash.

## Hardware wiring

**No new wires**, same JP1 ⇄ ESP32 map and power connections as V9.
`uio[0:5]`: QSPI SCK + DQ0..DQ3 + Flash CS#; `uo_out[5:6]`: two PSRAM CS#;
`uio[6:7]`: GPIO/I²C open-drain; `uo_out[3:4]`: GPIO/PWM;
`uo_out[7]`: UART TX; `ui_in[7]`: UART RX; `rst_n`: ESP32 GPIO21
(open-drain release); `ena`: Tiny Tapeout project-select (tied high on DE10).
**Actual ASIC I²C requires pull-ups to 3.3 V**. Internal ESP32 weak pull-up
was used in the V9 prototype and is not an ASIC substitute.

## Steps on the actual DE10 + ESP32 boards

1. Keep the **working V9 directory and .sof as a rollback**.
2. Open `ctw_de10.qpf` from **this V10 directory**, Quartus Compile,
   program its NEW `.sof` on DE10. Do not reuse the V9 `.sof`.
3. Upload **this V10** `esp32/ctw_mcu_cradle/ctw_mcu_cradle.ino` via Arduino
   IDE, COM12; close Arduino Serial Monitor.
4. Run sequential baseline regressions (multiple firmware uploads, same .sof):

   ```powershell
   py -m pip install -r tools/requirements.txt
   py tools/run_v10_regression.py --port COM12
   ```

5. Run V10 directed ISA+PSRAM and FORCE autonomous watchdog reboot; **0 h**
   means no multi-hour soak yet:

   ```powershell
   py tools/test_v10.py --port COM12 --hours 0
   ```

6. Run 100 external reset/reboot/ISA/RAM cycles with V10 firmware still in Flash:

   ```powershell
   py tools/test_v10_reset.py --port COM12 --cycles 100
   ```

7. **8-hour continuous CPU/RAM/UART/signature stress test**. Keep PC,
   ESP32, FPGA and power on for the entire run. Do not open Serial Monitor:

   ```powershell
   py tools/test_v10.py --port COM12 --hours 8 --csv logs/v10_8h.csv
   ```

   For extended qualification use `--hours 24 --csv logs/v10_24h.csv`.
   Default watchdog self-test runs first; use `--no-watchdog-test` only when
   testing a diagnosed watchdog problem. A serial timeout, signature error,
   unexpected WDT reset or power interruption is **FAIL**, not an automatic retry.
   The script does **not** continue testing in the background after exit.

8. For additional control-register/RTL unit simulations under Linux/WSL with
   Icarus Verilog installed: `make test-v10-prepd`. Independently run Quartus
   Fitter/TimeQuest, then Tiny Tapeout shuttle-specific STA/DRC/LVS/precheck.

See [`docs/V10_SIGNOFF.md`](docs/V10_SIGNOFF.md) for a gate-by-gate matrix.

## Important scope and non-guarantees

- V10 is the **final requested MCU feature version**, **NOT an ASIC signoff**.
- No real Flash or PSRAM IC was available for the prototype; protocol models
  do not establish physical I/O timing, power-on reset or signal integrity.
- The RV32EC test is directed, **not** an exhaustive formal ISA-compliance
  suite. Core TinyQV may have nonstandard exception/CSR behaviors; a separate
  waiver or architectural fix is needed for unsupported ISA features.
- FPGA 50 MHz proof does not guarantee SKY130 10 MHz physical signoff.
- Power loss or a stopped system clock is NOT detectable by this clocked WDT.
- The PSRAM `CS#` safety timeout still parks the CPU on a RAM bus fault;
  it requires an external reset. This is deliberate: avoid unsafe memory
  transactions once the 6 µs safety margin expires.
