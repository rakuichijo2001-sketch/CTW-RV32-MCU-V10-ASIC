## How it works

The CTW RV32EC V8 MCU uses a TinyQV core, GPIO, a UART and off-chip Flash and
dual PSRAM on six shared QSPI signals and two dedicated output CS# lines.
PSRAM A CS# is uo_out[5], PSRAM B CS# is uo_out[6], UART TX is
uo_out[7]. The uio[6:7] pads are programmable bidirectional GPIOs, high-Z until software configures output direction. An on-chip boot controller enters continuous
read mode on a W25Q128JVSIM and QPI on two APS6404L-3SQR-SN chips. GPIO
and UART are memory-mapped. V8 adds GPIO edge IRQ, one-shot timer compare IRQ and level-sensitive UART RX/TX IRQ on TinyQV custom interrupt lines 16–19.

## How to test

Select the project, supply the nominal 10 MHz clock. QSPI sampling is fixed internally.
Inputs 6:4 are GPIO, input 7 is UART RX, and output 7 is UART TX. Outputs 0:4 are GPIO. Outputs 5:6 are PSRAM chip selects. With `rst_n` held low, a programmer
can upload an RV32EC image at offset 0 and must release its six bus lines
before raising `rst_n`. Hardware initializes all three memories before
the CPU executes. The smoke image reports GPIO upper bits corresponding
to 0xA4 and sends OK on UART. GPIO input bit 0 toggles GPIO output bit 1.

## External hardware

A 3.3 V W25Q128JVSIM and two APS6404L-3SQR-SN with separate CS# lines.
An external programmer can steer Flash CS#, SCK, DQ0–DQ3 and reset.
The programmer never drives the two PSRAM CS# lines.
