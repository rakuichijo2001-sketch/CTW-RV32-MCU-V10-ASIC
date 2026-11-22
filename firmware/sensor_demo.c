// SPDX-License-Identifier: Apache-2.0
// ESP32 presents a synthetic 3-bit sensor sample on ui_in[6:4].
// A byte 'S' on UART RX asks the CPU to capture, scale and return it.
#include <stdint.h>

#define MMIO(addr) (*(volatile uint32_t *)(uintptr_t)(addr))
#define GPIO_IN MMIO(0x08000000u)
#define GPIO_OUT MMIO(0x08000004u)
#define UART_DATA MMIO(0x0800000cu)
#define UART_STATUS MMIO(0x08000010u)

static void uart_put(uint32_t value)
{
    while (UART_STATUS & 1u) {}
    UART_DATA = value;
}

int main(void)
{
    GPIO_OUT = 0xa0u;  // ready, starting with no processed sample
    for (;;) {
        if (!(UART_STATUS & 2u)) continue;
        if (UART_DATA != 'S') continue;

        const uint32_t raw = (GPIO_IN >> 4) & 7u;
        const uint32_t scaled = (raw << 1) + raw + 7u;
        GPIO_OUT = 0xa0u | (raw << 1);
        uart_put(0xa5u);
        uart_put(raw);
        uart_put(scaled);
        uart_put(0xa5u ^ raw ^ scaled);
    }
}
