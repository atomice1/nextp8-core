/*
 * memtest.s
 * Comprehensive memory access test for nextp8
 * 
 * Tests all memory types with write, three unrelated accesses, then read pattern:
 * - SRAM (0x000000-0x3FFFFF)
 * - MMIO debug register (0x800062, 0x800064)
 * - Video RAM back buffer (0xC00000-0xC01FFF)
 * - Video RAM front buffer (0xC02000-0xC03FFF)
 * - Video RAM overlay back (0xC04000-0xC05FFF)
 * - Video RAM overlay front (0xC06000-0xC07FFF)
 * - Palette RAM (0xC08000-0xC0803F)
 * - Digital Audio RAM (0xC0C000-0xC0FFFF)
 */

    .section .text
    .global _start

/* Memory addresses for testing */
.equ POST_CODE,         0x80000C

.equ SRAM_ADDR,         0x010000    /* SRAM test location */
.equ DEBUG_REG_LO,      0x800064    /* MMIO debug register low */
.equ DEBUG_REG_HI,      0x800062    /* MMIO debug register high */
.equ VRAM_BACK,         0xC00100    /* Video back buffer */
.equ VRAM_FRONT,        0xC02100    /* Video front buffer */
.equ VRAM_OV_BACK,      0xC04100    /* Video overlay back */
.equ VRAM_OV_FRONT,     0xC06100    /* Video overlay front */
.equ PAL_RAM,           0xC08010    /* Palette RAM */
.equ DA_RAM,            0xC0C100    /* Digital audio RAM */

/* Test values */
.equ TEST_VAL_1,        0xABCD
.equ TEST_VAL_2,        0x1234
.equ TEST_VAL_3,        0x5678
.equ TEST_VAL_4,        0x9ABC
.equ TEST_VAL_5,        0xDEF0
.equ TEST_VAL_6,        0x4321
.equ TEST_VAL_7,        0x800F    /* Palette RAM: only bits [7,3:0] per byte are stored */
.equ TEST_VAL_8,        0xFEDC

