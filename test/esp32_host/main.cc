#include "Arduino.h"
#include "SPI.h"
#include "Vctw_jp1_harness.h"
#include "../../esp32/ctw_mcu_cradle/ctw_mcu_cradle.ino"
#include <algorithm>
#include <cstdarg>
#include <fstream>
#include <iostream>
#include <iterator>
#include <stdexcept>
#include <vector>

static Vctw_jp1_harness top;
static uint64_t ticks=0; // 10 ns per tick for simulated clk at 50 MHz
static uint8_t latch=0;
static bool reset_open_drain=false, inject_flash_read_error=false;
MockSerial Serial;
MockSPI SPI;
MockUART Serial2;
static bool reset_with_gpio_high=false;
static bool break_uart=false;
static constexpr uint64_t UART_BIT_TICKS=868; // physical 115200 at 10 ns/tick

static void evaluate() {
    top.eval();
    Serial2.observe(ticks, break_uart ? true : bool(top.sensor_uart_out));
    if (top.rst_drive_low && top.sensor_data==7) reset_with_gpio_high=true;
    if ((top.host_oe & 0xc0) || (top.host_oe && !top.rst_drive_low))
        throw std::runtime_error("ESP drove bus outside of target reset");
    if (top.rst_drive_low && (top.mcu_oe != 0x00 || (top.bus_i & 0xc0) != 0xc0))
        throw std::runtime_error("MCU did not isolate bus / deselect PSRAMs immediately");
    if (top.host_oe & top.fpga_oe)
        throw std::runtime_error("Pad contention detected");
}
static void move_ticks(uint64_t count) {
    for (;count;--count) { ++ticks; top.clk ^= 1; evaluate(); }
}
void MockUART::begin(unsigned baud,int format,int rx_pin,int tx_pin) {
    if (baud!=115200 || format!=SERIAL_8N1 || rx_pin!=16 || tx_pin!=17)
        throw std::runtime_error("Unexpected UART config");
    enabled=true;
}
void MockUART::observe(uint64_t now,bool level) {
    if (!enabled) return;
    if (!receiving && last_tx && !level) {
        receiving=true;
        framed=true;
        next_bit=now+UART_BIT_TICKS/2u;
        bit_index=0;
        byte=0;
    }
    if (receiving && now>=next_bit) {
        next_bit+=UART_BIT_TICKS;
        if (bit_index==0) framed=!level;
        else if (bit_index<=8) byte|=uint8_t(level)<<(bit_index-1u);
        else {
            if (level && framed) rx.push_back(byte);
            receiving=false;
        }
        ++bit_index;
    }
    last_tx=level;
}
size_t MockUART::write(uint8_t value) {
    top.sensor_uart_in=0; evaluate(); move_ticks(UART_BIT_TICKS);
    for (unsigned bit=0;bit<8;++bit) {
        top.sensor_uart_in=(value>>bit)&1u; evaluate(); move_ticks(UART_BIT_TICKS);
    }
    top.sensor_uart_in=1; evaluate(); move_ticks(UART_BIT_TICKS);
    return 1;
}
static int sensor_bit(uint8_t pin) {
    return pin==32 ? 0 : pin==33 ? 1 : pin==22 ? 2 : -1;
}
static unsigned bus_bit(uint8_t p) {
    switch(p) {
        case 27:return 0; case 23:return 1; case 19:return 2; case 18:return 3;
        case 25:return 4; case 26:return 5;
        default:throw std::runtime_error("Sketch used unexpected GPIO");
    }
}
void pinMode(uint8_t pin,int mode) {
    // IRQ/sensor harness does not drive the bidirectional test pads.
    if (pin==13 || pin==14) {
        if (mode!=INPUT) throw std::runtime_error("Bidir drive not implemented in this harness");
        return;
    }
    if (sensor_bit(pin)>=0) {
        if (mode!=OUTPUT) throw std::runtime_error("sensor GPIO should be output");
        return;
    }
    if (pin==21) {
        if (mode!=INPUT && mode!=OUTPUT_OPEN_DRAIN) throw std::runtime_error("Reset not open-drain");
        reset_open_drain=mode==OUTPUT_OPEN_DRAIN;
        top.rst_drive_low=reset_open_drain;
        evaluate();
        return;
    }
    const unsigned b=1u<<bus_bit(pin);
    if (mode==OUTPUT) top.host_oe|=b; else top.host_oe&=~b;
    evaluate();
}
void digitalWrite(uint8_t pin,int value) {
    int index=sensor_bit(pin);
    if (index>=0) {
        unsigned mask=1u<<index;
        top.sensor_data=(top.sensor_data&~mask)|(value ? mask : 0);
        evaluate();
        return;
    }
    if (pin==21) {
        if (value || (reset_open_drain && !top.rst_drive_low))
            throw std::runtime_error("Unexpected reset level");
        return;
    }
    const unsigned b=1u<<bus_bit(pin);
    if (value) latch|=b; else latch&=~b;
    top.host_o=latch;
    evaluate();
}
int digitalRead(uint8_t pin) { evaluate(); return inject_flash_read_error ? 0 : ((top.bus_i>>bus_bit(pin))&1u); }
void delayMicroseconds(unsigned us) { move_ticks(uint64_t(us)*100); }
void delay(unsigned ms) { move_ticks(uint64_t(ms)*100000); }
uint32_t millis() { return ticks/100000; }

