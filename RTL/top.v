module top#(
	parameter CLK_FREQ = 50_000_000,
	parameter BAUD     = 115200,
	parameter TIMEOUT = 20 * (CLK_FREQ / BAUD)
)
(
	input clk,
	input rst_n,
	input clear,
	input uart_rx,
	output uart_tx,
	input data_valid_in,
	input [15:0]data_in,
	output [15:0] crc_out
);

	//Internal wires
	//uart
	wire rx_valid,tx_valid, tx_ready;
	wire [7:0] rx_data, tx_data;
	//crc_ctr
	wire bus_16_in, init_ones_in, xor_ones_in;
	wire [15:0] poly_in;
	
	//Mapping
	//uart
	uart #(
		.CLK_FREQ(CLK_FREQ),
		.BAUD(BAUD)
	) u_uart (
		.clk(clk),
		.rst_n(rst_n),
		.uart_rx(uart_rx),
		.uart_tx(uart_tx),
		.rx_data(rx_data),
		.rx_valid(rx_valid),
		.tx_data(tx_data),
		.tx_valid(tx_valid),
		.tx_ready(tx_ready)
	);

	//config_ctrl
	crc_ctrl #(
		.TIMEOUT(TIMEOUT)
    ) u_crc_ctrl (
		.clk(clk),
		.rst_n(rst_n),
		.rx_data(rx_data),
		.rx_valid(rx_valid),
		.tx_data(tx_data),
		.tx_valid(tx_valid),
		.tx_ready(tx_ready),
		.poly_in(poly_in),
		.bus_16_in(bus_16_in),
		.init_ones_in(init_ones_in),
		.xor_ones_in(xor_ones_in)
    );
	 
	//crc_block
	crc_block u_crc_block (
		.clk(clk),
		.clear(clear),
		.poly_in(poly_in),
		.bus_16_in(bus_16_in),
		.init_ones_in(init_ones_in),
		.xor_ones_in(xor_ones_in),
		.data_valid(data_valid_in),
		.data_in(data_in),
		.crc_out(crc_out)
	);

endmodule