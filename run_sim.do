# Create and map the working library
vlib work
vmap work work

# Compile the RTL design files
vlog -work work RTL/top.v
vlog -work work RTL/uart/uart.v
vlog -work work RTL/uart/uart_rx.v
vlog -work work RTL/uart/uart_tx.v
vlog -work work RTL/control_unit.v
vlog -work work RTL/crc/crc.v

# Compile the Testbench
vlog -work work Testbenches/top_tb.v

# Load the simulation with visibility access for waveforms (+acc) and stop instead of exiting on $finish
vsim -voptargs="+acc" -onfinish stop work.top_tb

# Configure Waveform Viewer
view wave
delete wave *

# Add signals to the waveform viewer
add wave -divider "Top Level IO"
add wave -hex sim:/top_tb/clk
add wave -hex sim:/top_tb/rst_n
add wave -hex sim:/top_tb/clear
add wave -hex sim:/top_tb/uart_rx
add wave -hex sim:/top_tb/uart_tx
add wave -hex sim:/top_tb/data_valid_in
add wave -hex sim:/top_tb/data_in
add wave -hex sim:/top_tb/crc_out

add wave -divider "Control Unit (UART FSM)"
add wave -hex sim:/top_tb/dut/u_crc_ctrl/state
add wave -hex sim:/top_tb/dut/u_crc_ctrl/rx_valid
add wave -hex sim:/top_tb/dut/u_crc_ctrl/rx_data
add wave -hex sim:/top_tb/dut/u_crc_ctrl/poly_in
add wave -hex sim:/top_tb/dut/u_crc_ctrl/ctrl_reg

add wave -divider "CRC Block Math"
add wave -hex sim:/top_tb/dut/u_crc_block/crc_reg
add wave -hex sim:/top_tb/dut/u_crc_block/temp_crc

# Format the wave window
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1

# Run the simulation
run -all

# Zoom full to see the whole simulation
wave zoom full
