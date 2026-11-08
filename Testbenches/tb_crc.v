`timescale 1ns/1ps

module tb_crc;

    // Clock and Reset
    reg clk;
    reg clear;

    // Configuration Inputs
    reg [15:0] poly_in;
    reg        bus_16_in;
    reg        init_ones_in;
    reg        xor_ones_in;

    // Data Inputs
    reg        data_valid;
    reg [15:0] data_in;

    // Outputs
    wire [15:0] crc_out;

    // Instantiate the DUT
    crc_block dut (
        .clk          (clk),
        .clear        (clear),
        .poly_in      (poly_in),
        .bus_16_in    (bus_16_in),
        .init_ones_in (init_ones_in),
        .xor_ones_in  (xor_ones_in),
        .data_valid   (data_valid),
        .data_in      (data_in),
        .crc_out      (crc_out)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test sequence
    initial begin
        // Initialize inputs
        clear        = 0;
        poly_in      = 0;
        bus_16_in    = 0;
        init_ones_in = 0;
        xor_ones_in  = 0;
        data_valid   = 0;
        data_in      = 0;

        // Wait for reset
        #20;

        // ==========================================
        // Test 1: CRC-16/CCITT-FALSE (8-bit bus)
        // String: "123456789", Expected: 0x29B1
        // ==========================================
        $display("\nRunning Test 1: CCITT-FALSE 8-bit...");
        config_and_clear(16'h1021, 0, 1, 0);
        send_byte(8'h31);
        send_byte(8'h32);
        send_byte(8'h33);
        send_byte(8'h34);
        send_byte(8'h35);
        send_byte(8'h36);
        send_byte(8'h37);
        send_byte(8'h38);
        send_byte(8'h39);
        check_result(16'h29B1);

        // ==========================================
        // Test 2: CRC-16/XMODEM (8-bit bus)
        // String: "123456789", Expected: 0x31C3
        // ==========================================
        $display("\nRunning Test 2: XMODEM 8-bit...");
        config_and_clear(16'h1021, 0, 0, 0);
        send_byte(8'h31); send_byte(8'h32); send_byte(8'h33);
        send_byte(8'h34); send_byte(8'h35); send_byte(8'h36);
        send_byte(8'h37); send_byte(8'h38); send_byte(8'h39);
        check_result(16'h31C3);

        // ==========================================
        // Test 3: CRC-16/BUYPASS (8-bit bus)
        // String: "123456789", Expected: 0xFEE8
        // ==========================================
        $display("\nRunning Test 3: BUYPASS 8-bit...");
        config_and_clear(16'h8005, 0, 0, 0);
        send_byte(8'h31); send_byte(8'h32); send_byte(8'h33);
        send_byte(8'h34); send_byte(8'h35); send_byte(8'h36);
        send_byte(8'h37); send_byte(8'h38); send_byte(8'h39);
        check_result(16'hFEE8);

        // ==========================================
        // Test 4: CRC-16/GENIBUS (8-bit bus)
        // String: "123456789", Expected: 0xD64E
        // ==========================================
        $display("\nRunning Test 4: GENIBUS 8-bit (Tests XOR OUT)...");
        config_and_clear(16'h1021, 0, 1, 1);
        send_byte(8'h31); send_byte(8'h32); send_byte(8'h33);
        send_byte(8'h34); send_byte(8'h35); send_byte(8'h36);
        send_byte(8'h37); send_byte(8'h38); send_byte(8'h39);
        check_result(16'hD64E);

        // ==========================================
        // Test 5: CCITT-FALSE (16-bit bus)
        // String: "12345678" (8 bytes), Expected: 0xA12B
        // ==========================================
        $display("\nRunning Test 5: CCITT-FALSE 16-bit...");
        config_and_clear(16'h1021, 1, 1, 0);
        send_word(16'h3132);
        send_word(16'h3334);
        send_word(16'h3536);
        send_word(16'h3738);
        check_result(16'hA12B);

        // ==========================================
        // Test 6: Verify Configuration Hold
        // Set CCITT-FALSE 16-bit, string "12345678"
        // Then mess up input config BEFORE sending data!
        // ==========================================
        $display("\nRunning Test 6: Verify Configuration Hold...");
        config_and_clear(16'h1021, 1, 1, 0); // Pulse clear with correct config
        
        // Now corrupt inputs (should be ignored by DUT!)
        poly_in      = 16'hDEAD;
        bus_16_in    = 0;
        xor_ones_in  = 1;
        init_ones_in = 0; // Won't matter, init happens on clear

        // Send same 16-bit words
        send_word(16'h3132);
        send_word(16'h3334);
        send_word(16'h3536);
        send_word(16'h3738);

        // The result should STILL be 0xA12B
        check_result(16'hA12B);

        $display("\n=================================");
        $display("       ALL TESTS PASSED!         ");
        $display("=================================\n");
        $stop;
    end

    // Tasks for stimulus
    task config_and_clear(input [15:0] p, input b16, input i1, input x1);
        begin
            @(negedge clk);
            poly_in      = p;
            bus_16_in    = b16;
            init_ones_in = i1;
            xor_ones_in  = x1;
            clear        = 1;
            @(negedge clk);
            clear        = 0;
        end
    endtask

    task send_byte(input [7:0] d);
        begin
            @(negedge clk);
            data_in    = {8'h00, d}; // Put on lower 8 bits
            data_valid = 1;
            @(negedge clk);
            data_valid = 0;
            // Add a wait cycle to prove data_valid pause works
            @(negedge clk);
        end
    endtask

    task send_word(input [15:0] d);
        begin
            @(negedge clk);
            data_in    = d;
            data_valid = 1;
            @(negedge clk);
            data_valid = 0;
        end
    endtask

    task check_result(input [15:0] expected);
        begin
            #1; // Wait for combinational logic to settle just in case
            if (crc_out !== expected) begin
                $display("ERROR: Expected %h but got %h", expected, crc_out);
                $stop;
            end else begin
                $display("  -> SUCCESS! Output matched: %h", crc_out);
            end
        end
    endtask

endmodule
