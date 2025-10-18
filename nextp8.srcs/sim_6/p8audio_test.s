/*
 * p8audio_test.s
 * Simple 68K test program for p8audio integration
 * 
 * This program:
 * 1. Sets up p8audio registers
 * 2. Triggers SFX 0 on channel 0
 * 3. Waits for completion
 * 4. Updates post_code to signal progress
 */

    .section .text
    .global _start

/* p8audio register addresses */
.equ P8AUDIO_BASE,      0x800100
.equ SFX_BASE_HI,       0x800104
.equ SFX_BASE_LO,       0x800106
.equ CTRL,              0x800102
.equ NOTE_ATK,          0x800110
.equ NOTE_REL,          0x800112
.equ SFX_CMD,           0x800114
.equ SFX_LEN,           0x800116

/* Post code output (via GPIO) */
.equ POST_CODE,         0x80000C

/* SFX data location in RAM */
.equ SFX_DATA_ADDR,     0x3200

_start:
    /* Initialize stack pointer */
    move.l  #0x00001000, %sp
    
    /* Signal: Initializing p8audio (post_code = 3) */
    move.w  #3, POST_CODE
    
    /* Configure SFX base address = 0x3200 */
    move.w  #0x0000, SFX_BASE_HI   /* Upper 16 bits = 0 */
    move.w  #SFX_DATA_ADDR, SFX_BASE_LO  /* Lower 16 bits = 0x3200 */
    
    /* Enable p8audio: CTRL.RUN = 1 */
    move.w  #0x0001, CTRL
    
    /* Set note attack time = 20 */
    move.w  #20, NOTE_ATK
    
    /* Set note release time = 20 */
    move.w  #20, NOTE_REL
    
    /* Signal: Configuration complete (post_code = 4) */
    move.w  #4, POST_CODE
    
    /* Trigger SFX 0 on channel 0 with full length
     * SFX_CMD format:
     *   Bit 15:    Command valid (1)
     *   Bits 14-12: Channel (0 = channel 0)
     *   Bits 11-6:  Offset (0)
     *   Bits 5-0:   SFX index (0)
     */
    move.w  #0x8000, SFX_CMD       /* 1000_0000_0000_0000 */
    
    /* Set SFX length = 0 (play full SFX) */
    move.w  #0, SFX_LEN
    
    /* Signal: SFX triggered (post_code = 5) */
    move.w  #5, POST_CODE
    
    /* Wait a bit for SFX to play */
    move.l  #0x100000, %d0
wait_loop:
    subq.l  #1, %d0
    bne     wait_loop
    
    /* Signal: Test complete (post_code = 6) */
    move.w  #6, POST_CODE
    
    /* Trigger another SFX (SFX 1 on channel 0) */
    move.w  #0x8001, SFX_CMD
    move.w  #7, POST_CODE
    
    /* Wait again */
    move.l  #0x100000, %d0
wait_loop2:
    subq.l  #1, %d0
    bne     wait_loop2
    
    /* Final signal (post_code = 8) */
    move.w  #8, POST_CODE
    
    /* Loop forever */
infinite_loop:
    nop
    bra     infinite_loop

/* Reset vectors at beginning of ROM */
    .section .vectors, "a"
    .long   0x00001000      /* Initial SP */
    .long   _start          /* Initial PC */
