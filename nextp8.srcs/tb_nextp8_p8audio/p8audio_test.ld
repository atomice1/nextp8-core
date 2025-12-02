/*
 * p8audio_test.ld
 * Linker script for p8audio test ROM
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

    /* Error if .data section is non-empty (we want ROM-only data in .rodata) */
    ASSERT(SIZEOF(.data) == 0, "ERROR: .data section must be empty - use .rodata for ROM data")

    .bss :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > RAM
}
