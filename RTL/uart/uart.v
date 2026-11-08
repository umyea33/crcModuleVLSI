module uart #(
	parameter CLK_FREQ = 50_000_000,
	parameter BAUD	= 115200
)(
	input clk,
	input rst_n,
	input uart_rx,
	output uart_tx,
	output [7:0] rx_data,
	output rx_valid,
	input [7:0] tx_data,
	input tx_valid,
	output tx_ready
);
	localparam CLKS_PER_BIT = CLK_FREQ / BAUD;

	uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
		.clk(clk),
		.rst_n(rst_n),
		.rx(uart_rx),
		.rx_data(rx_data),
		.rx_valid(rx_valid)
	);

	uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
		.clk(clk),
		.rst_n(rst_n),
		.tx_data(tx_data),
		.tx_valid(tx_valid),
		.tx_ready(tx_ready),
		.uart_tx(uart_tx)
);
	
endmodule