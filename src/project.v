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
  // 1. INPUT INTERFACE (ROTARY ENCODERS)
  // ==========================================
  wire [7:0] enc1_val; // Max Brightness
  wire [7:0] enc2_val; // Decay Rate

  // Encoder 1 (ui_in[1] and ui_in[2])
  quad_decoder encoder1 (
      .clk(clk),
      .rst_n(rst_n),
      .enc_a(ui_in[1]),
      .enc_b(ui_in[2]),
      .count(enc1_val)
  );

  // Encoder 2 (ui_in[3] and ui_in[4])
  quad_decoder encoder2 (
      .clk(clk),
      .rst_n(rst_n),
      .enc_a(ui_in[3]),
      .enc_b(ui_in[4]),
      .count(enc2_val)
  );


  // ==========================================
  // 2. SHARED HEARTBEAT COUNTER
  // ==========================================
  reg[23:0] heartbeat;
  always @(posedge clk) begin
      if (!rst_n) heartbeat <= 24'd0;
      else        heartbeat <= heartbeat + 1'b1;
  end

  wire spi_clk = heartbeat[5];
  wire [7:0] pwm_ramp = heartbeat[15:8];
  
  // DYNAMIC DECAY: We use Encoder 2 to change which heartbeat bit triggers the decay!
  // If enc2_val is high, it uses a higher bit (slower decay).
  reg decay_tick;
  always @(*) begin
      case(enc2_val[7:5]) // Use the top 3 bits to give us 8 speed zones
          3'd0: decay_tick = (heartbeat[16:0] == 17'd0); // Super Fast!
          3'd1: decay_tick = (heartbeat[17:0] == 18'd0);
          3'd2: decay_tick = (heartbeat[18:0] == 19'd0);
          3'd3: decay_tick = (heartbeat[19:0] == 20'd0); // Normal (Start value)
          3'd4: decay_tick = (heartbeat[20:0] == 21'd0);
          3'd5: decay_tick = (heartbeat[21:0] == 22'd0);
          3'd6: decay_tick = (heartbeat[22:0] == 23'd0);
          3'd7: decay_tick = (heartbeat[23:0] == 24'd0); // Super Slow!
      endcase
  end


  // ==========================================
  // 3. AUDIO TRIGGER EDGE DETECTION & DECAY
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
          
          // DYNAMIC BRIGHTNESS: Jump to Encoder 1's value instead of hardcoded FF!
          if (audio_hit) brightness <= enc1_val; 
          else if (decay_tick && brightness > 8'd0) brightness <= brightness - 1'b1; 
      end
  end

  // ==========================================
  // 4. MASTER STATE MACHINE & INIT ROM
  // ==========================================
  localparam STATE_BOOT = 2'd0;
  localparam STATE_INIT = 2'd1;
  localparam STATE_RUN  = 2'd2;

  reg [1:0] system_state;
  reg [2:0] init_index;
  reg [7:0] init_cmd;

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
  reg [7:0] data_to_send;
  reg       dc_val;
  wire      spi_busy; 

  always @(posedge clk) begin
      if (!rst_n) begin
          system_state <= STATE_BOOT;
          init_index   <= 3'd0;
          send_trigger <= 1'b0;
          dc_val       <= 1'b0;
      end else begin
          send_trigger <= 1'b0; 

          case (system_state)
              STATE_BOOT: begin
                  if (heartbeat[6]) system_state <= STATE_INIT; // Fast boot for simulation
              end

              STATE_INIT: begin
                  if (!spi_busy && !send_trigger) begin
                      if (init_index < 4) begin
                          dc_val       <= 1'b0; 
                          data_to_send <= init_cmd;
                          send_trigger <= 1'b1;
                          init_index   <= init_index + 1'b1;
                      end else begin
                          system_state <= STATE_RUN;
                      end
                  end
              end

              STATE_RUN: begin
                  if (!spi_busy && !send_trigger) begin
                      dc_val       <= 1'b1; 
                      data_to_send <= (brightness > 128) ? 8'hFF : heartbeat[12:5]; 
                      send_trigger <= 1'b1;
                  end
              end
              
              default: system_state <= STATE_BOOT;
          endcase
      end
  end

  // ==========================================
  // 5. SPI SHIFT REGISTER (TX ENGINE)
  // ==========================================
  reg [7:0] shift_reg;
  reg [3:0] bit_cnt;
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
  // 6. OUTPUT WIRING
  // ==========================================
  assign uo_out[0] = (brightness > pwm_ramp); 
  assign uo_out[1] = spi_clk;                 
  assign uo_out[2] = spi_mosi;                
  assign uo_out[3] = spi_dc_reg;              
  assign uo_out[7:4] = 4'b0;

  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;
  wire _unused = &{ena, ui_in[7:5], uio_in, 1'b0};

endmodule


// ==========================================
// 7. NEW MODULE: QUADRATURE DECODER
// ==========================================
module quad_decoder (
    input wire clk,
    input wire rst_n,
    input wire enc_a,
    input wire enc_b,
    output reg [7:0] count
);
    // 3-bit shift registers for synchronization and edge detection
    reg [2:0] a_sync;
    reg [2:0] b_sync;

    always @(posedge clk) begin
        if (!rst_n) begin
            a_sync <= 3'b000;
            b_sync <= 3'b000;
            count  <= 8'd128; // Start knobs exactly in the middle!
        end else begin
            // Shift new values in from the right (synchronizing them)
            a_sync <= {a_sync[1:0], enc_a};
            b_sync <= {b_sync[1:0], enc_b};

            // Detect a RISING edge on Pin A (went from 0 to 1)
            if (a_sync[2:1] == 2'b01) begin
                // If B is low, we are turning Clockwise
                if (b_sync[1] == 1'b0) begin
                    if (count < 8'hFF) count <= count + 1'b1; // Prevent overflowing past 255
                end 
                // If B is high, we are turning Counter-Clockwise
                else begin
                    if (count > 8'h00) count <= count - 1'b1; // Prevent underflowing past 0
                end
            end
        end
    end
endmodule
