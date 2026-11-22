#pragma once
#include <stdint.h>
struct WireStub{
 bool begin(uint8_t,int,int,uint32_t){return true;}
 void onReceive(void(*)(int)){}
 void onRequest(void(*)()){}
 int available(){return 0;}
 int read(){return -1;}
 size_t write(uint8_t){return 1;}
 size_t slaveWrite(const uint8_t*,size_t n){return n;}
 void end(){}
};
extern WireStub Wire;
