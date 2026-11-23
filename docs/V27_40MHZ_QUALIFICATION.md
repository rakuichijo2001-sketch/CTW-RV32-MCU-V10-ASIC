# V27 — 4x2 / 40 MHz qualification candidate

Derived from V22 (the best measured 50 MHz RTL timing candidate) with **no
CPU/memory-controller functional RTL modifications**. This branch is intended
as a functional and physical-timing baseline while optimization experiments
continue on other branches.

## Synchronous clock configuration

- TinyTapeout requested clock: **40,000,000 Hz** (`info.yaml`).
- P&R clock period: **25 ns** (`src/config.json`).
- ASIC top default `CLK_HZ`: **40,000,000 Hz**.
- ASIC UART divisor: **347** clock cycles (25 ns × 347 = 8,675 ns);
  close to 115,200 baud (8,680.56 ns per bit).
- ASIC RTL testbench clock: **25 ns**; FPGA/model variants retain their
  previous 20 ns test clocks, because those wrappers have different clocks
  and UART configurations.
- Clock-sensitive boot/powerup and watchdog timers derive from `CLK_HZ`.
- TinyTapeout allocation remains **4x2 tiles**.

## Release gates

Do not label V27 verified or tapeout-ready without all of:
1. GDS/PNR completion and TinyTapeout Precheck/GL simulation pass.
2. Post-route worst-corner setup **WNS >= 0** and **TNS = 0**; hold
   violations 0 across required corners.
3. All full RTL regression tests pass, notably `test-irq-asic`,
   `gate-irq`, and external Flash/PSRAM timing tests.
4. Check DRC/LVS and relevant I/O clock constraints. Current TinyTapeout
   config has `RUN_KLAYOUT_DRC = 0`, so GDS/precheck alone is not full DRC
   signoff. Clock-frequency signoff also requires valid external QSPI timing.

The 50 MHz RTL timing of V22 cannot be declared sufficient for 40 MHz
without rerunning P&R. Any failing test is a blocker; do not bypass it just
to make CI green.
