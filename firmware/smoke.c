#include <stdint.h>

#define MMIO(addr) (*(volatile uint32_t *)(uintptr_t)(addr))
#define GPIO_IN MMIO(0x08000000)
#define GPIO_OUT MMIO(0x08000004)
#define TIMER MMIO(0x08000008)
#define UART_DATA MMIO(0x0800000c)
#define UART_STATUS MMIO(0x08000010)
#define ID MMIO(0x08000014)
#define RAM_A ((volatile uint32_t *)0x01000100)
#define RAM_B ((volatile uint32_t *)0x01800100)
#ifndef PASS_LED
#define PASS_LED 0xa4u
#endif

static volatile uint32_t init_data = 0x12345678u;
static volatile uint32_t zero_data;

__attribute__((noinline)) static uint32_t stack_test(uint32_t a, uint32_t b)
{
    volatile uint32_t words[4];
    words[0] = a;
    words[3] = b;
    return words[0] ^ words[3];
}

static void uart_put(uint32_t x)
{
    while (UART_STATUS & 1u) {}
    UART_DATA = x;
}

__attribute__((noreturn)) static void fail(uint32_t id)
{
    GPIO_OUT = 0xe0u | (id << 1);
    uart_put('E');
    uart_put('0' + id);
    for (;;) {}
}

int main(void)
{
    GPIO_OUT = 0x12;
    if (init_data != 0x12345678u || zero_data != 0 || ID != 0x43545731u)
        fail(1);
    zero_data = 0xabcdu; /* Warm reset must zero this again. */
    if (stack_test(init_data, 0xdeadbeefu) != 0xcc99e897u)
        fail(2);
    for (uint32_t i = 0; i < 8; ++i) {
        RAM_A[i] = 0x11223300u | i;
        RAM_B[i] = 0xaa55cc00u | (31u - i);
    }
    for (uint32_t i = 0; i < 8; ++i)
        if (RAM_A[i] != (0x11223300u | i) || RAM_B[i] != (0xaa55cc00u | (31u - i)))
            fail(3);
    ((volatile uint8_t *)RAM_A)[1] = 0x56;
    ((volatile uint16_t *)RAM_B)[1] = 0x789a;
    if (RAM_A[0] != 0x11225600u || RAM_B[0] != 0x789acc1fu)
        fail(4);
#ifdef CTW_TIMING_TEST
    /* 2 KiB is also a 1 KiB page boundary. Keep away from the stack,
       which occupies the first 1 KiB of RAM A in this linker script. */
    volatile uint32_t *edge_a=(volatile uint32_t *)0x010007f0u;
    volatile uint32_t *edge_b=(volatile uint32_t *)0x018007f0u;
    for (uint32_t i=0;i<12;++i) {
        edge_a[i]=0x5a123400u ^ ((i<<24) | (i<<9) | i);
        edge_b[i]=0xa5ba0000u ^ ((i<<20) | (i<<11) | (i<<3));
    }
    for (uint32_t i=0;i<12;++i)
        if (edge_a[i]!=(0x5a123400u ^ ((i<<24) | (i<<9) | i)) ||
            edge_b[i]!=(0xa5ba0000u ^ ((i<<20) | (i<<11) | (i<<3))))
            fail(6);
    volatile uint32_t *end_a=(volatile uint32_t *)0x017ffffcu;
    volatile uint32_t *end_b=(volatile uint32_t *)0x01fffffcu;
    *end_a=0x69edc451u;
    *end_b=0x964e35a2u;
    if (*end_a!=0x69edc451u || *end_b!=0x964e35a2u) fail(7);
#endif
    uint32_t t0 = TIMER;
    if ((uint32_t)(TIMER - t0) == 0)
        fail(5);
    GPIO_OUT = PASS_LED;
    uart_put('O'); uart_put('K'); uart_put('\n');

    for (;;) {
        if (UART_STATUS & 2u) {
            uint32_t c = UART_DATA;
            uart_put(c);
        }
        GPIO_OUT = (GPIO_IN & 1u) ? (PASS_LED | 2u) : PASS_LED;
    }
}
