`timescale 1ns / 1ps

module reg_interface #(parameter TIMEOUT = 5000)(
    input clk,
    input rst_n,
    input [7:0] rx_data,
    input rx_valid,
    input tx_ready,
    input crc_busy,
    input crc_valid,
    input [15:0] crc_result,
    output reg [7:0] tx_data,
    output reg tx_valid,
    output reg [7:0] cfg_opts,      // [0] bus16 [1] init_ones [2] xor_ones [3] reflect [4] enable [6] crc16
    output reg [15:0] cfg_poly,
    output reg cfg_clear
    );

    function integer clogb2(input integer value);
        integer v;
        begin
            v = value - 1;
            for(clogb2 = 0; v > 0; clogb2 = clogb2 + 1)
                v = v >> 1;
        end
    endfunction

    localparam CNT_W = clogb2(TIMEOUT + 1);
    localparam IDLE = 2'd0, GET_ADDR = 2'd1, GET_DATA = 2'd2, SEND = 2'd3;
    localparam WRITE = 8'h01, READ = 8'h02;

    reg [1:0] state, next_state;
    reg [7:0] address, rd_mux;
    reg [CNT_W-1:0] to_cnt;
    reg is_write, cmd_err;

    wire timeout = (to_cnt == TIMEOUT);
    wire locked  = cfg_opts[4];

    always@(*)begin
        next_state = state;
        case(state)
            IDLE:begin
                if(rx_valid && (rx_data == READ || rx_data == WRITE))
                    next_state = GET_ADDR;
            end
            GET_ADDR:begin
                if(rx_valid)
                    next_state = is_write ? GET_DATA : SEND;
                else if(timeout)
                    next_state = IDLE;
            end
            GET_DATA:begin
                if(rx_valid || timeout)
                    next_state = IDLE;
            end
            SEND:begin
                if(tx_ready)
                    next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // rx_data is the address during GET_ADDR
    always@(*)begin
        case(rx_data)
            8'h00:   rd_mux = cfg_opts;
            8'h01:   rd_mux = {4'b0000, locked, cmd_err, crc_valid, crc_busy};
            8'h02:   rd_mux = crc_result[7:0];
            8'h03:   rd_mux = crc_result[15:8];
            8'h04:   rd_mux = cfg_poly[7:0];
            8'h05:   rd_mux = cfg_poly[15:8];
            default: rd_mux = 8'h00;
        endcase
    end

    // State and registers that need reset
    always@(posedge clk)begin
        if(!rst_n)begin
            state     <= IDLE;
            cmd_err   <= 1'b0;
            tx_valid  <= 1'b0;
            cfg_clear <= 1'b0;
            cfg_opts  <= 8'h00;
            cfg_poly  <= 16'h0000;
        end else begin
            state     <= next_state;
            tx_valid  <= 1'b0;
            cfg_clear <= 1'b0;
            case(state)
                IDLE:begin
                    if(rx_valid && !(rx_data == READ || rx_data == WRITE))
                        cmd_err <= 1'b1;                      // for unknown CMD
                end
                GET_ADDR:begin
                    if(rx_valid)begin
                        if(!is_write)begin
                            if(rx_data == 8'h01)      cmd_err <= 1'b0;   // status read clears error
                            else if(rx_data > 8'h05)  cmd_err <= 1'b1;   // illegal read
                        end
                    end else if(timeout)
                        cmd_err <= 1'b1;
                end
                GET_DATA:begin
                    if(rx_valid)begin
                        case(address)
                            8'h00:begin
                                if(rx_data[5])begin                      // clear, always accepted
                                    cfg_clear <= 1'b1;
                                    cfg_opts  <= rx_data & 8'h4F;        // clear not stored, enable forced 0
                                end else if(locked)
                                    cmd_err   <= 1'b1;
                                else
                                    cfg_opts  <= rx_data & 8'h5F;        // clear not stored
                            end
                            8'h04: if(locked) cmd_err <= 1'b1; else cfg_poly[7:0]  <= rx_data;
                            8'h05: if(locked) cmd_err <= 1'b1; else cfg_poly[15:8] <= rx_data;
                            default: cmd_err <= 1'b1;                    // illegal address
                        endcase
                    end else if(timeout)
                        cmd_err <= 1'b1;
                end
                SEND:begin
                    if(tx_ready)
                        tx_valid <= 1'b1;
                end
                default: ;
            endcase
        end
    end

    always@(posedge clk)begin
        case(state)
            IDLE:begin
                is_write <= (rx_data == WRITE);
                to_cnt   <= {CNT_W{1'b0}};
            end
            GET_ADDR:begin
                if(rx_valid)begin
                    address <= rx_data;
                    tx_data <= rd_mux;
                    to_cnt  <= {CNT_W{1'b0}};
                end else
                    to_cnt <= to_cnt + 1'b1;
            end
            GET_DATA: to_cnt <= to_cnt + 1'b1;
            default: ;
        endcase
    end

endmodule