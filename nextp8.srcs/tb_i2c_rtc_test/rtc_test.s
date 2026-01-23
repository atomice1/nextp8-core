/*
 * rtc_test.s
 * Test program for DS1307 RTC via I2C
 * 
 * This program:
 * 1. Reads the date from the DS1307 RTC via I2C
 * 2. Packs the date in BCD format (DDMMYYYY)
 * 3. Writes it to the debug register at 0x800062 (32-bit)
 * 4. Sets POST code to indicate success
 */

    .section .text
    .global _start

/* I2C register addresses */
/* Note: I2C slave address is hardcoded in nextp8 I2C master (0x68 for DS1307) */
.equ I2C_DATA,          0x800021    /* I2C data register (read/write) */
.equ I2C_CTRL,          0x800023    /* I2C control/status register */
.equ I2C_STATUS,        0x800023    /* Alias for control (read status, write control) */

/* I2C control bits (write) */
.equ I2C_ENA_BIT,       0x01        /* Enable/latch command */
.equ I2C_RW_BIT,        0x02        /* Read/Write select (0=Write, 1=Read) */

/* I2C status bits (read) */
.equ I2C_BUSY_BIT,      0x01        /* Transaction busy flag */
.equ I2C_ERR_BIT,       0x02        /* Acknowledge error flag */

/* DS1307 I2C addresses */
.equ DS1307_ADDR,       0x68        /* DS1307 7-bit I2C address */
.equ DS1307_WRITE,      0xD0        /* DS1307 I2C write address (0x68<<1 | 0) */
.equ DS1307_READ,       0xD1        /* DS1307 I2C read address (0x68<<1 | 1) */

/* DS1307 register addresses */
.equ DS1307_REG_SEC,    0x00
.equ DS1307_REG_MIN,    0x01
.equ DS1307_REG_HOUR,   0x02
.equ DS1307_REG_DAY,    0x03
.equ DS1307_REG_DATE,   0x04
.equ DS1307_REG_MONTH,  0x05
.equ DS1307_REG_YEAR,   0x06

/* Debug register */
.equ DEBUG_REG,         0x800062    /* 32-bit debug register */

/* Post code output */
.equ POST_CODE,         0x80000C

_start:
    /* Initialize stack pointer */
    move.l  #0x00010000, %sp

    /* POST 1: Starting I2C RTC test */
    move.b  #1, POST_CODE

    /* Read date/month/year from DS1307 RTC via I2C */
    /* Sequence: write reg 0x04 (date), read it, write 0x05 (month), read it, */
    /*           write 0x06 (year), read it. Keep enable high throughout. */

wait_idle:
    /* Wait for I2C to be idle before starting */
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    bne.s   wait_idle

    /* POST 2: I2C idle, starting sequence */
    move.b  #2, POST_CODE

    /* Cmd1: write register address 0x04 (date) */
    move.b  #0x04, I2C_DATA
    move.b  #I2C_ENA_BIT, I2C_CTRL       /* ena=1, rw=0 (write) */
c1_rise:
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    beq.s   c1_rise                      /* wait busy rise */
    btst    #1, %d7
    bne     fail

    /* POST 3: Cmd1 latched, Cmd2 (read date) */
    move.b  #3, POST_CODE

    /* Cmd2: read date */
    move.b  #0x03, I2C_CTRL                     /* ena=1, rw=1 (0x01|0x02) */
c2_clear:
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    bne.s   c2_clear                     /* wait busy clear */
    btst    #1, %d7
    bne     fail
c2_rise:
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    beq.s   c2_rise                      /* wait busy rise */
    btst    #1, %d7
    bne     fail

    /* POST 4: Date read, Cmd3 (write month) */
    move.b  #4, POST_CODE

    /* Cmd3: write register address 0x05 (month) */
    move.b  #0x05, I2C_DATA
    move.b  #I2C_ENA_BIT, I2C_CTRL       /* ena=1, rw=0 (write) */
