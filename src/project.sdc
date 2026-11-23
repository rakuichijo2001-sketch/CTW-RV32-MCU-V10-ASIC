# CTW V29 30 MHz single-clock implementation and signoff SDC.
# The design has one clock (clk). Keep the LibreLane baseline clock, I/O,
# drive, loading and derating constraints. Do not declare fake false paths.
# This file replaces the fallback SDC in both PnR and signoff.
create_clock -name clk -period $::env(CLOCK_PERIOD) [get_ports clk]

set input_delay_value [expr {$::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100.0}]
set output_delay_value [expr {$::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100.0}]
set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if {[info exists ::env(MAX_TRANSITION_CONSTRAINT)]} {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
}
if {[info exists ::env(MAX_CAPACITANCE_CONSTRAINT)]} {
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}

set clk_input [get_ports clk]
set data_inputs [all_inputs]
set clk_index [lsearch $data_inputs $clk_input]
if {$clk_index < 0} {
    error "Clock port clk was not found in ASIC inputs"
}
set data_inputs [lreplace $data_inputs $clk_index $clk_index]
set_input_delay $input_delay_value -clock [get_clocks clk] $data_inputs
set_output_delay $output_delay_value -clock [get_clocks clk] [all_outputs]

set input_driver [split $::env(SYNTH_DRIVING_CELL) "/"]
set_driving_cell -lib_cell [lindex $input_driver 0] -pin [lindex $input_driver 1] $data_inputs
if {![info exists ::env(SYNTH_CLK_DRIVING_CELL)]} {
    set ::env(SYNTH_CLK_DRIVING_CELL) $::env(SYNTH_DRIVING_CELL)
}
set clk_driver [split $::env(SYNTH_CLK_DRIVING_CELL) "/"]
set_driving_cell -lib_cell [lindex $clk_driver 0] -pin [lindex $clk_driver 1] $clk_input
set_load [expr {$::env(OUTPUT_CAP_LOAD) / 1000.0}] [all_outputs]
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) [get_clocks clk]
set_clock_transition $::env(CLOCK_TRANSITION_CONSTRAINT) [get_clocks clk]

set_timing_derate -early [expr {1.0 - $::env(TIME_DERATING_CONSTRAINT) / 100.0}]
set_timing_derate -late  [expr {1.0 + $::env(TIME_DERATING_CONSTRAINT) / 100.0}]

if {[info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS)} {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}
