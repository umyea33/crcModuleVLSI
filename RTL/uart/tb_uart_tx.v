`timescale 1ns/1ps
module tb_uart_tx();

// Inputs
reg [7:0] dataBus;
reg byteReady;
reg loadXmtDatareg;
reg tByte;
reg clk;
reg rst;

// Output
wire serialOut;

// Initialize the uart
uart_tx theUart(dataBus, byteReady, loadXmtDatareg, tByte, clk, rst, serialOut);

// Setup a clock
always #5 clk = ~clk;

initial begin

// Initialize inputs
dataBus = 0;
byteReady = 0;
loadXmtDatareg = 0;
tByte = 0;
clk = 0;
rst = 0;

// Start the actual stuff
dataBus = 8'b01101010;
rst = 1;
#10 rst = 0;
#10 loadXmtDatareg = 1;
#10 // Let it go into wait1 state
#10 byteReady = 1;
#10 #10 #10 // Let it go into wait2 state for a while
#10 tByte = 1;
#10 // First bit should output now and we should go into sending state
#10 // Second bit out
#10 // Third bit out
#10 // Fourth bit out
#10 // Fifth bit out
#10 // Sixth bit out
#10 // Seventh bit out
#10 // Eighth bit out
#10 // Nineth bit out
#10 // Tenth bit out
 // Now we moved into the clear state.
loadXmtDatareg = 0;
byteReady = 0;
tByte = 0;
#10 // Now we should be back to idle.
#30 rst = 1;
#30;

end

endmodule

