/*
 * keyboard_test.s
 * 68K test program for keyboard matrix and latching keyboard (btnp)
 *
 * This program tests:
 * 1. Reading keyboard matrix at 0x800040-0x80005f
 * 2. Reading latched keyboard matrix at 0x800080-0x80009f
 * 3. Clearing latched keys by writing to 0x800080-0x80009f
 */

    .section .text
    .global _start

/* Keyboard register addresses */
/* Post code output */
/* Debug register */
/* Test key indices - using scancode 0x1C (A key) = key index 0x1C */
.equ TEST_KEY_1,        0x1C        /* A key scancode */
.equ TEST_KEY_2,        0x23        /* D key scancode */


#include "asm/nextp8.h"

_start:
    /* Initialize stack pointer */
    move.l  #0x00010000, %sp

    /* POST 4: Starting test */
    move.b  #4, _POST_CODE

    /* ================================================================
     * TEST 1: Check that both matrices are initially clear
     * ================================================================ */

    move.b  #5, _POST_CODE

    /* Check all 16 words of regular keyboard matrix (256 bits = 32 bytes = 16 words) */
    lea     _KEYBOARD_MATRIX, %a0
    move.w  #15, %d7        /* Counter: 0-15 (16 words) */
check_matrix_clear:
    move.w  (%a0)+, %d0
    tst.w   %d0
    bne     fail            /* If any bit set, fail */
    dbf     %d7, check_matrix_clear

    /* Check all 16 words of latching keyboard matrix */
    lea     _KEYBOARD_MATRIX_LATCHED, %a0
    move.w  #15, %d7        /* Counter: 0-15 (16 words) */
check_latch_clear:
    move.w  (%a0)+, %d0
    tst.w   %d0
    bne     fail            /* If any bit set, fail */
    dbf     %d7, check_latch_clear

    /* POST 6: Initial clear check passed */
    move.b  #6, _POST_CODE

    /* ================================================================
     * TEST 2: Wait for key press, check it appears in both matrices
     * Testbench will inject TEST_KEY_1 (0x1C = bit 28 of word 1)
     * Word address = 0x1C >> 4 = 1, bit = 0x1C & 0xF = 12
     * ================================================================ */

    move.b  #7, _POST_CODE

    /* Calculate byte offset and bit mask for TEST_KEY_1 */
    move.w  #TEST_KEY_1, %d0
    move.w  %d0, %d1
    lsr.w   #3, %d0         /* Byte offset = key_index / 8 */
    andi.w  #7, %d1         /* Bit position = key_index & 7 */

    /* Wait for key in regular matrix */
    lea     _KEYBOARD_MATRIX, %a0

wait_key1_regular:
    move.b  (%a0,%d0.w), %d3
    btst    %d1, %d3
    beq     wait_key1_regular

    /* POST 8: Key detected in regular matrix */
    move.b  #8, _POST_CODE

    /* Check key also in latching matrix */
    lea     _KEYBOARD_MATRIX_LATCHED, %a0
    move.b  (%a0,%d0.w), %d3
    btst    %d1, %d3
    beq     fail

    /* POST 9: Key detected in latching matrix */
    move.b  #9, _POST_CODE

    /* ================================================================
     * TEST 3: Wait for key release, verify regular matrix clears
     *         but latching matrix stays set
     * ================================================================ */

    move.b  #10, _POST_CODE

    /* Wait for key to be released from regular matrix */
    lea     _KEYBOARD_MATRIX, %a0
wait_key1_release:
    move.b  (%a0,%d0.w), %d3
    btst    %d1, %d3
    bne     wait_key1_release

    /* POST 11: Key released from regular matrix */
    move.b  #11, _POST_CODE

    /* Verify key still set in latching matrix */
    lea     _KEYBOARD_MATRIX_LATCHED, %a0
    move.b  (%a0,%d0.w), %d3
    btst    %d1, %d3
    beq     fail

    /* POST 12: Key still latched */
    move.b  #12, _POST_CODE

    /* ================================================================
     * TEST 4: Press and latch a second key (TEST_KEY_2)
     * ================================================================ */

    move.b  #13, _POST_CODE

    /* Calculate byte offset and bit for TEST_KEY_2 (0x23) */
    move.w  #TEST_KEY_2, %d4
    move.w  %d4, %d5
    lsr.w   #3, %d4         /* Byte offset = key_index / 8 */
    andi.w  #7, %d5         /* Bit position = key_index & 7 */

    /* Wait for second key in regular matrix */
    lea     _KEYBOARD_MATRIX, %a0
wait_key2_regular:
    move.b  (%a0,%d4.w), %d3
    btst    %d5, %d3
    beq     wait_key2_regular

    /* POST 14: Second key detected */
    move.b  #14, _POST_CODE

    /* Wait for second key release */
wait_key2_release:
    move.b  (%a0,%d4.w), %d3
    btst    %d5, %d3
    bne     wait_key2_release

    /* POST 15: Second key released */
    move.b  #15, _POST_CODE

    /* Verify both keys latched */
    lea     _KEYBOARD_MATRIX_LATCHED, %a0
    move.b  (%a0,%d0.w), %d3
    btst    %d1, %d3
    beq     fail
    move.b  (%a0,%d4.w), %d3
    btst    %d5, %d3
    beq     fail

    /* POST 16: Both keys latched */
    move.b  #16, _POST_CODE

    /* ================================================================
     * TEST 5: Clear first key by writing to latching matrix
     *         Verify only that bit is cleared, not the second key
     * ================================================================ */

    move.b  #17, _POST_CODE

    /* Create bitmask to clear TEST_KEY_1 */
    move.b  #1, %d6
    lsl.b   %d1, %d6        /* Shift to bit position */

    /* Write to clear TEST_KEY_1 */
    lea     _KEYBOARD_MATRIX_LATCHED, %a0
    move.b  %d6, (%a0,%d0.w)

    /* POST 18: Wrote clear command */
    move.b  #18, _POST_CODE

    /* Verify TEST_KEY_1 is now clear */
    move.b  (%a0,%d0.w), %d3
    btst    %d1, %d3
    bne     fail

    /* POST 19: First key cleared */
    move.b  #19, _POST_CODE

    /* Verify TEST_KEY_2 is still latched */
    move.b  (%a0,%d4.w), %d3
    btst    %d5, %d3
    beq     fail

    /* POST 20: Second key still latched */
    move.b  #20, _POST_CODE

    /* ================================================================
     * TEST 6: Clear second key
     * ================================================================ */

    move.b  #1, %d6
    lsl.b   %d5, %d6
    move.b  %d6, (%a0,%d4.w)

    /* Verify cleared */
    move.b  (%a0,%d4.w), %d3
    btst    %d5, %d3
    bne     fail

    /* POST 21: Second key cleared */
    move.b  #21, _POST_CODE

    /* ================================================================
     * ALL TESTS PASSED
     * ================================================================ */

    /* POST 25: Success! */
    move.b  #25, _POST_CODE

done:
    bra     done

fail:
    /* POST 50: Test failed */
    move.b  #50, _POST_CODE
fail_loop:
    bra     fail_loop

/* Reset vectors at beginning of ROM */
    .section .vectors, "a"
    .long   0x00010000      /* Initial SP */
    .long   _start          /* Initial PC */

    .section .data
    .align 4

