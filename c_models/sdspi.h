/*
 * Copyright (C) 2025 Chris January
 */

#ifndef SDSPI_H
#define SDSPI_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

extern void SDSPI_SetChipSelect(unsigned cs);
extern void SDSPI_SetDataIn(uint8_t data);
extern void SDSPI_SetDivider(uint8_t divider);
extern void SDSPI_SetWriteEnable(int enable);
extern uint8_t SDSPI_GetDataOut(void);
extern int SDSPI_GetReady(void);

#ifdef __cplusplus
}
#endif

#endif
