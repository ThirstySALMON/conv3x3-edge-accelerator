import cnn_pkg::*;

// top: fsm + window_gen + coeff_reg + 9 mults + 3-stage adder tree -> sat -> relu
// 1 pixel/cycle, win_valid -> valid_out is 3 cycles; a valid_in stall shows up as a bubble
module top #(
    parameter bit RELU = RELU_EN
) (
    input  logic            clk,
    input  logic            rst_n,

    input  logic [IN_W-1:0] input_in,
    input  logic            valid_in,

    // kernel load, ignored while busy; write_addr = 3*row + col, row-major like the taps (0 = w00 .. 8 = w22)
    input  logic              write_en,
    input  logic [3:0]        write_addr,
    input  logic [COEF_W-1:0] data_write,

    output logic signed [OUT_W-1:0] pixel_out,
    output logic                    valid_out,
    output logic                    busy
);

    // 3 * 255 * 128 = 97920 -> 18b signed
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

    control_fsm u_cu (
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

    window_gen u_wg (
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

    coeff_reg u_cr (  // write-locked while busy
        .clk(clk),
        .rst_n(rst_n),
        .write_en(write_en),
        .write_addr(write_addr),
        .data_write(data_write),
        .busy(busy),

        .coef_out(coef)
    );

    genvar k;
    generate
        for (k = 0; k < NTAP; k++) begin : g_mul
            mult8x8 u_mul (.coef(coef[k]), .pix(tap_out[k]), .prod(prod[k]));
        end
    endgenerate


    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < NTAP; i++) prod_r[i] <= '0;
            v_prod <= 1'b0;
        end else begin
            prod_r <= prod;
            v_prod <= win_valid;
        end
    end

    assign row_sum[0] = prod_r[0] + prod_r[1] + prod_r[2];
    assign row_sum[1] = prod_r[3] + prod_r[4] + prod_r[5];
    assign row_sum[2] = prod_r[6] + prod_r[7] + prod_r[8];

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 0; i < KSIZE; i++) row_r[i] <= '0;
            v_row <= 1'b0;
        end else begin
            row_r <= row_sum;
            v_row <= v_prod;
        end
    end

    assign acc = row_r[0] + row_r[1] + row_r[2];

    // saturate via sign-extension check (top 5 bits all equal) instead of two 20b compares
    logic [ACC_W-OUT_W:0] acc_top;
    logic                 fits;

    assign acc_top = acc[ACC_W-1 -: (ACC_W-OUT_W+1)];
    assign fits    = (acc_top == '0) || (acc_top == '1);

    always_comb begin
        if (fits)            sat = acc[OUT_W-1:0];
        else if (acc[ACC_W-1]) sat = OUT_MIN[OUT_W-1:0];
        else                   sat = OUT_MAX[OUT_W-1:0];
    end

    assign relu_out = (RELU && sat[OUT_W-1]) ? '0 : sat;

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
