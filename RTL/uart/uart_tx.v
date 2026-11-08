module uart_tx #(
    parameter CLKS_PER_BIT = 434
)(
    input wire clk,
    input wire rst_n,

    input wire [7:0] tx_data,
    input wire tx_valid,
    output reg tx_ready,

    output reg uart_tx
);

    // FSM states
    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0] state;
    reg [15:0] clk_cnt;
    reg [2:0] bit_idx;
    reg [7:0] shift_reg;

    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= IDLE;
            uart_tx   <= 1'b1;   // UART is high while idle
            tx_ready  <= 1'b1;
            clk_cnt   <= 16'd0;
            bit_idx   <= 3'd0;
            shift_reg <= 8'd0;
        end
        else begin
            case (state)

                // Wait for a byte to be sent
                IDLE: begin
                    uart_tx  <= 1'b1;
                    tx_ready <= 1'b1;
                    clk_cnt  <= 16'd0;
                    bit_idx  <= 3'd0;

                    // Accept new data when it is valid and TX is available
                    if (tx_valid && tx_ready) begin
                        shift_reg <= tx_data;
                        tx_ready  <= 1'b0;
                        state     <= START;
                    end
                end

                // Send the start bit for one bit period
                START: begin
                    uart_tx <= 1'b0;

                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt <= 16'd0;
                        state   <= DATA;
                    end
                    else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Send all 8 data bits, least-significant bit first
                DATA: begin
                    uart_tx <= shift_reg[0];

                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt   <= 16'd0;
                        shift_reg <= shift_reg >> 1;

                        if (bit_idx == 3'd7) begin
                            state <= STOP;
                        end
                        else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                    else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // Send the stop bit for one bit period
                STOP: begin
                    uart_tx <= 1'b1;

                    if (clk_cnt == CLKS_PER_BIT - 1) begin
                        clk_cnt  <= 16'd0;
                        tx_ready <= 1'b1;
                        state    <= IDLE;
                    end
                    else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: begin
                    state    <= IDLE;
                    uart_tx  <= 1'b1;
                    tx_ready <= 1'b1;
                    clk_cnt  <= 16'd0;
                    bit_idx  <= 3'd0;
                end

            endcase
        end
    end

endmodule