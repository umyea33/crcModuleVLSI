# Programmable CRC Module with UART Configuration

## Overview
This project implements a highly configurable, hardware-accelerated CRC (Cyclic Redundancy Check) calculation block. The CRC polynomial and algorithm behavior (bus width, initialization, and final XOR) are fully programmable at runtime using a simplified UART interface.

## Register Map

The system uses two 16-bit registers to control the CRC engine.

| Address | Register Name | Description |
| :---: | :--- | :--- |
| `0x0` | **Polynomial** | 16-bit CRC polynomial. (e.g., `0x1021` for XMODEM/CCITT). |
| `0x1` | **Control Flags** | 16-bit configuration flags.<br>`[0]` `bus_16`: 1 = 16-bit data processing, 0 = 8-bit.<br>`[1]` `init_ones`: 1 = Init CRC with `0xFFFF`, 0 = Init with `0x0000`.<br>`[2]` `xor_ones`: 1 = XOR final output with `0xFFFF`, 0 = No XOR.<br>`[15:3]` Reserved (Write as 0). |

---

## UART Command Structure

The host configures the module by sending commands over UART (Default: 115200 Baud). The protocol uses a 1-byte command header followed by data payload(s).

### Command Byte Format

| Bit 7 | Bits 6:1 | Bit 0 |
| :---: | :---: | :---: |
| **R / W**<br>`1` = Write<br>`0` = Read | **Reserved**<br>Must be `000000` | **Address**<br>`0` = Polynomial<br>`1` = Control Flags |

* **`0x80`** : Write Polynomial
* **`0x81`** : Write Control Flags
* **`0x00`** : Read Polynomial
* **`0x01`** : Read Control Flags

---

### 1. Write Sequence (Host to Device)
To write to a register, the host sends **3 consecutive bytes**: the Command Byte, followed by the Data MSB, and finally the Data LSB.

```text
Host TX:  [ CMD_BYTE ] ---> [ DATA_MSB ] ---> [ DATA_LSB ]
          (e.g. 0x80)       (e.g. 0x10)       (e.g. 0x21)
```

**Example - Configuring for XMODEM CRC:**
1. Send `0x80` `0x10` `0x21` (Writes `0x1021` to Polynomial).
2. Send `0x81` `0x00` `0x00` (Writes `0x0000` to Control: 8-bit bus, Init=0, Xor=0).

*Note: If the transmission is interrupted mid-write, the device will silently time out after ~320 clock cycles and discard the incomplete frame, ready for the next command.*

---

### 2. Read Sequence (Bidirectional)
To read a register, the host sends a **1-byte command**. The device immediately responds with **2 bytes** (MSB then LSB).

```text
Host TX:   [ CMD_BYTE ]
           (e.g. 0x01)

Device TX:                [ DATA_MSB ] ---> [ DATA_LSB ]
                          (e.g. 0x00)       (e.g. 0x05)
```

**Example - Reading the Control Register:**
1. Host sends `0x01`.
2. Device responds with `0x00` then `0x05` (indicating `bus_16=1` and `xor_ones=1`).

---

## Hardware Operation Note (`clear` pin)
Writing to the UART registers updates the `control_unit` immediately, but **the `crc_block` only latches these new settings when the `clear` pin is pulsed HIGH.** 

**Typical Usage Flow:**
1. Program the `Polynomial` via UART.
2. Program the `Control Flags` via UART.
3. Pulse the hardware `clear` pin (latches config and resets the CRC accumulator).
4. Stream data into the `data_in` port using the `data_valid` strobe.
5. Read the final mathematical result from the `crc_out` port.
