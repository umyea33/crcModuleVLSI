`timescale 1ns / 1ps

module tb_reg_interface;
    localparam TIMEOUT = 50, GAP = 3;              // GAP must be < TIMEOUT
    localparam CMD_WRITE = 8'h01, CMD_READ = 8'h02;

    reg         clk = 0, rst_n = 0, rx_valid = 0, tx_ready = 1;
    reg         crc_busy = 0, crc_valid = 0;
    reg  [7:0]  rx_data = 0;
    reg  [15:0] crc_result = 0;
    wire [7:0]  tx_data, cfg_opts;
    wire [15:0] cfg_poly;
    wire        tx_valid, cfg_clear;

    reg_interface #(.TIMEOUT(TIMEOUT)) dut (
        .clk(clk), .rst_n(rst_n), .rx_data(rx_data), .rx_valid(rx_valid),
        .tx_ready(tx_ready), .crc_busy(crc_busy), .crc_valid(crc_valid),
        .crc_result(crc_result), .tx_data(tx_data), .tx_valid(tx_valid),
        .cfg_opts(cfg_opts), .cfg_poly(cfg_poly), .cfg_clear(cfg_clear));

    always #5 clk = ~clk;

    reg [7:0]  sh_opts;
    reg [15:0] sh_poly;
    reg        sh_err;
    integer    pass_cnt = 0, fail_cnt = 0;

    task do_reset;
        begin
            rst_n = 0; rx_valid = 0; tx_ready = 1;
            sh_opts = 0; sh_poly = 0; sh_err = 0;
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

    task reg_write(input [7:0] addr, input [7:0] data);
        reg     exp_clr;
        integer clr_cnt, i;
        begin
            exp_clr = 0;
            if (addr == 8'h00) begin
                if (data[5])           begin sh_opts = data & 8'h4F; exp_clr = 1; end  // clear wins, enable forced 0
                else if (sh_opts[4])   sh_err = 1;                                     // locked
                else                   sh_opts = data & 8'h5F;
            end
            else if (addr == 8'h04 || addr == 8'h05) begin
                if (sh_opts[4])        sh_err = 1;                                     // locked
                else if (addr == 8'h04) sh_poly[7:0]  = data;
                else                    sh_poly[15:8] = data;
            end
            else sh_err = 1;                                                           // illegal

            send_byte(CMD_WRITE); send_byte(addr); send_byte(data);
            clr_cnt = cfg_clear;                       
            for (i = 0; i < 5; i = i + 1) begin
                @(posedge clk); #1;
                if (cfg_clear) clr_cnt = clr_cnt + 1;
            end

            if (cfg_opts === sh_opts && cfg_poly === sh_poly && clr_cnt == exp_clr)
                pass_cnt = pass_cnt + 1;
            else begin
                fail_cnt = fail_cnt + 1;
                $display("Fail | write %h<=%h: opts %h/%h poly %h/%h clr_pulses %0d/%0d (got/exp)",
                    addr, data, cfg_opts, sh_opts, cfg_poly, sh_poly, clr_cnt, exp_clr);
            end
        end
    endtask

    task reg_read(input [7:0] addr, input integer stall);
        reg [7:0] exp, got;
        reg       seen, bad;
        integer   t;
        begin
            seen = 0; 
            bad = 0; 
            got = 0;
            case (addr)
                8'h00:   exp = sh_opts;
                8'h01:   exp = {4'b0000, sh_opts[4], sh_err, crc_valid, crc_busy};
                8'h02:   exp = crc_result[7:0];
                8'h03:   exp = crc_result[15:8];
                8'h04:   exp = sh_poly[7:0];
                8'h05:   exp = sh_poly[15:8];
                default: exp = 8'h00;
            endcase
            if (addr == 8'h01)     sh_err = 0;         // STATUS read clears the error
            else if (addr > 8'h05) sh_err = 1;         // illegal read

            tx_ready = 0;
            send_byte(CMD_READ); 
            send_byte(addr);
            for (t = 0; t < stall; t = t + 1) begin
                @(posedge clk); #1;
                if (tx_valid) bad = 1;                 // fired while not ready
            end
            tx_ready = 1;

            for (t = 0; t < 50 && !seen; t = t + 1) begin
                @(posedge clk); #1;
                if (tx_valid) begin seen = 1; got = tx_data; end
            end
            @(posedge clk); #1;
            if (tx_valid) bad = 1;                     // pulse

            if (seen && !bad && got === exp) pass_cnt = pass_cnt + 1;
            else begin
                fail_cnt = fail_cnt + 1;
                $display("Fail | read %h: got %h, exp %h, seen=%b, bad_pulse=%b", addr, got, exp, seen, bad);
            end
        end
    endtask

    initial begin
        do_reset;

        // reset
        reg_read(8'h00, 0); reg_read(8'h01, 0); reg_read(8'h04, 0); reg_read(8'h05, 0);

        // Program then read
        crc_result = 16'hA55A; {crc_valid, crc_busy} = 2'b10;
        reg_write(8'h04, 8'h21); reg_write(8'h05, 8'h10);          // poly = 0x1021
        reg_write(8'h00, 8'h4B);                                   // crc16, reflect, init, bus16
        reg_read(8'h00, 0); reg_read(8'h04, 0); reg_read(8'h05, 0);
        reg_read(8'h02, 0); reg_read(8'h03, 0); reg_read(8'h01, 0);

        // ctrl and polynomial writes ignored and flagged
        reg_write(8'h00, 8'h5B);                                   // enable set
        reg_write(8'h00, 8'h4B);                                   // ignored, error
        reg_write(8'h04, 8'hFF);                                   // ignored, error
        reg_read(8'h00, 0); reg_read(8'h04, 0);                    // unchanged
        reg_read(8'h01, 0); reg_read(8'h01, 0);                    // locked + error, then error cleared

        //Clear while locked
        reg_write(8'h00, 8'h72);
        reg_read(8'h00, 0); reg_read(8'h01, 0);                    // clear bit reads 0, locked = 0
        reg_write(8'h04, 8'h07);                                   // POLY writable again

        //Read-only and illegal addresses
        reg_write(8'h02, 8'hFF); reg_write(8'h06, 8'hFF);
        reg_read(8'h02, 0);                                        // result unchanged
        reg_read(8'h06, 0);                                        // illegal read returns 0, sets error
        reg_read(8'h01, 0);

        //Unknown CMD byte
        send_byte(8'h05); sh_err = 1;
        reg_read(8'h01, 0);

        // Timeouts in GET_ADDR and in GET_DATA, then a valid command
        send_byte(CMD_WRITE); repeat (TIMEOUT + 20) @(posedge clk);
        send_byte(CMD_WRITE); send_byte(8'h04); repeat (TIMEOUT + 20) @(posedge clk);
        sh_err = 1;
        reg_read(8'h01, 0);
        reg_read(8'h04, 0);

        //Late bytes must not time out
        send_byte(CMD_WRITE); repeat (TIMEOUT - 10) @(posedge clk);
        send_byte(8'h04);     repeat (TIMEOUT - 10) @(posedge clk);
        send_byte(8'hA5);     sh_poly[7:0] = 8'hA5;
        reg_read(8'h04, 0);

        //tx_ready stall
        reg_read(8'h00, 5);

        //Reset in the middle of a command
        send_byte(CMD_WRITE); send_byte(8'h00);
        do_reset;
        reg_read(8'h00, 0); reg_read(8'h04, 0);

        $display("DONE: %0d pass, %0d fail", pass_cnt, fail_cnt);
        $finish;
    end

endmodule