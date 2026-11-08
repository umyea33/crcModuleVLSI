//No clock so we count our own clock cycles to knwo when each bit is.
//Strategy: find the falling edge of the start bit, wait half a bit to land in the middle of the first bit,
//then step one full bit  at a time so every sample alos lands in the middle. Chose the middle because it's the safest place.
module uart_rx #(parameter CLKS_PER_BIT = 434)(
	input clk,
	input	rst_n,
	input	rx,
	output reg [7:0] rx_data,
	output reg rx_valid
);

//FSM states
localparam 
IDLE = 2'd0, //waiting for line to drop
START = 2'd1, //confirms the start bit and reaches its middle
DATA = 2'd2, //samples the 8 data bits
STOP = 2'd3; // checks the stop bit

reg rx_s1, rx_s2; //2-flop synchronizer for the asynchronous rx pin
reg [1:0] state;
reg [15:0] clk_cnt; //counts clocks within the current bit
reg [2:0]  bit_idx; //the specific bit 0-7 that we're on
reg [7:0]  shift; //collects bits as they arrive

always @(posedge clk) begin
	if (!rst_n) //resets to 1 since an idle line is high
	begin
		rx_s1 <= 1'b1;
		rx_s2 <= 1'b1;
		rx_valid <= 1'b0;
		rx_data <= 8'b0;
		clk_cnt <= 16'b0;
		bit_idx <= 3'b0;
		shift <= 8'b0;
		state <= IDLE;
	end
	else 
	begin
		//rx pin is not connected to our clock,so if a change happens at a clock edge a single flop can be unstable,
		//so passing it through two makes it more likely to be a solid 0 or 1 signal. (called a 2 flop synchronizer)
		//looking at rx_s2 for here on
		rx_s1 <= rx;
		rx_s2 <= rx_s1;
		rx_valid <= 1'b0;
		case (state)
			IDLE: begin
			clk_cnt <= 16'b0;
			bit_idx <= 3'b0;
			if(rx_s2 == 0)
			state <= START;
			else
			state <= IDLE;
			end
			START: begin
			if(clk_cnt == ((CLKS_PER_BIT / 2) - 1)) begin //heres the waiting half a bit mentioned at the start
				if(rx_s2 == 0) begin
					state <= DATA;
					clk_cnt <= 16'b0; // FIX: Reset the counter for the DATA state
					end
					else
					state <= IDLE;
			end else begin
			clk_cnt <= clk_cnt + 1;
			end
			end
			DATA: begin
			if(clk_cnt == (CLKS_PER_BIT - 1)) begin //full bit elapsed
				clk_cnt <= 16'b0;
				shift <= rx_s2;
				shift <= {rx_s2, shift[7:1]}; //bit arrives lsb first so concatenated to account for it
				if(bit_idx == 7) //8th bit
					state <= STOP;
				else begin
					bit_idx <= bit_idx + 1;
					state <= DATA;
				end
			end else begin
				clk_cnt <= clk_cnt + 1;
				end
			end
			STOP: begin
			if(clk_cnt == (CLKS_PER_BIT - 1)) begin
				clk_cnt <= 16'b0;
				state <= IDLE;
				if(rx_s2 == 1)begin
					rx_data <= shift;
					rx_valid <= 1'b1;
					state <= IDLE;
				end
			end else begin
				clk_cnt <= clk_cnt + 1;
				end
			end
			default: begin
			state <= IDLE;
			end
		endcase
	end
end

endmodule