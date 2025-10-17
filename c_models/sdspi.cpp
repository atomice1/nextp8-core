/*
 * Copyright (C) 2025 Chris January
 *
 * GPL-3
 */

#include "sdspi.h"
#include "sdspisim.h"

extern "C" uint16_t *pc;

namespace {
    const int CPI = 3;
    uint16_t *prev_pc = 0;

    class SDSPI {
    public:
        SDSPI() {
            sim0.load("sdcard.img");
        }
        void operator()() {
            int rcounter_ = rcounter, ready_ = ready, SCLK_ = SCLK, ww_ = ww, state_ = state, MOSI_ = MOSI, MISO_ = MISO;
            uint8_t data_out_ = data_out;
			rcounter_ = rcounter+1; 
			MOSI_ = (data_in >> state) & 1;
			if (rcounter>=divider || (ww==0 && w==1 && ready==0)) {
				rcounter_ = 0;
				if (state==7 && SCLK==0 && ww==0 && w==1) {
					ready_ = 1; 
					SCLK_ = 1;
					ww_ = w;
				} else if (state==7 && SCLK==1) {
					state_ = 6;
                    data_out_ = (data_out & ~(1 << state)) | (MISO << state);
					SCLK_ = 0;
				} else if (state==6 && SCLK==0) {
					SCLK_ = 1;
				} else if (state==6 && SCLK==1) {
					state_ = 5;
					data_out_ = (data_out & ~(1 << state)) | (MISO << state);
					SCLK_ = 0;
				} else if (state==5 && SCLK==0) {
					SCLK_ = 1;
				} else if (state==5 && SCLK==1) {
					state_ = 4;
					data_out_ = (data_out & ~(1 << state)) | (MISO << state);
					SCLK_ = 0;
				} else if (state==4 && SCLK==0) {
					SCLK_ = 1;
				} else if (state==4 && SCLK==1) {
					state_ = 3;
					data_out_ = (data_out & ~(1 << state)) | (MISO << state);
					SCLK_ = 0;
				} else if (state==3 && SCLK==0) {
					SCLK_ = 1;
				} else if (state==3 && SCLK==1) {
					state_ = 2;
					data_out_ = (data_out & ~(1 << state)) | (MISO << state);
					SCLK_ = 0;
				} else if (state==2 && SCLK==0) {
					SCLK_ = 1;
				} else if (state==2 && SCLK==1) {
					state_ = 1;
					data_out_ = (data_out & ~(1 << state)) | (MISO << state);
					SCLK_ = 0;
				} else if (state==1 && SCLK==0) {
					SCLK_ = 1;
				} else if (state==1 && SCLK==1) {
					state_ = 0;
					data_out_ = (data_out & ~(1 << state)) | (MISO << state);
					SCLK_ = 0;
				} else if (state==0 && SCLK==0) {
					SCLK_ = 1;
				} else if (state==0 && SCLK==1) {
					data_out_ = (data_out & ~(1 << state)) | (MISO << state);
					SCLK_ = 0;
					state_ = 7;
					ready_ = 0;
					ww_ = w;
                } else {
					SCLK_ = 0;
					ready_ = 0;
					ww_ = w;
                }
            }
            if ((chip_select & 3) == 0)
                fprintf(stderr, "ERROR: both SPIs selected!\n");
            int MISO0 = sim0(chip_select & 1, SCLK, MOSI);
            int MISO1 = sim1((chip_select & 2) ? 1 : 0, SCLK, MOSI);
            if ((chip_select & 1) == 0)
                MISO_ = MISO0;
            else
                MISO_ = MISO1;
            MOSI = MOSI_;
            rcounter = rcounter_;
            ready = ready_;
            SCLK = SCLK_;
            ww = ww_;
            state = state_;
            MISO = MISO_;
            data_out = data_out_;
            /*if (rcounter == 0)
                printf("SCLKo=%d MOSI=%d MISO=%d w=%d ready=%d data_in=%d data_out=%d divider=%d rcounter=%d state=%d ww=%d\n",
                        SCLK,    MOSI,    MISO,  w,   ready,   data_in,   data_out,   divider,   rcounter,   state,   ww);
                        */
        }
        unsigned chip_select = 0xff;
        int w = 0;
        int ready = 0;
        uint8_t data_out = 0;
        int divider = 2;
        uint8_t data_in = 0;
    private:
        SDSPISIM sim0{true};
        SDSPISIM sim1{true};
        int SCLK = 0;
        int MOSI = 1;
        int MISO = 0;
        int rcounter = 0;
        int state = 7;
        int ww = 0;
    };

    SDSPI spi;

    void Advance() {
        if (prev_pc != 0) {
            uint32_t pc_inc = (prev_pc < pc) ? (pc - prev_pc) : (prev_pc - pc);
            if (pc_inc == 0)
                pc_inc = 1;
            if (pc_inc > 100)
                pc_inc = 100;
            for (uint32_t i=0;i<pc_inc * CPI;++i)
                spi();
        }
        prev_pc = pc;
    }
}

extern "C" void SDSPI_SetChipSelect(unsigned cs)
{
    Advance();
    //printf("SDSPI_SetChipSelect(%d)\n", cs);
    spi.chip_select = cs;
}

extern "C" void SDSPI_SetDataIn(uint8_t data)
{
    Advance();
    spi.data_in = data;
}

extern "C" void SDSPI_SetDivider(uint8_t div)
{
    Advance();
    spi.divider = div;
}

extern "C" void SDSPI_SetWriteEnable(int enable)
{
    Advance();
    //printf("SDSPI_SetWriteEnable(%d)\n", enable);
    spi.w = enable;
}

extern "C" uint8_t SDSPI_GetDataOut(void)
{
    Advance();
    return spi.data_out;
}

extern "C" int SDSPI_GetReady(void)
{
    Advance();
    return spi.ready;
}
