# SDC constraint for abc timing analysis
create_clock -period 5.0 [get_ports clk]   ;# 200 MHz = 5 ns
set_driving_cell sky130_fd_sc_hd__buf_4
