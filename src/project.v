/*
 * Copyright (c) 2026 FilteredNoise
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_filterednoise_infinity_core (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire[7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  // ==========================================
  // 1. SHARED HEARTBEAT COUNTER
  // ==========================================
  reg[23:0] heartbeat;
  always @(posedge clk) begin
      if (!rst_n) heartbeat <= 24'd0;
      else        heartbeat <= heartbeat + 1'b1;
  end

  wire spi_clk = heartbeat[5];
  wire [7:0] pwm_ramp = heartbeat[15:8];
  wire decay_tick = (heartbeat[19:0] == 20'b0);

  // ==========================================
  // 2. AUDIO TRIGGER EDGE DETECTION
  // ==========================================
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
          audio_trig_prev <= audio_trig;
          if (audio_hit) brightness <= 8'hFF; 
          else if (decay_tick && brightness > 8'd0) brightness <= brightness - 1'b1; 
      end
  end

  // ==========================================
  // 4. SPI SHIFT REGISTER (TX ENGINE)
  // ==========================================
  reg [7:0] shift_reg;
  reg[3:0] bit_cnt;
  reg       spi_busy;
  reg       spi_dc_reg;

  // Edge detectors for the SPI clock
  // heartbeat[5] falls exactly when heartbeat[5:0] hits 32 (binary 100000)
  // heartbeat[5] rises exactly when heartbeat[5:0] hits 0  (binary 000000)
  wire spi_fall = (heartbeat[5:0] == 6'b100000); 
  wire spi_rise = (heartbeat[5:0] == 6'b000000);

  // Test Logic: Send 0xAA (10101010) every time the audio hits
  wire       send_trigger = audio_hit;
  wire [7:0] data_to_send = 8'hAA; 

  always @(posedge clk) begin
      if (!rst_n) begin
          shift_reg  <= 8'd0;
          bit_cnt    <= 4'd0;
          spi_busy   <= 1'b0;
          spi_dc_reg <= 1'b1;
      end else begin
          // If we are idle and get a trigger to send data...
          if (!spi_busy) begin
              if (send_trigger) begin
                  shift_reg  <= data_to_send;
                  spi_dc_reg <= 1'b1; // 1 = Data Mode, 0 = Command Mode
                  bit_cnt    <= 4'd8; // We have 8 bits to send
                  spi_busy   <= 1'b1; // Lock the engine
              end
          end else begin
              // Shift data out on the FALLING edge of the SPI clock
              if (spi_fall && bit_cnt > 0) begin
                  shift_reg <= {shift_reg[6:0], 1'b0}; // Shift left
                  bit_cnt   <= bit_cnt - 1'b1;
              end 
              // Release the busy flag after the final RISING edge reads the last bit
              else if (spi_rise && bit_cnt == 0) begin
                  spi_busy <= 1'b0;
              end
          end
      end
  end

  wire spi_mosi = shift_reg[7]; // MSB is always the highest bit of the shift register

  // ==========================================
  // 5. OUTPUT WIRING
  // ==========================================
  assign uo_out[0] = (brightness > pwm_ramp); // PWM
  assign uo_out[1] = spi_clk;                 // SPI SCK 
  assign uo_out[2] = spi_mosi;                // SPI MOSI
  assign uo_out[3] = spi_dc_reg;              // SPI DC 
  assign uo_out[7:4] = 4'b0;

  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;
  wire _unused = &{ena, ui_in[7:1], uio_in, 1'b0};

endmodule
