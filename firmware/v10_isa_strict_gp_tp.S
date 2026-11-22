// SPDX-License-Identifier: Apache-2.0
// RV32E STANDARD CONFORMANCE CHECK; EXPECTED TO FAIL on stock TinyQV.
// x3/gp and x4/tp must be writable GPRs in standard RV32E.
.section .text,"ax",@progbits
.option push
.option norvc
.globl v10_isa_strict_gp_tp
v10_isa_strict_gp_tp:
    addi sp,sp,-16
    sw gp,0(sp)
    sw tp,4(sp)
    li gp,0x12345678
    mv t0,gp
    li a0,231
    li a5,0x12345678
    bne t0,a5,.Ldone
    li tp,0x87654321
    mv t0,tp
    li a0,232
    li a5,0x87654321
    bne t0,a5,.Ldone
    li a0,0
.Ldone:
    lw gp,0(sp)
    lw tp,4(sp)
    addi sp,sp,16
    ret
.option pop
