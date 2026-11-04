# Universal CRC-16 Generator (`crc_block`)

## Overview
`crc_block` is a highly configurable, single-cycle hardware CRC-16 generator. It can process either 8 bits or 16 bits of data per clock cycle and supports dynamic configuration of the polynomial, initialization values, and final XOR masking.

The module is written in standard synthesizable Verilog and is designed to sit on a datapath bus (like AXI-Stream, Avalon-ST, or a custom internal bus), processing data on the fly.

## Port Map

### Clock & Control
| Port | Direction | Description |
| :--- | :--- | :--- |
| `clk` | Input | System clock. All operations are rising-edge triggered. |
| `clear` | Input | **Synchronous High Reset & Config Latch**. When `clear` is high, the module stops calculation, latches all configuration inputs (`poly_in`, `bus_16_in`, `xor_ones_in`), and resets the internal CRC state to the value dictated by `init_ones_in`. |

### Configuration (Sampled on `clear`)
*Note: These signals only need to be valid when `clear` is high. The module holds them internally afterward.*
| Port | Direction | Description |
| :--- | :--- | :--- |
| `poly_in` | Input [15:0] | The CRC polynomial in normal form (the implicit $x^{16}$ term is omitted). Example: `16'h1021` for CCITT. |
| `bus_16_in` | Input | **0**: 8-bit mode (processes `data_in[7:0]`).<br>**1**: 16-bit mode (processes `data_in[15:0]`). |
| `init_ones_in`| Input | **0**: Initializes internal CRC register to `16'h0000`.<br>**1**: Initializes internal CRC register to `16'hFFFF`. |
| `xor_ones_in` | Input | **0**: No final XOR applied (`crc_out` = internal state).<br>**1**: Inverts final output (`crc_out` = internal state ^ `16'hFFFF`). |

### Data Interface
| Port | Direction | Description |
| :--- | :--- | :--- |
| `data_valid` | Input | Clock enable for the data. The module only ingests `data_in` and updates the CRC state on a rising clock edge when `data_valid == 1`. |
| `data_in` | Input [15:0] | The payload data. In 8-bit mode (`bus_16_in = 0`), only the lower 8 bits (`[7:0]`) are used. |
| `crc_out` | Output [15:0]| The live CRC result. Valid continuously, reflecting the CRC of all data processed up to the previous clock cycle. |

---

## Assumptions & Usage Rules

1. **Configuration Lock-in**: 
   The configuration signals (`poly_in`, `bus_16_in`, etc.) **do not** affect the calculation directly. They are only sampled into hardware registers when `clear` is `1`. This means you must pulse `clear` high for at least one clock cycle to load a new configuration and prepare the module for a new packet.
   
2. **Data Valid Pausing**:
   `data_valid` acts as a strict clock enable. If your upstream data source has gaps (e.g., waiting for memory), simply pull `data_valid` low. The module will perfectly hold its current CRC state indefinitely until `data_valid` goes high again.
   
3. **Latency**:
   The module has **1 clock cycle of latency**. If you assert `data_valid` and provide data on Clock Edge 1, `crc_out` will reflect the updated CRC value immediately after Clock Edge 1 (available for sampling on Clock Edge 2).

4. **8-bit Mode Alignment**:
   When operating in 8-bit mode (`bus_16_in = 0`), the module expects the data byte to be on the **lower 8 bits** (`data_in[7:0]`). The upper 8 bits (`data_in[15:8]`) are ignored.

5. **Odd Byte Lengths on 16-bit Bus**:
   The 16-bit mode assumes every valid clock cycle contains exactly 2 bytes. If you have an odd-length packet (e.g., 9 bytes), you will need external logic to handle the final byte (e.g., reverting to 8-bit mode, or padding and applying a custom correction).

---

## Examples of Standard Protocols

Here is how you would configure the module for common CRC-16 standards:

| Standard | `poly_in` | `bus_16_in` | `init_ones_in` | `xor_ones_in` | Known Test String | Expected Output |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **CCITT-FALSE** | `16'h1021` | `0` | `1` | `0` | `"123456789"` | `16'h29B1` |
| **XMODEM** | `16'h1021` | `0` | `0` | `0` | `"123456789"` | `16'h31C3` |
| **BUYPASS** | `16'h8005` | `0` | `0` | `0` | `"123456789"` | `16'hFEE8` |
| **GENIBUS** | `16'h1021` | `0` | `1` | `1` | `"123456789"` | `16'hD64E` |
