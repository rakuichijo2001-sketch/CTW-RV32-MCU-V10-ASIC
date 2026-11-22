# V10 stress UART timeout: FENCE instruction deadlock

Observed on user's DE10 + ESP32: all V10 regressions pass; test_v10 upload
2136 bytes CRC32 BBE53C4E; first request returns `V10 UART timeout bytes=0`.

**Proven in RTL static inspection, not yet hardware-verified**:
- `v10_isa.S` has one `fence` between memory-lane tests and RVC tests.
- Flash instruction at offset 0x0800 is `0x0FF0000F`, opcode 0x0F.
- Pre-fix decoder has no handler for opcode 0x0F, leaving every instruction
  classification deasserted for this instruction.
- `tinyqv_core.instr_complete` will not assert for an instruction with
  all such classes low. The instruction can remain active indefinitely.

Fix: recognize base `FENCE` (funct3=000) as architecturally inert ADDI x0,x0,0.
This is valid ONLY for this in-order, blocking-memory TinyQV implementation.
FENCE.I remains unsupported, not silently reinterpreted as FENCE.

Follow-up: RTL simulation for timeout, GPIO LED state, watchdog expiry/reboot;
full V10 ISA signature and two-bank memory test on DE10, then reset/soak. With
no Icarus simulator here, the `tb_fence_decode.sv` test has NOT been run.
