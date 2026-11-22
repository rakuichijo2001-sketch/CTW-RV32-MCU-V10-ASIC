# CTW RV32 MCU V7 — ASIC pinout & GPIO registers

This file supersedes V6 pinout for the new V7 candidate.

| Signal | Function |
|---|---|
| `ui_in[6:0]` | GPIO input; `ui_in[6:4]` available for sensor example |
| `ui_in[7]` | UART RX (also readable in GPIO input register) |
| `uo_out[4:0]` | Five GPIO outputs |
| `uo_out[5]` | PSRAM A CS#, active low, output only |
| `uo_out[6]` | PSRAM B CS#, active low, output only |
| `uo_out[7]` | UART TX |
| `uio[0]` | Flash CS#, shared with ESP32 programmer when MCU reset |
| `uio[1]`, `uio[2]` | QSPI DQ0/MOSI, DQ1/MISO |
| `uio[3]` | QSPI SCK |
| `uio[4]`, `uio[5]` | QSPI DQ2, DQ3 |
| **`uio[6]`** | **programmable GPIO bidir bit 0** |
| **`uio[7]`** | **programmable GPIO bidir bit 1** |
| `rst_n` | Active-low reset + Flash programmer ownership; raw reset releases pad enables |
| `ena` | Tiny Tapeout project selection. Hardwired to 1 on DE10 prototype |
| `clk` | System clock; 10 MHz ASIC target (not signed off) |

## Memory map (CPU byte addresses)

| Address | Register | Access | Semantics |
|---|---|---|---|
| `0x08000000` | GPIO_IN | R | 8 input bits `ui_in[7:0]` |
| `0x08000004` | GPIO_OUT | R/W | Legacy output register. `uo_out[4:0]` drive directly |
| `0x08000008` | TIMER | R | Clock-cycle counter |
| `0x0800000C` | UART_DATA | R/W | UART RX or TX data |
| `0x08000010` | UART_STATUS | R | bit0 TX busy, bit1 RX valid |
| `0x08000014` | CHIP_ID | R | `0x43545731` |
| **`0x08000018`** | **BIDIR_DIR** | R/W | bits [1:0]: 0=input/Hi-Z, 1=output |
| **`0x0800001C`** | **BIDIR_OUT** | R/W | bits [1:0]: output values |
| **`0x08000020`** | **BIDIR_IN** | R | bits [1:0]: synchronized physical pin levels |

`BIDIR_IN[0]` reads `uio[6]`, `BIDIR_IN[1]` reads `uio[7]`.
All unused high bits read 0. Power-up/reset default: `BIDIR_DIR = 0`, `BIDIR_OUT = 0`.
The pad enable is **also** gated by reset, `ena`, boot ready and RAM timeout, so it remains
Hi-Z even if a fault occurs while firmware has configured an output.
Firmware should **write OUT first, then enable DIR** to avoid unexpected output glitches.

## DE10-Nano JP1 breakout

- Existing ESP32/DE10 wiring and V5 sensor/UART wires remain unchanged.
- New **JP1 physical pin 19 (FPGA PIN_D12) → `uio[6]`**.
- New **JP1 physical pin 20 (FPGA PIN_AD20) → `uio[7]`**.
- Both are bidirectional and **do not connect directly to 5 V**.
- For V7 ESP32 bidir test only, **ESP32 GPIO13 ↔ 1 kΩ ↔ JP1 pin 19** and
  **ESP32 GPIO14 ↔ 1 kΩ ↔ JP1 pin 20**. These resistors provide limited
  contention protection during development; firmware and sketch still must
  relinquish output ownership before the other endpoint drives.

Physical JP1 pin numbers refer to header pin position, not FPGA package pins.
Both signals remain distinct from the PSRAM CS outputs JP1 pins 7/8 on DE10.
When ASIC packaged, use the Tiny Tapeout carrier pin map, not DE10 JP1 numbering.
