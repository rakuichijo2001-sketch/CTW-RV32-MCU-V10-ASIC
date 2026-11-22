# CTW RV32 MCU V10 — ASIC Stage 1 (Sky130 / Tiny Tapeout SKY26d)

**Bản nguồn:** copy nguyên trạng `CTW-RV32-MCU-V10-GP-TP-GPR-FIX`. Không đổi RTL, QSPI protocol, pinout, firmware hoặc tham số clock. Tất cả file đã đóng băng bằng `asic/rtl_freeze_manifest.json`.

## Trạng thái kỹ thuật

- FPGA evidence do người dùng chạy trên DE10 + ESP32: ISA torture 10,000/10,000; strict gp/tp PASS; regression PASS; final 2-hour soak 142,294 packets / 2,276,720 rounds; reset 100/100; watchdog autonomous reboot PASS.
- Thiết kế đang **YÊU CẦU** 4×2 tiles và 20 MHz (50 ns). **Chưa có kết quả silicon-specific synthesis, area hoặc STA.** Đừng nhầm với FPGA 50 MHz.
- ASIC top: `tt_um_ctw_rv32_mcu`; 17 file RTL trong `info.yaml`; SKY26d `tt-gds-action`, `sky130A`.
- 16 MiB Flash + 2×8 MiB PSRAM là **external IC**, không tính vào diện tích cell ở tile; FPGA dùng mô hình bộ nhớ, chưa kiểm tra IC vật lý.

## Bước 1 — Preflight trên Windows (chạy được ngay)

Mở PowerShell trong thư mục gốc dự án:

```powershell
py asic/preflight.py
```

Kỳ vọng `PREFLIGHT PASS`. Kiểm tra nội dung các file theo SHA-256, đủ 17 Verilog source, đúng clock/tiles/top, các mục cấu hình GDS. Đây là preflight tĩnh, không phải STA.

## Bước 2 — Chạy GDS / ASIC tự động (ưu tiên)

Đẩy **toàn bộ thư mục gốc dự án** lên GitHub repository của đại ca (không chỉ mỗi `src/`). Workflow có sẵn `.github/workflows/gds.yaml` dùng `TinyTapeout/tt-gds-action@ttsky26d` và `sky130A`.

GitHub → **Actions** → chọn workflow **gds** → **Run workflow** nếu chưa tự chạy khi push. Theo dõi bốn job:

1. `gds` — synthesis, floorplan, placement, CTS, route, GDS (nếu flow thành công).
2. `precheck` — kiểm tra hợp lệ theo shuttle.
3. `gl_test` — chạy gate-level test; nếu thiếu/không chạy test hoặc bị SKIP thì vẫn là lỗ hổng verification, không được ghi PASS.
4. `viewer` — xem GDS nếu thành công.

**Không thanh toán/submission/tapeout** trước khi review metrics và kết quả signoff.

> Chú ý: các tệp `test/` hiện tại chưa chắc chạy được toàn bộ bài ISA torture ở GL mode. Kết quả GL cần được đánh giá riêng, không suy từ job xanh nếu các bài quan trọng bị SKIP.

## Bước 3 — Local P&R trong WSL2 Ubuntu + Docker

Theo tài liệu chính thức https://tinytapeout.com/guides/local-hardening/:

- Python 3.11+, Docker, PDK_ROOT, `PDK=sky130A`, LibreLane compatible với SKY26d.
- Clone `https://github.com/TinyTapeout/tt-support-tools` vào thư mục `tt/`.
- Cài `pip install -r tt/requirements.txt` và phiên bản `librelane` đúng với shuttle/workflow (KHÔNG tự chọn phiên bản khác mà không đối chiếu).
- Chạy:

```bash
export PDK=sky130A
export PDK_ROOT="$HOME/ttsetup/pdk"
bash asic/run_local_hardening.sh
```

Lệnh sẽ chạy `tt_tool.py --create-user-config`, `--harden`, `--print-warnings`, lưu log vào `asic/reports/`.

## Bước 4 — Chỉ nghiệm thu khi có kết quả thật

Mở `asic/SIGNOFF_GATES.csv` và điền PASS/FAIL/NA có chứng cứ. Các gate quan trọng: technology-mapped area, 4×2 tile fit, setup/hold 50 ns (các PVT corners), fanout/CDC/reset, DRC/LVS, TT precheck, gate-level simulation, QSPI/I2C pin & external memory timing.

### Rủi ro cần ưu tiên

- `src/config.json` đang đặt `RUN_KLAYOUT_DRC=0`, `RUN_KLAYOUT_XOR=0` theo template. **Không được coi những bước bị tắt là đã kiểm chứng vật lý**; TT precheck / signoff phải xác nhận DRC/LVS riêng.
- 20 MHz internal clock không có nghĩa QSPI/I2C đạt mọi timing ở IC nhớ ngoài thực tế; phải kiểm tra datasheet PVT, IO pad round-trip, pullups, `tCEM` PSRAM và IO load.
- ASIC không có bộ nhớ chương trình nội; vẫn cần nạp Flash thật. `ena` là TT project selection, reset/program via external ESP32.
- CPU là TinyQV-derived RV32EC; strict x3/x4 và directed ISA PASS không đồng nghĩa đã chứng minh mọi encoding, illegal trap, interrupt/CSR behavior theo chuẩn.

## Công cụ phụ

`python3 asic/run_generic_synth.py` thử Yosys tổng hợp generic **nếu cài Yosys**. PASS của lệnh này không chứng minh SKY130 fit/timing. Tại môi trường soạn gói này không có Yosys, OpenROAD, LibreLane hoặc SKY130 PDK, vì vậy chưa có kết quả area/P&R/STA hay GDS.

## Mốc kế tiếp

**Lấy kết quả job `gds` lần đầu tiên** (GDS artifact, synthesis/area metrics, worst slack, warnings). Nếu FAIL, sửa theo error cụ thể; nếu PASS, kiểm chứng gate-level và physical signoff trước khi nộp shuttle.