_start:
    /* Initialize stack pointer */
    move.l  #0x00010000, %sp

    /* POST 4: Starting memory tests */
    move.b  #4, POST_CODE

    /*========================================
     * TEST 1: SRAM
     *========================================*/
    /* POST 5: Testing SRAM */
    move.b  #5, POST_CODE
    
    /* Write test value to SRAM */
    move.w  #TEST_VAL_1, SRAM_ADDR
    
    /* Three unrelated accesses */
    move.w  #0x1111, VRAM_BACK
    move.w  #0x2222, VRAM_FRONT
    move.w  #0x3333, DA_RAM
    
    /* Read back and verify */
    move.w  SRAM_ADDR, %d0
    cmp.w   #TEST_VAL_1, %d0
    bne     fail_sram

    /*========================================
     * TEST 2: MMIO Debug Register
     *========================================*/
    /* POST 6: Testing MMIO */
    move.b  #6, POST_CODE
    
    /* Write test value to debug register */
    move.w  #TEST_VAL_2, DEBUG_REG_LO
    
    /* Three unrelated accesses */
    move.w  #0x4444, SRAM_ADDR
    move.w  #0x5555, VRAM_BACK
    move.w  #0x6666, PAL_RAM
    
    /* Read back and verify */
    move.w  DEBUG_REG_LO, %d0
    cmp.w   #TEST_VAL_2, %d0
    bne     fail_mmio

    /*========================================
     * TEST 3: Video RAM Back Buffer
     *========================================*/
    /* POST 7: Testing VRAM back */
    move.b  #7, POST_CODE
    
    /* Write test value */
    move.w  #TEST_VAL_3, VRAM_BACK
    
    /* Three unrelated accesses */
    move.w  #0x7777, SRAM_ADDR
    move.w  #0x8888, DEBUG_REG_LO
    move.w  #0x9999, VRAM_FRONT
    
    /* Read back and verify */
    move.w  VRAM_BACK, %d0
    cmp.w   #TEST_VAL_3, %d0
    bne     fail_vram_back

    /*========================================
     * TEST 4: Video RAM Front Buffer
     *========================================*/
    /* POST 8: Testing VRAM front */
    move.b  #8, POST_CODE
    
    /* Write test value */
    move.w  #TEST_VAL_4, VRAM_FRONT
    
    /* Three unrelated accesses */
    move.w  #0xAAAA, VRAM_BACK
    move.w  #0xBBBB, SRAM_ADDR
    move.w  #0xCCCC, DA_RAM
    
    /* Read back and verify */
    move.w  VRAM_FRONT, %d0
    cmp.w   #TEST_VAL_4, %d0
    bne     fail_vram_front

    /*========================================
     * TEST 5: Video RAM Overlay Back
     *========================================*/
    /* POST 9: Testing VRAM overlay back */
    move.b  #9, POST_CODE
    
    /* Write test value */
    move.w  #TEST_VAL_5, VRAM_OV_BACK
    
    /* Three unrelated accesses */
    move.w  #0xDDDD, VRAM_OV_FRONT
    move.w  #0xEEEE, PAL_RAM
    move.w  #0xFFFF, SRAM_ADDR
    
    /* Read back and verify */
    move.w  VRAM_OV_BACK, %d0
    cmp.w   #TEST_VAL_5, %d0
    bne     fail_vram_ov_back

    /*========================================
     * TEST 6: Video RAM Overlay Front
     *========================================*/
    /* POST 10: Testing VRAM overlay front */
    move.b  #10, POST_CODE
    
    /* Write test value */
    move.w  #TEST_VAL_6, VRAM_OV_FRONT
    
    /* Three unrelated accesses */
    move.w  #0x1122, VRAM_OV_BACK
    move.w  #0x3344, DEBUG_REG_LO
    move.w  #0x5566, VRAM_BACK
    
    /* Read back and verify */
    move.w  VRAM_OV_FRONT, %d0
    cmp.w   #TEST_VAL_6, %d0
    bne     fail_vram_ov_front

    /*========================================
     * TEST 7: Palette RAM
     *========================================*/
    /* POST 11: Testing palette RAM */
    move.b  #11, POST_CODE
    
    /* Write test value */
    move.w  #TEST_VAL_7, PAL_RAM
    
    /* Three unrelated accesses */
    move.w  #0x7788, SRAM_ADDR
    move.w  #0x99AA, VRAM_FRONT
    move.w  #0xBBCC, DA_RAM
    
    /* Read back and verify */
    move.w  PAL_RAM, %d0
    cmp.w   #TEST_VAL_7, %d0
    bne     fail_pal_ram

    /*========================================
     * TEST 8: Digital Audio RAM
     *========================================*/
    /* POST 12: Testing digital audio RAM */
    move.b  #12, POST_CODE
    
    /* Write test value */
    move.w  #TEST_VAL_8, DA_RAM
    
    /* Three unrelated accesses */
    move.w  #0xDDEE, PAL_RAM
    move.w  #0xFF00, SRAM_ADDR
    move.w  #0x1100, VRAM_BACK
    
    /* Read back and verify */
    move.w  DA_RAM, %d0
    cmp.w   #TEST_VAL_8, %d0
    bne     fail_da_ram

    /*========================================
     * ALL TESTS PASSED
     *========================================*/
    /* POST 13: All tests passed */
    move.b  #13, POST_CODE
    
    bra     success_loop

fail_sram:
    move.b  #25, POST_CODE       /* Stay at test 1 */
    bra     infinite_loop

fail_mmio:
    move.b  #26, POST_CODE       /* Stay at test 2 */
    bra     infinite_loop

fail_vram_back:
    move.b  #27, POST_CODE       /* Stay at test 3 */
    bra     infinite_loop

fail_vram_front:
    move.b  #28, POST_CODE       /* Stay at test 4 */
    bra     infinite_loop

fail_vram_ov_back:
    move.b  #29, POST_CODE       /* Stay at test 5 */
    bra     infinite_loop

fail_vram_ov_front:
    move.b  #30, POST_CODE      /* Stay at test 6 */
    bra     infinite_loop

fail_pal_ram:
    move.b  #31, POST_CODE      /* Stay at test 7 */
    bra     infinite_loop

fail_da_ram:
    move.b  #32, POST_CODE      /* Stay at test 8 */
    bra     infinite_loop

success_loop:
    nop
    bra     success_loop

infinite_loop:
    nop
    bra     infinite_loop

/* Reset vectors at beginning of ROM */
    .section .vectors, "a"
    .long   0x00010000      /* Initial SP */
    .long   _start          /* Initial PC */
