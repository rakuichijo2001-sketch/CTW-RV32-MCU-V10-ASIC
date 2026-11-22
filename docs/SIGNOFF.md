# CTW RV32 MCU V8 — bàn giao tiền tapeout

**Trạng thái: ứng viên RTL, chưa signoff tapeout.** Bộ dữ liệu thử đang nhắm
Tiny Tapeout SKY130, 3,3 V I/O, Flash W25Q128JVSIM và đúng hai IC
APS6404L-3SQR-SN (standard grade). PCB dùng hai nguồn riêng cho DevKit
ESP32 và DE10 khi test; bảo đảm GND chung. Khi hệ hoàn chỉnh có thể
chung nguồn nếu thiết kế nguồn và trình tự lên nguồn phù hợp.

## Điều kiện tương tác

| Pad ASIC | Tín hiệu | Kết nối |
|---|---|---|
| uio[0] | Flash CS# | Flash riêng |
| uio[1:2] | DQ0, DQ1 | Chia sẻ giữa ba IC + mạch nạp |
| uio[3] | SCK | Chia sẻ giữa ba IC + mạch nạp |
| uio[4:5] | DQ2, DQ3 | Chia sẻ giữa ba IC + mạch nạp |
| uio[6], uio[7] | GPIO hai chiều | Mặc định Hi-Z khi reset; điều khiển qua BIDIR_DIR/OUT, đọc BIDIR_IN |
| uo_out[5] | PSRAM A CS# | Chỉ output, giữ HIGH khi reset hoặc boot lỗi |
| uo_out[6] | PSRAM B CS# | Chỉ output, giữ HIGH khi reset hoặc boot lỗi |
| uo_out[7] | UART TX | Output nối đến RX của ESP32 hoặc host khác |
| rst_n | Reset tác động mức thấp | ESP32 GPIO21 open-drain qua pull-up trên mạch đích |
| clk | Clock hệ thống | Tiny Tapeout danh định 10 MHz, SCK runtime tối đa 5 MHz |
| ui_in[6:4] | GPIO input D[2:0] | Không ảnh hưởng đến QSPI, lấy mẫu cố định 000 trong RTL |
| ui_in[7] | UART RX | 115200 8N1, nhận từ TX của ESP32 |
| uo_out[0:4] | GPIO output[0:4] | 5 ngõ ra tự do |
| ena | Chọn project | Do mux của shuttle điều khiển |

**V7 không còn khớp Pmod QSPI tám đường mặc định.**
Hai CS# RAM chuyển sang ngõ ra chuyên dụng, nên mạch carrier phải
chuyển tiếp uo_out[5]/uo_out[6] tới chân CS# của hai PSRAM. Uart TX
nằm trên uo_out[7]. Không giả định Pmod chuẩn sẽ tự nối các đường này. Xác minh schematic đúng
revision của carrier khi chốt shuttle, nhất là chỗ truy cập
`rst_n` và cách nhả driver của MCU trên devkit. Không nối
ESP32 hoặc pull-up 5 V vào bus 3,3 V. Nguồn các IC nhớ cần
tụ decoupling và phải ổn định trước khi cho chạy boot. Trước đó
cần giữ ba CS# cao theo VDD, SCK và DQ ở mức idle phù hợp với
datasheet. Phải đo điều kiện **CE# bám VDD trong 200 mV** của
APS6404L nếu lên nguồn cùng nhau. Pull và giám sát reset của board
có thể cần thiết vì thiết kế số không điều khiển pad khi chưa có
nguồn hoặc chưa được chọn.

## Trước khi nộp tapeout

1. **Đóng băng cấu hình.** Ghi commit, shuttle, PDK và revision carrier.
   Mặc định gói dùng flow tham chiếu SKY 26d, 4×2 tile và clock constraint
   100 ns. Đây không phải xác nhận đã có slot hay đã fit 4×2.
2. **Chạy flow của shuttle thực tế.** Lấy kết quả tổng hợp, placement,
   routing và STA setup/hold ở các corner có trong flow. Xác nhận
   không có endpoint không ràng buộc ngoài các ngoại lệ đã giải thích.
   Kiểm tra GDS/precheck, DRC, LVS và báo cáo công suất theo clock đã chốt.
