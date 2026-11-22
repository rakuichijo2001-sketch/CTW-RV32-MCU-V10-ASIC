// SPDX-License-Identifier: Apache-2.0
// Use the actual target clock: DE10=50MHz; target ASIC candidate=20MHz (STA pending).
#ifndef CTW_CLK_HZ
#define CTW_CLK_HZ 50000000UL
#endif
#define CTW_I2C_DIV(hz) ((CTW_CLK_HZ / (2UL * (hz))) - 1UL)
// Example: FPGA 50MHz -> 249 for 100kHz; ASIC 20MHz -> 99.
