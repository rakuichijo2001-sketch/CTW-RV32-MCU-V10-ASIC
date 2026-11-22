// SPDX-License-Identifier: Apache-2.0
// V10 peripheral edges: PWM 0/50%, I2C address NACK then repeated START.
// Arduino ESP32 slave must preload 0xC3 on GPIO13/14 as in V9.
#include <stdint.h>
#include "ctw_clock_config.h"
#define REG(a) (*(volatile uint32_t*)(uintptr_t)(a))
#define LED REG(0x08000004u)
#define UART_D REG(0x0800000cu)
#define UART_S REG(0x08000010u)
#define PINMUX REG(0x08000034u)
#define PWM_E REG(0x08000038u)
#define PWM_DIV REG(0x0800003cu)
#define PWM_0 REG(0x08000040u)
#define PWM_1 REG(0x08000044u)
#define I2C_C REG(0x08000050u)
#define I2C_A REG(0x08000054u)
#define I2C_T REG(0x08000058u)
#define I2C_R REG(0x0800005cu)
#define I2C_S REG(0x08000060u)
#define I2C_D REG(0x08000064u)
static void put(uint32_t b){ while(UART_S&1u){} UART_D=b; }
static uint8_t get(void){ while(!(UART_S&2u)){} return (uint8_t)UART_D; }
static uint32_t i2c(uint32_t op){
 I2C_C=op;
 for(volatile uint32_t i=0;i<500000u;i++){
  uint32_t status=I2C_S;
  if(status&2u)return status;
 }
 return 8u;
}
static void die(uint8_t why){ LED=0xe0u|why;put('E');put(why);for(;;){} }
int main(void){
 LED=0x90;
 PINMUX=0;
 PWM_E=0;
 PWM_DIV=399; // ~488 Hz at 50 MHz; 0% and 50% easy for ESP32 pulseIn
 PWM_0=0; PWM_1=128;
 PWM_E=1; PINMUX=6;
 LED=0x91;
 put('Z');
 if(get()!='I') die(1);
 PINMUX=7;
 I2C_D=CTW_I2C_DIV(100000u); // FPGA 249; ASIC 10MHz would use 49
 I2C_A=0x43; I2C_T=0x5a;
 uint32_t st=i2c(1u);
 if((st&0x0eu)!=0x06u) die(2); // done=1,nack=1,timeout=0
 put('N');
 I2C_A=0x42; I2C_T=0xa5;
 st=i2c(5u); // operation=2 (write-read with repeated START), START=1
 if((st&0x0eu)!=2u) die(3);
 if((uint8_t)I2C_R!=0xc3u) die(4);
 put('R');put((uint8_t)I2C_R);
 PINMUX=0;PWM_E=0;
 LED=0x9f;put('P');
 for(;;){}
}
