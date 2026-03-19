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
    output wire[7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

  // ==========================================
  // 1. INPUT INTERFACE (ROTARY ENCODERS)
  // ==========================================
  wire [7:0] enc1_val; // Max Brightness & Noise Density
  wire [7:0] enc2_val; // Decay Rate

  quad_decoder encoder1 (
      .clk(clk), .rst_n(rst_n),
      .enc_a(ui_in[1]), .enc_b(ui_in[2]),
      .count(enc1_val)
  );

  quad_decoder encoder2 (
      .clk(clk), .rst_n(rst_n),
      .enc_a(ui_in[3]), .enc_b(ui_in[4]),
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

  wire[7:0] pwm_ramp = heartbeat[15:8];
  
  // DYNAMIC DECAY
  reg decay_tick;
  always @(*) begin
      case(enc2_val[7:5]) 
          3'd0: decay_tick = (heartbeat[16:0] == 17'd0); // Super Fast (Real-world value)
          3'd1: decay_tick = (heartbeat[17:0] == 18'd0);
          3'd2: decay_tick = (heartbeat[18:0] == 19'd0);
          3'd3: decay_tick = (heartbeat[19:0] == 20'd0); 
          3'd4: decay_tick = (heartbeat[20:0] == 21'd0);
          3'd5: decay_tick = (heartbeat[21:0] == 22'd0);
          3'd6: decay_tick = (heartbeat[22:0] == 23'd0);
          3'd7: decay_tick = (heartbeat[23:0] == 24'd0); // Slow
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
          
          if (audio_hit) brightness <= enc1_val; 
          else if (decay_tick && brightness > 8'd0) brightness <= brightness - 1'b1; 
      end
  end

  // ==========================================
  // 4. LFSR NOISE & PROBABILITY ENGINE
  // ==========================================
  reg[31:0] lfsr;
  always @(posedge clk) begin
      if (!rst_n) begin
          lfsr <= 32'hACE1ACE1; // Must be non-zero seed
      end else begin
          // Standard Galois LFSR polynomial taps
          lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[21] ^ lfsr[1] ^ lfsr[0]};
      end
  end

  wire[7:0] noise_byte;
  // If random number is less than brightness, pixel is ON (1). Else OFF (0).
  assign noise_byte[0] = (lfsr[7:0]   < brightness);
  assign noise_byte[1] = (lfsr[15:8]  < brightness);
  assign noise_byte[2] = (lfsr[23:16] < brightness);
  assign noise_byte[3] = (lfsr[31:24] < brightness);
  assign noise_byte[4] = ({lfsr[3:0],   lfsr[31:28]} < brightness);
  assign noise_byte[5] = ({lfsr[11:8],  lfsr[7:4]}   < brightness);
  assign noise_byte[6] = ({lfsr[19:16], lfsr[15:12]} < brightness);
  assign noise_byte[7] = ({lfsr[27:24], lfsr[23:20]} < brightness);

  // ==========================================
  // 5. MASTER STATE MACHINE & FRAME CONTROLLER
  // ==========================================
  localparam STATE_BOOT       = 2'd0;
  localparam STATE_INIT       = 2'd1;
  localparam STATE_WAIT_FRAME = 2'd2;
  localparam STATE_DRAW_FRAME = 2'd3;

  reg [1:0] system_state;
  reg [2:0] init_index;
  reg [7:0] init_cmd;
  reg [9:0] pixel_cnt;
  reg       last_frame_tick;

  // heartbeat[21] flips every ~83 milliseconds = ~12 Frames Per Second
  wire frame_tick = heartbeat[21];

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
  reg       cs_val; // Chip Select Register
  wire      spi_busy; 

  always @(posedge clk) begin
      if (!rst_n) begin
          system_state    <= STATE_BOOT;
          init_index      <= 3'd0;
          send_trigger    <= 1'b0;
          dc_val          <= 1'b0;
          cs_val          <= 1'b1; // CS is Active LOW, default to HIGH (deselected)
          pixel_cnt       <= 10'd0;
          last_frame_tick <= 1'b0;
      end else begin
          send_trigger    <= 1'b0; 
          last_frame_tick <= frame_tick;

          case (system_state)
              STATE_BOOT: begin
                  // Wait ~5ms for hardware OLED stabilization
                  if (heartbeat[18]) system_state <= STATE_INIT; 
              end

              STATE_INIT: begin
                  if (!spi_busy && !send_trigger) begin
                      if (init_index < 4) begin
                          cs_val       <= 1'b0; // Select Display
                          dc_val       <= 1'b0; // Command Mode
                          data_to_send <= init_cmd;
                          send_trigger <= 1'b1;
                          init_index   <= init_index + 1'b1;
                      end else begin
                          cs_val       <= 1'b1; // Deselect Display
                          system_state <= STATE_WAIT_FRAME;
                      end
                  end
              end

              STATE_WAIT_FRAME: begin
                  if ((frame_tick && !last_frame_tick) || audio_hit) begin
                      pixel_cnt    <= 10'd0;
                      cs_val       <= 1'b0; // Select Display for upcoming frame
                      system_state <= STATE_DRAW_FRAME;
                  end
              end

              STATE_DRAW_FRAME: begin
                  if (!spi_busy && !send_trigger) begin
                      dc_val       <= 1'b1; // Data Mode
                      data_to_send <= noise_byte;
                      send_trigger <= 1'b1;
                      
                      if (pixel_cnt == 10'd1023) begin
                          cs_val       <= 1'b1; // Deselect Display (Frame Complete)
                          system_state <= STATE_WAIT_FRAME; 
                      end else begin
                          pixel_cnt <= pixel_cnt + 1'b1;
                      end
                  end
              end
              
              default: system_state <= STATE_BOOT;
          endcase
      end
  end

  // ==========================================
  // 6. GATED SPI SHIFT REGISTER (TX ENGINE)
  // ==========================================
  reg [7:0] shift_reg;
  reg [3:0] bit_cnt;
  reg       spi_busy_reg;
  reg       spi_dc_reg;
  reg [5:0] spi_div;      // Generates internal SPI clock
  reg       spi_clk_out;  // The actual gated clock pin

  assign spi_busy = spi_busy_reg;

  always @(posedge clk) begin
      if (!rst_n) begin
          shift_reg    <= 8'd0;
          bit_cnt      <= 4'd0;
          spi_busy_reg <= 1'b0;
          spi_dc_reg   <= 1'b1;
          spi_div      <= 6'd0;
          spi_clk_out  <= 1'b0;
      end else begin
          if (!spi_busy_reg) begin
              spi_clk_out <= 1'b0; // Ensure clock is flat LOW when idle
              spi_div     <= 6'd0;
              if (send_trigger) begin
                  shift_reg    <= data_to_send;
                  spi_dc_reg   <= dc_val; 
                  bit_cnt      <= 4'd8; 
                  spi_busy_reg <= 1'b1; 
              end
          end else begin
              spi_div <= spi_div + 1'b1;
              
              // Rising Edge: Display reads the bit
              if (spi_div == 6'd31) begin
                  spi_clk_out <= 1'b1;
              end 
              // Falling Edge: We load the next bit onto the wire
              else if (spi_div == 6'd63) begin
                  spi_clk_out <= 1'b0;
                  shift_reg   <= {shift_reg[6:0], 1'b0}; 
                  bit_cnt     <= bit_cnt - 1'b1;
                  
                  if (bit_cnt == 4'd1) begin
                      spi_busy_reg <= 1'b0; // End transmission after 8th bit
                  end
              end
          end
      end
  end

  wire spi_mosi = shift_reg[7];

  // ==========================================
  // 7. OUTPUT WIRING
  // ==========================================
  assign uo_out[0] = (brightness > pwm_ramp); 
  assign uo_out[1] = spi_clk_out;             // Gated SPI Clock
  assign uo_out[2] = spi_mosi;                
  assign uo_out[3] = spi_dc_reg;              
  assign uo_out[4] = cs_val;                  // Active LOW Chip Select
  assign uo_out[7:5] = 3'b0;

  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;
  wire _unused = &{ena, ui_in[7:5], uio_in, enc2_val[4:0], 1'b0};

endmodule


// ==========================================
// 8. QUADRATURE DECODER MODULE (SNAPPY VERSION)
// ==========================================
module quad_decoder (
    input wire clk,
    input wire rst_n,
    input wire enc_a,
    input wire enc_b,
    output reg [7:0] count
);
    reg [2:0] a_sync;
    reg [2:0] b_sync;
    
    // Sink unused bits for a clean linter
    wire _unused_bits = &{a_sync[0], b_sync[2], b_sync[0], 1'b0};

    always @(posedge clk) begin
        if (!rst_n) begin
            a_sync <= 3'b000;
            b_sync <= 3'b000;
            count  <= 8'd128; // Start knobs exactly in the middle!
        end else begin
            a_sync <= {a_sync[1:0], enc_a};
            b_sync <= {b_sync[1:0], enc_b};

            if (a_sync[2:1] == 2'b01) begin
                if (b_sync[1] == 1'b0) begin
                    // Increment by 8, but stop at 255
                    if (count <= 8'd247) count <= count + 8'd8;
                    else                 count <= 8'd255;
                end else begin
                    // Decrement by 8, but stop at 0
                    if (count >= 8'd8)   count <= count - 8'd8;
                    else                 count <= 8'd0;
                end
            end
        end
    end
endmodule
