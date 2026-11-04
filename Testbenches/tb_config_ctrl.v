`timescale 1ns / 1ps

module config_ctrl_tb;
    reg  [7:0]  cfg_opts = 0;
    reg  [15:0] cfg_poly = 0;
    reg         cfg_clear = 0, data_valid_in = 0;
    wire [15:0] poly_in;
    wire        clear, bus_16_in, init_ones_in, xor_ones_in, reflect_in, crc16_in, data_valid;

    config_ctrl dut (
        .cfg_opts(cfg_opts), .cfg_poly(cfg_poly), .cfg_clear(cfg_clear),
        .data_valid_in(data_valid_in), .clear(clear), .poly_in(poly_in),
        .bus_16_in(bus_16_in), .init_ones_in(init_ones_in), .xor_ones_in(xor_ones_in),
        .reflect_in(reflect_in), .crc16_in(crc16_in), .data_valid(data_valid));

    integer pass_cnt = 0, fail_cnt = 0;
    integer m, k;

    // m = {dv, clr, opts[7:0]}
    task apply_and_check(input [15:0] poly, input [9:0] m);
        reg [15:0] exp_poly;
        begin
            cfg_poly = poly;
            {data_valid_in, cfg_clear, cfg_opts} = m;
            exp_poly = m[6] ? poly : {8'h00, poly[7:0]};
            #1;

            if (poly_in === exp_poly && bus_16_in === m[0] && init_ones_in === m[1] &&
                xor_ones_in === m[2] && reflect_in === m[3] && crc16_in === m[6] &&
                clear === m[8] && data_valid === (m[9] & m[4]))
                pass_cnt = pass_cnt + 1;
            else begin
                fail_cnt = fail_cnt + 1;
                $display("FAIL poly=%h m=%b: poly_in %h/%h b16 %b i %b x %b r %b c16 %b clr %b dv %b (got)",
                    poly, m, poly_in, exp_poly, bus_16_in, init_ones_in, xor_ones_in,
                    reflect_in, crc16_in, clear, data_valid);
            end
        end
    endtask

    initial begin
        // All 1024 combinations of opts, clear, data_valid, each with a random polynomial
        for (m = 0; m < 1024; m = m + 1)
            apply_and_check($random, m);

        // Directed polynomials in both widths (crc16 = opts[6])
        for (m = 0; m < 2; m = m + 1) begin
            apply_and_check(16'h0000, m ? 10'h040 : 10'h000);
            apply_and_check(16'hFFFF, m ? 10'h040 : 10'h000);
            apply_and_check(16'h8005, m ? 10'h040 : 10'h000);
            apply_and_check(16'h1021, m ? 10'h040 : 10'h000);
            apply_and_check(16'h0007, m ? 10'h040 : 10'h000);
            apply_and_check(16'h002F, m ? 10'h040 : 10'h000);
        end

        // Walking one across the polynomial, both widths
        for (k = 0; k < 16; k = k + 1) begin
            apply_and_check(16'h0001 << k, 10'h000);
            apply_and_check(16'h0001 << k, 10'h040);
        end

        $display("%0d pass, %0d fail", pass_cnt, fail_cnt);
        $finish;
    end
endmodule