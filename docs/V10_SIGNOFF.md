# CTW-RV32-MCU V10 — Pre-PD qualification and tapeout release gates

Version: V10; functional baseline V9 (100 kHz I2C with ESP32 preloaded slave
reply). Never call the design ASIC-silicon validated until real-chip tests.

## Pinout — no changes from V9

| Tiny Tapeout | Function |
|---|---|
| `ui_in[0:6]` | 7 GPIO inputs; bits 4:6 also used as 3-bit sensor interface |
| `ui_in[7]` | UART RX |
| `uo_out[0:2]` | GPIO outputs |
| `uo_out[3:4]` | GPIO/PWM0 and GPIO/PWM1 |
| `uo_out[5:6]` | PSRAM A/B CS# (output-only) |
| `uo_out[7]` | UART TX |
| `uio[0]` | Flash CS# |
| `uio[1],uio[2],uio[4],uio[5]` | QSPI DQ0..DQ3 (in that order) |
| `uio[3]` | QSPI SCK |
| `uio[6:7]` | Bidirectional GPIO or I2C SDA/SCL |
| `clk, rst_n, ena` | clock, active-low reset, project select |

The external memory wiring must connect both PSRAM CS# pins from **output
pins 5 and 6**, not from the two bidirectional pads (V6+ pinout change).
During programming FPGA/ASIC releases 6 Flash-bus pins, keeps both PSRAM CS#
HIGH. ESP32 pulls `rst_n` LOW, uploads and verifies Flash, releases bus,
then allows MCU autonomous Flash+PSRAM initialization before CPU begins.

## V10 software interface

- CPU memory map: Flash XIP `0x00000000..00ffffff`, PSRAM A
  `0x01000000..017fffff`, PSRAM B `0x01800000..01ffffff`, MMIO `0x08000000...`.
- Watchdog config at MMIO `0x08000068`, magic feed at `0x0800006c`, reset
  cause/count at `0x08000070`, elapsed milliseconds at `0x08000074`.
- WDT registers use clock divided into milliseconds; they are not an RTC.
  `enable=0` is reset default. Firmware uses 8-second timeout in normal
  operation and a deliberate 250-millisecond freeze test.
- V10 UART diagnostic frame: `D7` magic, ASCII kind, 32-bit little-endian
  sequence, 32-bit little-endian arithmetic signature, 8-bit WDT counter,
  XOR checksum. The host additionally recomputes the arithmetic signature
  **independently**; a UART echo alone cannot pass.

## Mandatory functional qualification

| Gate | Exact test | Acceptance | Status at hand-off |
|---|---|---|---|
| Q01 | RV32EC source build | Firmware <=4096 bytes; no compiler errors | PASS (Clang in preparation) |
| Q02 | ESP32 sketch syntax/mock build | No host-side C++ syntax errors | PASS (mock only) |
| Q03 | Python loader/CRC/signature code | All unit tests | PASS |
| Q04 | FPGA Quartus compile and TimeQuest | 50MHz timing closed; correct pin mapping, no latches/multi-driver | **NOT RUN HERE** |
| Q05 | Functional regressions V5..V9 on one V10 .sof | sensor 8/8, bidir 4+4+Z, IRQ, I²C 100k 0x5A/0xC3, PWM ~25/75, I²C NACK/repeated START, PWM 0/50 | **TO RUN ON DE10** |
| Q06 | ECALL/EBREAK and MRET | Both traps return via mcause/mepc and send X; LED A9 | **TO RUN ON DE10** |
| Q07 | Directed RV32E/RVC | V10S returns seq 4 and correct independent signature | **TO RUN ON DE10** |
| Q08 | RAM A/B randomized, sign/zero extension, 1KB boundary, stack, .data, .bss | no mismatches, result signature agrees with host | **TO RUN ON DE10** |
| Q09 | Watchdog fault injection | WDT expires after deliberate hang; reboot; reset count>=1; firmware restarts | **TO RUN ON DE10** |
| Q10 | 100 external reset cycles, no reflash | every cycle reboots, reruns ISA/RAM, WDT counter cleared by ext reset | **TO RUN ON DE10** |
| Q11 | 8h 100%-monitored logical stress | zero packet loss, zero signature mismatch, zero unexpected WDT resets; CSV log kept | **NOT RUN** |
| Q12 | 24h extended stress | same metrics as Q11; useful but optional if scheduling constrained | **NOT RUN** |
| Q13 | RTL: WDT disable/feed/expiry/reset history | Icarus `make test-v10-watchdog` PASS | **NOT RUN HERE (Icarus unavailable)** |
| Q14 | RTL: old peripheral + protocol regressions; PSRAM 6us CS guard | Icarus/Verilator all benches pass; force stalls, resets and bus contention | **NOT RUN HERE** |
| Q15 | Physical 1Flash+2PSRAM at exact part numbers | cold boot, warm reset, QSPI waveform/JEDEC, timing, both RAMs | **NOT RUN (NO REAL CHIPS)** |
| Q16 | SKY130 P&R and final timing | area fits shuttle tiles, setup+hold, no unconstrained paths, clock/reset CDC checks | **NOT RUN** |
| Q17 | Shuttle-signoff DRC/LVS and TT precheck | every required signoff clean; pad + ESD + max freq compatible | **NOT RUN** |