3. **Không bỏ qua đường QSPI ngoài chip.** Lập ngân sách đường đi
   CLK/CS/DQ và đường trở về DQ, gồm pad/mux, PCB, thông số tACLK/tCLQV,
   setup/hold và đổi chiều DQ/tHZ. So với spec **của chính shuttle**,
   không dùng phép đo một shuttle cũ làm worst case. Chạy lại fixture
   giả lập bằng biên độ trễ và skew đã chốt, rồi chạy netlist sau route
   với các giao dịch nạp/boot/reset cần thiết.
4. **Nếu chưa có IC thật.** Vẫn chạy được các bài test RTL, fixture timing
   và GLS. Ghi riêng rủi ro còn lại của boot nguội, timing pin, nguồn và
   wiring trên carrier. Không dùng mô phỏng để tuyên bố đạt các phép đo đó.

## Khi có phần cứng

- Chọn project và clock 10 MHz. Xác thực JEDEC ID Flash `EF 70 18`.
  Nạp A rồi B, quan sát mã GPIO 0xA4 rồi 0x58 và đọc kết quả firmware,
  không chỉ dựa vào PASS của uploader.
- Đo SCK, CS# từng bộ nhớ và DQ trong nạp, boot và truy cập RAM.
  Kiểm tra CS# không trùng, bus không bị hai nguồn lái và
  thời gian chọn PSRAM nằm dưới 8 µs trên đúng mã standard.
- Reset nhiều lần không cấp lại nguồn. Sau đó cắt nguồn cả chip và
  bộ nhớ, ngắt mạch nạp, cấp lại và xác nhận B tự boot.
- Nạp `smoke_timing.bin` để kiểm tra hai bên ranh giới 1 KiB và từ
  cuối của cả hai bank. Cần test thêm dung lượng toàn dải, burst dài,
  ngắt giữa giao dịch và biên nguồn/nhiệt trước khi chốt vận hành.
  Firmware smoke không phải chứng nhận tương thích toàn bộ tập ISA.

## Nguồn tham chiếu

- [Tiny Tapeout QSPI pinout](https://tinytapeout.com/specs/pinouts/#qspi-flash-and-psram)
- [Tiny Tapeout GPIO / multiplexer](https://tinytapeout.com/specs/gpio/)
- [Tiny Tapeout SKY 26d build flow](https://github.com/TinyTapeout/tinytapeout-sky-26d/blob/main/BUILDING.md)
- [AP Memory APS6404L-3SQR datasheet](https://www.apmemory.com/wp-content/uploads/APS6404L-3SQR.pdf)
- [Winbond W25Q128JVSIM datasheet](https://www.rxelectronics.de/datasheet/cb/W25Q128JVSIM.pdf)


## V7: Bi-directional GPIO checks required before tapeout

- Prove both uio[6] and uio[7] remain High-Z whenever `rst_n=0`, `ena=0`,
  during boot, and on RAM timeout — regardless of written `BIDIR_DIR`.
- Test CPU MMIO writes to `0x08000018` (DIR) and `0x0800001C` (OUT), and
  sampled input from `0x08000020` through two synchronizer flip-flops.
- On FPGA, use JP1 physical pins 19 and 20, with 1 kΩ series resistors to
  ESP32 GPIO13/14 for direction handoff test; never have both drive at once.
- Run V7 firmware and dedicated testbench (see `docs/GPIO_BIDIR.md`), plus
  all V6 regressions. Neither current test results nor compile-only checks
  replace physical FPGA testing and ASIC signoff.

## V8 bổ sung
- Phải chạy `make test-irq gate-irq`, kiểm tra hướng/độ trễ GPIO, timer mask/pending, UART RX/TX, MRET và warm reset.
- Đánh giá diện tích và STA lại do bổ sung timer compare, irq masks và core edge capture. Không tái sử dụng kết quả PD của V7.
- Kiểm tra xung ngắt đồng thời, ngắt khi CPU đang truy cập PSRAM/XIP, không mất giao dịch hoặc sai PC; kiểm tra thời gian đáp ứng IRQ và giới hạn RX một byte.