size_t MockSerial::readBytesUntil(char end,char *buf,size_t n) {
    size_t i=0;
    while(i<n && !input.empty()) {
        auto d=input.front();input.pop_front();
        if(d==uint8_t(end)) break;
        buf[i++]=char(d);
    }
    return i;
}
size_t MockSerial::readBytes(uint8_t *buf,size_t n) {
    size_t i=0;
    while(i<n && !input.empty()) { buf[i++]=input.front(); input.pop_front(); }
    return i;
}
void MockSerial::printf(const char *fmt,...) {
    char buf[256];
    va_list ap; va_start(ap,fmt); vsnprintf(buf,sizeof buf,fmt,ap); va_end(ap);
    output+=buf;
}
void MockSPI::begin(int c,int i,int o,int) {
    sck=c;miso=i;mosi=o;
    digitalWrite(sck,LOW);pinMode(sck,OUTPUT);pinMode(miso,INPUT);pinMode(mosi,OUTPUT);
}
void MockSPI::end() { pinMode(sck,INPUT);pinMode(miso,INPUT);pinMode(mosi,INPUT); }
void MockSPI::beginTransaction(SPISettings s) { half_ticks=50000000u/s.hz; }
uint8_t MockSPI::transfer(uint8_t v) {
    uint8_t r=0;
    for(int i=7;i>=0;--i) {
        digitalWrite(mosi,(v>>i)&1u);
        move_ticks(half_ticks); digitalWrite(sck,HIGH);
        move_ticks(half_ticks); r|=digitalRead(miso)<<i; digitalWrite(sck,LOW);
    }
    return r;
}
static void expect_led(uint8_t val) {
    for(unsigned i=0;i<450000 && top.led!=val;++i) move_ticks(2);
    if(top.led!=val) {
        std::cerr<<"LED "<<unsigned(top.led)<<" expected "<<unsigned(val)<<'\n';
        throw std::runtime_error("Firmware did not boot");
    }
}
static void send(const std::vector<uint8_t>& bin,uint32_t crc) {
    char h[48];
    snprintf(h,sizeof h,"CTW3 %zu %08X\n",bin.size(),unsigned(crc));
    const std::string line(h);
    Serial.input.insert(Serial.input.end(),line.begin(),line.end());
    Serial.input.insert(Serial.input.end(),bin.begin(),bin.end());
    Serial.output.clear();
    loop();
    std::cout<<Serial.output;
    if(top.host_oe) throw std::runtime_error("ESP never released GPIO");
}
static std::vector<uint8_t> binary(const char *path) {
    std::ifstream f(path,std::ios::binary);
    std::vector<uint8_t> v((std::istreambuf_iterator<char>(f)),{});
    if(v.empty()) throw std::runtime_error("Missing firmware");
    return v;
}
int main(int argc,char** argv) {
    if(argc!=5) return 2;
    try {
        auto a=binary(argv[1]), b=binary(argv[2]), sensor=binary(argv[3]), irq=binary(argv[4]);
        top.clk=0;top.rst_drive_low=0;top.key=3;top.host_o=0;top.host_oe=0;
        top.sensor_uart_in=1;top.sensor_data=0;
        evaluate();delay(1);setup();
        expect_led(0xe0);
        send(a,crc32(a.data(),a.size())^1);
        if(Serial.output.find("ERR CRC")==std::string::npos || top.rst_drive_low)
            throw std::runtime_error("CRC error was not rejected without holding reset");
        auto good=[&](const auto& image,uint8_t result){
            send(image,crc32(image.data(),image.size()));
            if(Serial.output.find(" RUN")==std::string::npos || top.rst_drive_low)
                throw std::runtime_error("ESP programmer failed or kept target in reset");
            expect_led(result);
        };
        good(a,0xa4);
        top.key=1;expect_led(0xa6); top.key=3;expect_led(0xa4);
        good(b,0x58); // begin with firmware A running
        top.key=2; evaluate(); // no clock move before checking async release
        if(top.mcu_oe!=0x00 || top.host_oe) throw std::runtime_error("KEY0 contention");
        delay(1); top.key=3; expect_led(0x58);
        inject_flash_read_error=true;
        send(a,crc32(a.data(),a.size()));
        if(Serial.output.find("ERR JEDEC")==std::string::npos || !top.rst_drive_low)
            throw std::runtime_error("Programmer must hold reset after Flash error");
        inject_flash_read_error=false;
        good(a,0xa4);
        std::cout<<"PASS sketch and RTL pads, runtime A/B upload, KEY0 reboot, CRC and JEDEC error/retry without contention\n";
        good(sensor,0xa0);
        auto command=[&](const std::string& cmd) {
            Serial.output.clear();
            Serial.input.insert(Serial.input.end(),cmd.begin(),cmd.end());
            loop();
            std::cout<<Serial.output;
        };
        command("SENSOR\n");
        if (Serial.output.find("SENSOR PASS 8") == std::string::npos ||
            !reset_with_gpio_high || top.led!=0xa8)
            throw std::runtime_error("GPIO/UART sensor roundtrip failed");
        break_uart=true;
        command("SENSOR\n");
        if (Serial.output.find("ERR SENSOR timeout") == std::string::npos ||
            Serial.output.find("SENSOR PASS") != std::string::npos)
            throw std::runtime_error("Disconnected MCU UART must fail the sensor test");
        std::cout<<"PASS GPIO and physical UART roundtrip for all 8 samples, then detect disconnected MCU TX\n";
        break_uart=false;
        send(irq,crc32(irq.data(),irq.size()));
        if(Serial.output.find(" RUN")==std::string::npos || top.rst_drive_low)
            throw std::runtime_error("IRQ firmware upload failed");
        command("IRQ\n");
        if(Serial.output.find("IRQ PASS ALL")==std::string::npos)
            throw std::runtime_error("IRQ integrated roundtrip failed");
        std::cout<<"PASS IRQ hardware+firmware+ESP32 host harness\n";
    } catch(const std::exception& e) {
        std::cerr<<e.what()<<'\n';return 1;
    }
    return 0;
}
