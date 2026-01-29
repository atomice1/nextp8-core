/*
 * hello_test.s
 * Simple 68K test program for UART "Hello, world!" output
 * 
 * This program tests:
 * 1. Initializes the system
 * 2. Performs some basic sanity tests
 * 3. Outputs "Hello, world!" via the Pi UART
 * 4. Updates post_code to signal progress
 */

    .section .text
    .global _start

/* UART register addresses */
/* Post code output */

#include "asm/nextp8.h"

_start:
    /* Initialize stack pointer  */
    move.l  #0x00010000, %sp

    /* POST 4: Starting function call test */
    move.b  #4, _POST_CODE

    /* Initialize test data with known value */
    lea     test_data, %a0
    move.l  #0x12345678, (%a0)

    /* POST 5: About to call function */
    move.b  #5, _POST_CODE

    /* Call test function with pointer argument in a0 */
    lea     test_data, %a0
    jsr     test_function

    /* POST 6: Returned from function */
    move.b  #6, _POST_CODE

    /* Check return value in d0 (should be 0x42) */
    cmp.l   #0x00000042, %d0
    bne     fail

    /* POST 7: Return value correct */
    move.b  #7, _POST_CODE

    /* Check that function wrote correct value to pointer */
    lea     test_data, %a0
    move.l  (%a0), %d1
    cmp.l   #0xDEADBEEF, %d1
    bne     fail

    /* POST 8: Written value correct */
    move.b  #8, _POST_CODE

    /* POST 9: Starting UART test */
    move.b  #9, _POST_CODE

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
    /* POST 10: All tests complete */
    move.b  #10, _POST_CODE

    /* Test complete - loop forever */
    bra     infinite_loop

test_function:
    /* Function that:
     *   - Takes pointer argument in a0
     *   - Writes 0xDEADBEEF to the address
     *   - Returns 0x42 in d0
     */
    move.l  #0xDEADBEEF, (%a0)   /* Write to pointer */
    move.l  #0x00000042, %d0      /* Set return value */
    rts

fail:
infinite_loop:
    nop
    bra     infinite_loop

/* Message string */
hello_msg:
    .ascii  "Hello, world!\n\0"

/* Test data storage */
    .align  4
test_data:
    .long   0x00000000

/* Reset vectors at beginning of ROM */
    .section .vectors, "a"
    .long   0x00010000      /* Initial SP */
    .long   _start          /* Initial PC */
