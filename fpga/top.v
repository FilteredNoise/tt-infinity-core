`default_nettype none

module top (
    input  wire clk,    
    input  wire btn_s1, 
    output wire [5:0] led 
);

    wire [7:0] ui_in;
    wire [7:0] uo_out;

    // --- 1. POWER-ON RESET ---
    reg [22:0] por_cnt = 0;
    wire rst_n = por_cnt[22]; 
    always @(posedge clk) if (!rst_n) por_cnt <= por_cnt + 1;

    // --- 2. DEBOUNCER & HOLD TIMER ---
    reg [17:0] db_cnt;
    reg btn_clean;
    always @(posedge clk) begin
        if (btn_s1 == btn_clean) db_cnt <= 0;
        else begin
            db_cnt <= db_cnt + 1;
            if (db_cnt == 18'd250_000) btn_clean <= btn_s1;
        end
    end

    reg [24:0] hold_timer;
    always @(posedge clk) begin
        if (!btn_clean) hold_timer <= hold_timer + 1;
        else            hold_timer <= 0;
    end
    
    wire is_holding = (hold_timer > 25'd13_500_000);

    // --- 3. INPUT MAPPING ---
    assign ui_in[0] = (~btn_clean) && !is_holding; 
    assign ui_in[3] = is_holding ? hold_timer[22] : 1'b0; 
    assign ui_in[4] = 1'b1; // Direction: Faster
    assign ui_in[2:1] = 2'b0;
    assign ui_in[7:5] = 3'b0;

    // --- 4. THE ASIC CORE ---
    tt_um_filterednoise_infinity_core infinity_core (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (8'b0),
        .uio_out (),
        .uio_oe  (),
        .ena     (1'b1),
        .clk     (clk),
        .rst_n   (rst_n) 
    );

    // --- 5. PHYSICAL LED MAP (Matching the Official CST) ---
    assign led[0] = ~uo_out[5];       // LED 0: Heartbeat
    assign led[1] = ~is_holding;      // LED 1: "Adjusting Speed" Mode
    assign led[2] = ~btn_clean;       // LED 2: Button Status
    assign led[3] = ~uo_out[4];       // LED 3: SPI CS Flicker
    assign led[4] = ~ui_in[3];        // LED 4: Encoder Click Monitor
    assign led[5] = ~uo_out[0];       // LED 5: THE VISUALIZER

endmodule
