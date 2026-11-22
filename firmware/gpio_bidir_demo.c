// SPDX-License-Identifier: Apache-2.0
// CTW RV32 MCU V7 bidirectional GPIO exercise, UART commands via ESP32.
// Two addressable pins: BIT0 -> uio[6], BIT1 -> uio[7].
#include <stdint.h>
#define MMIO(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define GPIO_LED MMIO(0x08000004u)
#define UART_DATA MMIO(0x0800000cu)
#define UART_STATUS MMIO(0x08000010u)
#define BIDIR_DIR MMIO(0x08000018u)
#define BIDIR_OUT MMIO(0x0800001cu)
#define BIDIR_IN MMIO(0x08000020u)

static void put(uint32_t c) {
    while (UART_STATUS & 1u) { }
    UART_DATA = c;
}
static uint8_t get(void) {
    while (!(UART_STATUS & 2u)) { }
    return (uint8_t)UART_DATA;
}
static void reply(uint8_t cmd, uint8_t value) {
    put(0xb5u);
    put(cmd);
    put(value);
    put(0xb5u ^ cmd ^ value);
}
int main(void) {
    BIDIR_DIR = 0u; // Important: do not drive pins before host releases them.
    BIDIR_OUT = 0u;
    GPIO_LED = 0xb0u;
    for (;;) {
        uint8_t cmd = get();
        if (cmd == 'Z') { // Release both to input/high-Z first.
            BIDIR_DIR = 0;
            GPIO_LED = 0xb0u;
            reply(cmd, (uint8_t)BIDIR_DIR);
        } else if (cmd == 'I') {
            uint8_t ignored = get();
            (void)ignored;  // Host already presents the sample on the pins.
            BIDIR_DIR = 0;
            uint8_t seen = (uint8_t)(BIDIR_IN & 3u);
            GPIO_LED = 0xb0u | (uint32_t)(seen << 1);
            reply(cmd, seen);
        } else if (cmd == 'O') {
            uint8_t value = get() & 3u;
            BIDIR_OUT = value; // Set data before enabling output buffers.
            BIDIR_DIR = 3u;
            GPIO_LED = 0xb8u | (uint32_t)value;
            reply(cmd, (uint8_t)(BIDIR_OUT & 3u));
        }
    }
}
