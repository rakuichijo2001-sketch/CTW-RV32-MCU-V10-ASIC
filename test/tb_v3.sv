`timescale 1ns/1ps
module tb_v3 #(parameter integer TEST_PAD_NS=30);
`ifdef ASIC
    // Match 30 MHz ASIC clock (33.333... ns) configured in info.yaml/src/config.json.
    localparam real CLK_NS=1000.0/30.0;
    localparam MODEL=0, ASIC_MODE=1;
`elsif EXTERNAL
    localparam integer CLK_NS=20;
    localparam MODEL=0, ASIC_MODE=0;
`else
    localparam integer CLK_NS=20;
    localparam MODEL=1, ASIC_MODE=0;
`endif
    reg clk=0;
    always #(CLK_NS/2) clk=!clk;
    reg [1:0] key=2'b11;
`ifdef ASIC
    // Sensor data must not affect QSPI phase selection during reset.
    // Deliberately start with 111 to guard against the former V28 hazard.
    reg [2:0] sensor_d=3'b111;
`ifdef DATASHEET_TIMING
    // Explicit boot-only ui_in[1] strap, independent from sensor_data.
    // 0/10 ns pad cases use phase 001; 30 ns uses phase 010.
    reg short_pad_strap=(TEST_PAD_NS<20);
`else
    reg short_pad_strap=1'b1; // zero-delay fixture uses phase 001
`endif
`else
    reg [2:0] sensor_d=3'b000;
    reg short_pad_strap=1'b0; // ignored by the DE10 FPGA wrapper
`endif
    reg sensor_rx=1;
    wire sensor_tx;
    reg rst_n=0, ena=0, fixture_power=0;
    tri [7:0] bus;
    pullup(bus[0]); pullup(bus[6]); pullup(bus[7]);
    pulldown(bus[3]);
    reg [7:0] host_o=0, host_oe=0;
    wire [7:0] led, mcu_oe, mcu_o, pad_oe;
    wire ram_a_cs_n, ram_b_cs_n;
    wire [3:0] return_oe;
    wire fcs=bus[0], sck=bus[3], acs=bus[6], bcs=bus[7];
    wire [3:0] model_data, model_flash, model_flash_oe;
    wire xip, qpi_a, qpi_b;
    genvar i;
    generate for (i=0;i<8;i=i+1) begin: host_pads
        assign bus[i]=host_oe[i] ? host_o[i] : 1'bz;
    end endgenerate
`ifdef ASIC
    wire [7:0] uo;
