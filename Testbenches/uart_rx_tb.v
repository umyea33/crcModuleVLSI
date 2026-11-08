`timescale 1ns / 1ps

module uart_rx_tb;

    localparam CLKS_PER_BIT = 16;   // tiny value so waveforms are short
    localparam CLK_PERIOD   = 10;

    reg        clk   = 1'b0;
    reg        rst_n = 1'b0;
    reg        rx    = 1'b1;        // idle line is high
    wire [7:0] rx_data;
    wire       rx_valid;

    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) dut (
        .clk     (clk),
        .rst_n   (rst_n),
        .rx      (rx),
        .rx_data (rx_data),
        .rx_valid(rx_valid)
    );

    always #(CLK_PERIOD/2) clk = ~clk;

    // ------------------------------------------------------------
    // Monitor: records every byte the DUT reports, and checks that
    // rx_valid is never high for two clocks in a row.
    // ------------------------------------------------------------
    integer    errors   = 0;
    integer    rx_count = 0;
    reg [7:0]  got [0:63];
    reg        prev_valid = 1'b0;

    always @(posedge clk) begin
        if (rx_valid) begin
            got[rx_count] = rx_data;
            rx_count      = rx_count + 1;
            if (prev_valid) begin
                $display("ERROR @%0t: rx_valid high for more than one clock", $time);
                errors = errors + 1;
            end
        end
        prev_valid = rx_valid;
    end

    // ------------------------------------------------------------
    // Helpers (all timing on negedge so we never race the DUT's posedge)
    // ------------------------------------------------------------
    task wait_clks(input integer n);
        begin
            repeat (n) @(negedge clk);
        end
    endtask

    // Standard frame: start bit, 8 data bits LSB first, stop bit
    task send_byte(input [7:0] b);
        integer i;
        begin
            rx = 1'b0;                       // start bit
            wait_clks(CLKS_PER_BIT);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];                   // LSB first
                wait_clks(CLKS_PER_BIT);
            end
            rx = 1'b1;                       // stop bit
            wait_clks(CLKS_PER_BIT);
        end
    endtask

    // Same frame, but the stop bit is low (framing error)
    task send_byte_bad_stop(input [7:0] b);
        integer i;
        begin
            rx = 1'b0;
            wait_clks(CLKS_PER_BIT);
            for (i = 0; i < 8; i = i + 1) begin
                rx = b[i];
                wait_clks(CLKS_PER_BIT);
            end
            rx = 1'b0;                       // BAD stop bit
            wait_clks(CLKS_PER_BIT);
            rx = 1'b1;                       // return to idle
        end
    endtask

    // Short low pulse, shorter than half a bit: should be rejected
    task send_glitch;
        begin
            rx = 1'b0;
            wait_clks(CLKS_PER_BIT/4);
            rx = 1'b1;
        end
    endtask

    // Check that byte number `idx` equals `exp`
    task check_byte(input integer idx, input [7:0] exp);
        begin
            if (idx >= rx_count) begin
                $display("FAIL: byte %0d never arrived (expected 0x%02h)", idx, exp);
                errors = errors + 1;
            end else if (got[idx] !== exp) begin
                $display("FAIL: byte %0d got 0x%02h, expected 0x%02h", idx, got[idx], exp);
                errors = errors + 1;
            end else begin
                $display("PASS: byte %0d = 0x%02h", idx, got[idx]);
            end
        end
    endtask

    // ------------------------------------------------------------
    // Test sequence
    // ------------------------------------------------------------
    integer count_before;

    initial begin
        $dumpfile("uart_rx_tb.vcd");
        $dumpvars(0, uart_rx_tb);

        // Reset
        rx = 1'b1;
        wait_clks(5);
        rst_n = 1'b1;
        wait_clks(10);

        // Test 1: single bytes, spaced out. 0x01 and 0x80 expose a backwards shift.
        send_byte(8'h01);  wait_clks(CLKS_PER_BIT * 2);
        send_byte(8'h80);  wait_clks(CLKS_PER_BIT * 2);
        send_byte(8'hA5);  wait_clks(CLKS_PER_BIT * 2);
        send_byte(8'h5A);  wait_clks(CLKS_PER_BIT * 2);
        send_byte(8'hFF);  wait_clks(CLKS_PER_BIT * 2);
        send_byte(8'h00);  wait_clks(CLKS_PER_BIT * 2);

        check_byte(0, 8'h01);
        check_byte(1, 8'h80);
        check_byte(2, 8'hA5);
        check_byte(3, 8'h5A);
        check_byte(4, 8'hFF);
        check_byte(5, 8'h00);

        // Test 2: back-to-back bytes, no idle gap between frames
        send_byte(8'h3C);
        send_byte(8'hC3);
        send_byte(8'h96);
        wait_clks(CLKS_PER_BIT * 2);

        check_byte(6, 8'h3C);
        check_byte(7, 8'hC3);
        check_byte(8, 8'h96);

        // Test 3: glitch (low for less than half a bit) must be ignored
        count_before = rx_count;
        send_glitch;
        wait_clks(CLKS_PER_BIT * 12);
        if (rx_count != count_before) begin
            $display("FAIL: glitch was accepted as a byte (got 0x%02h)", got[rx_count-1]);
            errors = errors + 1;
        end else
            $display("PASS: glitch ignored");

        // Test 4: bad stop bit must NOT produce a byte
        count_before = rx_count;
        send_byte_bad_stop(8'hA5);
        wait_clks(CLKS_PER_BIT * 12);
        if (rx_count != count_before) begin
            $display("FAIL: framing error still produced %0d byte(s), last = 0x%02h",
                     rx_count - count_before, got[rx_count-1]);
            errors = errors + 1;
        end else
            $display("PASS: bad stop bit rejected");

        // Test 5: receiver still works after the error cases
        send_byte(8'h7E);
        wait_clks(CLKS_PER_BIT * 2);
        check_byte(rx_count - 1, 8'h7E);

        // Summary
        if (errors == 0)
            $display("\nALL TESTS PASSED (%0d bytes received)", rx_count);
        else
            $display("\n%0d ERROR(S)", errors);

        $finish;
    end

    // Safety net so a hung sim doesn't run forever
    initial begin
        #(CLK_PERIOD * CLKS_PER_BIT * 600);
        $display("TIMEOUT");
        $finish;
    end

endmodule