c3_clear:
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    bne.s   c3_clear                     /* wait busy clear */
    btst    #1, %d7
    bne     fail
    /* Capture date while programming next command */
    move.b  I2C_DATA, %d1                /* d1 = date (BCD) */
c3_rise:
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    beq.s   c3_rise                      /* wait busy rise */
    btst    #1, %d7
    bne     fail

    /* Cmd4: read month */
    move.b  #0x03, I2C_CTRL                     /* ena=1, rw=1 (0x01|0x02) */
c4_clear:
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    bne.s   c4_clear                     /* wait busy clear */
    btst    #1, %d7
    bne     fail
c4_rise:
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    beq.s   c4_rise                      /* wait busy rise */
    btst    #1, %d7
    bne     fail

    /* POST 5: Month latched, Cmd5 (write year) */
    move.b  #5, POST_CODE

    /* Cmd5: write register address 0x06 (year) */
    move.b  #0x06, I2C_DATA
    move.b  #I2C_ENA_BIT, I2C_CTRL       /* ena=1, rw=0 (write) */
c5_clear:
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    bne.s   c5_clear                     /* wait busy clear */
    /* Capture month while programming next command */
    move.b  I2C_DATA, %d2                /* d2 = month (BCD) */
    btst    #1, %d7
    bne     fail
c5_rise:
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    beq.s   c5_rise                      /* wait busy rise */
    btst    #1, %d7
    bne     fail

    /* Cmd6: read year */
    move.b  #0x03, I2C_CTRL                     /* ena=1, rw=1 (0x01|0x02) */
c6_clear:
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    bne.s   c6_clear                     /* wait busy clear */
    btst    #1, %d7
    bne     fail
c6_rise:
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    beq.s   c6_rise                      /* wait busy rise */
    btst    #1, %d7
    bne     fail

    /* Final clear: wait for year read to complete */
c6_final:
    move.b  I2C_STATUS, %d7
    btst    #0, %d7
    bne.s   c6_final                     /* poll busy until clear */
    btst    #1, %d7
    bne     fail
    /* Capture year */
    move.b  I2C_DATA, %d3                /* d3 = year (BCD) */

    /* Drop enable to complete transaction */
    move.b  #0x00, I2C_CTRL

    /* POST 6: All data read, packing into 32-bit value */
    move.b  #6, POST_CODE

    /* Pack date into 32-bit value: 0xDDMM20YY format (DDMMYYYY in BCD) */
    /* d1=date, d2=month, d3=year */
    moveq   #0, %d4
    move.b  %d1, %d4                     /* d4.L = date */
    lsl.l   #8, %d4                      /* d4 = date << 8 (0x0000DD00) */
    or.b    %d2, %d4                     /* d4 |= month in low byte (0x0000DDMM) */
    lsl.l   #8, %d4                      /* d4 = (date,month) << 8 (0x00DDMM00) */
    or.b    #0x20, %d4                   /* d4 |= 0x20 (0x00DDMM20) */
    lsl.l   #8, %d4                      /* d4 = (date,month,20) << 8 (0xDDMM2000) */
    or.b    %d3, %d4                     /* d4 |= year (0xDDMM20YY) */

    /* POST 7: Date packed, writing to debug register */
    move.b  #7, POST_CODE

    /* Write packed date to debug register as 32-bit value */
    move.l  %d4, DEBUG_REG

    /* POST 8: Success! */
    move.b  #8, POST_CODE

    /* Test complete - loop forever */
    bra     infinite_loop

fail:
    /* POST 15: Error occurred */
    move.b  #15, POST_CODE
    /* Fall through to infinite loop */

infinite_loop:
    nop
    bra     infinite_loop

/* Reset vectors at beginning of ROM */
    .section .vectors, "a"
    .long   0x00010000      /* Initial SP */
    .long   _start          /* Initial PC */
