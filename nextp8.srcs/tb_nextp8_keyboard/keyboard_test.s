/*
 * keyboard_test.s
 * 68K test program for keyboard matrix, latching keyboard (btnp),
 * and keyboard event queue.
 *
 * This program tests:
 * 1. Reading keyboard matrix at 0x800040-0x80005f
 * 2. Reading latched keyboard matrix at 0x800080-0x80009f
 * 3. Clearing latched keys by writing to 0x800080-0x80009f
 * 7. Clear the event queue by writing to the event register
 * 8. Read from empty queue returns 0
 * 9. Wait for key press from queue
 * 10. Wait for key release from queue
 * 11. Write to the event register clears the queue
 *
 * Event format (32-bit):
 *   [31]   0: press, 1: release
 *   [30]   membrane mode
 *   [29:16] reserved
 *   [27:24] lock keys
 *   [23:16] modifiers
 *   [15:0]  scancode
 */

    .section .text
    .global _start

/* Keyboard register addresses */
/* Post code output */
/* Debug register */

/* USB HID scancodes (for matrix and event queue) */
/* A key USB HID = 0x04, D key USB HID = 0x07, 2 key USB HID = 0x1F */
.equ TEST_KEY_1,        0x04        /* A key - USB HID scancode */
.equ TEST_KEY_2,        0x07        /* D key - USB HID scancode */
.equ TEST_KEY_3,        0x1F        /* 2 key - USB HID scancode */


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
     * Testbench will inject TEST_KEY_1 (USB HID 0x04 = bit 4 of word 0)
     * Word address = 0x04 >> 4 = 0, bit = 0x04 & 0xF = 4
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
    lsl.b   %d1, %d6        /* Shift to bit position - d6 has the bit to clear */

    /* Load latching matrix address */
    lea     _KEYBOARD_MATRIX_LATCHED, %a1

    /* Write the bit to clear (hardware does: current & ~write_data) */
    move.b  %d6, (%a1,%d0.w)

    /* POST 18: Wrote clear command */
    move.b  #18, _POST_CODE

    /* Verify TEST_KEY_1 is now clear */
    move.b  (%a1,%d0.w), %d3
    btst    %d1, %d3
    bne     fail

    /* POST 19: First key cleared */
    move.b  #19, _POST_CODE

    /* Verify TEST_KEY_2 is still latched */
    move.b  (%a1,%d4.w), %d3
    btst    %d5, %d3
    beq     fail

    /* POST 20: Second key still latched */
    move.b  #20, _POST_CODE

    /* ================================================================
     * TEST 6: Clear second key
     * ================================================================ */

    move.b  #1, %d6
    lsl.b   %d5, %d6        /* d6 has the bit to clear */
    move.b  %d6, (%a1,%d4.w) /* Write the bit to clear */

    /* Verify cleared */
    move.b  (%a1,%d4.w), %d3
    btst    %d5, %d3
    bne     fail

    /* POST 21: Second key cleared */
    move.b  #21, _POST_CODE

    /* ================================================================
     * NEW TEST 7: Clear the event queue by writing to the event register
     * ================================================================ */

    /* Clear the queue by writing any value to the event register */
    move.w  #0, _KEYBOARD_EVENT_QUEUE_LO

    /* POST 22: Queue cleared */
    move.b  #22, _POST_CODE

    /* ================================================================
     * NEW TEST 8: Read from empty queue returns 0
     * ================================================================ */

    move.l  _KEYBOARD_EVENT_QUEUE_HI, %d0  /* Big-endian 32-bit read */
    tst.l   %d0
    bne     fail            /* Should return 0 */

    /* POST 23: Empty queue read verified (returns 0) */
    move.b  #23, _POST_CODE

    /* ================================================================
     * NEW TEST 9: Wait for key press from queue
     * Testbench will inject TEST_KEY_1 (PS/2 0x1C = USB HID 0x04)
     * Event contains USB HID scancode 0x04
     * Press event = 0x00000004, release event = 0x80000004
     * ================================================================ */

    /* Wait for key press in regular matrix first */
    lea     _KEYBOARD_MATRIX, %a0
    move.w  #TEST_KEY_1, %d0
    move.w  %d0, %d1
    lsr.w   #3, %d0         /* Byte offset = key_index / 8 */
    andi.w  #7, %d1         /* Bit position = key_index & 7 */

