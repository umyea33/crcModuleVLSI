`timescale 1ns / 1ps

//==============================================================================
// crc_ctrl : UART-programmed control unit for crc_block
//
// Command Protocol:
// This module implements two 16-bit registers:
//   Reg 0: Polynomial
//   Reg 1: Control Signals ([0] bus_16, [1] init_ones, [2] xor_ones, [15:3] reserved)
//
// Frame Structure:
//   Command Byte (Host -> Device):
//     Bit 7   : Read/Write (1 = Write, 0 = Read)
//     Bit 6:1 : Reserved (should be 0)
//     Bit 0   : Register Address (0 = Poly, 1 = Control)
//
// Write Sequence (3 Bytes):
//   Host sends: [CMD] [DATA_MSB] [DATA_LSB]
//   Example: Write 0x8005 to Poly -> Send 0x80, 0x80, 0x05
//
// Read Sequence (1 Byte Command, 2 Bytes Response):
//   Host sends: [CMD]
//   Device replies: [DATA_MSB] [DATA_LSB]
//   Example: Read Ctrl (0x01) -> Chip replies 0x00, 0x07 (if all bits set)
//==============================================================================
module crc_ctrl #(parameter TIMEOUT = 5000)(
    input             clk,
    input             rst_n,
    // UART receive side
    input      [7:0]  rx_data,
    input             rx_valid,
    // UART transmit side
    output reg [7:0]  tx_data,
    output reg        tx_valid,
    input             tx_ready,
    // Configuration to crc_block
    output reg [15:0] poly_in,
    output wire       bus_16_in,
    output wire       init_ones_in,
    output wire       xor_ones_in
);

    // Control register: [0] bus_16, [1] init_ones, [2] xor_ones
    reg [15:0] ctrl_reg;
    assign bus_16_in    = ctrl_reg[0];
    assign init_ones_in = ctrl_reg[1];
    assign xor_ones_in  = ctrl_reg[2];

    // Timeout counter logic
    function integer clogb2(input integer value);
        integer v;
        begin
            v = value - 1;
            for(clogb2 = 0; v > 0; clogb2 = clogb2 + 1)
                v = v >> 1;
        end
    endfunction

    localparam CNT_W = clogb2(TIMEOUT + 1);
    reg [CNT_W-1:0] to_cnt;
    wire timeout = (to_cnt == TIMEOUT);

    // FSM States
    localparam IDLE   = 3'd0;
    localparam WR_MSB = 3'd1;
    localparam WR_LSB = 3'd2;
    localparam RD_MSB = 3'd3;
    localparam RD_LSB = 3'd4;

    reg [2:0] state;
    reg       cmd_addr;   // 0 = Poly, 1 = Control
    reg [7:0] temp_msb;   // Holds MSB during a write
    reg [15:0] rd_buf;    // Holds data to be transmitted during a read

    always @(posedge clk) begin
        if (!rst_n) begin
            state    <= IDLE;
            tx_valid <= 1'b0;
            tx_data  <= 8'h00;
            cmd_addr <= 1'b0;
            temp_msb <= 8'h00;
            rd_buf   <= 16'h0000;
            to_cnt   <= {CNT_W{1'b0}};
        end else begin
            case (state)
                IDLE: begin
                    tx_valid <= 1'b0;
                    to_cnt   <= {CNT_W{1'b0}};
                    if (rx_valid) begin
                        cmd_addr <= rx_data[0];
                        if (rx_data[7] == 1'b1) begin
                            // Write command
                            state <= WR_MSB;
                        end else begin
                            // Read command
                            state  <= RD_MSB;
                            rd_buf <= (rx_data[0] == 1'b0) ? poly_in : ctrl_reg;
                        end
                    end
                end

                WR_MSB: begin
                    if (rx_valid) begin
                        temp_msb <= rx_data;
                        state    <= WR_LSB;
                        to_cnt   <= {CNT_W{1'b0}};
                    end else begin
                        to_cnt <= to_cnt + 1'b1;
                        if (timeout) state <= IDLE;
                    end
                end

                WR_LSB: begin
                    if (rx_valid) begin
                        if (cmd_addr == 1'b0) begin
                            poly_in <= {temp_msb, rx_data};
                        end else begin
                            ctrl_reg <= {temp_msb, rx_data};
                        end
                        state <= IDLE;
                    end else begin
                        to_cnt <= to_cnt + 1'b1;
                        if (timeout) state <= IDLE;
                    end
                end

                RD_MSB: begin
                    if (!tx_valid) begin
                        tx_data  <= rd_buf[15:8];
                        tx_valid <= 1'b1;
                    end else if (tx_ready) begin
                        tx_valid <= 1'b0;
                        state    <= RD_LSB;
                    end
                end

                RD_LSB: begin
                    if (!tx_valid) begin
                        tx_data  <= rd_buf[7:0];
                        tx_valid <= 1'b1;
                    end else if (tx_ready) begin
                        tx_valid <= 1'b0;
                        state    <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule