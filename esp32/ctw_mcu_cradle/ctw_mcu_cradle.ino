// SPDX-License-Identifier: Apache-2.0
// ESP32-WROOM-32/32E DevKit. PC -> USB UART -> ESP32 -> DE10 JP1.
// Controls only the Flash bus + target reset. The MCU initializes its memories.
#include <Arduino.h>
#include <SPI.h>
#include <Wire.h>
#include <driver/gpio.h> // ESP32: enable weak pull-ups without changing I2C pin function
#include <cstdio>
#include <cstring>

namespace {
constexpr uint8_t FLASH_CS=27, TARGET_RST_N=21, SCK=18;
constexpr uint8_t DQ[4]={23,19,25,26};
// ESP viewpoint: GPIO17 transmits to MCU RX; GPIO16 receives MCU TX.
constexpr uint8_t SENSOR_D[3]={32,33,22}, SENSOR_UART_RX=16, SENSOR_UART_TX=17;
constexpr uint8_t SENSOR_COMMAND='S', SENSOR_MARKER=0xa5;
// GPIO13/14 are used only for the V7 bidirectional GPIO test, never for Flash.
constexpr uint8_t BIDIR_PINS[2]={13,14};
constexpr uint8_t PWM_SENSE[2]={34,35};
volatile uint8_t v9LastI2cByte=0;
volatile bool v9I2cWriteSeen=false;
volatile uint32_t v9I2cRequestCount=0;
void onI2cReceive(int count) {
  while (Wire.available()) {
    v9LastI2cByte=uint8_t(Wire.read());
    v9I2cWriteSeen=true;
  }
}
void onI2cRequest() {
  ++v9I2cRequestCount;
  Wire.write(uint8_t(0xC3)); // Response to a normal Wire request.
}

constexpr size_t SECTOR=4096, PAGE=256;
constexpr uint32_t SPI_FAST_HZ=2000000, SPI_SLOW_HZ=250000;
constexpr uint32_t EXPECTED_JEDEC=0xef7018;
char jedecError[96];
uint8_t image[SECTOR];
bool spi_on=false;
bool targetHeldReset=false;

void assertTargetReset() {
  digitalWrite(TARGET_RST_N,LOW);
  pinMode(TARGET_RST_N,OUTPUT_OPEN_DRAIN);
  digitalWrite(TARGET_RST_N,LOW);
  targetHeldReset=true;
}
void releaseTargetReset() {
  pinMode(TARGET_RST_N,INPUT);
  targetHeldReset=false;
}

void stopSPI() {
  if (spi_on) {
    SPI.endTransaction();
    SPI.end();
    spi_on=false;
  }
}
void releaseBus() {
  stopSPI();
  for (auto pin:DQ) pinMode(pin,INPUT);
  pinMode(SCK,INPUT);
  pinMode(FLASH_CS,INPUT);
}
void ownCS() {
  digitalWrite(FLASH_CS,HIGH);
  pinMode(FLASH_CS,OUTPUT);
  digitalWrite(FLASH_CS,HIGH);
}
void takeManual() {
  stopSPI();
  ownCS();
  digitalWrite(SCK,LOW);
  pinMode(SCK,OUTPUT);
  digitalWrite(SCK,LOW);
  for (auto pin:DQ) pinMode(pin,INPUT);
}
void holdInactiveFlashPins() {
  for (unsigned i=2;i<4;++i) {
    digitalWrite(DQ[i],HIGH);
    pinMode(DQ[i],OUTPUT);
    digitalWrite(DQ[i],HIGH);
  }
}
void startSPI(uint32_t hz) {
  takeManual();
  holdInactiveFlashPins();
  SPI.begin(SCK,DQ[1],DQ[0],-1);
  SPI.beginTransaction(SPISettings(hz,MSBFIRST,SPI_MODE0));
  spi_on=true;
}
void select(uint8_t cs) {
  digitalWrite(cs,LOW); delayMicroseconds(1);
}
void deselect(uint8_t cs) {
  digitalWrite(cs,HIGH); delayMicroseconds(2);
}
void pulse() {
  delayMicroseconds(1);
  digitalWrite(SCK,HIGH); delayMicroseconds(2);
  digitalWrite(SCK,LOW); delayMicroseconds(1);
}
void driveQuad() { for (auto pin:DQ) pinMode(pin,OUTPUT); }
void quad(uint8_t n) {
  for (unsigned i=0;i<4;++i) digitalWrite(DQ[i],(n>>i)&1);
  pulse();
}
void spiCmd(uint8_t cs,uint8_t cmd) {
  select(cs); SPI.transfer(cmd); deselect(cs);
}
uint8_t flashReg(uint8_t cmd) {
  select(FLASH_CS); SPI.transfer(cmd);
  const uint8_t v=SPI.transfer(0);
  deselect(FLASH_CS); return v;
}
void flashAddress(size_t addr) {
  SPI.transfer((addr>>16)&255); SPI.transfer((addr>>8)&255); SPI.transfer(addr&255);
}
bool waitFlash() {
  const uint32_t start=millis();
  do {
    if ((flashReg(0x05)&1)==0) return true;
    delay(1);
  } while (static_cast<uint32_t>(millis()-start)<3000);
  return false;
}
bool wren() {
  spiCmd(FLASH_CS,0x06);
  return (flashReg(0x05)&2)!=0;
}
uint32_t readJedec() {
  select(FLASH_CS);
  SPI.transfer(0x9f);
  const uint8_t a=SPI.transfer(0);
  const uint8_t b=SPI.transfer(0);
  const uint8_t c=SPI.transfer(0);
  deselect(FLASH_CS);
  return (uint32_t(a)<<16) | (uint32_t(b)<<8) | uint32_t(c);
}
void leaveFlashXip() {
  takeManual();
  driveQuad();
  select(FLASH_CS);
  for (unsigned i=0;i<8;++i) quad(0x0f);
  deselect(FLASH_CS);
}
const char *programImage(size_t n) {
  // Wait for target pad release and cover Winbond power-up write inhibit.
  assertTargetReset();
  delay(10);
  leaveFlashXip();
  startSPI(SPI_FAST_HZ);
  const uint32_t fastId=readJedec();
  if (fastId!=EXPECTED_JEDEC) {
    // Re-establish a known protocol state, then try the slower clock.
    // Keep using it for program/readback if the ID is valid at that speed.
    leaveFlashXip();
    startSPI(SPI_SLOW_HZ);
    const uint32_t slowId=readJedec();
    if (slowId!=EXPECTED_JEDEC) {
      snprintf(jedecError,sizeof jedecError,
               "JEDEC got %02X %02X %02X @2MHz; %02X %02X %02X @250kHz; expected EF 70 18",
               unsigned(fastId>>16),unsigned((fastId>>8)&0xff),unsigned(fastId&0xff),
               unsigned(slowId>>16),unsigned((slowId>>8)&0xff),unsigned(slowId&0xff));
      return jedecError;
    }
  }
  if (!waitFlash() || !wren()) return "FLASH WREN before erase";
  select(FLASH_CS); SPI.transfer(0x20); flashAddress(0); deselect(FLASH_CS);
  if (!waitFlash()) return "FLASH erase timeout";
  for (size_t offset=0;offset<n;offset+=PAGE) {
    if (!wren()) return "FLASH WREN before page program";
    select(FLASH_CS); SPI.transfer(0x02); flashAddress(offset);
    for (size_t i=offset;i<n && i<offset+PAGE;++i) SPI.transfer(image[i]);
    deselect(FLASH_CS);
    if (!waitFlash()) return "FLASH page program timeout";
  }
  select(FLASH_CS); SPI.transfer(0x03); flashAddress(0);
  for (size_t i=0;i<n;++i) {
    if (SPI.transfer(0)!=image[i]) { deselect(FLASH_CS); return "FLASH readback mismatch"; }
  }
  deselect(FLASH_CS);
  return nullptr;
}
void setSensorSample(uint8_t sample) {
  for (unsigned bit=0;bit<3;++bit) digitalWrite(SENSOR_D[bit],(sample>>bit)&1);
}

bool sensorSample(uint8_t sample) {
  setSensorSample(sample);
  delayMicroseconds(20); // GPIO settles before the MCU sees the UART trigger
  while (Serial2.available()) Serial2.read();
  Serial2.write(SENSOR_COMMAND);
  const uint32_t start=millis();
  uint8_t frame[4]={0};
  unsigned used=0;
  while (used<sizeof frame && uint32_t(millis()-start)<200) {
    int next=Serial2.read();
    if (next<0) { delay(1); continue; }
    if (!used && next!=SENSOR_MARKER) continue;
    frame[used++]=uint8_t(next);
  }
  if (used!=sizeof frame) {
    Serial.printf("ERR SENSOR timeout sample=%u bytes=%u\n",unsigned(sample),used);
    return false;
  }
  const uint8_t expected=uint8_t(3u*sample+7u);
  if (frame[1]!=sample || frame[2]!=expected ||
      frame[3]!=(SENSOR_MARKER ^ frame[1] ^ frame[2])) {
    Serial.printf("ERR SENSOR mismatch sent=%u got=%u result=%u expected=%u check=%02X\n",
                  unsigned(sample),unsigned(frame[1]),unsigned(frame[2]),
                  unsigned(expected),unsigned(frame[3]));
    return false;
  }
  Serial.printf("SAMPLE %u %u\n",unsigned(frame[1]),unsigned(frame[2]));
  return true;
}

void runSensorTest() {
  if (targetHeldReset) {
    Serial.println("ERR SENSOR target held in reset after failed upload");
    return;
  }
  // Hold GPIO high across reset. In V5 it must no longer affect QSPI sampling.
  setSensorSample(7);
  assertTargetReset();
  delay(2);
  releaseTargetReset();
  delay(50);
  constexpr uint8_t sequence[]={7,0,1,6,2,5,3,4};
  for (uint8_t sample:sequence) {
    if (!sensorSample(sample)) return;
  }
  Serial.println("SENSOR PASS 8");
}

void releaseBidirPins() {
  for (auto pin:BIDIR_PINS) pinMode(pin,INPUT); // Never oppose MCU outputs.
}
void driveBidirPins(uint8_t pattern) {
  // Enter only after firmware has acknowledged DIR=0 / high-Z.
  for (unsigned i=0;i<2;++i) {
    digitalWrite(BIDIR_PINS[i],(pattern>>i)&1);
    pinMode(BIDIR_PINS[i],OUTPUT);
  }
}
uint8_t readBidirPins() {
  return (uint8_t(digitalRead(BIDIR_PINS[0]))&1u) |
         ((uint8_t(digitalRead(BIDIR_PINS[1]))&1u)<<1);
}
bool bidirCommand(uint8_t cmd,uint8_t arg,uint8_t &result) {
  while (Serial2.available()) Serial2.read();
  Serial2.write(cmd);
  if (cmd!='Z') Serial2.write(arg);
  uint8_t frame[4]={0};
  unsigned used=0;
  const uint32_t start=millis();
  while (used<sizeof frame && uint32_t(millis()-start)<250) {
    const int v=Serial2.read();
    if (v<0) { delay(1); continue; }
    if (!used && v!=0xb5) continue;
    frame[used++]=uint8_t(v);
  }
  if (used!=4 || frame[1]!=cmd ||
      frame[3]!=(0xb5u ^ frame[1] ^ frame[2])) {
    Serial.printf("ERR BIDIR UART cmd=%c bytes=%u\n",char(cmd),used);
    return false;
  }
  result=frame[2];
  return true;
}
void runBidirTest() {
  if (targetHeldReset) {
    Serial.println("ERR BIDIR target held in reset after failed upload");
    return;
  }
  releaseBidirPins();
  uint8_t ack=0;
  // This reset makes both MCU pads high-Z even if previous firmware drove them.
  assertTargetReset();
  delay(2);
  releaseTargetReset();
  delay(50);
  if (!bidirCommand('Z',0,ack) || ack!=0) {
    Serial.println("ERR BIDIR cannot enter input mode"); return;
  }
  for (uint8_t x=0;x<4;++x) {
    driveBidirPins(x);
    delayMicroseconds(100);
    if (!bidirCommand('I',x,ack) || ack!=x) {
      releaseBidirPins();
      Serial.printf("ERR BIDIR input sent=%u got=%u\n",unsigned(x),unsigned(ack));
      return;
    }
    Serial.printf("BIDIR IN %u\n",unsigned(x));
  }
  // Release ESP32 outputs BEFORE commanding MCU to drive the same lines.
  releaseBidirPins();
  delayMicroseconds(100);
  for (uint8_t x=0;x<4;++x) {
    if (!bidirCommand('O',x,ack) || ack!=x) {
      Serial.printf("ERR BIDIR output command=%u ack=%u\n",unsigned(x),unsigned(ack));
      return;
    }
    delayMicroseconds(100);
    const uint8_t observed=readBidirPins();
    if (observed!=x) {
      Serial.printf("ERR BIDIR output sent=%u observed=%u\n",unsigned(x),unsigned(observed));
      return;
    }
    Serial.printf("BIDIR OUT %u\n",unsigned(x));
  }
  if (!bidirCommand('Z',0,ack) || ack!=0) {
    Serial.println("ERR BIDIR failed to release output drivers"); return;
  }
  Serial.println("BIDIR PASS IN=4 OUT=4 Z");
}

// V8 test: the target sends one byte only after each actual ISR.
bool expectIRQByte(uint8_t expected, const char *stage) {
  const uint32_t start=millis();
  while (uint32_t(millis()-start)<2500) {
    int v=Serial2.read();
    if (v<0) { delay(1); continue; }
    if (v!=expected) {
      Serial.printf("ERR IRQ %s expected=%02X got=%02X\n",stage,unsigned(expected),unsigned(v));
      return false;
    }
    return true;
  }
  Serial.printf("ERR IRQ %s timeout expected=%02X\n",stage,unsigned(expected));
  return false;
}
void runIRQTest() {
  if (targetHeldReset) { Serial.println("ERR IRQ target held in reset"); return; }
  releaseBidirPins();
  assertTargetReset();
  setSensorSample(0);
  delay(3);
  while (Serial2.available()) Serial2.read();
  releaseTargetReset();
  if (!expectIRQByte('T',"timer/mask")) return;
  Serial.println("IRQ TIMER PASS");
  if (!expectIRQByte('X',"uart tx")) return;
  Serial.println("IRQ TX PASS");
  if (!expectIRQByte('R',"ready")) return;
  for (unsigned n=0;n<4;++n) {
    setSensorSample(1); // ui_in[4] only; no UART command triggers this event
    if (!expectIRQByte('H',"gpio rising")) return;
    setSensorSample(0);
    if (!expectIRQByte('L',"gpio falling")) return;
    Serial.printf("IRQ GPIO %u PASS\n",n);
    Serial2.write(uint8_t('a'+n));
    if (!expectIRQByte(uint8_t('A'+n),"uart rx")) return;
    Serial.printf("IRQ RX %u PASS\n",n);
  }
  delay(10);
  if (Serial2.available()) { Serial.println("ERR IRQ unexpected repeated response"); return; }
  Serial.println("IRQ PASS ALL");
}

// V9 hardware exercise. ESP32 is an I2C slave only during this test.
bool expectV9UART(uint8_t expected,const char *stage) {
  uint32_t start=millis();
  while(uint32_t(millis()-start)<3000) {
    int received=Serial2.read();
    if(received<0) { delay(1); continue; }
    if(received=='E') {
      uint32_t t=millis();
      while(!Serial2.available() && uint32_t(millis()-t)<100) delay(1);
      int status=Serial2.read();
      Serial.printf("ERR V9 MCU I2C status=%02X at %s\n",unsigned(status)&255,stage);
      return false;
    }
    if(received != int(expected)) {
      Serial.printf("ERR V9 UART %s expected=%02X got=%02X onRequest=%lu writeSeen=%d lastWrite=%02X\n",
                    stage,unsigned(expected),unsigned(received)&255,
                    (unsigned long)v9I2cRequestCount,
                    int(v9I2cWriteSeen),unsigned(v9LastI2cByte));
      return false;
    }
    return true;
  }
  Serial.printf("ERR V9 UART timeout %s\n",stage);
  return false;
}
int pwmDutyPercent(uint8_t pin) {
  const unsigned long high=pulseIn(pin,HIGH,100000);
  const unsigned long low=pulseIn(pin,LOW,100000);
  if(!high || !low) return -1;
  return int((high*100UL)/(high+low));
}
void runV9Test() {
  if(targetHeldReset) { Serial.println("ERR V9 target held in reset"); return; }
  releaseBidirPins();
  v9LastI2cByte=0; v9I2cWriteSeen=false; v9I2cRequestCount=0;
  Wire.onReceive(onI2cReceive);
  Wire.onRequest(onI2cRequest);
  if (!Wire.begin(uint8_t(0x42),int(BIDIR_PINS[0]),int(BIDIR_PINS[1]),100000u)) {
    Serial.println("ERR V9 Wire I2C slave initialization failed");
    return;
  }
  // ESP32 classic I2C slave: preload the first reply byte *before* the
  // master's read request, since the onRequest callback can be serviced late.
  // Both pins must remain open-drain; never switch them to push-pull HIGH.
  gpio_pullup_en(static_cast<gpio_num_t>(BIDIR_PINS[0]));
  gpio_pullup_en(static_cast<gpio_num_t>(BIDIR_PINS[1]));
  const uint8_t reply=0xc3;
  const size_t preloaded=Wire.slaveWrite(&reply,1);
  Serial.printf("DBG V9: I2C slave preloaded=%u, internal pull-ups enabled\n",
                unsigned(preloaded));
  assertTargetReset();
  delay(3);
  while(Serial2.available()) Serial2.read();
  releaseTargetReset();
  if (!expectV9UART('P',"boot ready")) { Wire.end(); releaseBidirPins(); return; }
  delay(25);
  int p0=pwmDutyPercent(PWM_SENSE[0]);
  int p1=pwmDutyPercent(PWM_SENSE[1]);
  if (p0<18 || p0>32 || p1<68 || p1>82) {
    Serial.printf("ERR V9 PWM duty0=%d%% duty1=%d%% (expected 25/75)\n",p0,p1);
    Wire.end(); releaseBidirPins(); return;
  }
  Serial.printf("V9 PWM PASS duty0=%d%% duty1=%d%%\n",p0,p1);
  Serial2.write(uint8_t('I'));
  if(!expectV9UART('W',"I2C write ACK")) { Wire.end(); releaseBidirPins(); return; }
  delay(10);
  if(!v9I2cWriteSeen || v9LastI2cByte!=0x5a) {
    Serial.printf("ERR V9 I2C write: seen=%d value=%02X\n",
                  int(v9I2cWriteSeen),unsigned(v9LastI2cByte));
    Wire.end(); releaseBidirPins(); return;
  }
  Serial.println("V9 I2C WRITE PASS 0x5A");
  if(!expectV9UART('R',"I2C read response")) { Wire.end(); releaseBidirPins(); return; }
  if(!expectV9UART(0xc3,"I2C byte from slave")) {
    Serial.printf("DBG V9: onRequest calls=%lu, receivedWrite=%d, lastWrite=0x%02X\n",
                  (unsigned long)v9I2cRequestCount,
                  int(v9I2cWriteSeen),unsigned(v9LastI2cByte));
    Wire.end(); releaseBidirPins(); return;
  }
  Serial.println("V9 I2C READ PASS 0xC3");
  if(!expectV9UART('Z',"GPIO pinmux restore")) { Wire.end(); releaseBidirPins(); return; }
  Wire.end(); releaseBidirPins();
  Serial.println("V9 PASS ALL");
}

// V10: 12-byte response [D7,kind,seq(LE32),signature(LE32),wdt_count,XOR] .
// ESP32 forwards exact decoded data to PC. It never controls RAM chip-selects.
bool v10Frame(uint8_t expected, uint32_t &sequence, uint32_t &sig, uint8_t &wdt) {
  uint8_t data[12]={0};
  size_t used=0;
  const uint32_t start=millis();
  while(used<sizeof data && uint32_t(millis()-start)<15000) {
    int next=Serial2.read();
    if(next<0) { delay(1); continue; }
    if(!used && next!=0xd7) continue;
    data[used++]=uint8_t(next);
  }
  if(used!=sizeof data) {
    Serial.printf("ERR V10 UART timeout bytes=%u\n",unsigned(used));
    return false;
  }
  uint8_t check=0;
  for(unsigned i=0;i<11;++i) check^=data[i];
  if(check!=data[11] || data[1]!=expected) {
    Serial.printf("ERR V10 frame kind=%02X expected=%02X check=%02X actual=%02X\n",
                  unsigned(data[1]),unsigned(expected),unsigned(data[11]),unsigned(check));
    return false;
  }
  sequence=0; sig=0;
  for(unsigned i=0;i<4;++i) {
    sequence|=uint32_t(data[2+i])<<(8*i);
    sig|=uint32_t(data[6+i])<<(8*i);
  }
  wdt=data[10];
  return true;
}
void runV10Edges() {
  if(targetHeldReset) { Serial.println("ERR V10EDGE target held reset"); return; }
  releaseBidirPins();
  v9I2cWriteSeen=false; v9LastI2cByte=0;
  Wire.onReceive(onI2cReceive); Wire.onRequest(onI2cRequest);
  if(!Wire.begin(uint8_t(0x42),int(BIDIR_PINS[0]),int(BIDIR_PINS[1]),100000u)) {
    Serial.println("ERR V10EDGE slave start"); return;
  }
  gpio_pullup_en(static_cast<gpio_num_t>(BIDIR_PINS[0]));
  gpio_pullup_en(static_cast<gpio_num_t>(BIDIR_PINS[1]));
  const uint8_t reply=0xc3;
  Wire.slaveWrite(&reply,1);
  assertTargetReset(); delay(10);
  while(Serial2.available()) Serial2.read();
  releaseTargetReset();
  if(!expectV9UART('Z',"V10EDGE PWM ready")) { Wire.end();releaseBidirPins();return; }
  delay(20);
  bool pwm0AlwaysLow=true;
  for(unsigned i=0;i<64;++i) {
    if(digitalRead(PWM_SENSE[0])!=LOW) pwm0AlwaysLow=false;
    delayMicroseconds(120);
  }
  const int duty1=pwmDutyPercent(PWM_SENSE[1]);
  if(!pwm0AlwaysLow || duty1<40 || duty1>60) {
    Serial.printf("ERR V10EDGE PWM 0%%/50%%: pwm0_low=%d duty1=%d\n",int(pwm0AlwaysLow),duty1);
    Wire.end();releaseBidirPins();return;
  }
  Serial.printf("V10EDGE PWM PASS duty0=0%% duty1=%d%%\n",duty1);
  Serial2.write(uint8_t('I'));
  if(!expectV9UART('N',"V10EDGE address NACK")) { Wire.end();releaseBidirPins();return; }
  Serial.println("V10EDGE NACK PASS address=0x43");
  if(!expectV9UART('R',"V10EDGE repeated read")) { Wire.end();releaseBidirPins();return; }
  if(!expectV9UART(0xc3,"V10EDGE repeated read data")) { Wire.end();releaseBidirPins();return; }
  if(!expectV9UART('P',"V10EDGE pinmux restore")) { Wire.end();releaseBidirPins();return; }
  Serial.println("V10EDGE I2C REPEATED PASS 0xC3");
  Wire.end(); releaseBidirPins();
  Serial.println("V10EDGE PASS ALL");
}
void runV10Exceptions() {
  // A fresh external reset is necessary because the ECALL/EBREAK test runs
  // immediately at boot. Capture UART while program runs.
  while(Serial2.available()) Serial2.read();
  assertTargetReset(); delay(10);
  releaseTargetReset();
  const uint32_t start=millis();
  while(uint32_t(millis()-start)<3000) {
    int v=Serial2.read();
    if(v==int('X')) { Serial.println("EXCEPTIONS PASS ECALL EBREAK MRET"); return; }
    if(v>=0) {
      Serial.printf("ERR EXCEPTIONS unexpected UART byte %02X\n",unsigned(v));
      return;
    }
    delay(1);
  }
  Serial.println("ERR EXCEPTIONS timeout (check LED; expected A9, fault EE)");
}
void resetV10External() {
  if(targetHeldReset) { Serial.println("ERR V10 external reset blocked"); return; }
  assertTargetReset();
  delay(10);
  while(Serial2.available()) Serial2.read();
  releaseTargetReset();
  delay(30);
  Serial.println("V10 RESET OK");
}
void runV10(uint8_t opcode) {
  if(targetHeldReset) { Serial.println("ERR V10 target held in reset"); return; }
  // Only UART is active here; do NOT reset/reflash just to poll the target.
  // On the V10 watchdog test, the internal watchdog itself must reset MCU.
  while(Serial2.available()) Serial2.read();
  Serial2.write(opcode);
  if(opcode=='W') {
    delay(950); // >= 250ms expiration + boot/autonomous memory initialization
    while(Serial2.available()) Serial2.read();
    Serial2.write('H');
  }
  uint32_t seq=0, sig=0;
  uint8_t wdt=0;
  const uint8_t expected=(opcode=='W') ? 'H' : opcode;
  if(!v10Frame(expected,seq,sig,wdt)) return;
  if(opcode=='W' && wdt==0) {
    Serial.println("ERR V10 watchdog did not record a reset");
    return;
  }
  Serial.printf("V10 %c seq=%08lX sig=%08lX wd=%u\n",char(opcode),
                (unsigned long)seq,(unsigned long)sig,unsigned(wdt));
}

uint32_t crc32(const uint8_t *buf,size_t n) {
  uint32_t c=~uint32_t{0};
  while(n--) {
    c^=*buf++;
    for(unsigned bit=0;bit<8;++bit) c=(c>>1)^((c&1)?0xedb88320u:0u);
  }
  return ~c;
}
}  // namespace

