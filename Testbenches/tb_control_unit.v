`timescale 1ns / 1ps

module crc_ctrl_tb;
    localparam TIMEOUT = 50, GAP = 3;              // GAP must be < TIMEOUT
    localparam KEY = 8'hA5, ACK = 8'h06, NAK = 8'h15;

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

    reg [2:0]  sh_opts = 3'bxxx;                   // {xor, init, bus16}, unknown until written
    reg [15:0] sh_poly = 16'hxxxx;
    integer    pass_cnt = 0, fail_cnt = 0, p;

    task do_reset;                                 // FSM only, config is kept
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
                $display("FAIL response sent after an incomplete frame");
            end else
                pass_cnt = pass_cnt + 1;
        end
    endtask

    // Sends one frame and checks the response and the config outputs.
    // addr[7] = read. hold = idle cycles after ADDR. chk_err is XORed into CHK.
    // stall = cycles tx_ready is held low after the frame.
    task frame(input [7:0] addr, input [7:0] data, input integer hold,
               input [7:0] chk_err, input integer stall);
        reg [7:0] exp_resp, got;
        reg       seen, bad;
        integer   t;
        begin
            seen = 0; bad = 0; got = 0; exp_resp = NAK;

            if (chk_err == 8'h00 && addr[6:2] == 5'b00000) begin
                if (addr[7]) begin                                  // read
                    case (addr[1:0])
                        2'd0:    exp_resp = {5'b00000, sh_opts};
                        2'd1:    exp_resp = sh_poly[7:0];
                        2'd2:    exp_resp = sh_poly[15:8];
                        default: ;                                  // PRESET is write-only
                    endcase
                end else begin                                      // write
                    exp_resp = ACK;
                    case (addr[1:0])
                        2'd0: sh_opts = data[2:0];
                        2'd1: sh_poly[7:0]  = data;
                        2'd2: sh_poly[15:8] = data;
                        2'd3: begin
                            sh_opts[0] = data[3];
                            case (data[2:0])
                                3'd0: begin sh_poly = 16'h1021; sh_opts[2:1] = 2'b00; end
                                3'd1: begin sh_poly = 16'h1021; sh_opts[2:1] = 2'b01; end
                                3'd2: begin sh_poly = 16'h1021; sh_opts[2:1] = 2'b11; end
                                3'd3: begin sh_poly = 16'h1021; sh_opts[2:1] = 2'b10; end
                                3'd4: begin sh_poly = 16'h8005; sh_opts[2:1] = 2'b00; end
                                3'd5: begin sh_poly = 16'h8005; sh_opts[2:1] = 2'b01; end
                                3'd6: begin sh_poly = 16'h0700; sh_opts[2:1] = 2'b00; end
                                3'd7: begin sh_poly = 16'h1DCF; sh_opts[2:1] = 2'b11; end
                            endcase
                        end
                    endcase
                end
            end

            tx_ready = 0;
            send_byte(addr);
            repeat (hold) @(posedge clk);
            send_byte(data);
            send_byte(addr ^ data ^ KEY ^ chk_err);

            for (t = 0; t < stall; t = t + 1) begin
                @(posedge clk); #1;
                if (tx_valid) bad = 1;                              // must wait for tx_ready
            end
            tx_ready = 1;

            for (t = 0; t < 20 && !seen; t = t + 1) begin
                @(posedge clk); #1;
                if (tx_valid) begin seen = 1; got = tx_data; end
            end
            @(posedge clk); #1;
            if (tx_valid) bad = 1;                                  // must be a 1-cycle pulse

            if (seen && !bad && got === exp_resp &&
                {xor_ones_in, init_ones_in, bus_16_in} === sh_opts && poly_in === sh_poly)
                pass_cnt = pass_cnt + 1;
            else begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL frame %h %h chk_err=%h: resp %h/%h seen=%b bad=%b opts %b/%b poly %h/%h (got/exp)",
                    addr, data, chk_err, got, exp_resp, seen, bad,
                    {xor_ones_in, init_ones_in, bus_16_in}, sh_opts, poly_in, sh_poly);
            end
        end
    endtask

    initial begin
        do_reset;

        // Write each register and read it back
        frame(8'h01, 8'h21, 0, 0, 0);
        frame(8'h02, 8'h10, 0, 0, 0);
        frame(8'h00, 8'hFD, 0, 0, 0);                  // upper DATA bits ignored
        frame(8'h80, 8'h00, 0, 0, 0);
        frame(8'h81, 8'h00, 0, 0, 0);
        frame(8'h82, 8'h00, 0, 0, 0);

        // Presets, then read back what they loaded
        for (p = 0; p < 8; p = p + 1)
            frame(8'h03, p, 0, 0, 0);
        frame(8'h03, 8'h08, 0, 0, 0);
        frame(8'h80, 8'h00, 0, 0, 0);
        frame(8'h81, 8'h00, 0, 0, 0);
        frame(8'h82, 8'h00, 0, 0, 0);

        // Rejected frames get a NAK and change nothing
        frame(8'h00, 8'h07, 0, 8'h01, 0);              // bad checksum on a write
        frame(8'h81, 8'h00, 0, 8'h80, 0);              // bad checksum on a read
        frame(8'h00, 8'h00, 0, KEY, 0);                // 00 00 00 on the wire
        frame(8'h04, 8'hFF, 0, 0, 0);                  // illegal address
        frame(8'h40, 8'hFF, 0, 0, 0);                  // illegal address bits
        frame(8'h83, 8'h00, 0, 0, 0);                  // read of the write-only PRESET

        // Incomplete frames time out silently, and the next frame still works
        send_byte(8'h01);
        wait_quiet(TIMEOUT + 20);
        frame(8'h02, 8'h55, 0, 0, 0);
        send_byte(8'h01); send_byte(8'h42);
        wait_quiet(TIMEOUT + 20);
        frame(8'h02, 8'h66, 0, 0, 0);

        // Slow but legal frame, and a stalled tx_ready
        frame(8'h01, 8'h99, TIMEOUT - 10, 0, 0);
        frame(8'h81, 8'h00, 0, 0, 5);

        // Reset mid-frame keeps the config
        send_byte(8'h01); send_byte(8'h42);
        do_reset;
        frame(8'h82, 8'h00, 0, 0, 0);
        frame(8'h02, 8'h33, 0, 0, 0);

        $display("DONE: %0d pass, %0d fail", pass_cnt, fail_cnt);
        $finish;
    end

    initial begin #2000000; $display("TIMEOUT: testbench hung"); $finish; end
endmodule