`timescale 1ns / 1ps

module crc_ctrl_tb;
    localparam TIMEOUT = 50, GAP = 3;

    reg         clk = 0, rst_n = 0, rx_valid = 0, tx_ready = 1;
    reg  [7:0]  rx_data = 0;
    wire [7:0]  tx_data;
    wire [15:0] poly_in;
    wire        tx_valid, bus_16_in, init_ones_in, xor_ones_in;

    crc_ctrl #(.TIMEOUT(TIMEOUT)) dut (
        .clk(clk), .rst_n(rst_n), .rx_data(rx_data), .rx_valid(rx_valid),
        .tx_data(tx_data), .tx_valid(tx_valid), .tx_ready(tx_ready),
        .poly_in(poly_in), .bus_16_in(bus_16_in),
        .init_ones_in(init_ones_in), .xor_ones_in(xor_ones_in));

    always #5 clk = ~clk;

    integer pass_cnt = 0, fail_cnt = 0;

    task do_reset;
        begin
            rst_n = 0; rx_valid = 0;
            repeat (3) @(posedge clk);
            #1 rst_n = 1;
            repeat (2) @(posedge clk);
        end
    endtask

    task send_byte(input [7:0] b);
        begin
            repeat (GAP) @(posedge clk);
            #1 rx_data = b; rx_valid = 1;
            @(posedge clk);
            #1 rx_valid = 0;
        end
    endtask

    // Waits n cycles and fails if the DUT transmits anything
    task wait_quiet(input integer n);
        integer i;
        reg     bad;
        begin
            bad = 0;
            for (i = 0; i < n; i = i + 1) begin
                @(posedge clk); #1;
                if (tx_valid) bad = 1;
            end
            if (bad) begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL response sent unexpectedly");
            end else
                pass_cnt = pass_cnt + 1;
        end
    endtask

    task uart_write(input [7:0] cmd, input [15:0] data);
        begin
            send_byte(cmd);
            send_byte(data[15:8]);
            send_byte(data[7:0]);
            wait_quiet(10); // Writes produce no TX response in new protocol
        end
    endtask

    task uart_read(input [7:0] cmd, input [15:0] exp_data, input integer stall);
        reg [15:0] got;
        reg bad, seen_msb, seen_lsb;
        integer t;
        begin
            got = 16'hxxxx;
            seen_msb = 0; seen_lsb = 0; bad = 0;
            tx_ready = 1;

            send_byte(cmd);
            
            // Wait for MSB
            for (t = 0; t < 20 && !seen_msb; t = t + 1) begin
                @(posedge clk); #1;
                if (tx_valid) begin 
                    seen_msb = 1; 
                    got[15:8] = tx_data; 
                    if (stall > 0) tx_ready = 0; // Test stalling the transmitter
                end
            end

            // Stall if requested
            for (t = 0; t < stall; t = t + 1) begin
                @(posedge clk); #1;
            end
            tx_ready = 1;

            // Wait for LSB
            for (t = 0; t < 20 && !seen_lsb; t = t + 1) begin
                @(posedge clk); #1;
                if (tx_valid) begin 
                    seen_lsb = 1; 
                    got[7:0] = tx_data; 
                end
            end

            if (seen_msb && seen_lsb && (got === exp_data)) begin
                pass_cnt = pass_cnt + 1;
            end else begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL Read %h: got %h, expected %h (seen_msb=%b, seen_lsb=%b)", cmd, got, exp_data, seen_msb, seen_lsb);
            end
        end
    endtask

    initial begin
        do_reset;

        // Write Poly Register (CMD 0x80)
        uart_write(8'h80, 16'h1021);
        if (poly_in === 16'h1021) pass_cnt = pass_cnt + 1;
        else begin fail_cnt = fail_cnt + 1; $display("FAIL Poly output wrong"); end

        // Write Control Register (CMD 0x81)
        uart_write(8'h81, 16'h0007); // bus_16=1, init_ones=1, xor_ones=1
        if ({xor_ones_in, init_ones_in, bus_16_in} === 3'b111) pass_cnt = pass_cnt + 1;
        else begin fail_cnt = fail_cnt + 1; $display("FAIL Ctrl output wrong"); end

        // Read Poly Register (CMD 0x00)
        uart_read(8'h00, 16'h1021, 0);

        // Read Control Register (CMD 0x01) with TX stall testing
        uart_read(8'h01, 16'h0007, 5); // delay tx_ready for 5 cycles between MSB and LSB

        // Incomplete frames time out silently, and the next frame still works
        send_byte(8'h80); // Command byte only
        wait_quiet(TIMEOUT + 20); // Should time out silently
        
        // Write Poly again with new value
        uart_write(8'h80, 16'h8005);
        uart_read(8'h00, 16'h8005, 0); // Verify it updated properly

        // Reset mid-frame keeps the config
        send_byte(8'h80); send_byte(8'h42);
        do_reset; // resets FSM, keeps registers
        uart_read(8'h00, 16'h8005, 0); // Poly should remain 8005

        $display("DONE: %0d pass, %0d fail", pass_cnt, fail_cnt);
        $finish;
    end

    initial begin #2000000; $display("TIMEOUT: testbench hung"); $finish; end
endmodule