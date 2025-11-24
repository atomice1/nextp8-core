/*
 * Copyright (C) 2015 Theodoulos Liontakis
 * Copyright (C) 2025 Chris January
 *
 * GPL-3
 *
 * C++ model of UART from uart.vhd
 */

#include "uart.h"
#include <cstring>
#include <cstdio>

namespace {
    const int RBLEN = 1024;  // Receive buffer length
    const int TBLEN = 1024;  // Transmit buffer length
}

class UART {
public:
    UART() {
        reset();
    }

    void reset() {
        Tx = 1;
        data_ready = 0;
        ready = 1;
        speed = 1301;  // Default @ 22MHz for 115200 baud

        rcounter = 1;
        tcounter = 1;
        rstate = 0;
        tstate = 0;
        rptr1 = 0;
        rptr2 = 0;
        tptr1 = 0;
        tptr2 = 0;
        dr = false;
        rd = true;
        wa = false;
        ra = false;
        rx0 = 1;
        rx1 = 1;
        Rx_in = 1;

        inb = 0;
        outb = 0;
        data_out = 0;
        data_in = 0;
        r = 0;
        w = 0;

        std::memset(rFIFO, 0, sizeof(rFIFO));
        std::memset(tFIFO, 0, sizeof(tFIFO));
    }

    void tick() {
        // Input sampling
        rx1 = Rx_in;
        rx0 = rx1;

        // Receive logic
        rcounter++;
        if (rcounter == speed || (rstate == 0 && rx1 == 0 && rx0 == 0 && Rx_in == 0)) {
            if (rstate == 0 && Rx_in == 0 && rx1 == 0 && rx0 == 0) {
                // Start bit detected
                rcounter = speed / 2;
                rstate = 1;
            } else if (rstate == 1) {
                rstate = 2;
                rcounter = 1;
            } else if (rstate >= 2 && rstate < 10) {
                // Receive data bits (bits 2-9 of inb, which map to bits 0-7 of the byte)
                int bit_pos = rstate - 2;  // Map rstate 2-9 to bit positions 0-7
                if (Rx_in) {
                    inb |= (1 << bit_pos);
                } else {
                    inb &= ~(1 << bit_pos);
                }
                rcounter = 1;
                rstate++;
            } else if (rstate == 10) {
                // Stop bit
                rcounter = 1;
                rstate = 0;

                // Store received byte in FIFO
                rFIFO[rptr2] = inb;
                if (rptr2 + 1 < RBLEN) {
                    if (rptr2 + 1 != rptr1) {
                        rptr2++;
                    }
                } else {
                    if (rptr1 != 0) {
                        rptr2 = 0;
                    }
                }
                data_ready = 1;
                dr = true;
            } else {
                rcounter = 1;
            }
        }

        // Transmit logic
        tcounter++;
        if (tcounter == speed) {
            if (tstate == 0 && (tptr1 != tptr2 || rd == false)) {
                // Start transmission
                tcounter = 1;
                Tx = 0;  // Start bit
                outb = tFIFO[tptr1];
                tstate = 2;
            } else if (tstate >= 2 && tstate < 10) {
                // Transmit data bits (bits 2-9 of outb, which map to bits 0-7 of the byte)
                int bit_pos = tstate - 2;  // Map tstate 2-9 to bit positions 0-7
                Tx = (outb >> bit_pos) & 1;
                tcounter = 1;
                tstate++;
            } else if (tstate == 10) {
                // Stop bit
                Tx = 1;
                tcounter = 1;
                tstate = 0;
                if (tptr1 < TBLEN - 1) {
                    tptr1++;
                } else {
                    tptr1 = 0;
                }
                ready = 1;
                rd = true;
            } else {
                tcounter = 1;
                Tx = 1;
            }
        }

        // Read logic
        if (r == 1 && ra == false) {
            if (dr) {
                data_out = rFIFO[rptr1];
                if (rptr1 + 1 < RBLEN) {
                    rptr1++;
                    if (rptr1 == rptr2) {
                        data_ready = 0;
                        dr = false;
                    }
                } else {
                    rptr1 = 0;
                    if (rptr2 == 0) {
                        data_ready = 0;
                        dr = false;
                    }
                }
            }
            ra = true;
        } else {
            if (r == 0) {
                ra = false;
            }
            if (dr == true) {
                data_out = rFIFO[rptr1];
            }
        }

        // Write logic
        if (w == 1 && rd == true && wa == false) {
            wa = true;
            tFIFO[tptr2] = data_in;
            if (tptr2 < TBLEN - 1) {
                if (tptr2 + 1 == tptr1) {
                    ready = 0;
                    rd = false;
                }
                tptr2++;
            } else {
                tptr2 = 0;
                if (tptr1 == 0) {
                    ready = 0;
                    rd = false;
                }
            }
        } else {
            if (w == 0) {
                wa = false;
            }
        }
    }

