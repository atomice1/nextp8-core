/*
 * Copyright (C) 2015 Theodoulos Liontakis
 * Copyright (C) 2025 Chris January
 *
 * GPL-3
 */

#ifndef UART_H
#define UART_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct UART_t UART_t;

extern UART_t* UART_Create(void);
extern void UART_Destroy(UART_t* uart);
extern void UART_Reset(UART_t* uart);
extern void UART_SetRx(UART_t* uart, int rx);
extern int UART_GetTx(UART_t* uart);
extern void UART_SetDataIn(UART_t* uart, uint8_t data);
extern uint8_t UART_GetDataOut(UART_t* uart);
extern void UART_SetRead(UART_t* uart, int r);
extern void UART_SetWrite(UART_t* uart, int w);
extern int UART_GetDataReady(UART_t* uart);
extern int UART_GetReady(UART_t* uart);
extern void UART_SetSpeed(UART_t* uart, uint16_t speed);
extern void UART_Tick(UART_t* uart);
extern uint8_t UART_GetControl(UART_t* uart);
extern void UART_SetControl(UART_t* uart, uint8_t ctrl);
extern uint16_t UART_GetSpeed(UART_t *uart);
extern int UART_GetReadAcknowledge(UART_t *uart);
extern int UART_GetWriteAcknowledge(UART_t *uart);

#ifdef __cplusplus
}
#endif

#endif
