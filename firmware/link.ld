OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    FLASH (rx) : ORIGIN = 0x00000000, LENGTH = 2K
    RAM_A (rw) : ORIGIN = 0x01000000, LENGTH = 1K
}

/* Conservative smoke-test limits, not the physical IC capacities. */
__stack_top = ORIGIN(RAM_A) + LENGTH(RAM_A);

SECTIONS
{
    .text : {
        KEEP(*(.vectors))
        *(.text.startup .text.startup.* .text .text.*)
        *(.rodata .rodata.* .srodata .srodata.*)
        . = ALIGN(4);
    } > FLASH

    .data : {
        __data_start = .;
        *(.data .data.* .sdata .sdata.*)
        . = ALIGN(4);
        __data_end = .;
    } > RAM_A AT > FLASH
    __data_load = LOADADDR(.data);

    .bss (NOLOAD) : {
        __bss_start = .;
        *(.bss .bss.* .sbss .sbss.* COMMON)
        . = ALIGN(4);
        __bss_end = .;
    } > RAM_A

    /DISCARD/ : { *(.comment .eh_frame .eh_frame.* .note .note.*) }
}
ASSERT(__bss_end <= ORIGIN(RAM_A) + 0x100, "Static data overlaps the two-bank scratch test");