void setup() {
  releaseBus();
  releaseTargetReset();
  releaseBidirPins();
  for (auto pin:PWM_SENSE) pinMode(pin,INPUT);
  Serial2.begin(115200,SERIAL_8N1,SENSOR_UART_RX,SENSOR_UART_TX);
  for (auto pin:SENSOR_D) pinMode(pin,OUTPUT);
  setSensorSample(0);
  Serial.setRxBufferSize(8192);
  Serial.begin(115200);
  Serial.setTimeout(4000);
  Serial.println("CTW3");
}
void loop() {
  if (!Serial.available()) { delay(1); return; }
  char line[80]={0};
  const size_t len=Serial.readBytesUntil('\n',line,sizeof line-1);
  line[len]='\0';
  if (len && line[len-1]=='\r') line[len-1]='\0';
  if (strcmp(line,"PING")==0) { Serial.println("CTW3"); return; }
  if (strcmp(line,"SENSOR")==0) { runSensorTest(); return; }
  if (strcmp(line,"IRQ")==0) { runIRQTest(); return; }
  if (strcmp(line,"BIDIR")==0) { runBidirTest(); return; }
  if (strcmp(line,"V10EDGE")==0) { runV10Edges(); return; }
  if (strcmp(line,"V10X")==0) { runV10Exceptions(); return; }
  if (strcmp(line,"V10B")==0) { resetV10External(); return; }
  if (strcmp(line,"V10S")==0) { runV10('S'); return; }
  if (strcmp(line,"V10H")==0) { runV10('H'); return; }
  if (strcmp(line,"V10W")==0) { runV10('W'); return; }
  if (strcmp(line,"V10Q")==0) { runV10('Q'); return; }
  if (strcmp(line,"V9")==0) { runV9Test(); return; }
  unsigned count=0; unsigned long wanted=0; char extra=0;
  if (sscanf(line,"CTW3 %u %lx %c",&count,&wanted,&extra)!=2 || count==0 || count>SECTOR) {
    Serial.println("ERR header"); return;
  }
  Serial.println("READY");
  if (Serial.readBytes(image,count)!=count) {
    releaseBus(); Serial.println("ERR serial timeout"); return;
  }
  if (crc32(image,count)!=static_cast<uint32_t>(wanted)) {
    releaseBus(); Serial.println("ERR CRC"); return;
  }
  const char *error=programImage(count);
  // CS is high on every programImage return path. Always release the bus.
  releaseBus();
  if (error) {
    // Do not boot an erased/partially-written image. Upload again to recover.
    Serial.print("ERR "); Serial.println(error);
  } else {
    delayMicroseconds(10);
    releaseTargetReset(); // pull-up releases reset, ESP never drives it high
    Serial.printf("OK %04u %08lX RUN\n",count,wanted);
  }
}
