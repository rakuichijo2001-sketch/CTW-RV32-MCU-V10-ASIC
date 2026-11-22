/* SPDX-License-Identifier: Apache-2.0
 * RV32EC + implemented CSR subset. No standard mtvec/PLIC assumed.
 * Only x0..x15 are used; interrupt frame preserves all modified registers.
 */
.section .vectors,"ax",@progbits
.option norvc
.option norelax
.globl _start
_start:
    j reset_entry
    j fail
    j irq_entry
.section .text.startup,"ax",@progbits
reset_entry:
    li sp, 0x01000400
    li s0, 0x08000000
    li s1, 0x01000000
    li t0, 8
    csrc mstatus,t0
    csrw mie,zero
    csrw mip,zero
    sw zero,0(s1)        /* timer count */
    sw zero,4(s1)        /* tx count */
    sw zero,8(s1)        /* gpio count */
    sw zero,12(s1)       /* rx count */
    sw zero,16(s1)       /* rx data */
    sw zero,0x24(s0)
    sw zero,0x28(s0)
    sw zero,0x30(s0)
    li t0,0x10
    sw t0,4(s0)         /* LED: waiting for timer */
    li t0,0x20000
    csrw mie,t0
    lw t1,8(s0)
    li t2,4096
    add t1,t1,t2
    sw t1,0x2c(s0)
    li t1,1
    sw t1,0x30(s0)
/* Global IRQ masked: pending must latch but ISR must not run. */
wait_pending:
    csrr t1,mip
    and t1,t1,t0
    beqz t1,wait_pending
    lw t1,0(s1)
    bnez t1,fail
    li t1,8
    csrs mstatus,t1
wait_timer:
    lw t1,0(s1)
    beqz t1,wait_timer
    li t2,1
    bne t1,t2,fail
    li a0,84           /* T: timer ISR completed after unmask */
    call put
/* UART TX idle interrupt: ISR disables its mie bit to prevent retrigger. */
    li t0,0x80000
    csrw mie,t0
wait_tx:
    lw t1,4(s1)
    beqz t1,wait_tx
    li t2,1
    bne t1,t2,fail
    li a0,88           /* X: TX ISR ran */
    call put
/* GPIO4 rising/falling and UART RX. No GPIO or RX peripheral polling. */
    li t0,0x10
    sw t0,0x24(s0)
    sw t0,0x28(s0)
    li t0,0x50000
    csrw mie,t0
    li a2,0
    li a3,0
    li a4,0x13579bdf    /* untouched main-context sentinel */
    li t0,0x18
    sw t0,4(s0)
    li a0,82           /* R: armed and ready */
    call put
main_loop:
    li t0,0x13579bdf
    bne a4,t0,fail
    lw t0,8(s1)
    beq t0,a2,check_rx
    addi a2,a2,1
    bne t0,a2,fail
    lw t0,0(s0)
    andi t0,t0,0x10
    beqz t0,gpio_low
    li a0,72           /* H */
    j gpio_send
gpio_low:
    li a0,76           /* L */
gpio_send:
    call put
check_rx:
    lw t0,12(s1)
    beq t0,a3,main_loop
    addi a3,a3,1
    bne t0,a3,fail
    lw a0,16(s1)
    xori a0,a0,0x20
    call put
    j main_loop
put:
    lw t0,0x10(s0)
    andi t0,t0,1
    bnez t0,put
    sw a0,0xc(s0)
    ret
/* IRQ16/17 are latched in mip; IRQ18/19 are level sources. */
irq_entry:
    addi sp,sp,-16
    sw t0,0(sp)
    sw t1,4(sp)
    sw t2,8(sp)
    csrr t0,mcause
    li t1,0x80000010
    beq t0,t1,irq_gpio
    li t1,0x80000011
    beq t0,t1,irq_timer
    li t1,0x80000012
    beq t0,t1,irq_rx
    li t1,0x80000013
    beq t0,t1,irq_tx
    j fail
irq_gpio:
    li t1,0x10000
    csrc mip,t1
    lw t2,8(s1)
    addi t2,t2,1
    sw t2,8(s1)
    j irq_return
irq_timer:
    li t1,0x20000
    csrc mip,t1
    lw t2,0(s1)
    addi t2,t2,1
    sw t2,0(s1)
    j irq_return
irq_rx:
    lw t1,0xc(s0)      /* clears rx_valid */
    sw t1,16(s1)
    lw t2,12(s1)
    addi t2,t2,1
    sw t2,12(s1)
    j irq_return
irq_tx:
    li t1,0x80000
    csrc mie,t1         /* idle is level asserted; disable until next request */
    lw t2,4(s1)
    addi t2,t2,1
    sw t2,4(s1)
irq_return:
    lw t0,0(sp)
    lw t1,4(sp)
    lw t2,8(sp)
    addi sp,sp,16
    mret
fail:
    li t0,0x08000000
    li t1,0xee
    sw t1,4(t0)
1:  j 1b
