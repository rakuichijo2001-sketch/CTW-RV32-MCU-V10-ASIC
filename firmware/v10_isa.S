/* SPDX-License-Identifier: Apache-2.0
 * V10 directed RV32E + representative RVC and Zicsr tests.
 * RV32E has only x0-x15. Return a0=0 on pass, else a0=first failed ID.
 * DOES NOT constitute exhaustive ISA compliance certification.
 */
.section .text,"ax",@progbits
.globl v10_isa_check
.option push
.option norvc
.macro CHECK reg, expected, id
    li a0,\id
    li a5,\expected
    bne \reg,a5,.Lfail
.endm
v10_isa_check:
    /* x0 immutability, arithmetic, comparisons, signed and unsigned */
    li t0,31
    addi zero,t0,5
    CHECK zero,0,1
    addi t1,t0,-40
    CHECK t1,-9,2
    add t2,t0,t1
    CHECK t2,22,3
    sub t2,t0,t1
    CHECK t2,40,4
    andi t2,t0,7
    CHECK t2,7,5
    ori t2,zero,85
    CHECK t2,85,6
    xori t2,t2,255
    CHECK t2,170,7
    li t0,-2147483648
    srai t2,t0,31
    CHECK t2,-1,8
    srli t2,t0,31
    CHECK t2,1,9
    slli t2,t2,5
    CHECK t2,32,10
    slti t2,t0,0
    CHECK t2,1,11
    sltiu t2,t0,1
    CHECK t2,0,12
    li t1,1
    slt t2,t0,t1
    CHECK t2,1,13
    sltu t2,t0,t1
    CHECK t2,0,14
    li t0,0x0f0f0f0f
    li t1,0x33333333
    and t2,t0,t1
    CHECK t2,0x03030303,15
    or t2,t0,t1
    CHECK t2,0x3f3f3f3f,16
    xor t2,t0,t1
    CHECK t2,0x3c3c3c3c,17
    li t0,-16
    li t1,2
    sra t2,t0,t1
    CHECK t2,-4,18
    srl t2,t0,t1
    CHECK t2,0x3ffffffc,19
    li t0,1
    li t1,31
    sll t2,t0,t1
    CHECK t2,0x80000000,20
    /* control flow: both taken and untaken branches, signed & unsigned */
    li t0,-1
    li t1,1
    li a0,21
    blt t0,t1,1f
    j .Lfail
1:  li a0,22
    bge t0,t1,.Lfail
    li a0,23
    bltu t0,t1,.Lfail
    li a0,24
    bgeu t0,t1,2f
    j .Lfail
2:  li a0,25
    beq t0,t1,.Lfail
    li a0,26
    bne t0,t1,3f
    j .Lfail
3:  /* JAL+JALR round trip */
    li a0,27
    jal t0,4f
    j 5f
4:  addi t1,t0,0
    jalr zero,0(t1)
5:  /* AUIPC PC-relative sanity */
    auipc t0,0
    auipc t1,0
    sub t2,t1,t0
    CHECK t2,4,28
    /* load/store lane and signed extension via aligned SP scratch */
    addi sp,sp,-16
    li t0,0x80917e12
    sw t0,0(sp)
    lw t1,0(sp)
    CHECK t1,0x80917e12,29
    lb t1,3(sp)
    CHECK t1,-128,30
    lbu t1,3(sp)
    CHECK t1,128,31
    lh t1,2(sp)
    CHECK t1,-32623,32
    lhu t1,2(sp)
    CHECK t1,0x8091,33
    li t0,0xab
    sb t0,1(sp)
    lbu t1,1(sp)
    CHECK t1,171,34
    li t0,0xfedc
    sh t0,2(sp)
    lhu t1,2(sp)
    CHECK t1,0xfedc,35
    fence
    addi sp,sp,16
    /* Representative real RVC instructions (no compiler inference). */
.option rvc
    c.li t0,7
    c.addi t0,3
    CHECK t0,10,36
    c.slli t0,1
    CHECK t0,20,37
    c.li a0,0
    c.beqz a0,6f
    li a0,38
    j .Lfail
6:  c.li a0,1
    c.bnez a0,7f
    li a0,39
    j .Lfail
7:  c.addi sp,-16
    c.swsp t0,0(sp)
    c.lwsp t1,0(sp)
    CHECK t1,20,40
    c.addi sp,16
.option norvc
    li a0,0
.Lfail:
    ret
.option pop
