`timescale 1ns / 1ps

// ============================================================================
// top_tb: Testbench for the CRC chip & UART config
// ============================================================================
module top_tb;

	localparam CLK_FREQ_SIM = 1600;
	localparam BAUD_SIM = 100;
	localparam CLKS_PER_BIT = CLK_FREQ_SIM / BAUD_SIM;   // 16
	localparam TIMEOUT_SIM = 20 * CLKS_PER_BIT;	// 320 clocks
	localparam CLK_PERIOD = 10;

	reg clk = 1'b0;
	reg rst_n = 1'b0;
	reg clear = 1'b0;
	reg uart_rx = 1'b1; // idle high
	reg data_valid_in = 1'b0;
	reg [15:0] data_in = 16'h0000;
	wire uart_tx;
	wire [15:0] crc_out;

	top #(
		.CLK_FREQ(CLK_FREQ_SIM),
		.BAUD (BAUD_SIM),
		.TIMEOUT (TIMEOUT_SIM)
	) dut (
		.clk (clk),
		.rst_n (rst_n),
		.clear (clear),
		.uart_rx (uart_rx),
		.uart_tx (uart_tx),
		.data_valid_in(data_valid_in),
		.data_in (data_in),
		.crc_out (crc_out)
	);

	always #(CLK_PERIOD/2) clk = ~clk;

	integer errors = 0;
	integer checks = 0;
	integer seed = 32'h00C0FFEE;
	reg [7:0] msg [0:8];
	reg [15:0] resp16;

	// Background UART monitor to capture bytes sent back on uart_tx
	reg [7:0] tx_got [0:255];
	integer tx_count = 0;
	integer k;
	reg [7:0] tmp;

	initial begin
		@(posedge rst_n);
		forever begin
			@(negedge uart_tx);
			repeat (CLKS_PER_BIT/2) @(posedge clk);
			if (uart_tx === 1'b0) begin
				for (k = 0; k < 8; k = k + 1) begin
					repeat (CLKS_PER_BIT) @(posedge clk);
					tmp[k] = uart_tx;
				end
				repeat (CLKS_PER_BIT) @(posedge clk);
				if (uart_tx !== 1'b1) begin
					$display("ERROR: Bad stop bit detected");
					errors = errors + 1;
				end
				tx_got[tx_count] = tmp;
				tx_count = tx_count + 1;
			end
		end
	end

	// Software reference model for CRC calculations
	function [15:0] ref_byte(input [15:0] crc, input [7:0] b, input [15:0] poly);
		integer i;
		reg [15:0] c;
		begin
			c = crc ^ {b, 8'h00};
			for (i = 0; i < 8; i = i + 1)
			c = c[15] ? ((c << 1) ^ poly) : (c << 1);
			ref_byte = c;
		end
	endfunction

	task wait_clks(input integer n);
		repeat (n) @(negedge clk);
	endtask

	// Serialize and send a single UART byte (LSB first)
	task send_byte(input [7:0] b);
		integer i;
		begin
			uart_rx = 1'b0;
			wait_clks(CLKS_PER_BIT);
			for (i = 0; i < 8; i = i + 1) begin
				uart_rx = b[i];
				wait_clks(CLKS_PER_BIT);
			end
			uart_rx = 1'b1;
			wait_clks(CLKS_PER_BIT);
		end
	endtask

	// Write 16-bit data to a register (0: Poly, 1: Ctrl)
	task uart_write(input [0:0] reg_addr, input [15:0] data);
		begin
			send_byte({1'b1, 6'b000000, reg_addr}); // CMD Byte
			send_byte(data[15:8]);                  // MSB
			send_byte(data[7:0]);                   // LSB
			wait_clks(20);
		end
	endtask

	// Read 16-bit data from a register (0: Poly, 1: Ctrl)
	task uart_read(input [0:0] reg_addr, output [15:0] res);
		integer n0, waited;
		begin
			n0 = tx_count;
			send_byte({1'b0, 6'b000000, reg_addr}); // CMD Byte
			waited = 0;
			// Wait to receive 2 bytes
			while ((tx_count < n0 + 2) && (waited < 60 * CLKS_PER_BIT)) begin
				@(negedge clk);
				waited = waited + 1;
			end
			if (tx_count < n0 + 2) begin
				$display("FAIL: Timeout waiting for 2-byte read response");
				errors = errors + 1;
				res = 16'hxxxx;
			end else begin
				res = {tx_got[n0], tx_got[n0+1]};
			end
		end
	endtask

	task check_res16(input [15:0] got, input [15:0] exp, input [8*32-1:0] label);
		begin
			checks = checks + 1;
			if (got !== exp) begin
				$display("FAIL: %0s (got 0x%04h, expected 0x%04h)", label, got, exp);
				errors = errors + 1;
			end else begin
				$display("PASS: %0s", label);
			end
		end
	endtask

	task pulse_clear;
		begin
			clear = 1'b1;
			@(negedge clk);
			clear = 1'b0;
			@(negedge clk);
		end
	endtask

	task drive_word(input [15:0] w);
		begin
			data_in = w;
			data_valid_in = 1'b1;
			@(negedge clk);
			data_valid_in = 1'b0;
			data_in = 16'h0000;
		end
	endtask

	task check_crc(input [15:0] exp, input [8*32-1:0] label);
		begin
			checks = checks + 1;
			if (crc_out !== exp) begin
				$display("FAIL: %0s (crc_out = 0x%04h, expected 0x%04h)", label, crc_out, exp);
				errors = errors + 1;
			end else begin
				$display("PASS: %0s", label);
			end
		end
	endtask

	// Main Test Sequence Variables
	integer i;
	integer n0_timeout;
	reg [15:0] exp16;
	integer it;
	integer j;
	reg [15:0] poly;
	reg [15:0] w;
	reg [15:0] ref_val;
	reg [2:0] flags;

	initial begin
		$dumpfile("top_tb.vcd");
		$dumpvars(0, top_tb);

		msg[0] = "1"; msg[1] = "2"; msg[2] = "3"; msg[3] = "4"; msg[4] = "5";
		msg[5] = "6"; msg[6] = "7"; msg[7] = "8"; msg[8] = "9";

		$display("\n--- Starting Tests ---");

		// Power-on Reset
		rst_n = 1'b0;
		wait_clks(5);
		rst_n = 1'b1;
		wait_clks(10);

		// 1. Register Write / Readback
		uart_write(1'b0, 16'h1021); 
		uart_read(1'b0, resp16);
		check_res16(resp16, 16'h1021, "Write/Read Poly Register");

		uart_write(1'b1, 16'h0005); 
		uart_read(1'b1, resp16);
		check_res16(resp16, 16'h0005, "Write/Read Control Register");

		// 2. Frame Timeouts
		// Send 1 byte of a 3 byte write sequence and wait. The FSM should timeout and return to IDLE.
		send_byte(8'h80); // Command: Write Poly
		wait_clks(TIMEOUT_SIM + 2 * CLKS_PER_BIT);
		
		// Ensure the FSM recovered by doing a successful read afterwards
		uart_read(1'b0, resp16);
		check_res16(resp16, 16'h1021, "Poly Register intact after write timeout");

		// 3. Test CRC Calculation (XMODEM Equivalent: Poly 1021, Init=0, Xor=0, 8-bit bus)
		uart_write(1'b0, 16'h1021); // Poly
		uart_write(1'b1, 16'h0000); // Control: bus_16=0, init_ones=0, xor_ones=0
		pulse_clear();
		for (i = 0; i < 9; i = i + 1)
			drive_word({8'h00, msg[i]});
		wait_clks(2);
		check_crc(16'h31C3, "XMODEM CRC for '123456789'");

		// 4. 16-bit Bus Mode Check
		uart_write(1'b0, 16'h1021); // Poly
		uart_write(1'b1, 16'h0003); // Control: bus_16=1, init_ones=1, xor_ones=0
		pulse_clear();
		
		exp16 = 16'hFFFF;
		for (i = 0; i < 8; i = i + 1)
			exp16 = ref_byte(exp16, msg[i], 16'h1021);

		for (i = 0; i < 8; i = i + 2)
			drive_word({msg[i], msg[i+1]});
		wait_clks(2);
		check_crc(exp16, "16-bit bus calculation matches reference");

		// 5. Quick Random Regression (3 iterations)
		for (it = 0; it < 3; it = it + 1) begin
			poly  = $random(seed);
			flags = $random(seed) & 3'b111;
			uart_write(1'b0, poly);
			uart_write(1'b1, {13'b0, flags});
			pulse_clear();

			ref_val = flags[1] ? 16'hFFFF : 16'h0000;
			for (j = 0; j < 4; j = j + 1) begin
				w = $random(seed);
				ref_val = flags[0] ? ref_byte(ref_byte(ref_val, w[15:8], poly), w[7:0], poly) : ref_byte(ref_val, w[7:0], poly);
				drive_word(w);
			end
			wait_clks(2);
			if (flags[2]) ref_val = ref_val ^ 16'hFFFF;

			if (crc_out !== ref_val) begin
				$display("FAIL: Random test iteration %0d mismatch", it);
				errors = errors + 1;
			end
		end
		if (errors == 0) $display("PASS: Random regression suite");

		// Final Summary
		$display("\n==============================");
		if (errors == 0)
			$display(" ALL TESTS PASSED (%0d checks)", checks);
		else
			$display(" %0d ERROR(S) ENCOUNTERED", errors);
		$display("==============================\n");
		
		$finish;
	end

endmodule