/*
 * Copyright (C) 2026 Chris January
 *
 * The authors hereby grant permission to use, copy, modify, distribute,
 * and license this software and its documentation for any purpose, provided
 * that existing copyright notices are retained in all copies and that this
 * notice is included verbatim in any distributions. No written agreement,
 * license, or royalty fee is required for any of the authorized uses.
 * Modifications to this software may be copyrighted by their authors
 * and need not follow the licensing terms described here, provided that
 * the new terms are clearly indicated on the first page of each file where
 * they apply.
 */

#define _MEMIO_BASE         0x800000
#define _PARAMS             (_MEMIO_BASE + 0x1)
#define _POST_CODE          (_MEMIO_BASE + 0x3)
#define _BUILD_TIMESTAMP_HI (_MEMIO_BASE + 0x4)
#define _BUILD_TIMESTAMP_LO (_MEMIO_BASE + 0x6)
#define _HW_VERSION_HI      (_MEMIO_BASE + 0x8)
#define _HW_VERSION_LO      (_MEMIO_BASE + 0xa)
#define _DEBUG_REG_HI       (_MEMIO_BASE + 0xc)
#define _DEBUG_REG_LO       (_MEMIO_BASE + 0xe)
#define _RESET_TYPE         (_MEMIO_BASE + 0x11)
#define _RESET_REQ          (_MEMIO_BASE + 0x11)
#define _VBLANK_INTR_CTRL   (_MEMIO_BASE + 0x13)
#define _UTIMER_1MHZ        (_MEMIO_BASE + 0x14)
#define _UTIMER_1MHZ_6348   (_MEMIO_BASE + 0x14)
#define _UTIMER_1MHZ_4732   (_MEMIO_BASE + 0x16)
#define _UTIMER_1MHZ_3116   (_MEMIO_BASE + 0x18)
#define _UTIMER_1MHZ_1500   (_MEMIO_BASE + 0x1a)
#define _VFRONT             (_MEMIO_BASE + 0x1d)
#define _VFRONTREQ          (_MEMIO_BASE + 0x1d)
#define _OVERLAY_CONTROL    (_MEMIO_BASE + 0x1f)
#define _SDSPI_WRITE_ENABLE (_MEMIO_BASE + 0x21)
#define _SDSPI_DIVIDER      (_MEMIO_BASE + 0x23)
#define _SDSPI_DATA_IN      (_MEMIO_BASE + 0x25)
#define _SDSPI_DATA_OUT     (_MEMIO_BASE + 0x27)
#define _SDSPI_READY        (_MEMIO_BASE + 0x29)
#define _SDSPI_CHIP_SELECT  (_MEMIO_BASE + 0x2b)
#define _UART_CTRL          (_MEMIO_BASE + 0x31)
#define _UART_DATA          (_MEMIO_BASE + 0x33)
#define _UART_BAUD_DIV      (_MEMIO_BASE + 0x34)
#define _ESP_CTRL           (_MEMIO_BASE + 0x37)
#define _ESP_DATA           (_MEMIO_BASE + 0x39)
#define _ESP_BAUD_DIV       (_MEMIO_BASE + 0x3a)
#define _I2C_DATA           (_MEMIO_BASE + 0x3d)
#define _I2C_CTRL           (_MEMIO_BASE + 0x3f)
#define _I2C_STATUS         (_MEMIO_BASE + 0x3f)
#define _DA_CONTROL         (_MEMIO_BASE + 0x40)
#define _DA_PERIOD          (_MEMIO_BASE + 0x42)
#define _JOYSTICK0          (_MEMIO_BASE + 0x49)
#define _JOYSTICK1          (_MEMIO_BASE + 0x4b)
#define _JOYSTICK0_LATCHED  (_MEMIO_BASE + 0x4d)
#define _JOYSTICK1_LATCHED  (_MEMIO_BASE + 0x4f)
#define _MOUSE_X            (_MEMIO_BASE + 0x50)
#define _MOUSE_Y            (_MEMIO_BASE + 0x52)
#define _MOUSE_Z            (_MEMIO_BASE + 0x54)
#define _MOUSE_BUTTONS      (_MEMIO_BASE + 0x57)
#define _MOUSE_BUTTONS_LATCHED (_MEMIO_BASE + 0x59)
#define _KEYBOARD_MATRIX    (_MEMIO_BASE + 0x60)
#define _KEYBOARD_MATRIX_LATCHED (_MEMIO_BASE + 0x80)

