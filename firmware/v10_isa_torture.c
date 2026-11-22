// SPDX-License-Identifier: Apache-2.0
// Independent ISA qualification firmware: one test per host request.
// x3/x4 architectural compliance remains a separate strict-mode test.
#include <stdint.h>
#define REG(a) (*(volatile uint32_t *)(uintptr_t)(a))
#define LED REG(0x08000004u)
#define UART REG(0x0800000cu)
#define UART_STAT REG(0x08000010u)
#define WDT_CFG REG(0x08000068u)
#define WDT_FEED REG(0x0800006cu)
#define WDT_STATUS REG(0x08000070u)
#define TIMER REG(0x08000008u)
extern uint32_t v10_isa_check(void);
extern uint32_t v10_isa_torture(void);
#ifdef CTW_STRICT_GP_TP
extern uint32_t v10_isa_strict_gp_tp(void);
#endif
static uint32_t seq;
static void put(uint8_t c) {
    uint32_t timeout=2000000;
    while ((UART_STAT & 1u) && --timeout) {}
    if (timeout) UART=c;
}
static void answer(uint32_t number, uint32_t sign) {
    uint8_t f[12] = {0xd7,'S',0,0,0,0,0,0,0,0,0,0};
    for (uint32_t i=0;i<4;i++) {
        f[2+i]=(uint8_t)(number>>(8*i));
        f[6+i]=(uint8_t)(sign>>(8*i));
    }
    f[10]=(uint8_t)((WDT_STATUS>>8)&255u);
    for(uint32_t i=0;i<11;i++) f[11]^=f[i];
    for(uint32_t i=0;i<12;i++) put(f[i]);
}
int main(void) {
    LED=0x32;
    WDT_CFG=(8000u<<16)|1u;
    uint32_t last_feed=TIMER;
    for (;;) {
        if (!(UART_STAT&2u)) {
            uint32_t now=TIMER;
            if ((uint32_t)(now-last_feed)>500000u) {
                WDT_FEED=0xa55a5aa5u; last_feed=now;
            }
            continue;
        }
        uint8_t cmd=(uint8_t)UART;
        if (cmd!='S') continue;
        LED=0x35;
        uint32_t failed=v10_isa_check();
        if (!failed) failed=v10_isa_torture();
#ifdef CTW_STRICT_GP_TP
        if (!failed) failed=v10_isa_strict_gp_tp();
#endif
        if (failed) {
            LED=0xe0u|(failed&31u);
            answer(0xe0000000u|failed,0xbad00000u|failed);
            WDT_CFG=0;
            for(;;) {}
        }
        seq++;
        answer(seq,0xc7c7e00du^seq);
        LED=0x36;
        WDT_FEED=0xa55a5aa5u;
        last_feed=TIMER;
    }
}
