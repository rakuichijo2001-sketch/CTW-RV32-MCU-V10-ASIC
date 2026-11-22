# V6 – kiểm tra pinout mới, QSPI và cảm biến

V6 bắt đầu từ V5 đã được người dùng xác nhận chạy với DE10 + ESP32,
firmware A/B, sensor GPIO và UART, bộ nhớ mô phỏng trong FPGA. Phiên bản
này chỉ đổi chân ASIC và wrapper FPGA, chưa chạy Quartus Fitter hay thử
bản V6 trên board. V5 gốc vẫn giữ riêng làm mốc so sánh.

| Bài kiểm tra V6 | Kết quả |
|---|---|
| Biên dịch firmware RISC-V RV32EC | PASS, `sensor_demo.bin` 284 byte, CRC32 BC8BA57C |
| Biên dịch Arduino sketch cho ESP32 Dev Module | PASS, Arduino-ESP32 2.0.17 |
| Co-sim sketch ESP32 và top DE10 50 MHz | PASS upload A/B và sensor, warm reset giữ GPIO 111, phát đúng UART vật lý mô phỏng và nhận lại 8 khung 115200 8N1. Mô phỏng ngắt MCU TX phải báo timeout |
| Top Tiny Tapeout 10 MHz và fixture timing bộ nhớ | PASS 8 mẫu GPIO, thêm mẫu sau reset, giữ GPIO cao lúc khởi động. Fixture giả lập trễ 30 ns theo từng chiều bus nhớ; không phải độ trễ đo |
| Hồi quy controller QSPI và guard RAM | PASS ở các top DE10 model, DE10 fixture ngoài và Tiny Tapeout; giữ CS# tối đa 3,4/4,4 µs trong bài smoke |
| Hồi quy fixture timing QSPI gốc | PASS boot nguội/ấm ở 0, 10 và 30 ns mỗi chiều với delay cố định 000 |
| PC Python | PASS 7 bài về uploader và kết quả SENSOR, gồm CRC, dữ liệu sai và kết quả thiếu |
| Tổng hợp generic ASIC và ánh xạ sơ bộ Cyclone V | PASS. Không thay Quartus Fitter hay layout signoff |
| Pinout mới | PASS test riêng uo[0], uo[5], uo[6], uo[7] và uio[7:6] luôn high-Z |
| Netlist generic sau Yosys | PASS bài boot nguội, reset ấm và dual PSRAM. Log này in nhãn V4 do tên bài test cũ, nhưng netlist đã lấy từ RTL V6 |
| Đường nạp Flash, QSPI, PSRAM model, UART, sensor | PASS hồi quy A/B và tám mẫu GPIO trên RTL/co-sim |
| So sánh baseline | Flash model, code QSPI boot/runtime và reset guard không đổi. Chỉ chuyển pad CS#, UART TX và thêm GPIO0 vào ngõ ra uo[0] |
| Board với SOF V6 và 3 IC nhớ thật | Chưa chạy. Cần adapter cho hai CS# RAM trên uo[5]/uo[6] |
| GDS, STA đa corner, DRC/LVS và khả năng hoạt động trên silicon | Chưa xác nhận |

Lệnh chạy lại `make test test-sensor-pc test-esp32-host test-sensor-asic
test-ram-guard test-pinout test-timing`. Bản V6 vẫn dùng 13 dây vật lý DE10/ESP32 của V5. Trên ASIC, không
nối PSRAM CS# tới uio[6:7] vì hai chân này high-Z. Nối lần lượt
uo[5], uo[6] đến hai CS# và uo[7] làm UART TX. Testbench DE10 giữ
JP1 chân 7, 8, 18 như trước nhờ wrapper mới.

Thao tác với DE10 và ESP32 nằm ở
[SENSOR.md](SENSOR.md). Log lịch sử V4 được giữ riêng ở
`evidence/baseline-v4`. Log V6 nằm trong `evidence/v6/`.
Bài full netlist generic sau tổng hợp dùng `make gate`, tách biệt
với các bài pin-level RTL. Gói đã kiểm tra tổng hợp sơ bộ bằng Yosys,
chưa chạy Quartus Fitter để xác thực vị trí chân và thời gian trên DE10.


## V7 bidirectional GPIO extension — pending physical validation

- `make test-gpio`: dedicated RTL testbench for input sampler and pad output-enable, raw reset, and ena deselect.
- `make test-pinout`: previous V6 output remapping invariant.
- `make firmware`: compiles `gpio_bidir_demo.bin` with RISC-V GNU toolchain.
- `py tools/test_bidir.py --port COM12`: actual DE10/ESP32 end-to-end test after adding two resistively coupled lines on JP1 pins 19–20.
- Neither FPGA hardware run nor Tiny Tapeout physical signoff is claimed by this package.

## V8 — trạng thái thật tại bàn giao
- Baseline V7: người dùng đã báo PASS firmware 332 byte CRC32 56BB1557, đủ 4 mẫu IN/OUT và trả High-Z trên DE10 + ESP32, với mô hình bộ nhớ.
- Firmware `irq_demo.bin`: biên dịch bằng Clang RISC-V và LLD thành ELF32 RVE/RVC, binary 580 byte.
- Python: 10 test PASS (uploader, sensor, IRQ protocol).
- Sketch: `g++ -std=c++17 -fsyntax-only` với mock Arduino/SPI PASS; không phải biên dịch ESP32 Arduino thực tế.
- RTL/GLS/Quartus: CHƯA CHẠY trong môi trường bàn giao (không có Icarus/Verilator/Yosys/Quartus, apt không truy cập được). Các target `test-irq-model`, `test-irq-asic`, `gate-irq` đã thêm, cần chạy trước khi đánh giá V8.
- Chip nhớ thật và signoff ASIC vẫn chưa kiểm tra.
