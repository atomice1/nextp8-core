/*
 * Linker script for mouse test ROM
 * ROM starts at 0x00000000
 */

MEMORY
{
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS
{
    /* Reset vectors at 0x0000 */
    .vectors 0x00000000 :
    {
        KEEP(*(.vectors))
    } > ROM

    /* Program code starts at 0x1000 */
    .text 0x00001000 :
    {
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
    } > ROM

    .data : {
        *(.data)
        *(.data.*)
    } > ROM

    .bss : {
        *(.bss)
        *(.bss.*)
    } > ROM
}
