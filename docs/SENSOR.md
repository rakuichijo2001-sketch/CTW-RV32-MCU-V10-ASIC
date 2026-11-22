# V6 — ESP32 làm cảm biến mẫu cho RISC-V

ESP32 giả lập một giá trị 3 bit, giữ trên ba dây GPIO. UART của
ESP32 gửi một byte `S` để yêu cầu MCU lấy mẫu. CPU đọc thanh ghi GPIO,
tính `y = 3 × x + 7`, và dùng UART của MCU trả về 4 byte
`[0xA5, x, y, 0xA5 XOR x XOR y]`. ESP32 kiểm tra khung rồi báo qua
USB Serial cho PC. Kết quả do firmware RISC-V tính, không phải bypass
trong FPGA. Bài này dùng giá trị mô phỏng, không phải số đo cảm biến thật.

## Nối dây

Giữ nguyên toàn bộ dây từ V5 gồm JP1 1–6, 9 (reset) và 12 (GND).
Không nối vào JP1 chân 11 (5 V). Khi dùng FPGA model như V4,
không nối JP1 7–8 vào ESP32. Tắt nguồn hai board trước khi đổi dây.

| DE10 JP1 | Pin FPGA | Tín hiệu/lô-gic MCU | ESP32-WROOM-32/32E DevKit |
|---:|---|---|---|
| 13 | AD5 | Sensor D0 → ui_in[4] | GPIO32 output |
| 14 | AG14 | Sensor D1 → ui_in[5] | GPIO33 output |
| 15 | AE23 | Sensor D2 → ui_in[6] | GPIO22 output |
| 17 | AD23 | UART RX → ui_in[7] | GPIO17 UART2 TX |
| 18 | AE24 | UART TX ← uo_out[7] | GPIO16 UART2 RX |

Nối theo bảng V6 này, không theo phương án 2-in/2-out trao đổi ban đầu.
**Lưu ý khi chuyển lên ASIC Tiny Tapeout:** UART TX dùng uo_out[7], hai
CS# RAM dùng uo_out[5:6]. Trên DE10, các chân JP1 7/8 và 18 vẫn giữ
nguyên vì FPGA chỉ chuyển chúng tới pin vật lý như trước.
JP1 chân 16 để trống. Dùng số GPIO, không dùng vị trí pin trên header
ESP32. GPIO16 và GPIO17 ở đây dành cho WROOM, không mặc định áp dụng
cho WROVER. USB Serial vẫn dùng cổng sẵn có của ESP32 và không nối
GPIO1/GPIO3 sang DE10. Hai board dùng tín hiệu 3,3 V và GND chung.

## Chạy bài test

1. Giải nén V6 vào thư mục riêng. Compile project `ctw_de10.qpf`,
   nạp `output_files/ctw_de10.sof` mới vào DE10.
2. Nạp sketch mới `esp32/ctw_mcu_cradle/ctw_mcu_cradle.ino` vào ESP32
   trên COM12. Đóng Serial Monitor.
3. Mở PowerShell tại thư mục V6. Chạy một lệnh để ghi firmware cảm biến
   vào Flash rồi kiểm tra đủ tám mẫu:

```powershell
py tools/test_sensor.py --port COM12
```

Script nạp `firmware/sensor_demo.bin`. Sau khi ghi và đọc lại Flash,
ESP32 giữ mẫu `111` qua một lần reset của MCU, rồi thử lần lượt
`7,0,1,6,2,5,3,4`. V6 vẫn boot khi các bit GPIO này cao vì chúng
không còn chọn timing QSPI. Kết quả ví dụ:

```text
Flash verified: 284 bytes, CRC32 BC8BA57C
  GPIO 111 (7) -> CPU result 28
  GPIO 000 (0) -> CPU result 7
  ...
  GPIO 100 (4) -> CPU result 19
PASS: MCU read all 8 GPIO patterns, processed them and replied over UART.
```

LED DE10 là `0xA0 | (x << 1)` và dừng ở **0xA8** sau mẫu cuối x=4.
ESP32 chờ gói UART hoàn chỉnh và kiểm tra cả mẫu, kết quả, checksum.
LED không thay thế tiêu chí PASS của test UART.

- Thử lại không ghi Flash: `py tools/test_sensor.py --port COM12 --no-upload`.
- Muốn trở lại smoke B: `py tools/upload_esp32.py --port COM12 firmware/smoke_b.bin`.
  LED trở về 0x58, KEY1 ra 0x5A. Không cần đổi SOF.
- `ERR header` khi test mà nạp vẫn được: kiểm tra đã thực sự upload
  sketch V6, vì sketch cũ chưa nhận lệnh SENSOR.
- `SENSOR timeout`: kiểm tra SOF V6, đúng firmware cảm biến và nối chéo
  UART ở chân JP1 17–18. `SENSOR mismatch`: dò ba dây dữ liệu JP1 13–15.
- Khi PowerShell đã PASS đọc lại Flash nhưng hết thời gian chờ UART,
  quan sát LED để phân biệt CPU chưa boot và dây UART chưa nối đúng.

## Tài liệu chân

- [Terasic DE10-Nano User Manual](https://www.mouser.com/datasheet/3/996/1/DE10_Nano_User_manual.pdf)
- [Espressif ESP32-DevKitC V4 User Guide](https://docs.espressif.com/projects/esp-dev-kits/en/latest/esp32/esp32-devkitc/user_guide.html)
