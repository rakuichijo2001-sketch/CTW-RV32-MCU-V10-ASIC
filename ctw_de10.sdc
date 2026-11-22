create_clock -name clk50 -period 20.000 [get_ports {CLOCK_50}]
# Board reset / KEY0 assert asynchronously. Arbiters have synchronized release.
set_false_path -from [get_ports {KEY[*] ESP_RST_N}]
set_false_path -to [get_ports {LED[*]}]
# JP1 timing depends on MODEL_MEMORIES and the attached fixture. No claim of
# board-level I/O timing signoff is made by this clock-only starter constraint.
# Asynchronous GPIO input and UART serial I/O
set_false_path -from [get_ports {SENSOR_D[*] SENSOR_RX}]
set_false_path -to [get_ports SENSOR_TX]
