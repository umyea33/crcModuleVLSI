module crc_block (
    input  wire        clk,
    input  wire        clear,        // sync: latches config and loads init value
    input  wire [15:0] poly_in,      // polynomial, normal form (x^CRC_W term implicit)
    input  wire        bus_16_in,    // 0: 8-bit bus, 1: 16-bit bus
    input  wire        init_ones_in, // 0: init = all 0s, 1: init = all 1s
    input  wire        xor_ones_in,  // 0: final XOR = 0s, 1: final XOR = all 1s
    input  wire        data_valid,
    input  wire [15:0] data_in,
    output wire [15:0] crc_out       // CRC after final XOR
);

    // Latched configuration
    reg [15:0] poly_reg;
    reg        bus_16_reg;
    reg        xor_ones_reg;

    // CRC State register
    reg [15:0] crc_reg;

    // Temporary variable for combinatorial CRC math
    reg [15:0] temp_crc;
    integer i;

    always @(posedge clk) begin
        if (clear) begin
            // Latch configuration and load initialization value
            poly_reg     <= poly_in;
            bus_16_reg   <= bus_16_in;
            xor_ones_reg <= xor_ones_in;
            crc_reg      <= init_ones_in ? 16'hFFFF : 16'h0000;
        end else if (data_valid) begin
            
            temp_crc = crc_reg; // Start with current CRC
            
            if (bus_16_reg) begin
                // 16-bit bus processing: XOR data with current CRC, then shift 16 times
                temp_crc = temp_crc ^ data_in;
                for (i = 0; i < 16; i = i + 1) begin
                    if (temp_crc[15])
                        temp_crc = (temp_crc << 1) ^ poly_reg;
                    else
                        temp_crc = temp_crc << 1;
                end
            end else begin
                // 8-bit bus processing: XOR 8-bit data into the MSB of the current CRC, shift 8 times
                temp_crc = temp_crc ^ {data_in[7:0], 8'h00};
                for (i = 0; i < 8; i = i + 1) begin
                    if (temp_crc[15])
                        temp_crc = (temp_crc << 1) ^ poly_reg;
                    else
                        temp_crc = temp_crc << 1;
                end
            end
            
            // Final result goes to the hardware register
            crc_reg <= temp_crc;
        end
    end

    // Output logic with final XOR application
    assign crc_out = crc_reg ^ (xor_ones_reg ? 16'hFFFF : 16'h0000);

endmodule
