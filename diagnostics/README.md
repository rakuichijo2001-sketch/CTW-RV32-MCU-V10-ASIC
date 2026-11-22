# CTW V10: isolated FENCE diagnosis

Findings from the **original** user-tested V10 source:
- At `0x800` in `v10_qualification.bin` there is exactly one 32-bit base
  `FENCE` instruction (`0x0FF0000F`).
- `src/decode.v` did not decode opcode `0x0F`, and `src/core.v` requires
  one recognized operation to assert instruction retirement.
- Therefore the core can stall indefinitely on `FENCE`, making the first
  V10 stress UART response time out even though V5..V9 regression passes.

## Isolate the fault WITHOUT rebuilding Quartus

This diagnostic image changes ONLY the 32-bit FENCE at byte offset `0x800`
into `ADDI x0,x0,0` (0x00000013). It is **not** ISA-compliant test evidence
and must not be used for final signoff.

From the V10 project root, using your original current `.sof` on DE10 and the
same ESP32 sketch and wiring:

    py tools/test_v10.py --port COM12 --hours 0 --firmware diagnostics/v10_qualification_fence_nop.bin

If the test progresses, FENCE was blocking progress. It might reveal
additional bugs later in the qualification. In any case the real corrective
fix is in `src/decode.v`, and it REQUIRES Quartus recompile and a new SOF.

## Verify the permanent correction

1. Compile `ctw_de10.qpf` in this new folder (only one Quartus project).
2. Program the newly generated `.sof` into DE10.
3. Restore ordinary firmware (already unmodified in this package):

    py tools/test_v10.py --port COM12 --hours 0

4. Only once directed ISA/RAM/watchdog checks pass, run 8-hour stress.
5. Run `make test-v10-fence` with Icarus if available.

Do not claim signoff based on the diagnostic NOP image: it bypasses the FENCE
instruction instead of verifying the real RTL fix.
