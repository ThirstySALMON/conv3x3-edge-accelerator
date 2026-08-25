// ================= STRUCTURAL (fixed) =================
IMG_W      = 32     // fixed
IMG_H      = 32     // fixed
KERNEL     = 3x3    // fixed
BORDER     = zero   // same-size 32x32 out, sustains 1 px/cycle
N_MAC      = TBD    // parked -> throughput architecture, decide before RTL

// ================= PRECISION (chosen) =================
IN_W       = 8      // unsigned, Q8.0
COEF_W     = 8      // signed
COEF_FRAC  = 0      // Q8.0 integer (DEFAULT). Kept as a parameter:
                    //   rebuild at 7 -> Q1.7 normalized blur/Gaussian
OUT_W      = 16     // signed, SATURATING
RELU_EN    = 0      // bonus toggle, default off

// ================= DERIVED (not chosen — forced by the math) =================
PROD_W     = 16     // 8u x 8s  -> Q16.0  (range -32640..+32385)
ACC_W      = 20     // sum of 9 -> lossless (9x255x128 = 293760)
ROUND      = n/a    // only exists when COEF_FRAC>0; at 0 the shift/round
                    //   path optimizes away entirely -> leanest datapath, best FoM