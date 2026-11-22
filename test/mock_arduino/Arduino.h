#pragma once
#include <stdint.h>
#include <stddef.h>
#define INPUT 0
#define OUTPUT 1
#define INPUT_PULLUP 2
#define OUTPUT_OPEN_DRAIN 3
#define HIGH 1
#define LOW 0
#define SERIAL_8N1 0
inline void pinMode(int,int){}
inline void digitalWrite(int,int){}
inline int digitalRead(int){return 1;}
inline unsigned long millis(){return 0;}
inline void delay(unsigned long){}
inline void delayMicroseconds(unsigned long){}
inline unsigned long pulseIn(int,int,unsigned long){return 1;}
struct SerialStub {
 void begin(unsigned long){}
 void begin(unsigned long,int,int,int){}
 void setTimeout(unsigned long){}
 void setRxBufferSize(size_t){}
 void println(const char*){}
 void print(const char*){}
 template<class... A> void printf(const char*,A...){}
 size_t write(uint8_t){return 1;}
 size_t write(const char*){return 1;}
 int read(){return -1;}
 int available(){return 0;}
 size_t readBytes(uint8_t*,size_t){return 0;}
 size_t readBytesUntil(char,char*,size_t){return 0;}
};
extern SerialStub Serial,Serial2;