wait_key1_regular_new:
    move.b  (%a0,%d0.w), %d3
    btst    %d1, %d3
    beq     wait_key1_regular_new

    /* POST 24: Key detected in regular matrix */
    move.b  #24, _POST_CODE

    /* Wait for key press event in queue (32-bit event: USB HID scancode 0x04, press=0) */
wait_key1_event:
    move.l  _KEYBOARD_EVENT_QUEUE_HI, %d0  /* Big-endian: HI word first, then LO word */
    tst.l   %d0
    beq     wait_key1_event   /* Wait for non-zero event */
    cmp.l   #0x00000004, %d0  /* Press event for USB HID scancode 0x04 */
    bne     wait_key1_event

    /* POST 25: Key press event received */
    move.b  #25, _POST_CODE

    /* Clear the latched matrix for TEST_KEY_1 */
    move.b  #1, %d6
    lsl.b   %d1, %d6        /* d6 has the bit to clear */
    move.b  %d6, (%a1,%d4.w) /* Write the bit to clear (hw does: current & ~write_data) */

    /* POST 26: Latched key cleared */
    move.b  #26, _POST_CODE

    /* ================================================================
     * NEW TEST 10: Wait for key release from queue
     * Testbench will release TEST_KEY_1 (PS/2 0x1C = USB HID 0x04)
     * 32-bit event format: [31]=release, [15:0]=USB HID scancode
     * Release event = 0x80000004
     * ================================================================ */

    /* Wait for key release from regular matrix */
wait_key1_release_new:
    move.b  (%a0,%d4.w), %d3
    btst    %d1, %d3
    bne     wait_key1_release_new

    /* POST 27: Key released from regular matrix */
    move.b  #27, _POST_CODE

    /* Wait for key release event in queue (32-bit event: release + USB HID scancode 0x04) */
wait_key1_release_event:
    move.l  _KEYBOARD_EVENT_QUEUE_HI, %d0  /* Big-endian: HI word first, then LO word */
    cmp.l   #0x80000004, %d0  /* Release event for USB HID scancode 0x04 */
    bne     wait_key1_release_event

    /* POST 28: Key release event received */
    move.b  #28, _POST_CODE

    /* Clear the latched matrix again */
    move.b  #1, %d6
    lsl.b   %d1, %d6        /* d6 has the bit to clear */
    move.b  %d6, (%a1,%d0.w) /* Write the bit to clear */

    /* POST 29: Latched key cleared */
    move.b  #29, _POST_CODE

    /* ================================================================
     * NEW TEST 11: Write to the event register clears the queue
     * ================================================================ */

    /* Press a key to put an event in the queue */
    /* Note: This will be handled by testbench */

    /* POST 30: Waiting for key press to add to queue */
    move.b  #30, _POST_CODE

    /* Wait for the key press to appear in regular matrix */
    /* PS/2 0x1E (2 key) = USB HID 0x1F */
    move.w  #TEST_KEY_3, %d4
    move.w  %d4, %d5
    lsr.w   #3, %d4         /* Byte offset = 3 */
    andi.w  #7, %d5         /* Bit position = 7 */

wait_key3_regular:
    move.b  (%a0,%d4.w), %d3
    btst    %d5, %d3
    beq     wait_key3_regular

    /* POST 31: Key press detected */
    move.b  #31, _POST_CODE

    /* Verify event is in queue */
    move.l  _KEYBOARD_EVENT_QUEUE_HI, %d0  /* Big-endian 32-bit read */
    cmp.l   #0x4000001F, %d0  /* Expected press event for USB HID scancode 0x1F */
    bne     fail

    /* POST 32: Event in queue verified */
    move.b  #32, _POST_CODE

    /* Clear queue by writing to event register */
    move.w  #0, _KEYBOARD_EVENT_QUEUE_LO

    /* POST 33: Queue cleared */

    /* Verify queue is now empty (read should return 0) */
    move.l  _KEYBOARD_EVENT_QUEUE_HI, %d0  /* Big-endian 32-bit read */
    tst.l   %d0
    bne     fail            /* Should return 0 after clear */

    /* POST 34: Queue clear verified */
    move.b  #34, _POST_CODE

    /* Clear latched matrix */
    move.b  #1, %d6
    lsl.b   %d5, %d6        /* d6 has the bit to clear */
    move.b  %d6, (%a1,%d4.w) /* Write the bit to clear */

    /* POST 35: Latched key cleared */
    move.b  #35, _POST_CODE

    /* ================================================================
     * ALL TESTS PASSED
     * ================================================================ */

    /* POST 40: Success! */
    move.b  #40, _POST_CODE

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

