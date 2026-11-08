`timescale 1ns/1ps

module tb_uart_tx;

    // Inputs to the UART transmitter
    reg clk;
    reg rst_n;
    reg [7:0] tx_data;
    reg tx_valid;

    // Outputs from the UART transmitter
    wire tx_ready;
    wire uart_tx;

    // Use a small value so simulation finishes quickly.
    // With a 10 ns clock period, each UART bit lasts 4 clock cycles = 40 ns.
    uart_tx #(
        .CLKS_PER_BIT(4)
    ) theUart (
        .clk(clk),
        .rst_n(rst_n),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .uart_tx(uart_tx)
    );

    // Create a clock with a 10 ns period
    always #5 clk = ~clk;

    // Sends one byte using the tx_valid / tx_ready handshake
    task send_byte;
        input [7:0] byte_to_send;
        begin
            // Wait until the transmitter is idle and can accept data
            wait (tx_ready == 1'b1);

            // Change values on a falling edge so they are stable
            // before the next rising clock edge.
            @(negedge clk);
            tx_data  = byte_to_send;
            tx_valid = 1'b1;

            // The transmitter captures tx_data on the next rising edge.
            @(negedge clk);
            tx_valid = 1'b0;
        end
    endtask

    initial begin
        // Optional: creates a waveform file for GTKWave/Icarus Verilog
        $dumpfile("uart_tx_waveform.vcd");
        $dumpvars(0, tb_uart_tx);

        // Initialize signals
        clk      = 1'b0;
        rst_n    = 1'b0;  // Active-low reset
        tx_data  = 8'b0;
        tx_valid = 1'b0;

        // Hold reset for two clock cycles
        #20;
        rst_n = 1'b1;

        // Send 0x6A = 8'b01101010
        // UART sends it LSB first: 0, 1, 0, 1, 0, 1, 1, 0
        send_byte(8'b01101010);

        // Wait for the first UART frame to completely finish
        wait (tx_ready == 1'b1);
        #20;

        // Send a second byte to confirm it can transmit multiple bytes
        send_byte(8'b10110011);

        // Wait until the second byte finishes transmitting
        wait (tx_ready == 1'b1);
        #40;

        $finish;
    end

endmodule