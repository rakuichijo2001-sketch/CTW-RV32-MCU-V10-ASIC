# V8 — Interrupt subsystem

## 1. Kiến trúc và giới hạn

TinyQV core hiện có bốn nguồn ngắt local (custom machine interrupt 16–19).
V7 nối tất cả về 0; V8 giữ vector cố định reset 0x00, trap 0x04, IRQ 0x08.
Không giả định có mtvec/PLIC/CLINT chuẩn. Dùng CSR mstatus (MIE bit 3), mie,
mip, mcause, mepc, mret theo implementation TinyQV. Software không bật nested
interrupt. Core đã sửa để chốt cạnh IRQ16/17 mỗi clock (trước đó chỉ ở counter=5),
reset last_interrupt_req và ưu tiên sự kiện mới khi trùng thao tác xóa pending.
Mỗi nguồn có một bit pending (không phải FIFO/count; các sự kiện dồn có thể coalesce).

| IRQ | Nguồn | Kiểu | Acknowledge |
|---|---|---|---|
| 16 | GPIO rising/falling | Edge, latched mip[16] | `csrc mip, mask16` trong ISR |
| 17 | Timer compare | Edge, latched mip[17] | `csrc mip, mask17` trong ISR; rearm nếu cần |
| 18 | UART RX valid | Level | Đọc UART_DATA để clear rx_valid |
| 19 | UART TX idle | Level | Ghi dữ liệu mới hoặc tắt mie[19] |

IRQ19 báo sẵn sàng gửi, không phải cờ one-shot. Khi idle, nguồn luôn ở mức 1;
không bật mie[19] nếu không có dữ liệu hoặc không có ISR chuyển trạng thái.
UART vẫn là RX một byte, không có FIFO; sender phải có flow control phần mềm.
GPIO được đồng bộ 2 FF; xung ngắn hơn thời gian lấy mẫu có thể bị bỏ lỡ.
GPIO bidir chỉ tham gia ngắt khi ở input mode; để tránh ngắt giả lúc đổi hướng,
mask nguồn trước khi đổi hướng, đợi đồng bộ, xóa pending rồi enable lại.

## 2. Register map (32-bit word access)

Các địa chỉ cũ không đổi.

| Địa chỉ | Tên | Ý nghĩa |
|---|---|---|
| 0x08000000 | GPIO_IN | Đọc 8 bit input |
| 0x08000004 | GPIO_OUT | Ghi/đọc GPIO output latch, ASIC chỉ [4:0] |
| 0x08000008 | TIMER_COUNT | Free-running 32-bit, tăng mỗi clock |
| 0x0800000C | UART_DATA | Đọc/ghi UART, đọc ACK RX |
| 0x08000010 | UART_STATUS | bit0 TX busy; bit1 RX valid |
| 0x08000014 | ID | Không đổi |
| 0x08000018 | BIDIR_DIR | bit0/1: 0=input, 1=output |
| 0x0800001C | BIDIR_OUT | 2 bit output latch |
| 0x08000020 | BIDIR_IN | 2 bit giá trị đã đồng bộ |
| 0x08000024 | GPIO_IRQ_RISE | R/W mask 9 bit; reset 0 |
| 0x08000028 | GPIO_IRQ_FALL | R/W mask 9 bit; reset 0 |
| 0x0800002C | TIMER_COMPARE | R/W 32 bit; reset 0 |
| 0x08000030 | TIMER_CTRL | R/W bit0 arm; tự clear khi match; reset 0 |

Mask GPIO bit0–6 -> ui_in[0–6]; bit7 -> uio[6]; bit8 -> uio[7]. UART RX
ui_in[7] không nằm trong mask để tránh các cạnh UART gây ngắt GPIO.
Timer so sánh bằng tuyệt đối, không phải >=. Lập lịch đủ xa hơn chi phí truy cập
MMIO; disarm, ghi compare mới = count + delta, rồi arm. Nếu đã vượt compare
thì chờ tới vòng wrap 32 bit. Clock DE10 50 MHz, ASIC danh định 10 MHz.

## 3. Test trên DE10 + ESP32

Giữ toàn bộ dây V7. GPIO32 của ESP32 -> JP1 pin 13 -> ui_in[4] dùng cho ngắt GPIO.
UART giữ JP1 17 <- ESP32 GPIO17, JP1 18 -> GPIO16. Không dùng thêm chân.
Mở ctw_de10.qpf, compile/load SOF; upload sketch ESP32 V8, đóng Serial Monitor.

```powershell
py tools/test_irq.py --port COM12
py tools/test_irq.py --port COM12 --no-upload
```

Lệnh 1 nạp irq_demo.bin rồi reset để test. Lệnh 2 reset và chạy lại firmware,
không ghi Flash. Reset không xóa Flash mô phỏng khi FPGA vẫn có điện.
Test firmware dùng toàn bộ thanh ghi trong phạm vi x0–x15; 16-byte ISR frame trên
PSRAM A bảo toàn t0/t1/t2; ISR không gọi hàm, không thay đổi các thanh ghi khác.
Vectored code được đặt ở offset 0/4/8 bằng linker script cũ.

Các marker UART do main phát **sau khi ISR tăng counter trong PSRAM**, không phải
main polling trực tiếp GPIO/uart RX. Timer test khóa MIE toàn cục, chờ mip17,
xác nhận counter vẫn 0, mở MIE và đợi counter = 1. TX IRQ tự tắt trong ISR.
GPIO test có bốn cạnh lên và bốn cạnh xuống, không gửi lệnh UART kích GPIO;
RX IRQ đọc byte a..d, main trả A..D. Main kiểm tra sentinel và đếm sự kiện.
ESP32 kiểm tra không có marker lặp trong 10 ms sau mẫu cuối.

| LED DE10 | Ý nghĩa |
|---|---|
| 0x02 | Reset / programmer |
| 0x10 | Boot FSM hoặc firmware đang làm timer test |
| 0x18 | Firmware đã tới main loop GPIO/RX; kiểm tra thêm log UART |
| 0xEE | Firmware fail/trap |
| 0xE0 / 0xE8 | Boot fail / RAM guard |

Nếu lỗi, gửi nguyên dòng `IRQ test failed: ...` và LED. Không đổi dây QSPI nếu
Flash verified đã thành công. Không lấy một marker đơn lẻ làm bằng chứng toàn IRQ.

## 4. Regression trước tapeout

```sh
make test-irq              # DE10 model + ASIC timing fixture + Python protocol
make test test-timing test-ram-guard test-sensor-asic test-sensor-pc
make test-esp32-host        # Verilator C++ UART/SPI harness
make gate gate-irq gate-timing
```

Các test tích hợp kiểm tra timer pending/mask, GPIO rising/falling, UART RX/TX,
MRET, warm reset. Bổ sung coverage ngắt đồng thời, khi memory transaction đang
chạy, mask/clear races, reset trong ISR, stress UART, regression ISA/TinyQV khi
có simulator; chưa tuyên bố đã đạt những mục này. Test trên FPGA không chứng minh
timing I/O của ASIC hoặc IC nhớ thật. V8 chưa RTL Freeze, chưa signoff.
