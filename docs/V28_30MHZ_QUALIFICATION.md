# V28 — 4x2 / 30 MHz qualification candidate

Derived from V22 (the best measured 50 MHz RTL timing candidate) with **no
CPU/memory-controller functional RTL modifications**. This branch is intended
as a functional and physical-timing baseline while optimization experiments
continue on other branches.

## Synchronous clock configuration

- TinyTapeout requested clock: **30,000,000 Hz** (`info.yaml`).
- P&R clock period: **33.333 ns** (`src/config.json`).
- ASIC top default `CLK_HZ`: **30,000,000 Hz**.
- ASIC UART divisor: **260** clock cycles (33.333 ns × 260 = 8,666.67 ns);
  close to 115,200 baud (8,680.56 ns per bit).
- ASIC RTL testbench clock: **33.333 ns**; FPGA/model variants retain their
  previous 20 ns test clocks, because those wrappers have different clocks
  and UART configurations.
- Clock-sensitive boot/powerup and watchdog timers derive from `CLK_HZ`.
- TinyTapeout allocation remains **4x2 tiles**.

## Release gates

Do not label V28 verified or tapeout-ready without all of:
1. GDS/PNR completion and TinyTapeout Precheck/GL simulation pass.
2. Post-route worst-corner setup **WNS >= 0** and **TNS = 0**; hold
   violations 0 across required corners.
3. All full RTL regression tests pass, notably `test-irq-asic`,
   `gate-irq`, and external Flash/PSRAM timing tests.
4. Check DRC/LVS and relevant I/O clock constraints. Current TinyTapeout
   config has `RUN_KLAYOUT_DRC = 0`, so GDS/precheck alone is not full DRC
   signoff. Clock-frequency signoff also requires valid external QSPI timing.

The 50 MHz RTL timing of V22 cannot be declared sufficient for 30 MHz
without rerunning P&R. Any failing test is a blocker; do not bypass it just
to make CI green.

## IRQ regression caveat

The prior 40 MHz RTL regression failed at `test-irq-asic` with the
`ctw_timed_memory_fixture` despite passing model/ASIC smoke tests.
Do NOT waive this test. This branch adds dedicated diagnosis/repair before
qualifying any 30 MHz release.

## QSPI/Flash timed IRQ repair (experimental until full test PASS)

After 30 MHz timed-memory IRQ trace, the first instruction bytes were
misread at the former 001 sampling phase. At phase 010, the first two
halfwords are correctly read as 006f, 00c0 but the timing fixture reports
pad contention at the following redirect. QSPI now introduces a deselected
turnaround state with busy asserted after stop and before a subsequent
transaction start. This change must pass full IRQ, smoke, timed RAM,
gate-level and post-route STA checks before being considered qualified.

## 30 MHz Flash timing selection through real reset-time GPIO strap

The ASIC now reads `ui_in[6:4]` while the CPU is held in reset during
memory boot. Setting all three pins HIGH selects low-delay Flash read
configuration 001; all other input patterns use default 010. Following CPU
reset release the same pins retain their ordinary GPIO role (QSPI captures
the selection only during reset). The untimed ASIC RTL fixture sets all
three HIGH during boot to model short board propagation; the timed 30 ns
fixture leaves them LOW, modeling the longer roundtrip. This is **one RTL
design with a physical boot strap**, not a simulator-only choice.

This strap must be wired/documented for the actual test board. The default
010 must still pass the timed firmware IRQ sequence and the final netlist
must pass GDS/GL/STA. Confirm any GPIO6:4 changes during warm reset do not
select an unintended sample mode.
