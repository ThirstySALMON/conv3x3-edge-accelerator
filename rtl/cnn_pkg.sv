// cnn_pkg.sv - design parameters shared by all rtl
package cnn_pkg;

    parameter int IMG_W    = 32;
    parameter int IMG_H    = 32;
    parameter int KSIZE    = 3;
    parameter int NTAP     = KSIZE * KSIZE;
    parameter int N_MAC    = 9;    // fully parallel, 1 output pixel/cycle

    parameter int LB_DEPTH = IMG_W;           // full row delay, not IMG_W-3

    parameter int IN_W     = 8;    // unsigned Q8.0
    parameter int COEF_W   = 8;    // signed
    parameter int COEF_FRAC = 0;   // 0 = Q8.0, 7 = Q1.7
    parameter int OUT_W    = 16;   // signed, saturating
    parameter bit RELU_EN  = 1'b0;

    parameter int PROD_W   = IN_W + COEF_W;   // 8u x 8s fits 16 signed

    parameter int ACC_W    = 20;   // 9*255*128 = 293760 needs 20 bits signed

    parameter logic signed [ACC_W-1:0] OUT_MAX =  (1 <<< (OUT_W-1)) - 1;
    parameter logic signed [ACC_W-1:0] OUT_MIN = -(1 <<< (OUT_W-1));

    // only LB0 sits before the centre tap (LB1 feeds the zero-masked top row): 32 + tap reg + f->e shift
    parameter int FILL_CYCLES = LB_DEPTH + 2;

    parameter int NPIX = IMG_W * IMG_H;

    // output-only cycles must equal consume-only cycles; the extra shifts push garbage into the bottom tap row, masked by bottom_edge/right_edge
    parameter int DRAIN_CYCLES = FILL_CYCLES;

endpackage