    // Outputs
    int Tx;
    int data_ready;
    int ready;
    uint8_t data_out;

    // Inputs
    int Rx_in;
    uint8_t data_in;
    int r, w;
    uint16_t speed;

private:
    uint8_t rFIFO[RBLEN];
    uint8_t tFIFO[TBLEN];
    uint8_t inb, outb;
    uint16_t rcounter, tcounter;
    bool dr, rd, wa, ra;
    int rptr1, rptr2, tptr1, tptr2;
    int rstate, tstate;
    int rx0, rx1;
};

extern "C" {
    UART_t* UART_Create(void) {
        return reinterpret_cast<UART_t*>(new UART());
    }

    void UART_Destroy(UART_t* uart) {
        delete reinterpret_cast<UART*>(uart);
    }

    void UART_Reset(UART_t* uart) {
        reinterpret_cast<UART*>(uart)->reset();
    }

    void UART_SetRx(UART_t* uart, int rx) {
        reinterpret_cast<UART*>(uart)->Rx_in = rx;
    }

    int UART_GetTx(UART_t* uart) {
        return reinterpret_cast<UART*>(uart)->Tx;
    }

    void UART_SetDataIn(UART_t* uart, uint8_t data) {
        reinterpret_cast<UART*>(uart)->data_in = data;
    }

    uint8_t UART_GetDataOut(UART_t* uart) {
        return reinterpret_cast<UART*>(uart)->data_out;
    }

    void UART_SetRead(UART_t* uart, int r) {
        reinterpret_cast<UART*>(uart)->r = r;
    }

    void UART_SetWrite(UART_t* uart, int w) {
        reinterpret_cast<UART*>(uart)->w = w;
    }

    int UART_GetDataReady(UART_t* uart) {
        return reinterpret_cast<UART*>(uart)->data_ready;
    }

    int UART_GetReady(UART_t* uart) {
        return reinterpret_cast<UART*>(uart)->ready;
    }

    void UART_SetSpeed(UART_t* uart, uint16_t speed) {
        reinterpret_cast<UART*>(uart)->speed = speed;
    }

    void UART_Tick(UART_t* uart) {
        reinterpret_cast<UART*>(uart)->tick();
    }

    void UART_SetControl(UART_t* uart, uint8_t ctrl) {
        reinterpret_cast<UART*>(uart)->w = ctrl & 1;
        reinterpret_cast<UART*>(uart)->r = (ctrl & 2) >> 1;
    }

    uint8_t UART_GetControl(UART_t* uart) {
        uint8_t ctrl = 0;
        if (reinterpret_cast<UART*>(uart)->data_ready) {
            ctrl |= 1;  // data ready
        }
        if (reinterpret_cast<UART*>(uart)->ready) {
            ctrl |= 2;  // ready
        }
        return ctrl;
    }

    uint16_t UART_GetSpeed(UART_t *uart) {
        return reinterpret_cast<UART*>(uart)->speed;
    }
}
