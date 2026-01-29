/*
 * mouse_test.s
 * 68K test program for PS/2 mouse interface
 *
 * This program tests:
 * 1. Reading initial mouse position (should be 0,0)
 * 2. Detecting mouse movement and verifying X=10, Y=5
 * 3. Testing left mouse button
 * 4. Testing right mouse button
 */

    .section .text
    .global _start

/* Post code output */
/* Mouse register addresses */
/* Debug register */

#include "asm/nextp8.h"

_start:
    /* Initialize stack pointer */
    move.l  #0x00010000, %sp

    /* POST 4: Starting test */
    move.b  #4, _POST_CODE

    /* ================================================================
     * TEST 1: Check mouse position registers are initially zero
     * ================================================================ */

    move.b  #5, _POST_CODE

    /* Check X position is 0 */
    move.w  _MOUSE_X, %d0
    tst.w   %d0
    bne     fail

    /* Check Y position is 0 */
    move.w  _MOUSE_Y, %d0
    tst.w   %d0
    bne     fail

    /* POST 6: Initial position check passed */
    move.b  #6, _POST_CODE

    /* ================================================================
     * TEST_1: Wait for mouse movement X=10, Y=5
     * Testbench waits for POST 7 then sends movement
     * ================================================================ */

    move.b  #7, _POST_CODE

    /* Wait for X position to become 10 */
wait_x_10:
    move.w  _MOUSE_X, %d0
    cmp.w   #10, %d0
    bne     wait_x_10

    /* POST 8: X=10 detected */
    move.b  #8, _POST_CODE

    /* Wait for Y position to change from 0 (packet + CDC delay ~3ns) */
wait_y_nonzero:
    move.w  _MOUSE_Y, %d0
    tst.w   %d0
    beq     wait_y_nonzero

    /* Verify Y position is 5 */
    cmp.w   #5, %d0
    bne     fail

    /* POST 9: Y=5 verified */
    move.b  #9, _POST_CODE

    /* Write positions to debug register for logging */
    move.w  _MOUSE_X, %d2
    move.l  %d2, _DEBUG_REG_HI
    move.w  _MOUSE_Y, %d3
    move.l  %d3, _DEBUG_REG_HI

    /* POST 10: Movement test passed */
    move.b  #10, _POST_CODE

    /* ================================================================
     * TEST_2: Wait for and verify left mouse button press
     * Testbench waits for POST 12 then sends button press
     * ================================================================ */

    move.b  #12, _POST_CODE

    /* Wait for left button press (bit 0 of _MOUSE_BUTTONS) */
wait_left_button:
    move.w  _MOUSE_BUTTONS, %d0
    btst    #0, %d0
    beq     wait_left_button

    /* POST 13: Left button detected */
    move.b  #13, _POST_CODE

    /* Write button state to debug register */
    move.l  %d0, _DEBUG_REG_HI

    /* Wait for button release */
wait_left_release:
    move.w  _MOUSE_BUTTONS, %d0
    btst    #0, %d0
    bne     wait_left_release

    /* POST 14: Left button released */
    move.b  #14, _POST_CODE

    /* ================================================================
     * TEST_3: Wait for and verify right mouse button press
     * Testbench waits for POST 20 then sends right button press
     * ================================================================ */

    move.b  #20, _POST_CODE

    /* Wait for right button press (bit 1 of _MOUSE_BUTTONS) */
wait_right_button:
    move.w  _MOUSE_BUTTONS, %d0
    btst    #1, %d0
    beq     wait_right_button

    /* POST 21: Right button detected */
    move.b  #21, _POST_CODE

    /* Write button state to debug register */
    move.l  %d0, _DEBUG_REG_HI

    /* Wait for button release */
wait_right_release:
    move.w  _MOUSE_BUTTONS, %d0
    btst    #1, %d0
    bne     wait_right_release

    /* POST 22: Right button released */
    move.b  #22, _POST_CODE

    /* ================================================================
     * All tests passed
     * ================================================================ */

    move.b  #30, _POST_CODE

done:
    /* Infinite loop */
    bra     done

fail:
    /* POST 255: Test failed */
    move.b  #255, _POST_CODE

fail_loop:
    bra     fail_loop

/* Reset vectors at beginning of ROM */
    .section .vectors, "a"
    .long   0x00010000      /* Initial SP */
    .long   _start          /* Initial PC */

    .section .data
    .align 4
