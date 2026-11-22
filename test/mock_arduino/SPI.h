#pragma once
#define MSBFIRST 1
#define SPI_MODE0 0
struct SPISettings { SPISettings(int,int,int){} };
struct SPIStub{
 void begin(int,int,int,int){}
 void end(){}
 void beginTransaction(const SPISettings&){}
 void endTransaction(){}
 unsigned char transfer(unsigned char){return 0;}
};
extern SPIStub SPI;