**Signoff decision: HOLD.** Do not submit RTL/GDS until Q04..Q11, Q13..Q14,
Q16..Q17 are passed. Q15 must be passed or accepted through a recorded,
explicit high-risk waiver because no external hardware can be substituted for
real Flash/PSRAM power-up and data-valid measurement.

## ISA scope and known risks

The core is **TinyQV RV32EC, not a 32-register RV32I CPU**. The V10 directed
assembly covers LUI/AUIPC, JAL/JALR, all six main branches, signed/unsigned
byte/halfword/word reads, SB/SH/SW, arithmetic, comparisons, all shift forms,
FENCE, compressed instructions, and x0 immutability. The compiled C image
also exercises arithmetic and compressed control flow through Clang.
V8 firmware exercises CSR/machine interrupts/MRET. V10 exception firmware
checks ECALL/EBREAK and return by `mepc`. **Illegal instruction trapping,
reserved compressed encodings, misaligned access traps, privilege-spec
compliance and exhaustive `riscv-arch-test` coverage are NOT claimed.**
These must be formally reviewed or documented as explicit ISA restrictions.

Potential additional bug classes to test before PD: bus ownership during
ESP32 reset / power asymmetry; GPIO High-Z through watchdog reset; I²C
NACK/clock stretch/bus stuck, repeated START; UART framing and buffer overrun;
GPIO IRQ edges while masked; timer wrap; PSRAM retention and 8us `CS#` max;
Flash XIP exit from continuous mode after repeated warm reset; brownout and
clock loss; full 8MiB PSRAM address map and high-bank boundaries. Some need
additional RTL testbench development or actual ICs to obtain evidence.

## ASIC constraints and actual hardware requirements

- FPGA DE10 uses 50 MHz; **nominal ASIC target is 10 MHz, not yet signed off**.
- For 100 kHz I2C at ASIC 10 MHz the half-period divider should be 49,
  whereas FPGA 50 MHz uses 249. These are firmware settings, not fixed RTL.
- ESP32 test uses weak internal I2C pull-ups; real ASIC interface must have
  suitable external pull-ups to the shared 3.3 V rail.
- SRAM Flash/PSRAM emulation stores only 4096 bytes per chip, not the full
  physical 16MiB/8MiB/8MiB. Full-address tests need the real ICs or a larger
  protocol-level simulator.
- An ASIC file signoff must include TT cell-library corners, reset paths,
  IO pad drive/load and inter-chip QSPI timing. A successful FPGA test does
  not establish actual silicon timing or functionality.
