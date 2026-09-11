import cnn_pkg::*;

// Top level: control_fsm + window_gen + coeff_reg + 9 LUT multipliers +
// pipelined adder tree -> saturate -> ReLU (RELU_EN) -> pixel_out.
// 1 output pixel/cycle. win_valid -> valid_out latency = 3 cycles.
//
//   comb  : prod[k] = tap_out[k] * coef[k]             9 x 16b
//   reg 1 : prod_r, v_prod
//   comb  : row_sum = a+b+c | d+e+f | g+h+i            3 x 18b
//   reg 2 : row_r, v_row
//   comb  : acc = row0+row1+row2 -> saturate -> relu   20b -> 16b
//   reg 3 : pixel_out, valid_out
//
// Pipeline regs are free-running; the valid bit travels with the data, so a
// valid_in stall shows up as a bubble in valid_out 3 cycles later.
module top #(
    parameter bit RELU = RELU_EN   // package default; tb_top_all overrides it to test both builds
) (
    input  logic            clk,
    input  logic            rst_n,

    input  logic [IN_W-1:0] input_in,
    input  logic            valid_in,

    // kernel load, ignored while busy. write_addr = 3*row + col, same
    // row-major order as the taps (0 = a = w00 ... 8 = i = w22).
    input  logic              write_en,
    input  logic [3:0]        write_addr,
    input  logic [COEF_W-1:0] data_write,

    //output logic [IN_W-1:0] taps [0:NTAP-1], // comment out , for debug

    output logic signed [OUT_W-1:0] pixel_out,
    output logic                    valid_out,
    output logic                    busy
);

    // Sum of 3 products: 3 * 255 * 128 = 97_920 -> 18 bits signed, lossless.
    localparam int ROW_W = PROD_W + 2;

    logic top_edge, bottom_edge, left_edge, right_edge;
    logic en, win_valid, frame_done;

    logic [IN_W-1:0]   tap_out [0:NTAP-1];
    logic [COEF_W-1:0] coef    [0:NTAP-1];

    logic signed [PROD_W-1:0] prod    [0:NTAP-1];
    logic signed [PROD_W-1:0] prod_r  [0:NTAP-1];
    logic signed [ROW_W-1:0]  row_sum [0:KSIZE-1];
    logic signed [ROW_W-1:0]  row_r   [0:KSIZE-1];
    logic signed [ACC_W-1:0]  acc;
    logic signed [OUT_W-1:0]  sat, relu_out;
    logic                     v_prod, v_row;

    control_fsm u_cu (  // Control FSM
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in),

        .en(en),
        .win_valid(win_valid),
        .top_edge(top_edge),
        .bottom_edge(bottom_edge),
        .left_edge(left_edge),
        .right_edge(right_edge),
        .busy(busy),
        .frame_done(frame_done)
    );

    window_gen u_wg (  // Window generator
        .clk(clk),
        .rst_n(rst_n),
        .input_in(input_in),

        .top_edge(top_edge),
        .left_edge(left_edge),
        .right_edge(right_edge),
        .bottom_edge(bottom_edge),

        .en(en),

        .tap_out(tap_out)
    );

//    assign taps = tap_out; // comment out , for debug

    coeff_reg u_cr (  // Coefficient register, write-locked while busy
        .clk(clk),
        .rst_n(rst_n),
        .write_en(write_en),
        .write_addr(write_addr),
        .data_write(data_write),
        .busy(busy),

        .coef_out(coef)
    );

    // ---------------- 9 multipliers -> stage 1 ----------------
    genvar k;
    generate
        for (k = 0; k < NTAP; k++) begin : g_mul
            mult8x8 u_mul (.coef(coef[k]), .pix(tap_out[k]), .prod(prod[k]));
        end
    endgenerate


    // First pipeline regs
    always_ff @(posedge clk) begin           // synchronous reset (intentional)
        if (!rst_n) begin
            for (int i = 0; i < NTAP; i++) prod_r[i] <= '0;
            v_prod <= 1'b0;
        end else begin
            prod_r <= prod;
            v_prod <= win_valid;
        end
    end

    // ---------------- row adders -> stage 2 ----------------
    assign row_sum[0] = prod_r[0] + prod_r[1] + prod_r[2];   // a+b+c
    assign row_sum[1] = prod_r[3] + prod_r[4] + prod_r[5];   // d+e+f
    assign row_sum[2] = prod_r[6] + prod_r[7] + prod_r[8];   // g+h+i


    //Second pipeline reg
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < KSIZE; i++) row_r[i] <= '0;
            v_row <= 1'b0;
        end else begin
            row_r <= row_sum;
            v_row <= v_prod;
        end
    end

    // ---------------- final adder, saturate, relu -> stage 3 ----------------
    assign acc = row_r[0] + row_r[1] + row_r[2];

    // Saturation by sign-extension check rather than two 20-bit magnitude compares.
    // acc fits in OUT_W signed exactly when the upper bits are all copies of bit
    // OUT_W-1, so testing acc[ACC_W-1:OUT_W-1] for all-ones / all-zeros is the same
    // answer for every value of acc, in 2 LUTs instead of two carry chains.
    // Verified exhaustively over all 2^20 accumulator values.
    logic [ACC_W-OUT_W:0] acc_top;       // acc[19:15], 5 bits
    logic                 fits;

    assign acc_top = acc[ACC_W-1 -: (ACC_W-OUT_W+1)];
    assign fits    = (acc_top == '0) || (acc_top == '1);

    always_comb begin
        if (fits)            sat = acc[OUT_W-1:0];
        else if (acc[ACC_W-1]) sat = OUT_MIN[OUT_W-1:0];   // negative -> -32768
        else                   sat = OUT_MAX[OUT_W-1:0];   // positive -> +32767
    end

    assign relu_out = (RELU && sat[OUT_W-1]) ? '0 : sat;   // clip negatives

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            pixel_out <= '0;
            valid_out <= 1'b0;
        end else begin
            pixel_out <= relu_out;
            valid_out <= v_row;
        end
    end

endmodule