`ifdef GL_TEST
    // Gate-level power ports are inout: connect nets, not constant expressions.
    supply1 vpwr;
    supply0 vgnd;
`endif
    tt_um_ctw_rv32_mcu dut(
`ifdef GL_TEST
        .VPWR(vpwr),.VGND(vgnd),
`endif
        .ui_in({sensor_rx,sensor_d,2'b0,short_pad_strap,!key[1]}),.uio_in(bus),.uo_out(uo),.uio_out(mcu_o),
        .uio_oe(mcu_oe),.ena(ena),.clk(clk),.rst_n(rst_n && key[0])
    );
    // ASIC GPIO outputs 0..4 are observable, while uo[5:6] are the RAM
    // chip-selects and uo[7] is UART TX. LED is a testbench-only mirror.
    assign led={3'b000,uo[4:0]};
    assign sensor_tx=uo[7];
    assign ram_a_cs_n=uo[5];
    assign ram_b_cs_n=uo[6];
    assign pad_oe=mcu_oe;
    assign bus[6]=ram_a_cs_n;
    assign bus[7]=ram_b_cs_n;
    generate for(i=0;i<6;i=i+1) begin: mcu_pads
        assign bus[i]=mcu_oe[i] ? mcu_o[i] : 1'bz;
    end endgenerate
`else
    ctw_de10_top #(.MODEL_MEMORIES(MODEL)) dut(
        .CLOCK_50(clk),.KEY(key),.ESP_RST_N(rst_n),.SENSOR_D(sensor_d),
        .SENSOR_RX(sensor_rx),.SENSOR_TX(sensor_tx),
        .RAM_A_CS_N(ram_a_cs_n),.RAM_B_CS_N(ram_b_cs_n),
        .LED(led),.JP1_QSPI(bus[5:0])
    );
    assign bus[6]=ram_a_cs_n;
    assign bus[7]=ram_b_cs_n;
    assign mcu_oe=dut.mcu_oe;
    assign mcu_o=dut.mcu_o;
    assign pad_oe=dut.pad_oe;
`ifndef EXTERNAL
    assign xip=dut.model_memories.memory.flash_xip;
    assign qpi_a=dut.model_memories.memory.qpi_a;
    assign qpi_b=dut.model_memories.memory.qpi_b;
`endif
`endif
    generate if (!MODEL) begin: fixture
        wire [3:0] captured_dq={bus[5:4],bus[2:1]};
        wire [3:0] master_oe={mcu_oe[5:4],mcu_oe[2:1]};
`ifdef DATASHEET_TIMING
        ctw_timed_memory_fixture #(.PAD_NS(TEST_PAD_NS)) memories (
            .power_n(fixture_power), .cpu_sck(sck), .cpu_fcs(fcs), .cpu_acs(acs), .cpu_bcs(bcs),
            .cpu_dq({mcu_o[5:4],mcu_o[2:1]}), .cpu_dq_oe(master_oe), .from_mem(model_data), .from_mem_oe(return_oe),
            .flash_xip(xip), .qpi_a(qpi_a), .qpi_b(qpi_b), .flash_qe()
        );
`else
        ctw_memory_models memories (
            .clk(clk),.power_n(fixture_power),.sck(sck),.fcs(fcs),.acs(acs),.bcs(bcs),
            .master_dq(captured_dq),.master_oe(master_oe),.flash_dq(model_flash),
            .flash_oe(model_flash_oe),.data_to_master(model_data),
            .flash_xip(xip),.qpi_a(qpi_a),.qpi_b(qpi_b),.flash_image(),.flash_busy()
        );
        assign return_oe=!fcs ? model_flash_oe :
                         ((!acs && qpi_a) || (!bcs && qpi_b)) ? ~master_oe : 4'h0;
`endif
        for(i=0;i<4;i=i+1) begin: reply_pads
            localparam integer PIN=i<2 ? i+1 : i+2;
            assign bus[PIN]=return_oe[i] ? model_data[i] : 1'bz;
        end
    end else begin
        assign return_oe=4'h0;
    end endgenerate

    reg [7:0] a[0:2047], b[0:2047];
    localparam integer SIZE=808;
    localparam integer HALF=250; // 2 MHz host SPI
    localparam [7:0] MOSI_OE=8'h3b, DQ_MASK=8'h36;
    integer selected_ram_cycles=0, longest_ram_cycles=0;

    always @(negedge clk) begin
        if (fixture_power) begin
            if (mcu_oe[7:6]!==2'b00)
                $fatal(1,"Former PSRAM CS pads uio[7:6] must always be high-Z");
            if ((host_oe & pad_oe)!==8'h0 ||
                (return_oe & {mcu_oe[5:4]|host_oe[5:4],mcu_oe[2:1]|host_oe[2:1]})!==4'h0)
                $fatal(1,"Pad contention: host_oe=%h pad_oe=%h return=%h",host_oe,pad_oe,return_oe);
            if (host_oe!=0 && (rst_n || host_oe[7:6]!=0))
                $fatal(1,"ESP used forbidden pins or drove outside of reset");
            if (!rst_n || !key[0]) begin
                if (mcu_oe !== 8'h00 || {bcs,acs}!==2'b11)
                    $fatal(1,"MCU owns wrong pins during reset: %h",mcu_oe);
            end
            if ((!fcs && !acs) || (!fcs && !bcs) || (!acs && !bcs))
                $fatal(1,"Overlapping memory selects");
            if (!acs || !bcs) begin
                selected_ram_cycles=selected_ram_cycles+1;
                if (selected_ram_cycles>longest_ram_cycles) longest_ram_cycles=selected_ram_cycles;
                if (selected_ram_cycles*CLK_NS>=6000) $fatal(1,"PSRAM exceeds 6 us guard budget");
            end else selected_ram_cycles=0;
        end
    end

    task assert_reset;
        begin
            @(negedge clk); #2 rst_n=0;
            #1;
            if (mcu_oe!==8'h00 || {bcs,acs}!==2'b11)
                $fatal(1,"Asynchronous reset did not release pins: %02x",mcu_oe);
        end
    endtask
    task idle_bus;
        begin
            host_o=8'h31; host_oe=MOSI_OE; #(HALF*2);
        end
    endtask
    task select_cs(input integer cs);
        begin host_o[cs]=0; #(HALF*2); end
    endtask
    task deselect_cs(input integer cs);
        begin host_o[cs]=1; #(HALF*2); end
    endtask
    task pulse;
        begin #(HALF); host_o[3]=1; #(HALF); host_o[3]=0; end
    endtask
    task xfer(input [7:0] tx, output reg [7:0] rx);
        begin
            for (integer k=7;k>=0;k=k-1) begin
                host_o[1]=tx[k];
                #(HALF); rx[k]=bus[2]; host_o[3]=1;
                #(HALF); host_o[3]=0;
            end
        end
    endtask
    task put(input [7:0] data);
        reg [7:0] discard;
        begin xfer(data,discard); end
    endtask
    task quad(input [3:0] data);
        begin host_o[5:4]=data[3:2];host_o[2:1]=data[1:0];pulse(); end
    endtask
    task command(input integer cs, input [7:0] op);
        begin select_cs(cs);put(op);deselect_cs(cs); end
    endtask
    task address(input integer addr);
        begin put(addr[23:16]);put(addr[15:8]);put(addr[7:0]); end
    endtask
    task get_status(output reg [7:0] sr);
        begin select_cs(0);put(8'h05);xfer(0,sr);deselect_cs(0);end
    endtask
    task await_flash;
        reg [7:0] sr;
        begin
            sr=1;
            for (integer k=0;k<512 && sr[0];k=k+1) get_status(sr);
            if (sr[0]!==0) $fatal(1,"WIP timeout");
        end
    endtask

    task check_led(input [7:0] expected);
        begin
            for (integer k=0;k<450000 &&
                 (ASIC_MODE ? led[4:0]!==expected[4:0] : led!==expected);
                 k=k+1) @(negedge clk);
            if ((ASIC_MODE ? led[4:0]!==expected[4:0] : led!==expected))
                $fatal(1,"LED %02x expected %02x, XIP=%b QPI=%b%b",led,expected,xip,qpi_a,qpi_b);
        end
    endtask
    task program_and_run(input bit image_b, input [7:0] expected);
        reg [7:0] v;
        begin
            assert_reset();
            repeat(100) @(negedge clk);
            idle_bus();
            host_oe=MOSI_OE|DQ_MASK;
            select_cs(0);repeat(8) quad(4'hf);deselect_cs(0);host_oe=MOSI_OE;

            select_cs(0);put(8'h9f);xfer(0,v);if(v!==8'hef)$fatal(1,"JEDEC0 %h",v);
            xfer(0,v);if(v!==8'h70)$fatal(1,"JEDEC1 %h",v);
            xfer(0,v);if(v!==8'h18)$fatal(1,"JEDEC2 %h",v);deselect_cs(0);

            // A NOR cannot program if WREN was not issued.
            select_cs(0);put(8'h02);address(0);put(0);deselect_cs(0);
            get_status(v);
            if (v[0]!==0) $fatal(1,"Page Program accepted without WREN");

            command(0,8'h06);
            get_status(v);if(v[1]!==1)$fatal(1,"WEL missing");
            select_cs(0);put(8'h20);address(0);deselect_cs(0);
            get_status(v);if(v[0]!==1)$fatal(1,"Erase failed to set WIP");
            await_flash();
            select_cs(0);put(8'h03);address(0);xfer(0,v);deselect_cs(0);
            if(v!==8'hff)$fatal(1,"Erase did not restore FF");

            for (integer k=0;k<SIZE;k=k+256) begin
                command(0,8'h06);
                select_cs(0);put(8'h02);address(k);
                for(integer j=k;j<k+256 && j<SIZE;j=j+1)
                    put(image_b ? b[j] : a[j]);
                deselect_cs(0);await_flash();
            end
            // Programming FF without an erase must not restore a cleared bit.
            command(0,8'h06);
            select_cs(0);put(8'h02);address(0);put(8'hff);deselect_cs(0);await_flash();
            select_cs(0);put(8'h03);address(0);
            for(integer j=0;j<SIZE;j=j+1) begin
                xfer(0,v);
                if(v!==(image_b ? b[j] : a[j]))
                    $fatal(1,"SPI readback mismatch at %0d got %02x expected %02x",j,v,image_b ? b[j] : a[j]);
            end
            deselect_cs(0);
            $display("PASS image %s: JEDEC, WREN/WIP, erase, NOR 1-to-0 writes and full %0d-byte SPI readback",
                     image_b ? "B":"A",SIZE);


            host_oe=0;
            #(HALF*4);
            rst_n=1;
            check_led(expected);
            if ({xip,qpi_a,qpi_b}!==3'b111)
                $fatal(1,"MCU did not initialize all three memories");
            key[1]=0;check_led(expected|8'h02);
            key[1]=1;check_led(expected);
            key[0]=0;
            check_led(ASIC_MODE ? 8'h00 : 8'h02);
            key[0]=1;check_led(expected);
            $display("PASS image %s: automatic warm-memory init and LED=%02x after upload and KEY0 reset",
                     image_b ? "B":"A",expected);
        end
    endtask

    localparam integer UART_NS=8680;
    task uart_request(input [7:0] command_byte);
        begin
            sensor_rx=0; #UART_NS;
            for (integer i=0; i<8; i=i+1) begin sensor_rx=command_byte[i]; #UART_NS; end
            sensor_rx=1; #UART_NS;
        end
    endtask
    task uart_byte(output reg [7:0] value);
        begin
            @(negedge sensor_tx);
            #(UART_NS/2);
            if (sensor_tx!==0) $fatal(1,"invalid UART start bit");
            for (integer i=0; i<8; i=i+1) begin #UART_NS; value[i]=sensor_tx; end
            #UART_NS;
            if (sensor_tx!==1) $fatal(1,"invalid UART stop bit");
        end
    endtask
`ifdef IRQ_SMOKE
`ifdef FIRST_FETCH_CHECK
`ifdef ASIC
    // Fast timed-Flash correctness check before the 120ms IRQ test.
    // The IRQ image starts with 0x00c0006f (JAL +12).
    // The real flash fixture must return the first two little-endian halfwords
    // 006f, 00c0. A bad SPI read phase previously returned z6z6/f0z6.
    initial begin : irq_first_fetch_check
        wait(dut.soc.boot_ready === 1'b1);
        @(posedge dut.soc.mcu_i.cpu_i.instr_ready);
        #1;
        if (dut.soc.mcu_i.cpu_i.instr_data !== 16'h006f)
            $fatal(1, "IRQ_FLASH_FIRST wrong first halfword %h (expected 006f)",
                dut.soc.mcu_i.cpu_i.instr_data);
        @(posedge dut.soc.mcu_i.cpu_i.instr_ready);
        #1;
        if (dut.soc.mcu_i.cpu_i.instr_data !== 16'h00c0)
            $fatal(1, "IRQ_FLASH_FIRST wrong second halfword %h (expected 00c0)",
                dut.soc.mcu_i.cpu_i.instr_data);
        // Redirect at JAL can cause another transaction before the device
        // releases its QSPI outputs. Existing contention asserts remain live.
        #300000;
        $display("PASS IRQ_FLASH_FIRST: correct JAL halfwords and no early QSPI contention");
        $finish;
    end
    initial begin
        #7500000;
        $fatal(1, "IRQ_FLASH_FIRST timeout waiting for Flash fetch");
    end
`endif
`endif
    task expect_irq(input [7:0] expected);
        reg [7:0] observed;
        begin
            uart_byte(observed);
            if (observed !== expected)
                $fatal(1,"IRQ expected %h, got %h",expected,observed);
        end
    endtask
    task irq_sequence;
        begin
            // Timer event latches while globally masked; ISR runs after unmask.
            expect_irq("T"); expect_irq("X"); expect_irq("R");
            check_led(8'h18);
            for (integer n=0;n<4;n=n+1) begin
                sensor_d=1; expect_irq("H");
                sensor_d=0; expect_irq("L");
                fork
                    uart_request(8'h61+n);
                    expect_irq(8'h41+n);
                join
            end
            // No spurious retriggers after clearing GPIO/timer and masking TX.
            fork : silence_check
                begin #500000; end
                begin @(negedge sensor_tx); $fatal(1,"Unexpected IRQ UART response"); end
            join_any
            disable silence_check;
        end
    endtask
    initial begin
        #1;
`ifdef ASIC
        $readmemh("test/irq_demo.hex",fixture.memories.flash_i.flash,0,2047);
`else
        $readmemh("test/irq_demo.hex",dut.model_memories.memory.flash_i.flash,0,2047);
`endif
        #3000; fixture_power=1; ena=1; sensor_d=0;
        #1000; rst_n=1;
        irq_sequence();
        assert_reset();
        #1000; rst_n=1;
        irq_sequence();
        $display("PASS IRQ: timer pending while masked, TX, GPIO rising/falling, RX, MRET and warm reset");
        $finish;
    end
`elsif SENSOR_SMOKE
    task sample(input [2:0] value);
        reg [7:0] marker, raw, result, checksum;
        reg [7:0] expected;
        begin
            sensor_d=value;
            #20000;
            expected=3*value+7;
            fork
                uart_request("S");
                begin
                    uart_byte(marker);
                    uart_byte(raw);
                    uart_byte(result);
                    uart_byte(checksum);
                end
            join
            if (marker!==8'ha5 || raw!=={5'b0,value} || result!==expected ||
                checksum!==(8'ha5^{5'b0,value}^expected))
                $fatal(1,"sensor frame mismatch: sent %d, got %h %h %h %h",value,marker,raw,result,checksum);
            check_led(8'ha0 | {4'b0,value,1'b0});
            $display("PASS sensor %d -> %d via UART",value,expected);
        end
    endtask
    initial begin
        #1;
        $readmemh("test/sensor_demo.hex",fixture.memories.flash_i.flash,0,2047);
        #3000; fixture_power=1; ena=1;
        // Verify that all-high sensor data during reset no longer overrides
        // the independently strapped 30 ns QSPI read phase.
        sensor_d=7;
        #1000; rst_n=1;
        #8000000; // let the on-chip boot FSM finish before checking GPIO=0
        check_led(8'ha0);
        sample(7); sample(0); sample(1); sample(6);
        sample(2); sample(5); sample(3); sample(4);
        // Demonstrate a second boot with a nonzero setting on the reclaimed pins.
        sensor_d=5;
        assert_reset();
        #1000; rst_n=1;
        #8000000; // let the on-chip boot FSM finish before checking GPIO=0
        check_led(8'ha0);
        sample(5);
        $display("PASS SENSOR_SMOKE 8 patterns plus reset at 30 MHz, modeled I/O delay %0d ns each way",TEST_PAD_NS);
        $finish;
    end
`elsif GATE_SMOKE
    // Keep full-duration cold and warm boot, but use an offline preloaded
    // fixture in gate simulations instead of resending both binaries at 2 MHz.
    initial begin
        #1;
        `ifdef DATASHEET_TIMING
        $readmemh("test/smoke_timing.hex",fixture.memories.flash_i.flash,0,2047);
`else
        $readmemh("test/smoke_a.hex",fixture.memories.flash_i.flash,0,2047);
`endif
        #3000;fixture_power=1;
        if (mcu_oe!==8'h00) $fatal(1,"TT disabled with bus drive still on");
        ena=1;
        #1000;rst_n=1;
        check_led(8'ha4);
        if ({xip,qpi_a,qpi_b}!==3'b111) $fatal(1,"Cold boot modes not set");
        assert_reset();
        #1000;rst_n=1;
        check_led(8'ha4);
        if ({xip,qpi_a,qpi_b}!==3'b111) $fatal(1,"Warm boot modes not set");
        @(negedge clk);#2 ena=0;#1;
        if (mcu_oe!==0) $fatal(1,"TT ena low fails to release bus");
`ifdef DATASHEET_TIMING
        $display("PASS pin timing with %0d ns transport in each direction", TEST_PAD_NS);
`endif
        $display("PASS V6 gate: cold and warm boot, dual PSRAM, async reset and ena, max PSRAM CS-low %0d ns",
                 longest_ram_cycles*CLK_NS);
        $finish;
    end
`else
    initial begin
        $readmemh("test/smoke_a.hex",a);
        $readmemh("test/smoke_b.hex",b);
        #3000;fixture_power=1;
        if (ASIC_MODE && mcu_oe!==8'b0) $fatal(1,"Asserting reset and disabling TT must release all IO");
        ena=1;
        #1000;rst_n=1;
        if (!ASIC_MODE) check_led(8'he0); // blank flash, no invalid code runs
        else #6350000;
        program_and_run(0,8'ha4);
        wait(!fcs); // request reset in the middle of a Flash fetch for A
        program_and_run(1,8'h58);
        if (!MODEL) begin
            // Model power cycle drops Flash volatile QE/XIP and PSRAM QPI,
            // while the NOR array remains. No ESP is present.
            assert_reset();
            fixture_power=0; #10000; fixture_power=1;
            #1000;rst_n=1;
            check_led(8'h58);
            if ({xip,qpi_a,qpi_b}!==3'b111)
                $fatal(1,"Cold memory boot mode missing");
            $display("PASS cold-memory reboot from retained Flash image without a programmer");
        end
        if (ASIC_MODE) begin
            @(negedge clk);#2 ena=0;#1;
            if (mcu_oe!==0) $fatal(1,"TT ena low fails to release bus");
            #300;ena=1;check_led(8'h58);
        end
        $display("PASS V6 model=%0d asic=%0d, max PSRAM CS-low %0d ns",
                 MODEL,ASIC_MODE,longest_ram_cycles*CLK_NS);
        $finish;
    end
`endif
    initial begin #120000000;$fatal(1,"Timeout LED=%02x",led); end
endmodule
