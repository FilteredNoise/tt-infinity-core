/*
 * Copyright (c) 2026 FilteredNoise
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_filterednoise_infinity_core (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire[7:0] uio_oe,
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
  // 2. AUDIO TRIGGER EDGE DETECTION & DECAY
  // ==========================================
  reg audio_trig_prev;
  wire audio_trig = ui_in[0];
  wire audio_hit = (audio_trig && !audio_trig_prev);

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
  // 3. MASTER STATE MACHINE & INIT ROM
  // ==========================================
  localparam STATE_BOOT = 2'd0;
  localparam STATE_INIT = 2'd1;
  localparam STATE_RUN  = 2'd2;

  reg [1:0] system_state;
  reg[2:0] init_index;
  reg [7:0] init_cmd;

  // The 4 commands needed to wake up the SSD1306
  always @(*) begin
      case(init_index)
          3'd0: init_cmd = 8'hAE; // Display OFF
          3'd1: init_cmd = 8'h20; // Set Memory Addressing Mode
          3'd2: init_cmd = 8'h00; // Horizontal Addressing Mode
          3'd3: init_cmd = 8'hAF; // Display ON
          default: init_cmd = 8'h00;
      endcase
  end

  reg       send_trigger;
  reg[7:0] data_to_send;
  reg       dc_val;
  wire      spi_busy; // (Defined below in SPI block)

  always @(posedge clk) begin
      if (!rst_n) begin
          system_state <= STATE_BOOT;
          init_index   <= 3'd0;
          send_trigger <= 1'b0;
          dc_val       <= 1'b0;
      end else begin
          send_trigger <= 1'b0; // Default to not triggering

          case (system_state)
              STATE_BOOT: begin
                  // Wait ~5ms for OLED internal power-on reset
                  if (heartbeat[18]) system_state <= STATE_INIT;
              end

              STATE_INIT: begin
                  // If SPI is free, send the next command
                  if (!spi_busy && !send_trigger) begin
                      if (init_index < 4) begin
                          dc_val       <= 1'b0; // Command Mode
                          data_to_send <= init_cmd;
                          send_trigger <= 1'b1;
                          init_index   <= init_index + 1'b1;
                      end else begin
                          system_state <= STATE_RUN;
                      end
                  end
              end

              STATE_RUN: begin
                  // We are booted! Endlessly stream pixels.
                  if (!spi_busy && !send_trigger) begin
                      dc_val       <= 1'b1; // Data Mode
                      
                      // TEMPORARY PATTERN: 
                      // If the beat hits, the screen turns solid white. 
                      // As it decays, it turns into scrolling static noise!
                      data_to_send <= (brightness > 128) ? 8'hFF : heartbeat[12:5]; 
                      
                      send_trigger <= 1'b1;
                  end
              end
          endcase
      end
  end

  // ==========================================
  // 4. SPI SHIFT REGISTER (TX ENGINE)
  // ==========================================
  reg [7:0] shift_reg;
  reg[3:0] bit_cnt;
  reg       spi_busy_reg;
  reg       spi_dc_reg;

  wire spi_fall = (heartbeat[5:0] == 6'b100000); 
  wire spi_rise = (heartbeat[5:0] == 6'b000000);
  
  assign spi_busy = spi_busy_reg;

  always @(posedge clk) begin
      if (!rst_n) begin
          shift_reg    <= 8'd0;
          bit_cnt      <= 4'd0;
          spi_busy_reg <= 1'b0;
          spi_dc_reg   <= 1'b1;
      end else begin
          if (!spi_busy_reg) begin
              if (send_trigger) begin
                  shift_reg    <= data_to_send;
                  spi_dc_reg   <= dc_val; 
                  bit_cnt      <= 4'd8; 
                  spi_busy_reg <= 1'b1; 
              end
          end else begin
              if (spi_fall && bit_cnt > 0) begin
                  shift_reg <= {shift_reg[6:0], 1'b0}; 
                  bit_cnt   <= bit_cnt - 1'b1;
              end else if (spi_rise && bit_cnt == 0) begin
                  spi_busy_reg <= 1'b0;
              end
          end
      end
  end

  wire spi_mosi = shift_reg[7];

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