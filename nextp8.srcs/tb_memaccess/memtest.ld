/* Linker script for memtest.s */

OUTPUT_FORMAT("elf32-m68k")
OUTPUT_ARCH(m68k)
ENTRY(_start)

MEMORY
{
    ROM (rx) : ORIGIN = 0x000000, LENGTH = 512K
}

SECTIONS
{
    .vectors 0x000000 :
    {
        KEEP(*(.vectors))
    } > ROM

    .text :
    {
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
    } > ROM

    .data :
    {
        *(.data)
        *(.data.*)
    } > ROM

    .bss :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > ROM

    /DISCARD/ :
    {
        *(.eh_frame)
        *(.comment)
    }
}
