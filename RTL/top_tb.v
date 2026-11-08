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

	localparam [7:0] KEY = 8'hA5;
	localparam [7:0] ACK = 8'h06;
	localparam [7:0] NAK = 8'h15;

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
	reg [7:0] resp;

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

	// Send a 3-byte command frame [ADDR] [DATA] [CHK] and wait for response
	task xfer_raw(input [7:0] addr, input [7:0] data, input [7:0] chk);
		integer n0, waited;
		begin
			n0 = tx_count;
			send_byte(addr);
			send_byte(data);
			send_byte(chk);
			waited = 0;
			while (tx_count == n0 && waited < 40 * CLKS_PER_BIT) begin
				@(negedge clk);
				waited = waited + 1;
			end
			if (tx_count == n0) begin
				$display("FAIL: Timeout waiting for response to frame %02h %02h %02h", addr, data, chk);
				errors = errors + 1;
				resp = 8'hxx;
			end else
				resp = tx_got[n0];
		end
	endtask

	task xfer(input [7:0] addr, input [7:0] data);
	xfer_raw(addr, data, addr ^ data ^ KEY);
	endtask

	task check_res(input [7:0] got, input [7:0] exp, input [8*32-1:0] label);
		begin
		checks = checks + 1;
		if (got !== exp) begin
			$display("FAIL: %0s (got 0x%02h, expected 0x%02h)", label, got, exp);
			errors = errors + 1;
		end else
			$display("PASS: %0s", label);
		end
	endtask

	task wr(input [1:0] r, input [7:0] data, input [8*32-1:0] label);
		begin
			xfer({6'b000000, r}, data);
			check_res(resp, ACK, label);
		end
	endtask

	task rd(input [1:0] r, input [7:0] exp, input [8*32-1:0] label);
		begin
			xfer({6'b100000, r}, 8'h00);
			check_res(resp, exp, label);
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
			end else
				$display("PASS: %0s", label);
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
		wr(2'd0, 8'h05, "Write FLAGS");
		rd(2'd0, 8'h05, "Read FLAGS");
		wr(2'd1, 8'h21, "Write POLY_L");
		wr(2'd2, 8'h10, "Write POLY_H");
		rd(2'd1, 8'h21, "Read POLY_L");
		rd(2'd2, 8'h10, "Read POLY_H");

		// 2. Bad Frames & Error Rejections
		xfer_raw(8'h01, 8'h55, 8'hFF); // Bad checksum
		check_res(resp, NAK, "Bad checksum returns NAK");
		rd(2'd1, 8'h21, "POLY_L preserved after bad frame");

		xfer(8'h04, 8'h00); // Illegal address bit [2]
		check_res(resp, NAK, "Illegal address returns NAK");

		// 3. Frame Timeouts
		n0_timeout = tx_count;
		send_byte(8'h01); // Send ADDR only, drop rest
		wait_clks(TIMEOUT_SIM + 2 * CLKS_PER_BIT);
		if (tx_count != n0_timeout) begin
			$display("FAIL: Chip responded to incomplete frame");
			errors = errors + 1;
		end else
			$display("PASS: Timeout handled cleanly (no response)");

		// 4. Test Preset XMODEM (Preset 0)
		xfer(8'h03, 8'h00); // Load preset 0, 8-bit bus
		check_res(resp, ACK, "Load Preset 0");
		pulse_clear();
		for (i = 0; i < 9; i = i + 1)
			drive_word({8'h00, msg[i]});
		wait_clks(2);
		check_crc(16'h31C3, "Preset 0 CRC for '123456789'");

		// 5. 16-bit Bus Mode Check
		wr(2'd1, 8'h21, "Set poly low for 16-bit test");
		wr(2'd2, 8'h10, "Set poly high for 16-bit test");
		wr(2'd0, 8'h03, "Set FLAGS: 16-bit bus + init ones");
		pulse_clear();
        
		exp16 = 16'hFFFF;
		for (i = 0; i < 8; i = i + 1)
			exp16 = ref_byte(exp16, msg[i], 16'h1021);

		for (i = 0; i < 8; i = i + 2)
			drive_word({msg[i], msg[i+1]});
		wait_clks(2);
		check_crc(exp16, "16-bit bus calculation matches reference");

		// 6. Quick Random Regression (3 iterations)
		for (it = 0; it < 3; it = it + 1) begin
			poly  = $random(seed);
			flags = $random(seed);
			xfer(8'h01, poly[7:0]);
			xfer(8'h02, poly[15:8]);
			xfer(8'h00, {5'b0, flags});
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