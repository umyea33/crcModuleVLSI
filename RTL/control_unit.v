`timescale 1ns / 1ps

//==============================================================================
// crc_ctrl : UART-programmed control unit for crc_block
//
// Receives command frames from the UART, checks them, updates the CRC
// configuration registers, and sends a one-byte response back.
//
// Frame (host to chip, 3 bytes, each a normal UART byte):
//     [ADDR] [DATA] [CHK]
//     ADDR[7]   = 1 for a read, 0 for a write
//     ADDR[6:2] = must be 0, otherwise the frame is rejected
//     ADDR[1:0] = register select (table below)
//     DATA      = value to write (send 0x00 for reads, it is ignored)
//     CHK       = ADDR ^ DATA ^ 0xA5
//                 The 0xA5 key makes a stuck-low line (00 00 00) fail the check.
//
// Registers:
//     0  FLAGS   DATA[2:0] = {xor_ones, init_ones, bus_16}   read/write
//     1  POLY_L  poly[7:0]                                   read/write
//     2  POLY_H  poly[15:8]                                  read/write
//     3  PRESET  DATA[2:0] = preset index (ROM below)        write only
//                DATA[3]   = bus_16
//
// Response (chip to host, exactly one byte per complete frame):
//     good write            -> ACK (0x06)
//     good read             -> the register value
//     anything else         -> NAK (0x15)  (bad checksum, illegal address,
//                              read of the write-only PRESET register)
//     timeout               -> no response (the host should use its own timeout)
//
// Rules:
//   * A bad frame changes nothing. The write is committed only after the
//     checksum byte has been verified.
//   * Bytes received while a response is being sent are ignored, so the host
//     must wait for the response before sending the next frame.
//   * The Clear pin goes straight to crc_block. Assert it after the response to
//     the last config frame, because crc_block only latches config on Clear.
//   * Config registers have no reset (saves area), so they are unknown until
//     the host writes them. Only the FSM state and tx_valid are reset.
//==============================================================================
module crc_ctrl #(parameter TIMEOUT = 5000)(
    input             clk,
    input             rst_n,          // resets the FSM only
    // UART receive side
    input      [7:0]  rx_data,
    input             rx_valid,       // 1-cycle pulse per received byte
    // UART transmit side
    output     [7:0]  tx_data,        // valid while tx_valid is high
    output reg        tx_valid,       // 1-cycle pulse
    input             tx_ready,       // UART can accept a byte
    // Configuration to crc_block
    output reg [15:0] poly_in,
    output reg        bus_16_in,
    output reg        init_ones_in,
    output reg        xor_ones_in
    );

    // Constants
    // Bits needed to count up to the timeout value
    function integer clogb2(input integer value);
        integer v;
        begin
            v = value - 1;
            for(clogb2 = 0; v > 0; clogb2 = clogb2 + 1)
                v = v >> 1;
        end
    endfunction

    localparam CNT_W = clogb2(TIMEOUT + 1);

    // IDLE waits for ADDR, GET_DATA waits for DATA, GET_CHK waits for CHK,
    // SEND waits for the UART to accept the response byte
    localparam IDLE = 2'd0, GET_DATA = 2'd1, GET_CHK = 2'd2, SEND = 2'd3;

    localparam KEY = 8'hA5;               // checksum key
    localparam ACK = 8'h06, NAK = 8'h15;  // response codes

    //--------------------------------------------------------------------------
    // Signals
    //--------------------------------------------------------------------------
    reg [1:0]       state, next_state;
    reg             is_read;              // ADDR[7] of the current frame
    reg [1:0]       addr_q;               // ADDR[1:0] of the current frame
    reg             addr_ok;              // ADDR[6:2] were all zero
    reg [7:0]       data_q;               // held DATA byte, then reused as the TX byte
    reg [7:0]       chk_acc;              // running ADDR ^ DATA ^ KEY, compared to CHK
    reg [CNT_W-1:0] to_cnt;               // cycles spent waiting for the next byte

    reg [7:0]       rd_val;               // value returned for a read
    reg             rd_ok;                // 0 if the register cannot be read
    reg [15:0]      rom_poly;             // preset ROM outputs
    reg             rom_init, rom_xor;

    wire timeout  = (to_cnt == TIMEOUT);
    wire frame_ok = addr_ok && (rx_data == chk_acc);   // only meaningful in GET_CHK

    // data_q holds the response byte once a frame is complete, so TX needs no
    // separate buffer. It is not modified again until the next frame's DATA byte.
    assign tx_data = data_q;

    //--------------------------------------------------------------------------
    // Next-state logic
    //--------------------------------------------------------------------------
    always@(*)begin
        next_state = state;
        case(state)
            IDLE:begin
                if(rx_valid)                next_state = GET_DATA;
            end
            GET_DATA:begin
                if(rx_valid)                next_state = GET_CHK;
                else if(timeout)            next_state = IDLE;     // frame abandoned
            end
            GET_CHK:begin
                if(rx_valid)                next_state = SEND;     // every full frame gets a response
                else if(timeout)            next_state = IDLE;     // frame abandoned
            end
            SEND:begin
                if(tx_ready)                next_state = IDLE;
            end
            default:                        next_state = IDLE;
        endcase
    end

    //--------------------------------------------------------------------------
    // Read mux: value returned for the register selected by addr_q
    //--------------------------------------------------------------------------
    always@(*)begin
        rd_val = 8'h00;
        rd_ok  = 1'b1;
        case(addr_q)
            2'd0:    rd_val = {5'b00000, xor_ones_in, init_ones_in, bus_16_in};
            2'd1:    rd_val = poly_in[7:0];
            2'd2:    rd_val = poly_in[15:8];
            default: rd_ok  = 1'b0;                  // PRESET is write-only
        endcase
    end

    //--------------------------------------------------------------------------
    // Preset ROM, indexed by the held DATA byte. Every entry is a non-reflected
    // CRC that crc_block can run.
    //--------------------------------------------------------------------------
    always@(*)begin
        rom_poly = 16'h1021;
        rom_init = 1'b0;
        rom_xor  = 1'b0;
        case(data_q[2:0])
            3'd0:    ;                                                        // CRC-16/XMODEM
            3'd1:    rom_init = 1'b1;                                         // CRC-16/CCITT-FALSE
            3'd2:    begin rom_init = 1'b1; rom_xor = 1'b1; end               // CRC-16/GENIBUS
            3'd3:    rom_xor = 1'b1;                                          // CRC-16/GSM
            3'd4:    rom_poly = 16'h8005;                                     // CRC-16/BUYPASS
            3'd5:    begin rom_poly = 16'h8005; rom_init = 1'b1; end          // CRC-16/CMS
            3'd6:    rom_poly = 16'h0700;                                     // CRC-8/SMBus, left-aligned, use 8-bit bus
            3'd7:    begin rom_poly = 16'h1DCF; rom_init = 1'b1; rom_xor = 1'b1; end   // CRC-16/PROFIBUS
            default: ;
        endcase
    end

    //--------------------------------------------------------------------------
    // FSM state and TX handshake (the only registers with a reset)
    //--------------------------------------------------------------------------
    always@(posedge clk)begin
        if(!rst_n)begin
            state    <= IDLE;
            tx_valid <= 1'b0;
        end else begin
            state    <= next_state;
            tx_valid <= (state == SEND) && tx_ready;   // 1-cycle pulse as SEND ends
        end
    end

    //--------------------------------------------------------------------------
    // Frame capture, checksum, commit, response, and timeout counter.
    // No reset: every register is written before it is used.
    //--------------------------------------------------------------------------
    always@(posedge clk)begin
        case(state)
            // Byte 1: ADDR. Start the checksum with the key.
            IDLE:begin
                to_cnt <= {CNT_W{1'b0}};
                if(rx_valid)begin
                    is_read <= rx_data[7];
                    addr_q  <= rx_data[1:0];
                    addr_ok <= (rx_data[6:2] == 5'b00000);
                    chk_acc <= rx_data ^ KEY;
                end
            end

            // Byte 2: DATA. Hold it and fold it into the checksum.
            GET_DATA:begin
                if(rx_valid)begin
                    data_q  <= rx_data;
                    chk_acc <= chk_acc ^ rx_data;
                    to_cnt  <= {CNT_W{1'b0}};
                end else
                    to_cnt <= to_cnt + 1'b1;
            end

            // Byte 3: CHK. Verify, commit a good write, and load the response.
            GET_CHK:begin
                if(rx_valid)begin
                    data_q <= NAK;                           // default response
                    if(frame_ok)begin
                        if(is_read)begin
                            if(rd_ok) data_q <= rd_val;      // read: reply with the register
                        end else begin
                            data_q <= ACK;                   // write: commit and acknowledge
                            case(addr_q)
                                2'd0: {xor_ones_in, init_ones_in, bus_16_in} <= data_q[2:0];
                                2'd1: poly_in[7:0]  <= data_q;
                                2'd2: poly_in[15:8] <= data_q;
                                2'd3:begin                   // preset load (ROM reads the old data_q)
                                    poly_in      <= rom_poly;
                                    init_ones_in <= rom_init;
                                    xor_ones_in  <= rom_xor;
                                    bus_16_in    <= data_q[3];
                                end
                            endcase
                        end
                    end
                end else
                    to_cnt <= to_cnt + 1'b1;
            end

            default: ;                                       // SEND: hold everything
        endcase
    end

endmodule