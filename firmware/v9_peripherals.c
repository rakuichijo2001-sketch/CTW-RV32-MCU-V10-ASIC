// SPDX-License-Identifier: Apache-2.0
// V9 silicon-style smoke: PWM 25% / 75%, I2C write and read from ESP32 slave.
#include <stdint.h>
#define REG(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define LED       REG(0x08000004u)
#define UART_DATA REG(0x0800000cu)
#define UART_STAT REG(0x08000010u)
#define PINMUX    REG(0x08000034u)
#define PWM_CTRL  REG(0x08000038u)
#define PWM_DIV   REG(0x0800003cu)
#define PWM_DUTY0 REG(0x08000040u)
#define PWM_DUTY1 REG(0x08000044u)
#define I2C_CTRL  REG(0x08000050u)
#define I2C_ADDR  REG(0x08000054u)
#define I2C_TX    REG(0x08000058u)
#define I2C_RX    REG(0x0800005cu)
#define I2C_STAT  REG(0x08000060u)
#define I2C_DIV   REG(0x08000064u)

static void put(uint8_t c) {
    while (UART_STAT & 1u) { }
    UART_DATA = c;
}
static uint8_t get(void) {
    while (!(UART_STAT & 2u)) { }
    return (uint8_t)UART_DATA;
}
static uint8_t do_i2c(uint32_t command) {
    I2C_CTRL=command;
    for (volatile uint32_t count=0;count<500000u;count++) {
        uint32_t state=I2C_STAT;
        if (state & 2u) return (uint8_t)state;
    }
    return 0x80u; // software-side watchdog
}
int main(void) {
    LED=0x90u;
    PINMUX=0u;      // disable alternate functions during configuration
    PWM_DIV=199u;   // FPGA 50MHz: 976.56Hz; ASIC 10MHz: 195.31Hz
    PWM_DUTY0=64u;  // 25% nominal
    PWM_DUTY1=192u; // 75% nominal
    PWM_CTRL=1u;
    PINMUX=6u;      // bit1 PWM0, bit2 PWM1; leave GPIO I2C pins available
    LED=0x94u;
    put('P');       // host may now measure PWM levels
    for (;;) {
        uint8_t cmd=get();
        if(cmd!='I') continue;
        PINMUX=7u;  // switch uio[6:7] from GPIO to open-drain I2C
        I2C_ADDR=0x42u;
        I2C_TX=0x5au;
        I2C_DIV=249u; // FPGA 50MHz -> 100kHz nominal
        uint8_t st=do_i2c(1u); // START + WRITE 1 byte
        if ((st & 0x0eu) != 2u) {
            LED=0xe1u; put('E'); put(st); PINMUX=6u; continue;
        }
        put('W');
        st=do_i2c(3u); // START + READ 1 byte, then NACK/STOP
        if ((st & 0x0eu) != 2u) {
            LED=0xe2u; put('E'); put(st); PINMUX=6u; continue;
        }
        uint8_t value=(uint8_t)I2C_RX;
        put('R'); put(value);
        PINMUX=6u;  // release both I2C lines and restore GPIO high-Z
        LED=(value==0xc3u)?0x99u:0xe3u;
        put('Z');
    }
}
