# V7 GPIO bidirectional bench test: ESP32 + DE10-Nano

Use one Quartus project: `ctw_de10.qpf` (entity `ctw_de10_top`).
Keep all existing V5/V6 wires as they are. **Add only two new connections**:

| DE10-Nano JP1 physical pin | ESP32 WROOM DevKit pin | Purpose |
|---:|---|---|
| **19** | **GPIO13 through 1 kΩ series resistor** | `uio[6]` bidir bit 0 |
| **20** | **GPIO14 through 1 kΩ series resistor** | `uio[7]` bidir bit 1 |

Power off both boards before rewiring; both boards must share GND. ESP32 has
its own USB supply. Do NOT attach JP1 pin 11 (5 V) to an ESP32 GPIO.
Pin 19 is `PIN_D12`, pin 20 is `PIN_AD20` in the QSF.

## Install/execute

1. Compile **V7** in Quartus and download the new `ctw_de10.sof` to DE10.
2. Recompile and upload the **V7** `ctw_mcu_cradle.ino` on ESP32.
3. Close Arduino Serial Monitor; use the actual ESP32 COM port.
4. In PowerShell in the V7 folder:

```powershell
py -m pip install -r tools/requirements.txt
py tools/test_bidir.py --port COM12
```

The tool uploads `firmware/gpio_bidir_demo.bin`, which was built for RV32EC
and tests 2 input bits and 2 output bits through the RISC-V firmware.
Expected output has `Flash verified...`, four `IN: pattern` lines, four
`OUT: pattern` lines, ending with `PASS`.

**Safe sequence:** MCU reset releases both pads; MCU first acknowledges `Z`
(input/high-Z); ESP32 drives four input combinations and MCU reports them;
ESP32 releases both pins before MCU gets `O` commands; ESP32 then only reads
both pins; MCU acknowledges final `Z` and releases its outputs.

Running `test_sensor.py` and V5 `smoke.bin` should still behave as before.
After a board reset, uio[6:7] are input/high-Z until written by firmware.

## Verification limits

The delivered binary and tools can be run on the DE10 + ESP32. The source
includes `make test-gpio` for Icarus Verilog, but board performance, Quartus
Fitter, gate-level STA and the real IC memory interface require validation.
