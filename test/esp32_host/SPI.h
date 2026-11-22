#pragma once
#include <cstdint>
constexpr int MSBFIRST=1, SPI_MODE0=0;
struct SPISettings {
    uint32_t hz;
    SPISettings(uint32_t h,int,int):hz(h) {}
};
struct MockSPI {
    uint8_t sck=0, miso=0, mosi=0;
    uint32_t half_ticks=0;
    void begin(int c,int i,int o,int s);
    void end();
    void beginTransaction(SPISettings s);
    void endTransaction() {}
    uint8_t transfer(uint8_t v);
};
extern MockSPI SPI;
