# CTW RV32 MCU V6 — pinout sau chuyển chân

## Chân logic ASIC

| Nhóm | Chân | Vai trò |
|---|---|---|
| Input | `ui_in[0]` | GPIO input 0, KEY1 trên bản DE10 |
| Input | `ui_in[1:3]` | GPIO input 1–3 |
| Input | `ui_in[4:6]` | GPIO input 4–6, cảm biến mẫu ba bit từ ESP32 trong bài test |
| Input | `ui_in[7]` | UART RX của MCU, cũng đọc được qua thanh ghi GPIO input |
| Output | `uo_out[0:4]` | GPIO output 0–4 từ thanh ghi GPIO |
| Output | `uo_out[5]` | **PSRAM A CS#**, active-low |
| Output | `uo_out[6]` | **PSRAM B CS#**, active-low |
| Output | `uo_out[7]` | **UART TX** của MCU |
| Inout | `uio[0]` | Flash CS# |
| Inout | `uio[1]` | QSPI DQ0 / SPI MOSI |
| Inout | `uio[2]` | QSPI DQ1 / SPI MISO |
| Inout | `uio[3]` | Shared SCK |
| Inout | `uio[4:5]` | QSPI DQ2, DQ3 |
| Inout | `uio[6:7]` | **Chưa sử dụng, high-Z**, chừa để mở rộng sau này |
| System | `clk` | Clock MCU, danh định ASIC 10 MHz |
| System | `rst_n` | Reset active-low, được ESP32 kéo thấp khi nạp Flash |
| System | `ena` | Tiny Tapeout project enable, không dùng làm chế độ nạp |

**GPIO output còn 5 chân**, không phải 7 chân như V5. Nguyên nhân là
hai CS# PSRAM đã chiếm `uo_out[5:6]`, UART TX chiếm `uo_out[7]`.
`uio[6:7]` chưa được gán thành GPIO trong V6. Chúng không lái mạch
ngoài và có thể được thiết kế tiếp ở phiên bản sau.

## So với V5

| Tín hiệu | V5 | V6 |
|---|---|---|
| UART TX | `uo_out[0]` | `uo_out[7]` |
| PSRAM A CS# | `uio[6]` | `uo_out[5]` |
| PSRAM B CS# | `uio[7]` | `uo_out[6]` |
| GPIO output 0 | Chưa được xuất ra pad uo[0] | `uo_out[0]` |
| GPIO output 5–7 | `uo_out[5:7]` | Không còn là GPIO output trực tiếp |
| `uio[6:7]` | PSRAM CS# | Hi-Z |

## Trên DE10-Nano

Để không phải nối lại dây đã test từ V5, **FPGA top V6 vẫn đưa RAM A/B CS#
ra JP1 chân 7/8** và UART TX ra **JP1 chân 18**. Đây là chuyển tiếp của
mạch FPGA. Nó **không phải chân vật lý ASIC**. ESP32 vẫn chỉ điều khiển
6 dây Flash, reset, GPIO cảm biến và UART như trước. Tham khảo toàn bộ
các chân kết nối trong [SENSOR.md](SENSOR.md).

## Khi chuyển sang chip thật

Mạch carrier / adapter cần nối riêng:

- Flash CS# → `uio[0]`
- QSPI DQ0–DQ3 và SCK → `uio[1:5]`
- PSRAM A CS# → `uo_out[5]`
- PSRAM B CS# → `uo_out[6]`
- UART TX → `uo_out[7]`
- UART RX → `ui_in[7]`

Hai chân `uio[6:7]` **không nối vào CS# của PSRAM**. Đường nối này khác
Pmod QSPI tiêu chuẩn của Tiny Tapeout, nên phải có adapter riêng.
Đảm bảo có pull-up phù hợp trên các CS# khi chip chưa được cấp nguồn,
đang reset hoặc project chưa được chọn.
