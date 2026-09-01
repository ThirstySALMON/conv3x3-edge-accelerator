// ============================================================================
// cnn_pkg.sv - single source of truth for all design parameters.
// Values locked per docs/ARCHITECTURE_LOCKED.md. Do not change without
// updating that file first.
// ============================================================================
package cnn_pkg;

    // ---------------- Structural (fixed) ----------------
    parameter int IMG_W    = 32;   // image width  (frozen)
    parameter int IMG_H    = 32;   // image height (frozen)
    parameter int KSIZE    = 3;    // 3x3 kernel
    parameter int NTAP     = KSIZE * KSIZE;   // 9 taps
    parameter int N_MAC    = 9;    // fully parallel -> 1 output pixel/cycle

    // Line buffer depth = one full row of vertical delay. NOT IMG_W-3.
    parameter int LB_DEPTH = IMG_W;           // 32

    // ---------------- Precision ----------------
    parameter int IN_W     = 8;    // input pixel, unsigned Q8.0 (0..255)
    parameter int COEF_W   = 8;    // kernel coefficient, signed
    parameter int COEF_FRAC = 0;   // TOGGLE: 0 = Q8.0 (shipping). 7 = Q1.7 rebuild.
    parameter int OUT_W    = 16;   // output pixel, signed, saturating
    parameter bit RELU_EN  = 1'b0; // TOGGLE: bonus stage, default off

    // ---------------- Derived (forced by the math, not chosen) ----------------
    // 8u x 8s -> range -32640..+32385, fits 16 bits signed.
    parameter int PROD_W   = IN_W + COEF_W;   // 16

    // Sum of 9 products: 9 * 255 * 128 = 293_760 -> needs 20 bits signed, lossless.
    parameter int ACC_W    = 20;

    // Saturation limits applied at the ACC_W -> OUT_W narrowing stage.
    parameter logic signed [ACC_W-1:0] OUT_MAX =  (1 <<< (OUT_W-1)) - 1;  //  32767
    parameter logic signed [ACC_W-1:0] OUT_MIN = -(1 <<< (OUT_W-1));      // -32768

    // ---------------- Timing ----------------
    // Cycles of pipeline fill before the first valid 3x3 window is at the taps.
    // Derived cycle-accurately from window_gen + line_buffer as written:
    // output (0,0) is correct at enabled-cycle 34, then 1:1 gapless for 1024.
    // = LB0 depth (32) + 1 tap reg to reach f + 1 shift f->e  ->  34.
    // Only ONE line buffer sits between the input and the centre tap; LB1
    // feeds the top row, which is zero-masked on row 0 and so does not gate
    // the first valid output.
    parameter int FILL_CYCLES = LB_DEPTH + 2;  // 34

    parameter int NPIX = IMG_W * IMG_H;        // 1024 outputs per frame

endpackage
