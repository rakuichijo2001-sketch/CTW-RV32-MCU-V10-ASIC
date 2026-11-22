/* SPDX-License-Identifier: Apache-2.0
 * V10 directed ECALL/EBREAK exception handler. Checks mcause/mepc/MRET.
 * RV32EC machine-mode CSR subset as implemented by TinyQV.
 * Illegal-opcode traps need a separate architectural review of TinyQV;
 * this binary intentionally does NOT assert undocumented illegal traps.
 */
.section .vectors,"ax",@progbits
.option push
.option norvc
.globl _start
_start:
    j reset_entry
    j trap_entry
    j fail
.section .text,"ax",@progbits
reset_entry:
    li sp,0x01000400
    li s0,0x01000000
    li s1,0x08000000
    sw zero,0(s0)
    li t0,0x35
    sw t0,4(s1)
    ecall
    ebreak
    lw t0,0(s0)
    li t1,2
    bne t0,t1,fail
    li t0,0xa9
    sw t0,4(s1)
    li a0,88   /* 'X': both exceptions returned by MRET */
    call putchar
1:  j 1b
trap_entry:
    addi sp,sp,-16
    sw t0,0(sp)
    sw t1,4(sp)
    sw t2,8(sp)
    lw t0,0(s0)
    csrr t1,mcause
    bnez t0,2f
    li t2,11  /* ECALL from M mode */
    bne t1,t2,fail
    j 3f
2:  li t2,1
    bne t0,t2,fail
    li t2,3   /* EBREAK */
    bne t1,t2,fail
3:  addi t0,t0,1
    sw t0,0(s0)
    csrr t1,mepc
    addi t1,t1,4
    csrw mepc,t1
    lw t0,0(sp)
    lw t1,4(sp)
    lw t2,8(sp)
    addi sp,sp,16
    mret
putchar:
    lw t0,16(s1)
    andi t0,t0,1
    bnez t0,putchar
    sw a0,12(s1)
    ret
fail:
    li t0,0x08000004
    li t1,0xee
    sw t1,0(t0)
4:  j 4b
.option pop
