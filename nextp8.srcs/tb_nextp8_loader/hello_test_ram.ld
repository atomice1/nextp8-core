/*
 * hello_test_ram.ld
 * Linker script for hello test application loaded to RAM
 * Application is loaded at 128KB (0x20000) by the loader
 */

MEMORY
{
    RAM (rwx) : ORIGIN = 0x00020000, LENGTH = 3968K
}

SECTIONS
{
    /* Reset vectors (if present, but ignored for RAM apps) */
    .vectors 0x00020000 :
    {
        KEEP(*(.vectors))
    } > RAM

    /* Program starts right after vectors */
    .text :
    {
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
        *(.data)
        *(.data.*)
    } > RAM

    .bss :
    {
        *(.bss)
        *(.bss.*)
        *(COMMON)
    } > RAM
}
