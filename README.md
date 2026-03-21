![](../../workflows/gds/badge.svg) ![](../../workflows/docs/badge.svg) ![](../../workflows/test/badge.svg) ![](../../workflows/fpga/badge.svg)

# The Infinity Core

**A hardware-native, zero-CPU audio visualizer ASIC designed for the Tiny Tapeout shuttle.**

The Infinity Core is a standalone, hardware-accelerated audio visualizer that bridges analog signal processing, custom digital silicon design, and optical feedback. Designed to operate entirely without a traditional microcontroller, software, or memory buffers, the ASIC natively calculates and drives real-time audio-reactive light sequences and OLED pixel patterns through pure digital logic.

### System Architecture & Features

* **Pure Hardware Execution:** Written entirely in Verilog. The system relies on a 24-bit synchronous heartbeat counter and dedicated finite state machines (FSMs), achieving zero-latency execution without an operating system.
* **Algorithmic Visual Generation:** Utilizes a 32-bit Linear Feedback Shift Register (LFSR) and parallel probability comparators to render dynamic, audio-reactive pixel density directly to the display.
* **Custom Gated SPI Controller:** Features an interrupt-driven SPI shift register that autonomously initializes an SSD1306 OLED display and transmits 12 FPS video streams. The SPI clock is rigorously gated to ensure perfect Mode 0 phase alignment and signal integrity.
* **Hardware Quadrature Decoding:** Includes multi-stage synchronized and debounced decoders for two mechanical rotary encoders, enabling real-time adjustment of maximum brightness and LED/OLED decay rates.
* **Mixed-Signal Integration:** Designed to interface seamlessly with an external op-amp envelope follower/comparator circuit for precise, continuous analog beat detection.

### Pinout Specification

| Pin | Type | Function |
| :--- | :--- | :--- |
| `ui_in[0]` | Input | Digital Audio Trigger (Beat Pulse) |
| `ui_in[1:2]` | Input | Rotary Encoder 1 (Max Brightness / Pixel Density) |
| `ui_in[3:4]` | Input | Rotary Encoder 2 (LED / OLED Decay Speed) |
| `uo_out[0]` | Output | LED PWM Signal (Drives external MOSFET) |
| `uo_out[1]` | Output | SPI Clock (`SCK`) - Gated 781 kHz |
| `uo_out[2]` | Output | SPI Data (`MOSI`) |
| `uo_out[3]` | Output | SPI Data/Command (`DC`) |
| `uo_out[4]` | Output | SPI Chip Select (`CS`) - Active Low |
| `uo_out[5]` | Output | Debug Heartbeat Indicator (3 Hz Blink) |

### Verification & Testing
This design has been rigorously verified using `cocotb` and `iverilog`. The provided testbenches simulate over 60 milliseconds of real-world operational timing, covering physical encoder bounce resolution, 5.24ms hardware boot delays, SPI protocol compliance, and interrupt-driven frame rendering.

Furthermore, the RTL has been successfully synthesized and validated on physical hardware using a **Sipeed Tang Nano 9K FPGA**. This hardware-in-the-loop testing confirmed real-world logic stability, asynchronous input synchronization, and peripheral driving capabilities.

To generate the physical gate-level schematic and analyze the logic visually:
```bash
make diagram
```
(Requires Yosys and netlistsvg)
