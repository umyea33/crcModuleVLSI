module uart_tx(
  input wire [7:0] dataBus,
  input wire byteReady,
  input wire loadXmtDatareg,
  input wire tByte,
  input wire clk,
  input wire rst,
  output reg serialOut
);

reg [7:0] dataReg;
reg [9:0] shiftReg;

reg [3:0] statusReg;

// Define all my states
parameter [2:0] idle = 3'b000, loadData = 3'b001, wait1 = 3'b010,
	loadShift = 3'b011, wait2 = 3'b100, start = 3'b101,
	sending = 3'b110, clear = 3'b111;


reg [2:0] current_state;
reg [2:0] next_state;

// Set the state to change on the clock cycle
always @(posedge clk, posedge rst) begin

  if(rst)
    current_state <= idle;
  else
    current_state <= next_state;

end

// Set next state based on input and current state
always @(current_state, byteReady, loadXmtDatareg, tByte, clk) begin

  case (current_state)
    idle: begin
      if(loadXmtDatareg)
        next_state = loadData;
      else
        next_state = idle;
    end
    loadData: begin
      if(byteReady)
        next_state = loadShift;
      else
        next_state = wait1;
    end
    wait1: begin
      if(byteReady)
        next_state = loadShift;
      else
        next_state = wait1;
    end
    loadShift: begin
      if(tByte)
        next_state = start;
      else
        next_state = wait2;
    end
    wait2: begin
      if(tByte)
        next_state = start;
      else
        next_state = wait2;
    end
    start: begin
      next_state = sending;
    end
    sending: begin
      if(statusReg == 4'b1001)
        next_state = clear;
      else
        next_state = sending;
    end
    clear: begin
      next_state = idle;
    end
  endcase

end

// Do something based on the current state
always @(posedge clk) begin

  case (current_state)
    idle: begin
      // Do nothing
    end
    loadData: begin
      dataReg <= dataBus;
    end
    wait1: begin
      // Do nothing
    end
    loadShift: begin
      shiftReg <= {1'b1, dataReg, 1'b0};
    end
    wait2: begin
      // Do nothing
    end
    start: begin
      serialOut <= shiftReg[0];
      shiftReg <= shiftReg >> 1;
      statusReg <= 4'b0001;
    end
    sending: begin
      serialOut <= shiftReg[0];
      shiftReg <= shiftReg >> 1;
      statusReg <= statusReg + 1;
    end
    clear: begin
      statusReg <= 4'b0000;
    end
  endcase

end

endmodule

