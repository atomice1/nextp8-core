/*
 * p8audio_test.ld
 * Linker script for p8audio test ROM
 */

MEMORY
{
    ROM (rx) : ORIGIN = 0x00000000, LENGTH = 64K
    RAM (rwx): ORIGIN = 0x00001000, LENGTH = 960K
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

    .data :
    {
        *(.data)
        *(.data.*)
    } > RAM AT > ROM

    .bss :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > RAM
}
