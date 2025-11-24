/*
 * Copyright (C) 2025 Chris January
 *
 * GPL-3
 *
 * Test program for UART model - sends a message from one UART to another
 */

#include "uart.h"
#include <stdio.h>
#include <string.h>

int main() {
    // Create two UART instances
    UART_t* uart1 = UART_Create();
    UART_t* uart2 = UART_Create();

    // Reset both UARTs
    UART_Reset(uart1);
    UART_Reset(uart2);

    // Set baud rate (default is 1301 for 115200 @ 22MHz)
    UART_SetSpeed(uart1, 100);  // Use faster speed for simulation
    UART_SetSpeed(uart2, 100);

    // Test message
    const char* message = "Hello, UART!";
    int msg_len = strlen(message);

    printf("UART Test: Sending message '%s' from UART1 to UART2\n", message);
    printf("Message length: %d bytes\n\n", msg_len);

    // Send message from UART1
    printf("Transmitting...\n");
    for (int i = 0; i < msg_len; i++) {
        // Wait for UART1 to be ready
        while (!UART_GetReady(uart1)) {
            UART_Tick(uart1);
            UART_Tick(uart2);
            // Connect UART1 TX to UART2 RX
            UART_SetRx(uart2, UART_GetTx(uart1));
        }

        // Write byte to UART1
        UART_SetDataIn(uart1, message[i]);
        UART_SetWrite(uart1, 1);
        UART_Tick(uart1);
        UART_Tick(uart2);
        UART_SetRx(uart2, UART_GetTx(uart1));
        UART_SetWrite(uart1, 0);
        UART_Tick(uart1);
        UART_Tick(uart2);
        UART_SetRx(uart2, UART_GetTx(uart1));

        printf("  Sent: '%c' (0x%02X)\n", message[i], (unsigned char)message[i]);
    }

    // Run simulation for ALL transmission to complete
    // Each byte takes approximately: 10 bits * speed cycles = 10 * 100 = 1000 cycles
    printf("\nWaiting for all data to transmit and be received...\n");
    int max_cycles = msg_len * 1200 + 5000;  // Generous margin
    for (int cycle = 0; cycle < max_cycles; cycle++) {
        // Tick both UARTs
        UART_Tick(uart1);
        UART_Tick(uart2);
        UART_SetRx(uart2, UART_GetTx(uart1));
    }

    printf("Transmission phase complete. UART2 data_ready=%d\n", UART_GetDataReady(uart2));

    // Receive message from UART2
    printf("\nReceiving...\n");
    char received[256];

    for (int i = 0; i < msg_len; i++) {
        // Wait for data to be ready
        while (!UART_GetDataReady(uart2)) {
            UART_Tick(uart1);
            UART_Tick(uart2);
            UART_SetRx(uart2, UART_GetTx(uart1));
        }

        // Read byte from UART2
        UART_SetRead(uart2, 1);
        UART_Tick(uart1);
        UART_Tick(uart2);
        UART_SetRx(uart2, UART_GetTx(uart1));
        uint8_t byte = UART_GetDataOut(uart2);
        UART_SetRead(uart2, 0);
        UART_Tick(uart1);
        UART_Tick(uart2);
        UART_SetRx(uart2, UART_GetTx(uart1));

        received[i] = byte;
        printf("  Received: '%c' (0x%02X)\n", byte, byte);
    }

    received[msg_len] = '\0';

    // Check results
    printf("\n--- Results ---\n");
    printf("Sent:     '%s'\n", message);
    printf("Received: '%s'\n", received);

    if (strcmp(message, received) == 0) {
        printf("\n✓ Test PASSED: All bytes transmitted and received correctly!\n");
    } else {
        printf("\n✗ Test FAILED: Mismatch in transmission\n");
    }

    // Clean up
    UART_Destroy(uart1);
    UART_Destroy(uart2);

    return (strcmp(message, received) == 0) ? 0 : 1;
}
