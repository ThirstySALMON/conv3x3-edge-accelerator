import cnn_pkg::*;

// Dumb datapath: 2 line buffers + 9 tap regs + border zero-muxes.
// Holds NO frame-position state and produces NO valid_out - control_fsm owns
// all position/timing and drives en + the four edge flags.
//
// Tap map (row-major):   tap[0..2] = a b c  (top,    from LB1)
//                        tap[3..5] = d e f  (middle, from LB0)
//                        tap[6..8] = g h i  (bottom, from input_in)
// tap[4] = center = w11, never zeroed.
module window_gen (
    input  logic            clk,
    input  logic            rst_n,

    input  logic [IN_W-1:0] input_in,

    // padding controls, driven by control_fsm
    input  logic            top_edge,
    input  logic            left_edge,
    input  logic            right_edge,
    input  logic            bottom_edge,

    input  logic            en,            // = valid_in; gates every seq element

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

    always_ff @(posedge clk) begin           // synchronous reset (intentional)
        if (!rst_n) begin
            for (int i = 0; i < NTAP; i++)
                tap_reg[i] <= '0;
        end else if (en) begin
            tap_reg[0] <= tap_reg[1];        // a <- b
            tap_reg[1] <= tap_reg[2];        // b <- c
            tap_reg[2] <= in_c;              // c <- LB1

            tap_reg[3] <= tap_reg[4];        // d <- e
            tap_reg[4] <= tap_reg[5];        // e <- f
            tap_reg[5] <= in_f;              // f <- LB0

            tap_reg[6] <= tap_reg[7];        // g <- h
            tap_reg[7] <= tap_reg[8];        // h <- i
            tap_reg[8] <= input_in;          // i <- current pixel
        end
    end

    // Border zeroing. Separate ifs == OR behaviour, so a corner tap is zeroed
    // by both of its flags. Center tap[4] is never touched.
    always_comb begin
        for (int i = 0; i < NTAP; i++)
            tap_out[i] = tap_reg[i];

        if (top_edge)    begin tap_out[0] = '0; tap_out[1] = '0; tap_out[2] = '0; end
        if (bottom_edge) begin tap_out[6] = '0; tap_out[7] = '0; tap_out[8] = '0; end
        if (left_edge)   begin tap_out[0] = '0; tap_out[3] = '0; tap_out[6] = '0; end
        if (right_edge)  begin tap_out[2] = '0; tap_out[5] = '0; tap_out[8] = '0; end
    end

endmodule
