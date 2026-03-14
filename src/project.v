/*
 * Copyright (c) 2026 FilteredNoise
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_filterednoise_infinity_core (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // ==========================================
  // 1. SHARED HEARTBEAT COUNTER
  // ==========================================
  // A 24-bit counter that simply counts up forever.
  // This costs about 120-150 logic gates, but we use it for EVERYTHING.
  reg[23:0] heartbeat;

  always @(posedge clk) begin
      if (!rst_n) begin
          heartbeat <= 24'd0;
      end else begin
          heartbeat <= heartbeat + 1'b1;
      end
  end

  // -- Extracting Frequencies --
  
  // SPI Clock: heartbeat[5] = ~1.5 MHz (Very safe for SPI OLEDs)
  wire spi_clk = heartbeat[5];

  // PWM Ramp: An 8-bit saw-tooth wave running at 762 Hz.
  // We use bits[15:8]. 50MHz / 2^16 = ~762 Hz (Perfect for LED flicker-free PWM).
  wire [7:0] pwm_ramp = heartbeat[15:8];

  // Decay Tick: Pulses high once every ~1 million cycles.
  // 50 MHz / 2^20 = ~47.6 Hz (Perfect for dropping brightness smoothly).
  wire decay_tick = (heartbeat[19:0] == 20'b0);


  // ==========================================
  // 2. AUDIO TRIGGER EDGE DETECTION
  // ==========================================
  // If the audio pulse stays high, we only want to trigger once on the rising edge.
  reg audio_trig_prev;
  wire audio_trig = ui_in[0];
  wire audio_hit = (audio_trig && !audio_trig_prev);


  // ==========================================
  // 3. LED PWM & DECAY ENGINE
  // ==========================================
  reg [7:0] brightness;

  always @(posedge clk) begin
      if (!rst_n) begin
          audio_trig_prev <= 1'b0;
          brightness <= 8'd0;
      end else begin
          // Track previous state for edge detection
          audio_trig_prev <= audio_trig;

          // If the beat hits, jump to 100% brightness
          if (audio_hit) begin
              brightness <= 8'hFF; 
          end 
          // Otherwise, slowly fade out based on our Decay Tick
          else if (decay_tick && brightness > 8'd0) begin
              brightness <= brightness - 1'b1; 
          end
      end
  end

  // Generate the actual PWM signal by comparing the ramp to the brightness
  wire pwm_out = (brightness > pwm_ramp);


  // ==========================================
  // 4. OUTPUT WIRING
  // ==========================================
  assign uo_out[0] = (brightness > pwm_ramp); // PWM
  assign uo_out[1] = spi_clk;                 // SPI SCK (Placeholder)
  assign uo_out[2] = 1'b0;                    // SPI MOSI (Placeholder)
  assign uo_out[3] = 1'b1;                    // SPI DC (Default to Command mode)
  assign uo_out[7:4] = 4'b0;

  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

  // Tie off unused inputs to prevent synthesis warnings.
  // We are now using ui_in[0], so only [7:1] are unused!
  wire _unused = &{ena, ui_in[7:1], uio_in, 1'b0};

endmodule
