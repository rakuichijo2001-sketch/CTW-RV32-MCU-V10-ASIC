# CTW-RV32-MCU V9 — PWM / I²C Master / PINMUX

Derived from V8; one Quartus project in root `ctw_de10.qpf`, top `ctw_de10_top`.

## Important scope

V9 is an **implementation candidate**, not ASIC signoff. The original V8 IRQ
firmware is retained as a regression test; I²C/PWM have not been validated on
DE10-Nano hardware until the new V9 test is run.

## ASIC pin assignment (unchanged from V8)

- `uo_out[3]`: GPIO output or PWM channel 0 (when `PINMUX[1]=1`).
- `uo_out[4]`: GPIO output or PWM channel 1 (when `PINMUX[2]=1`).
- `uio[6]`: GPIO bidir or I²C SDA (when `PINMUX[0]=1`).
- `uio[7]`: GPIO bidir or I²C SCL (when `PINMUX[0]=1`).
- `uio[0:5]` still use Flash/PSRAM shared QSPI, and `uo_out[5:6]` retain two PSRAM CS#.
- `uo_out[7]` is UART TX, `ui_in[7]` is UART RX.
- `ena` stays TT project-selection, ESP32 continues to pull `rst_n` during programming.

**Reset:** `PINMUX=0`, `PWM_CTRL=0`, I²C idle, both uio pins High-Z.
For I²C, outputs are **open-drain only**: output enable drives `0`, output
release means `Z` (never drives high). Add **two 4.7 kΩ pull-ups to 3.3 V**
(one each on SDA and SCL). This is necessary with an actual ASIC. Keep wires
short. Do not connect 5 V pull-ups to either board.

## Register map (word aligned; 32-bit MMIO)

| Address | Name | Bits and use |
|---|---|---|
| `0x08000034` | PINMUX | bit 0 I²C, bit 1 PWM0, bit 2 PWM1 |
| `0x08000038` | PWM_CTRL | bit 0 enable; resets counter when 0 |
| `0x0800003C` | PWM_DIV | 16-bit prescale, each phase lasts `(DIV+1)` clocks |
| `0x08000040` | PWM_DUTY0 | 8-bit duty, counts high out of 256 |
| `0x08000044` | PWM_DUTY1 | same for PWM1 |
| `0x08000050` | I2C_CTRL | write: bit0 START, bits `[2:1]` operation |
| `0x08000054` | I2C_ADDR | 7-bit slave address |
| `0x08000058` | I2C_TX | byte to write, or register address for combined read |
| `0x0800005C` | I2C_RX | last received byte |
| `0x08000060` | I2C_STATUS | bit 0 BUSY, 1 DONE, 2 NACK, 3 TIMEOUT |
| `0x08000064` | I2C_DIV | 16-bit half-period; `(DIV+1)` core clock cycles |

I²C_CTRL `START=1` operations: `0=WRITE` (address+data+STOP),
`1=READ` (address+1 byte+NACK+STOP),
`2=WRITE-READ` (address+TX pointer+repeated START+one-byte read+STOP).
This is **7-bit, single-byte I²C**, not a general multi-byte DMA or FIFO
engine. Busy requests should be avoided; completion is polled on status.
On NACK or timeout, status is latched until next START. Timeout releases pads.

PWM period is `256 * (PWM_DIV + 1) / f_clk`; `PWM_DUTY=64` means 25%,
`192` means 75%, `0` means always low, and `255` means 255/256 high.

## DE10 ↔ ESP32 extra wires

Keep the 15 wires from V8, including `JP1-19 -> ESP32 GPIO13` and
`JP1-20 -> GPIO14`. These two become **SDA / SCL** when I²C PINMUX is enabled.
Add only:

| DE10 JP1 physical pin | ESP32 WROOM GPIO | Purpose |
|---|---|---|
| 21 | 34 (input-only) | PWM0 duty measurement |
| 22 | 35 (input-only) | PWM1 duty measurement |

DE10 JP1 pin 21 = FPGA `PIN_C12`, pin 22 = `PIN_AD17` per DE10-Nano manual.
**Power both boards off before rewiring.** Continue to use the existing
common GND (DE10 JP1 pin 12), and do not connect JP1 pin 11 (5 V).
Place two 4.7 kΩ resistors from SDA and SCL respectively to 3.3 V (for the
DE10 header, JP1 pin 29 provides 3.3 V), if available. On ESP32, GPIO13/14
are not driven push-pull during this I²C test.

## How to run

1. Compile and program `ctw_de10.qpf` (`MODEL_MEMORIES=1`).
2. Upload the V9 Arduino sketch from `esp32/ctw_mcu_cradle/`.
3. Close Arduino Serial Monitor and run:

   `py tools/test_v9.py --port COM12`

The Python tool flashes the **428-byte** V9 example, checks PWM0/PWM1
near 25%/75%, commands one I²C write of `0x5A` to ESP32 address `0x42`,
reads back `0xC3`, then restores GPIO mode on `uio[6:7]`.
A correct board run should show:

    Flash verified: ...
    V9 PWM PASS duty0=... duty1=...
    V9 I2C WRITE PASS 0x5A
    V9 I2C READ PASS 0xC3
    V9 PASS ALL

LED `0x99` is the firmware success marker; `0xE1`/`0xE2`/`0xE3`
indicate write, read or value mismatch. V9 has not passed FPGA validation
until these results are observed on the actual boards.

## Regression / silicon signoff

- Re-run V8 `test_irq.py`, V7 bidirectional GPIO and V5 sensor scripts on V9.
- Run `make test-v9-rtl` with Icarus and add independent I²C slave test vectors
  (ACK/NACK/clock stretch/repeated START and bus stuck low).
- Run Quartus Fitter on 50 MHz DE10 and capture slack.
- Run Tiny Tapeout standard-cell P&R, STA, DRC/LVS and precheck using the
  **actual target shuttle**; check new gate count against the purchased tile area.
- Test external Flash and two PSRAM ICs when possible. FPGA memory models do
  **not** prove silicon I/O timing or power-up behavior.
