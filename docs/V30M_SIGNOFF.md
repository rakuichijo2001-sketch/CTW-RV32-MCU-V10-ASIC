# V30m — 4x2, 30 MHz post-route release qualification

## Decision: preserve proven RTL and use the SKY130 HD transition limit

This candidate is derived without any RTL change from V30j, SHA
\`7fd4b3d7f601110f601722a6f6087e8862564709\`.

- 30,000,000 Hz in info.yaml, 33.333 ns PnR and signoff SDC.
- SKY130 HD max transition 1.5 ns (documented by the LibreLane
  [macro-first hardening guide](https://librelane.readthedocs.io/en/latest/additional_material/caravel/macro_first_hardening/index.html)).
  The earlier 0.75 ns limit was an *additional engineering target*, not
  a requirement implied by running at 30 MHz.
- The V30j physical build PASSED: worst setup slack +8.4011 ns, worst
  hold slack +0.0993 ns, zero setup/hold/slew/capacitance violations at
  all nine signoff corners; DRC, LVS, antenna, regression and GL passed.
- One known timing-rule exception is **nine intermediate CTS clock
  buffers** (one root, eight level-3 buffers) with fanout 8 against
  project preference 6. The signoff gate verifies their exact names
  and rejects any extra data-net violation. These are *not*
  max-slew or max-capacitance violations.

## Automated signoff guard

The GDS workflow now invokes \`asic/check_30mhz_signoff.py\` on the
post-route metric reports. It checks all nine STA corners,
MAX_TRANSITION_CONSTRAINT, clock period, die tiles, both DRC engines,
LVS, PDN, antenna, max slew/cap, and CTS fanout exceptions. If report
files are absent, constraints drift, or any required metric fails,
the GDS job fails and dependent precheck/GL do not proceed.

This is a release gate, **not a claim that custom silicon/board
operation has been measured**. Remaining engineering work includes
examining lint warnings, physical IR-drop with explicit VSRC locations,
and external Flash/PSRAM timing on the target test board.

V30i/V30l were not accepted as strict 0.75 ns variants despite their
GitHub GDS workflow successes, because their post-route slew counts
were nonzero. These runs are retained only for diagnostics.