#define _P8AUDIO_BASE          0x800100
#define _P8AUDIO_VERSION       (_P8AUDIO_BASE + 0x0)
#define _P8AUDIO_CTRL          (_P8AUDIO_BASE + 0x2)
#define _P8AUDIO_SFX_BASE_HI   (_P8AUDIO_BASE + 0x4)
#define _P8AUDIO_SFX_BASE_LO   (_P8AUDIO_BASE + 0x6)
#define _P8AUDIO_MUSIC_BASE_HI (_P8AUDIO_BASE + 0x8)
#define _P8AUDIO_MUSIC_BASE_LO (_P8AUDIO_BASE + 0xa)
#define _P8AUDIO_HWFX40        (_P8AUDIO_BASE + 0xd)
#define _P8AUDIO_HWFX41        (_P8AUDIO_BASE + 0xf)
#define _P8AUDIO_HWFX42        (_P8AUDIO_BASE + 0x11)
#define _P8AUDIO_HWFX43        (_P8AUDIO_BASE + 0x13)
#define _P8AUDIO_SFX_CMD       (_P8AUDIO_BASE + 0x18)
#define _P8AUDIO_SFX_LEN       (_P8AUDIO_BASE + 0x1a)
#define _P8AUDIO_MUSIC_CMD     (_P8AUDIO_BASE + 0x1c)
#define _P8AUDIO_MUSIC_FADE    (_P8AUDIO_BASE + 0x1e)
#define _P8AUDIO_STAT46        (_P8AUDIO_BASE + 0x20)
#define _P8AUDIO_STAT47        (_P8AUDIO_BASE + 0x22)
#define _P8AUDIO_STAT48        (_P8AUDIO_BASE + 0x24)
#define _P8AUDIO_STAT49        (_P8AUDIO_BASE + 0x26)
#define _P8AUDIO_STAT50        (_P8AUDIO_BASE + 0x28)
#define _P8AUDIO_STAT51        (_P8AUDIO_BASE + 0x2a)
#define _P8AUDIO_STAT52        (_P8AUDIO_BASE + 0x2c)
#define _P8AUDIO_STAT53        (_P8AUDIO_BASE + 0x2e)
#define _P8AUDIO_STAT54        (_P8AUDIO_BASE + 0x30)
#define _P8AUDIO_STAT55        (_P8AUDIO_BASE + 0x32)
#define _P8AUDIO_STAT56        (_P8AUDIO_BASE + 0x34)

#define _DA_MEMORY_BASE     0xc0c000
#define _DA_MEMORY_SIZE     16384
#define _DA_CLKS_PER_SECOND 11000000

#define _BACK_BUFFER_BASE   0xc00000
#define _FRONT_BUFFER_BASE  0xc02000
#define _OVERLAY_BACK_BUFFER_BASE  0xc04000
#define _OVERLAY_FRONT_BUFFER_BASE 0xc06000
#define _PALETTE_BASE       0xc08000
#define _FRAME_BUFFER_SIZE  8192 // 0x2000
#define _OVERLAY_ENABLE_BIT 0x40
#define _OVERLAY_TRANSPARENT_MASK 0xf
#define _PALETTE_SIZE       16
#define _SCREEN_WIDTH       128
#define _SCREEN_HEIGHT      128
#define _FONT_CHAR_WIDTH    4
#define _FONT_CHAR_HEIGHT   5
#define _FONT_LINE_HEIGHT   (_FONT_CHAR_HEIGHT + 1)

#define _TUBE_STDOUT        0xfffffe
#define _TUBE_STDERR        0xffffff

#define _CONFIG_BASE_ROM    0x7c000
#define _CONFIG_BASE        _CONFIG_BASE_ROM

#define LOADER_MAGIC 0x12345432

