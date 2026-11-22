// SPDX-License-Identifier: Apache-2.0
// Directed pre-PD firmware. CPU: RV32EC (no M/F/D/A), bare metal.
// Uses only 4 KiB Flash and first 4 KiB of each modeled PSRAM bank.
#include <stdint.h>
#define REG(addr) (*(volatile uint32_t*)(uintptr_t)(addr))
#define LED         REG(0x08000004u)
#define TIMER       REG(0x08000008u)
#define UART_DATA   REG(0x0800000cu)
#define UART_STAT   REG(0x08000010u)
#define ID          REG(0x08000014u)
#define BIDIR_DIR   REG(0x08000018u)
#define PINMUX      REG(0x08000034u)
#define WDT_CFG     REG(0x08000068u)
#define WDT_FEED    REG(0x0800006cu)
#define WDT_STATUS  REG(0x08000070u)
#define RAM_A       ((volatile uint32_t*)0x01000800u)
#define RAM_B       ((volatile uint32_t*)0x01800800u)

extern uint32_t v10_isa_check(void);
static volatile uint32_t initialized_word=0x7e25ac39u;
static volatile uint32_t zero_word;
static uint32_t seq=0, signature=0x31415926u;
static uint8_t fail_code=0;

static void tx(uint8_t c) {
    uint32_t timeout=2000000u;
    while ((UART_STAT & 1u) && --timeout) { }
    if (timeout) UART_DATA=c;
}
static void send_packet(uint8_t kind) {
    uint8_t f[12];
    f[0]=0xd7; f[1]=kind;
    for (unsigned i=0;i<4;i++) { f[2+i]=(uint8_t)(seq>>(8*i)); f[6+i]=(uint8_t)(signature>>(8*i)); }
    f[10]=(uint8_t)((WDT_STATUS>>8)&255u);
    uint8_t check=0;
    for (unsigned i=0;i<11;i++) check^=f[i];
    f[11]=check;
    for (unsigned i=0;i<12;i++) tx(f[i]);
}
static void fail(uint8_t id) {
    fail_code=id;
    LED=0xe0u|((uint32_t)id&31u);
    signature=(signature&0xffffff00u)|id;
    send_packet('E');
    WDT_CFG=(1000u<<16)|1u; // restart automatically if firmware wedges
    for (;;) { }
}
static uint32_t mix(uint32_t x) {
    x^=x<<13; x^=x>>17; x^=x<<5;
    return x;
}
static void exercise_ram(uint32_t round) {
    uint32_t seed=mix(signature ^ round ^ 0xa512bc34u);
    /* Exercise read-after-write, lane masks, distinct bank chip-selects. */
    for (uint32_t i=0;i<32;i++) {
        uint32_t a=mix(seed+i*0x00010101u);
        RAM_A[i]=a;
        RAM_B[i]=~a;
    }
    for (uint32_t i=0;i<32;i++) {
        uint32_t a=mix(seed+i*0x00010101u);
        if (RAM_A[i]!=a || RAM_B[i]!=~a) fail(2);
        signature=mix(signature ^ RAM_A[i] ^ (RAM_B[i] >> 3));
    }
    /* Cross a 1-KiB page edge, without touching the stack (first 1 KiB). */
    volatile uint32_t *edge_a=(volatile uint32_t*)0x010007fcu;
    volatile uint32_t *edge_b=(volatile uint32_t*)0x018007fcu;
    edge_a[0]=seed; edge_a[1]=~seed;
    edge_b[0]=seed^0x5a5a5a5au; edge_b[1]=~seed;
    if (edge_a[0]!=seed || edge_a[1]!=~seed ||
        edge_b[0]!=(seed^0x5a5a5a5au) || edge_b[1]!=~seed) fail(3);
    /* Byte and halfword byte-enable, sign extension and noninterference. */
    RAM_A[40]=0x11223344u;
    ((volatile uint8_t*)&RAM_A[40])[1]=0x80u;
    if (RAM_A[40]!=0x11228044u) fail(4);
    if (((volatile int8_t*)&RAM_A[40])[1]!=-128) fail(5);
    RAM_B[40]=0xaabbccddu;
    ((volatile uint16_t*)&RAM_B[40])[1]=0xfedcu;
    if (RAM_B[40]!=0xfedcccdd) fail(6);
}
static void step(void) {
    if ((seq & 63u)==0u) {
        uint32_t isa=v10_isa_check();
        if (isa) fail((uint8_t)(7u+(isa&15u)));
    }
    exercise_ram(seq);
    seq++;
    if ((seq & 15u)==0u) LED=0x40u | ((seq>>4)&0x0fu);
    WDT_FEED=0xa55a5aa5u;
}
int main(void) {
    PINMUX=0; BIDIR_DIR=0;
    LED=0x30;
    if (ID!=0x43545731u || initialized_word!=0x7e25ac39u || zero_word!=0u) fail(1);
    zero_word=0x55aaff00u; // Must be zeroed by startup on each reboot
    const uint32_t before=TIMER;
    for(volatile uint32_t k=0;k<32;k++) { }
    if(TIMER==before) fail(7);
    // 8-second watchdog for normal operation, fed after each verified step.
    WDT_CFG=(8000u<<16)|1u;
    LED=0x31;
    uint32_t last_idle_feed=TIMER;
    for (;;) {
        if (!(UART_STAT & 2u)) {
            // Feed during ordinary idle. A CPU hardware/software hang still
            // prevents feeding, allowing the independent pad-domain WDT to trip.
            uint32_t now=TIMER;
            if ((uint32_t)(now-last_idle_feed) >= 500000u) {
                WDT_FEED=0xa55a5aa5u;
                last_idle_feed=now;
            }
            continue;
        }
        last_idle_feed=TIMER;
        uint8_t cmd=(uint8_t)UART_DATA;
        if (cmd=='S') {
            for(uint32_t i=0;i<4;i++) step();
            send_packet('S');
        } else if (cmd=='H') {
            for(uint32_t i=0;i<16;i++) step();
            send_packet('H');
        } else if (cmd=='W') {
            LED=0x3e;
            // Deliberately withhold feed to prove autonomous watchdog recovery.
            WDT_CFG=(250u<<16)|1u;
            for (;;) { }
        } else if (cmd=='Q') {
            WDT_CFG=0;
            LED=0x3f;
            send_packet('Q');
        }
    }
}
