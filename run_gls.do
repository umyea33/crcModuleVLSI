# Create and map the working library
vlib work
vmap work work

# Compile the standard cell simulation library
vlog -work work /research/ece/lnis-teaching/Designkits/tsmc180nm/full_custom_lib/verilog/sclib_tsmc180.v

# Compile the Synthesized Netlist
vlog -work work RTL/top_netlist.v

# Compile the Testbench with the GATE_LEVEL macro defined
vlog -work work +define+GATE_LEVEL Testbenches/top_tb.v

# Load the simulation with visibility access for waveforms (+acc)
# Note: For gate-level simulations, you might also need to pass SDF files 
# if you are doing timing-annotated simulations (e.g., -sdfmax /dut=top.sdf)
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

add wave -divider "Internal Netlist Nodes"
# These replaced ctrl_reg[2:0] during synthesis
add wave -hex sim:/top_tb/dut/u_crc_ctrl/bus_16_in
add wave -hex sim:/top_tb/dut/u_crc_ctrl/init_ones_in
add wave -hex sim:/top_tb/dut/u_crc_ctrl/xor_ones_in

# The remaining signals might be optimized or flattened
add wave -hex sim:/top_tb/dut/u_crc_ctrl/rx_valid
add wave -hex sim:/top_tb/dut/u_crc_ctrl/rx_data
add wave -hex sim:/top_tb/dut/u_crc_ctrl/poly_in

# Format the wave window
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1

# Run the simulation
run -all

# Zoom full to see the whole simulation
wave zoom full
