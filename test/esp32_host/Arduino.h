#pragma once
#include <cstddef>
#include <cstdint>
#include <deque>
#include <string>
using std::size_t;
constexpr int INPUT=0, OUTPUT=1, OUTPUT_OPEN_DRAIN=2, LOW=0, HIGH=1;
void pinMode(uint8_t pin, int mode);
void digitalWrite(uint8_t pin, int value);
int digitalRead(uint8_t pin);
void delayMicroseconds(unsigned us);
void delay(unsigned ms);
uint32_t millis();
struct MockSerial {
    std::deque<uint8_t> input;
    std::string output;
    void setRxBufferSize(size_t) {}
    void begin(unsigned) {}
    void setTimeout(unsigned) {}
    int available() const { return static_cast<int>(input.size()); }
    size_t readBytesUntil(char end, char *buf, size_t n);
    size_t readBytes(uint8_t *buf, size_t n);
    void print(const char *s) { output+=s; }
    void println(const char *s) { output+=s; output+='\n'; }
    void printf(const char *fmt,...);
};
extern MockSerial Serial;

constexpr int SERIAL_8N1=1;
struct MockUART {
    bool enabled=false, last_tx=true, receiving=false, framed=true;
    uint64_t next_bit=0;
    unsigned bit_index=0;
    uint8_t byte=0;
    std::deque<uint8_t> rx;
    void begin(unsigned baud,int format,int rx_pin,int tx_pin);
    void observe(uint64_t ticks,bool level);
    size_t write(uint8_t value);
    int available() const { return static_cast<int>(rx.size()); }
    int read() {
        if (rx.empty()) return -1;
        const int received=rx.front();
        rx.pop_front();
        return received;
    }
};
extern MockUART Serial2;
