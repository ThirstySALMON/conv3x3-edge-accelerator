import cnn_pkg::*;

// 3x3 window datapath: 2 line buffers + 9 tap regs + border zeroing
// no position state here, control_fsm drives en and the edge flags
// tap map row-major: 0..2 top (LB1), 3..5 middle (LB0), 6..8 bottom (input_in); tap[4] is centre
module window_gen (
    input  logic            clk,
    input  logic            rst_n,

    input  logic [IN_W-1:0] input_in,

    input  logic            top_edge,
    input  logic            left_edge,
    input  logic            right_edge,
    input  logic            bottom_edge,

    input  logic            en,            // = valid_in, gates line buffers and taps

    output logic [IN_W-1:0] tap_out [0:NTAP-1]
);

    logic [IN_W-1:0] tap_reg [0:NTAP-1];
    logic [IN_W-1:0] in_f;   // LB0 out -> tap f and LB1 in
    logic [IN_W-1:0] in_c;   // LB1 out -> tap c

    line_buffer LB0 (
        .clk(clk), .rst_n(rst_n), .d_in(input_in), .en(en), .d_out(in_f)
    );

    line_buffer LB1 (
        .clk(clk), .rst_n(rst_n), .d_in(in_f),    .en(en), .d_out(in_c)
    );

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < NTAP; i++)
                tap_reg[i] <= '0;
        end else if (en) begin
            tap_reg[0] <= tap_reg[1];
            tap_reg[1] <= tap_reg[2];
            tap_reg[2] <= in_c;

            tap_reg[3] <= tap_reg[4];
            tap_reg[4] <= tap_reg[5];
            tap_reg[5] <= in_f;

            tap_reg[6] <= tap_reg[7];
            tap_reg[7] <= tap_reg[8];
            tap_reg[8] <= input_in;
        end
    end

    // separate ifs so a corner tap is zeroed by either flag, centre never touched
    always_comb begin
        for (int i = 0; i < NTAP; i++)
            tap_out[i] = tap_reg[i];

        if (top_edge)    begin tap_out[0] = '0; tap_out[1] = '0; tap_out[2] = '0; end
        if (bottom_edge) begin tap_out[6] = '0; tap_out[7] = '0; tap_out[8] = '0; end
        if (left_edge)   begin tap_out[0] = '0; tap_out[3] = '0; tap_out[6] = '0; end
        if (right_edge)  begin tap_out[2] = '0; tap_out[5] = '0; tap_out[8] = '0; end
    end

endmodule
