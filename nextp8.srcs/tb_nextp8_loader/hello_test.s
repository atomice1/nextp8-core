/*
 * hello_test.s
 * Simple 68K test program for UART "Hello, world!" output
 *
 * This program:
 * 1. Initializes the system
 * 2. Outputs "Hello, world!" via the Pi UART
 * 3. Updates post_code to signal progress
 */

    .section .text
    .global _start

/* UART register addresses */
/* Post code output */

#include "asm/nextp8.h"

_start:
    /* Initialize stack pointer */
    move.l  #0x00001000, %sp

    /* Signal: Starting UART test (post_code = 24) */
    move.b  #24, _POST_CODE

    /* Initialize message pointer */
    lea     hello_msg, %a0

send_loop:
    /* Load next character */
    move.b  (%a0)+, %d0

    /* Check for null terminator */
    beq     done

wait_uart_ready:
    /* Read UART status */
    move.b  _UART_CTRL, %d1

    /* Check bit 1 (ready) - UART ready to accept data */
    btst    #1, %d1
    beq     wait_uart_ready

    /* Write character to UART data register */
    move.b  %d0, _UART_DATA

    /* Pulse UART write strobe (set bit 8 in CTRL) */
    move.b  #0x01, _UART_CTRL

wait_uart_wa:
    /* Read UART status */
    move.b  _UART_CTRL, %d1

    /* Check bit 3 (wa) - UART write acknowledge */
    btst    #3, %d1
    beq     wait_uart_wa

    /* Clear write strobe */
    move.b  #0x00, _UART_CTRL

    /* Continue with next character */
    bra     send_loop

done:
    /* Signal: Test complete (post_code = 25) */
    move.b  #25, _POST_CODE

    /* Loop forever */
infinite_loop:
    nop
    bra     infinite_loop

/* Message string */
hello_msg:
    .ascii  "Hello, world!\n\0"

/* Reset vectors at beginning of ROM */
    .section .vectors, "a"
    .long   0x00001000      /* Initial SP */
    .long   _start          /* Initial PC */
