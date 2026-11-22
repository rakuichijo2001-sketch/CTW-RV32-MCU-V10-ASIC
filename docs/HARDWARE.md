# Handoff reset, bộ nhớ và board thật

## Quyền điều khiển bus

- Hold reset: `rst_n=0` đưa sáu pad QSPI của MCU về high-Z ngay cả khi không
  có clock. Hai PSRAM CS# giờ nằm ở uo_out[5:6] và vẫn do MCU giữ cao trong khi
  project được chọn.
- Trong DE10 MODEL, chỉ phần giả lập **Flash slave** trả dữ liệu SPI trên
  DQ1 khi ESP32 đọc. Pad master của MCU vẫn nhả cả sáu dây. Khi RUN, master
  xuất tín hiệu ra JP1 nhưng đọc phản hồi từ mô hình nội bộ.
- ESP32 kéo reset low ở GPIO21, chờ 10 ms rồi truy cập Flash ở 2 MHz.
  Nó tự thử lại ở 250 kHz nếu ID sai ở 2 MHz. Nó thoát chế độ đọc liên tục, kiểm tra JEDEC `EF 70 18`, xóa sector 0,
  ghi theo page, chờ WIP và đọc lại toàn bộ firmware. Sau khi nhả bus, nó
  chờ 10 µs rồi đổi GPIO21 về input để pull-up nhả reset.
- Khi reset được nhả và có clock, MCU chờ 6 ms tại clock cấu hình,
  thoát Flash continuous read, chờ Flash hết bận, đặt QE **volatile**
  nếu cần và vào lại chế độ continuous read. Sau đó từng PSRAM thoát
  QPI nếu đã vào từ lần chạy trước, reset và vào lại QPI. MCU giữ lõi
  ở reset đến khi chuỗi này xong. Clock của khối khởi tạo tối đa 2,5 MHz. Boot thử một byte đầu trong Flash để
  chặn ảnh trắng `0xFF`, không phải xác thực toàn bộ firmware.
- V6 nạp tại offset 0, tối đa 4096 byte/lần, cả với Flash thật. Không có
  A/B rollback nếu mất nguồn giữa khi xóa/ghi. `rst_n` không cắt nguồn
  và không tự reset ESP32. Không để ESP32 mất nguồn riêng khi vẫn nối
  bus đang hoạt động nếu chưa có cách ly phù hợp.

- Nếu CS# PSRAM bị giữ thấp khoảng 6 µs danh định, bảo vệ kéo tất cả
  CS# lên, ngừng SCK, nhả DQ và giữ CPU reset đến lần reset bên ngoài.
  `uo_out=0xE9` (bit 0 là UART idle); LED DE10 hiển thị `0xE8`. Tập
  tin trong Flash không bị xóa bởi cơ chế này. Giao dịch RAM đang
  dở có thể không hoàn tất. Bộ đếm chạy theo clock MCU nên **không
  dừng hay hạ clock giữa giao dịch QSPI**, và không áp dụng ngưỡng
  6 µs này cho biến thể PSRAM extended có tCEM 3 µs.

## Khi thay model bằng IC thật

| IC | Dung lượng thật | Địa chỉ nhìn từ MCU | Backing của model |
|---|---:|---|---:|
| Winbond W25Q128JVSIM | 16 MiB | 0x00000000–0x00FFFFFF | 4 KiB từ địa chỉ 0 |
| AP Memory APS6404L-3SQR-SN A | 8 MiB | 0x01000000–0x017FFFFF | 4 KiB đầu bank |
| AP Memory APS6404L-3SQR-SN B | 8 MiB | 0x01800000–0x01FFFFFF | 4 KiB đầu bank |

Nối chung SCK/DQ trên cả ba IC. Trên **DE10**, ba CS# vẫn hiện tại
JP1 chân 1/7/8 vì FPGA top chuyển chúng ra đúng chân cũ. Trên **ASIC**,
Flash CS# ở uio[0], còn RAM A/B CS# ở uo_out[5]/uo_out[6].
Cần adapter riêng cho Pmod QSPI, không chỉ cắm Pmod chuẩn. Hai chân
RAM CS# trên FPGA là output-only nên QSF không bật internal weak pull-up
cho chúng. Khi có bộ nhớ ngoài, đặt pull-up **trên PCB** và giữ chip
memory unselected trong quá trình cấp nguồn trước khi FPGA cấu hình. Nên đặt
tụ decoupling sát mỗi IC và giữ đường dây ngắn. Model chỉ hỗ trợ các
lệnh dùng trong V6 và không mô phỏng timing điện, refresh thực, độ
trễ pad hoặc nhiễu. Với APS6404L, tuân theo điều kiện power-up của
datasheet: nguồn ổn định tối thiểu 150 µs, CS# cao và bus DQ/SCK thấp
trong khoảng khởi động. FSM giữ bus thấp sau khi đã nhả reset và đã có
clock, nhưng không kiểm soát pad trước khi FPGA bắt đầu chạy. Kiểm tra
ramp, các pull và mức idle ngay trên mạch thật.

Trên Tiny Tapeout, cần board cho phép đưa `rst_n` ra mạch nạp,
chọn đúng project, xác nhận mức VIO và tắt các driver trên devkit
đang chiếm đường reset hoặc QSPI. V6 cố định cấu hình lấy mẫu QSPI
là `000` trong RTL cho cả DE10 và Tiny Tapeout, không còn đọc các chân
`ui_in[6:4]` lúc reset để chọn điểm lấy mẫu. Ba chân này là GPIO vào.
Phải đo thời điểm lấy mẫu với pad, carrier và chip nhớ thật trước khi
chốt clock cho tapeout. Nếu cần chọn điểm lấy mẫu khác, phải thực hiện ở
RTL trước tapeout. Không suy ra timing closure từ mô phỏng model.

Nguồn tham chiếu

- [Terasic DE10-Nano User Manual, bảng 3-9 và 3-10](https://www.mouser.com/datasheet/3/996/1/DE10_Nano_User_manual.pdf)
- [W25Q128JV-DTR Datasheet, W25Q128JVSIM](https://www.rxelectronics.de/datasheet/cb/W25Q128JVSIM.pdf)
- [AP Memory APS6404L-3SQR Datasheet](https://www.apmemory.com/wp-content/uploads/APS6404L-3SQR.pdf)
- [Tiny Tapeout GPIO](https://tinytapeout.com/specs/gpio/)
