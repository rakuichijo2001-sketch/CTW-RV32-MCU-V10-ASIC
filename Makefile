PYTHON ?= python3
CROSS ?= riscv64-unknown-elf-
IVERILOG ?= iverilog
VVP ?= vvp
YOSYS ?= yosys
VERILATOR ?= verilator
QUARTUS ?= quartus_sh
RTL := $(wildcard src/*.v)
MODELS := $(wildcard fpga/*.sv)
FLAGS := -march=rv32ec -mabi=ilp32e -mno-relax -msmall-data-limit=0 -Os -ffreestanding -fno-builtin -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -Wall -Wextra -Werror -nostdlib

.PHONY: all test test-model test-external test-asic test-uploader test-esp32-host firmware fpga synth gate clean
all: test
test: test-model test-external test-asic test-uploader test-pinout test-gpio test-irq

test-model test-external test-asic:
	test -s test/smoke_a.hex && test -s test/smoke_b.hex
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_v3 $(if $(filter test-external,$@),-DEXTERNAL,) $(if $(filter test-asic,$@),-DASIC,) -o build/$@ $(RTL) $(MODELS) ctw_de10_top.sv test/tb_v3.sv
	$(VVP) build/$@

test-uploader:
	$(PYTHON) -m unittest discover -s test -p test_uploader.py

test-esp32-host:
	mkdir -p build
	$(VERILATOR) --cc --exe --build -j 2 -CFLAGS "-I$(abspath test/esp32_host)" --top-module ctw_jp1_harness --Mdir build/esp-host $(RTL) $(MODELS) ctw_de10_top.sv test/esp32_host/ctw_jp1_harness.sv $(abspath test/esp32_host/main.cc)
	build/esp-host/Vctw_jp1_harness firmware/smoke.bin firmware/smoke_b.bin firmware/sensor_demo.bin firmware/irq_demo.bin

firmware: firmware/smoke.bin firmware/smoke_b.bin test/smoke_a.hex test/smoke_b.hex

firmware/smoke.bin firmware/smoke_b.bin: firmware/startup.S firmware/smoke.c firmware/link.ld
	mkdir -p build
	$(CROSS)gcc $(FLAGS) $(if $(filter %_b.bin,$@),-DPASS_LED=0x58u,) -T firmware/link.ld -o build/$(notdir $@).elf firmware/startup.S firmware/smoke.c
	$(CROSS)objcopy -O binary build/$(notdir $@).elf $@

test/smoke_a.hex: firmware/smoke.bin tools/bin_to_hex.py
	$(PYTHON) tools/bin_to_hex.py $< $@

test/smoke_b.hex: firmware/smoke_b.bin tools/bin_to_hex.py
	$(PYTHON) tools/bin_to_hex.py $< $@

fpga:
	$(QUARTUS) --flow compile ctw_de10

synth:
	mkdir -p build
	$(YOSYS) -Q -q -l build/yosys.log -p "read_verilog $(RTL); hierarchy -check -top tt_um_ctw_rv32_mcu; synth -flatten -top tt_um_ctw_rv32_mcu; check -assert; stat; write_verilog -noattr build/mcu-generic.v"

gate: synth
	$(IVERILOG) -g2012 -DASIC -DGATE_SMOKE -s tb_v3 -o build/tb-gate build/mcu-generic.v $(MODELS) test/tb_v3.sv
	$(VVP) build/tb-gate

clean:
	rm -rf build

.PHONY: test-timing test-ram-guard
test-timing:
	test -s test/smoke_timing.hex
	mkdir -p build
	set -e; for delay in 0 10 30; do \
	  $(IVERILOG) -g2012 -DASIC -DGATE_SMOKE -DDATASHEET_TIMING -Ptb_v3.TEST_PAD_NS=$$delay -s tb_v3 \
	    -o build/timed-$$delay $(RTL) $(MODELS) test/reference/timed_memory_fixture.sv test/reference/psram_pin_reference.sv test/tb_v3.sv; \
	  $(VVP) build/timed-$$delay; \
	done

test-ram-guard:
	mkdir -p build
	set -e; for period in 20 100; do \
	  $(IVERILOG) -g2012 -Ptb_ram_guard.CLK_NS=$$period -s tb_ram_guard -o build/guard-$$period $(RTL) test/reference/tb_ram_guard.sv; \
	  $(VVP) build/guard-$$period; \
	done

firmware: firmware/smoke_timing.bin test/smoke_timing.hex
firmware/smoke_timing.bin: firmware/startup.S firmware/smoke.c firmware/link.ld
	mkdir -p build
	$(CROSS)gcc $(FLAGS) -DCTW_TIMING_TEST -T firmware/link.ld -o build/smoke_timing.elf firmware/startup.S firmware/smoke.c
	$(CROSS)objcopy -O binary build/smoke_timing.elf $@
test/smoke_timing.hex: firmware/smoke_timing.bin tools/bin_to_hex.py
	$(PYTHON) tools/bin_to_hex.py $< $@

.PHONY: gate-timing
gate-timing: synth
	$(IVERILOG) -g2012 -DASIC -DGATE_SMOKE -DDATASHEET_TIMING -Ptb_v3.TEST_PAD_NS=30 -s tb_v3 \
	  -o build/gate-timing build/mcu-generic.v $(MODELS) test/reference/timed_memory_fixture.sv test/reference/psram_pin_reference.sv test/tb_v3.sv
	$(VVP) build/gate-timing

firmware: firmware/sensor_demo.bin test/sensor_demo.hex firmware/gpio_bidir_demo.bin test/gpio_bidir_demo.hex
firmware/gpio_bidir_demo.bin: firmware/startup.S firmware/gpio_bidir_demo.c firmware/link.ld
	mkdir -p build
	$(CROSS)gcc $(FLAGS) -T firmware/link.ld -o build/gpio_bidir_demo.elf firmware/startup.S firmware/gpio_bidir_demo.c
	$(CROSS)objcopy -O binary build/gpio_bidir_demo.elf $@
test/gpio_bidir_demo.hex: firmware/gpio_bidir_demo.bin tools/bin_to_hex.py
	$(PYTHON) tools/bin_to_hex.py $< $@

firmware/sensor_demo.bin: firmware/startup.S firmware/sensor_demo.c firmware/link.ld
	mkdir -p build
	$(CROSS)gcc $(FLAGS) -T firmware/link.ld -o build/sensor_demo.elf firmware/startup.S firmware/sensor_demo.c
	$(CROSS)objcopy -O binary build/sensor_demo.elf $@
test/sensor_demo.hex: firmware/sensor_demo.bin tools/bin_to_hex.py
	$(PYTHON) tools/bin_to_hex.py $< $@

.PHONY: test-sensor-asic test-sensor-pc
test-sensor-asic:
	test -s test/sensor_demo.hex
	mkdir -p build
	$(IVERILOG) -g2012 -DASIC -DSENSOR_SMOKE -DDATASHEET_TIMING -s tb_v3 -o build/sensor-asic \
	  $(RTL) $(MODELS) test/reference/timed_memory_fixture.sv test/reference/psram_pin_reference.sv test/tb_v3.sv
	$(VVP) build/sensor-asic

test-sensor-pc:
	$(PYTHON) -m unittest discover -s test -p test_sensor_tool.py

.PHONY: test-pinout
# ASIC-side wiring invariant independent of firmware or memory model.
test-pinout:
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_pinout_v6 -o build/tb-pinout $(RTL) test/tb_pinout_v6.sv
	$(VVP) build/tb-pinout

.PHONY: test-gpio
# GPIO bidirectional pad boundary tests, no external PSRAM required.
test-gpio:
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_gpio_bidir_v7 -o build/gpio-v7 $(RTL) test/tb_gpio_bidir_v7.sv
	$(VVP) build/gpio-v7

.PHONY: test-irq test-irq-model test-irq-asic test-irq-pc
# V8 test runs the actual firmware+ISR; no hierarchical forcing of CSR state.
firmware: firmware/irq_demo.bin test/irq_demo.hex
firmware/irq_demo.bin: firmware/irq_demo.S firmware/link.ld
	mkdir -p build
	$(CROSS)gcc -march=rv32ec_zicsr -mabi=ilp32e -mno-relax -nostdlib -T firmware/link.ld -o build/irq_demo.elf firmware/irq_demo.S
	$(CROSS)objcopy -O binary build/irq_demo.elf $@
test/irq_demo.hex: firmware/irq_demo.bin tools/bin_to_hex.py
	$(PYTHON) tools/bin_to_hex.py $< $@
test-irq: test-irq-model test-irq-asic test-irq-pc
test-irq-model:
	mkdir -p build
	$(IVERILOG) -g2012 -DIRQ_SMOKE -s tb_v3 -o build/irq-model $(RTL) $(MODELS) ctw_de10_top.sv test/tb_v3.sv
	$(VVP) build/irq-model
test-irq-asic:
	mkdir -p build
	$(IVERILOG) -g2012 -DASIC -DIRQ_SMOKE -DDATASHEET_TIMING -s tb_v3 -o build/irq-asic $(RTL) $(MODELS) test/reference/timed_memory_fixture.sv test/reference/psram_pin_reference.sv test/tb_v3.sv
	$(VVP) build/irq-asic
test-irq-pc:
	$(PYTHON) -m unittest discover -s test -p test_irq_tool.py

.PHONY: gate-irq
gate-irq: synth
	$(IVERILOG) -g2012 -DASIC -DIRQ_SMOKE -DDATASHEET_TIMING -s tb_v3 -o build/gate-irq build/mcu-generic.v $(MODELS) test/reference/timed_memory_fixture.sv test/reference/psram_pin_reference.sv test/tb_v3.sv
	$(VVP) build/gate-irq

# V9: one project / one top; peripherals RTL tests use Icarus if installed.
.PHONY: test-v9-rtl test-v9-host firmware-v9
firmware-v9:
	mkdir -p build
	$(CROSS)gcc $(FLAGS) -T firmware/link.ld -o build/v9_peripherals.elf firmware/startup.S firmware/v9_peripherals.c
	$(CROSS)objcopy -O binary build/v9_peripherals.elf firmware/v9_peripherals.bin
	$(PYTHON) tools/bin_to_hex.py firmware/v9_peripherals.bin test/v9_peripherals.hex

test-v9-rtl:
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_v9_peripherals -o build/v9-peripherals src/ctw_pwm.v src/ctw_i2c_master.v test/tb_v9_peripherals.sv
	$(VVP) build/v9-peripherals

test-v9-host:
	$(PYTHON) -m unittest discover -s test -p test_v9_tool.py

# V10 final pre-PD qualification; source is otherwise unchanged from V9.
.PHONY: firmware-v10-clang test-v10-python test-v10-watchdog test-v10-prepd
firmware-v10-clang:
	mkdir -p build
	clang --target=riscv32-unknown-elf -march=rv32ec_zicsr -mabi=ilp32e -mno-relax -msmall-data-limit=0 -Os -ffreestanding -fno-builtin -fno-stack-protector -fno-unwind-tables -fno-asynchronous-unwind-tables -Wall -Wextra -Werror -nostdlib -fuse-ld=lld -Wl,-T,firmware/link_v10.ld -o build/v10_qualification.elf firmware/startup.S firmware/v10_qualification.c firmware/v10_isa.S
	llvm-objcopy -O binary build/v10_qualification.elf firmware/v10_qualification.bin
	$(PYTHON) tools/bin_to_hex.py firmware/v10_qualification.bin test/v10_qualification.hex

test-v10-python:
	$(PYTHON) -m unittest discover -s test -p 'test_*.py' -v

test-v10-watchdog:
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_v10_watchdog -o build/v10-wdt src/ctw_sys_watchdog.v test/tb_v10_watchdog.sv
	$(VVP) build/v10-wdt

test-v10-prepd: test-v10-python test-v10-watchdog test-v9-rtl test-gpio test-irq-model test-irq-asic test-ram-guard
	@echo 'PRE-PD simulation regression complete; run DE10/ESP32 and PD separately.'

# V10 FENCE liveness regression (Icarus, run before FPGA/P&R)
.PHONY: test-v10-fence
test-v10-fence:
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_fence_decode -o build/v10-fence src/decode.v test/tb_fence_decode.sv
	$(VVP) build/v10-fence

.PHONY: test-v10-csr-rtl
# Requires Icarus Verilog installed on the engineer's machine.
test-v10-csr-rtl:
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_v10_csr_immediate -o build/tb_v10_csr_immediate src/core.v src/register.v src/alu.v src/counter.v test/tb_v10_csr_immediate.sv
	$(VVP) build/tb_v10_csr_immediate

# ISA architectural GPR repair: x3/gp and x4/tp must both be writable.
.PHONY: test-v10-gpr-rtl
test-v10-gpr-rtl:
	mkdir -p build
	$(IVERILOG) -g2012 -s tb_v10_gp_tp_gpr -o build/v10-gpr src/register.v test/tb_v10_gp_tp_gpr.sv
	$(VVP) build/v10-gpr
