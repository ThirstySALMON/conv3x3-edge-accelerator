# 7. Fixed-Point Bit-Width Analysis

Every arithmetic width in the design is derived from the input and coefficient formats
rather than chosen, and every intermediate stage is lossless up to the final narrowing. The
only place information is discarded is the deliberate 20-bit to 16-bit saturation at the
output, which is the behaviour the specification requires to be explained.

## 7.1 Input Precision and Its Justification

The input pixel format is **8-bit unsigned, Q8.0** (integer range 0 to 255), set by
`IN_W = 8` in rtl/cnn_pkg.sv.

- **Matches the source data exactly.** 8-bit grayscale is the native output of essentially
  every image sensor and the standard storage format for single-channel feature maps. An
  8-bit unsigned register represents the full range 0-255 with no loss and no scaling.
- **Narrower would lose information.** 7 bits would require discarding the least
  significant bit of every pixel, introducing quantisation error into every output.
- **Wider would gain nothing.** The input data contains no information beyond 8 bits, so a
  wider input path would carry zeros while increasing the width of nine multipliers, the
  pipeline registers and the 42-pin external interface.
- **Q8.0 needs no scaling hardware.** With zero fractional bits the arithmetic is pure
  integer: no alignment shifts, no rounding stage, no fractional bookkeeping between
  stages. The convolution result is exact.
- The coefficient format is **8-bit signed integer, Q8.0** (`COEF_W = 8`, range -128 to
  +127), fixed by specification item 4.

The package also declares `COEF_FRAC` as a documented toggle. In the submitted build it is
0, giving the integer format above. It is a declaration only: there is no shift or rounding
stage in the RTL, so a Q1.7 build would require adding that stage. No results are claimed
for it.

## 7.2 Width Derivation

| Stage | Signal | Format | Worst-case range | Width | Derivation |
|---|---|---|---|---|---|
| Input pixel | input_in, taps | unsigned Q8.0 | 0 .. 255 | 8 b | 8-bit grayscale |
| Coefficient | coef | signed Q8.0 | -128 .. +127 | 8 b | specification item 4 |
| Product | prod | signed | -32640 .. +32385 | 16 b | 255 x -128 and 255 x +127 |
| Row sum (3 products) | row_sum | signed | -97920 .. +97155 | 18 b | 3 x product range |
| Accumulator (9 products) | acc | signed | -293760 .. +291465 | 20 b | 9 x product range |
| Output | pixel_out | signed | -32768 .. +32767 | 16 b | specification item 6, saturated |

- **PROD_W = 16.** An 8-bit unsigned pixel multiplied by an 8-bit signed coefficient spans
  -32640 to +32385, which fits a 16-bit signed value (-32768 to +32767) exactly. The
  multiplier zero-extends the pixel to 9 bits so that a signed x unsigned product is formed
  correctly.
- **Row width = 18.** Three products span +/-97920, requiring 18 bits signed (a 17-bit
  signed value reaches only +/-65536). Implemented as `PROD_W + 2`.
- **ACC_W = 20, and not 19.** The nine-product accumulator must hold 9 x 255 x 128 =
  293760. A 19-bit signed value reaches 262143 - insufficient. A 20-bit signed value reaches
  524287, so 20 bits is the minimum lossless width. This is the single most consequential
  width in the design: too narrow and interior pixels wrap silently; wider costs adder and
  register area for range that cannot occur.
- Every stage up to the accumulator is lossless. No truncation or rounding occurs anywhere
  in the datapath.

## 7.3 Overflow and Saturation Handling

Specification item 6 requires an explanation of how overflow is handled. The design
**saturates**, and does not wrap or truncate.

- A 20-bit accumulator result outside the 16-bit signed range is clamped to +32767 or
  -32768 rather than allowed to wrap. Wrapping would turn a bright edge into a dark one -
  a visually catastrophic and silent failure. Saturation degrades gracefully and is the
  standard convention for fixed-point image pipelines.
- The clamp is implemented as a sign-extension test rather than two magnitude comparisons.
  A 20-bit signed value is representable in 16 bits if and only if its upper five bits are
  all copies of the sign bit:

```
acc_top = acc[19:15]                       5 bits
fits    = (acc_top == 5'b00000) || (acc_top == 5'b11111)

fits          -> sat = acc[15:0]           pass through
acc[19] == 1  -> sat = -32768              negative overflow
otherwise     -> sat = +32767              positive overflow
```

- **Why this form.** The obvious implementation, `if (acc > 32767) ... else if (acc <
  -32768) ...`, synthesises to two 20-bit magnitude comparators, each with its own carry
  chain. The sign-extension test is a single 5-bit equality check, roughly two LUTs, with
  no carry chain at all. Both forms give identical results for every input.
- **Equivalence proof.** The two implementations were compared over the complete 20-bit
  accumulator space - all 1,048,576 values - before the change entered the RTL: zero
  mismatches. The check is exhaustive rather than sampled, so the equivalence is a proof
  rather than evidence.
- **Hardware verification.** Real kernels never saturate, so the clamp paths were initially
  untested. Two synthetic kernels were added to force them: **satmax** (all coefficients
  +127) and **satmin** (all -128). Each drives all 1024 outputs to a clamp, including the
  zero-padded border windows where the sum is smaller. Both are checked against the golden
  model in every regression run (Section 9).
- **No rounding stage exists.** The arithmetic is integer throughout, so truncation and
  rounding do not arise. The only width reduction in the design is the saturating narrowing
  described above.

## 7.4 Measured Range Against Designed Range

The widths above are sized for the worst case reachable with arbitrary 8-bit signed
coefficients, as required by the programmability specification. The kernels actually shipped
use far less of that range:

| Kernel | Coefficients | Measured accumulator range | Saturates? |
|---|---|---|---|
| identity | 0, 1 | 41 .. 255 | no |
| sobel_x | 0, +/-1, +/-2 | -715 .. +875 | no |
| sobel_y | 0, +/-1, +/-2 | -898 .. +934 | no |
| sharpen | 0, +/-1, 5 | -169 .. +557 | no |
| laplacian | 0, +/-1, -4 | -357 .. +241 | no |
| satmax | +127 (all nine) | clamped, all 1024 outputs | yes, by construction |
| satmin | -128 (all nine) | clamped, all 1024 outputs | yes, by construction |

- The widest real excursion is sobel_y at -898 to +934, using about 0.3% of the 20-bit
  accumulator range and roughly 3% of the 16-bit output range.
- This is the correct outcome, not over-engineering: the write port accepts **any** 8-bit
  signed coefficient set, so the datapath must be lossless for the worst case a user can
  program, not merely for the kernels demonstrated. Narrowing the accumulator to fit the
  five shipped kernels would break programmability, which is a mandatory requirement.
- Measured ranges are taken from the golden model outputs, which are bit-identical to the
  hardware outputs (Section 9).

Sources: rtl/cnn_pkg.sv, rtl/top.sv, rtl/multiplier.sv, golden_model/golden.py,
golden_model/hex/.

**Table 7.1** - Bit-width derivation by stage (Section 7.2)

**Table 7.2** - Measured accumulator range per kernel (Section 7.4)

---

# 8. RTL Implementation Details

The design is 417 lines of SystemVerilog across seven files, plus four testbenches and the
build scripts. It is vendor-neutral apart from a single synthesis attribute.

## 8.1 Module Inventory

| File | Module | Role | Lines |
|---|---|---|---|
| rtl/cnn_pkg.sv | package cnn_pkg | every design parameter, imported by all modules | 33 |
| rtl/line_buffer.sv | line_buffer | one image row of delay, en-gated shift register | 31 |
| rtl/window_gen.sv | window_gen | 2 line buffers, 9 tap registers, zero-pad masks | 64 |
| rtl/control_unit.sv | control_fsm | five-state FSM, counters, registered edge flags | 106 |
| rtl/coeff_reg.sv | coeff_reg | 9 x 8-bit coefficient store, write-locked by busy | 34 |
| rtl/multiplier.sv | mult8x8 | one 8u x 8s LUT multiplier | 8 |
| rtl/top.sv | top | instantiation, adder tree, saturation, ReLU, pipeline | 141 |

## 8.2 Coding Decisions

- **Single parameter source.** Every width, depth and derived constant lives in
  `cnn_pkg`. No module declares a literal that another module must match; changing IMG_W
  propagates to the line buffer depth, the counter widths and the fill and drain lengths
  automatically. This is what makes the fill and drain bookkeeping self-consistent.
- **Synchronous reset everywhere.** All flip-flops reset on `posedge clk` with an active-low
  `rst_n` test inside the clocked block. No module uses an asynchronous reset. A consistent
  reset style avoids mixed reset domains, keeps the reset off the asynchronous set/reset
  pins of the fabric flip-flops, and does not prevent SRL inference in the line buffers
  because only the final element is read.
- **Clock enable on window state only.** Line buffers, tap registers and the FSM counters
  are gated by `en` so the window and the frame position freeze together during a stall. The
  three datapath pipeline registers are free-running, with correctness carried by the valid
  chain instead (Section 3.2). This keeps a high-fanout enable off the widest registers in
  the design.
- **Generate loop for the multipliers.** The nine multiplier instances are produced by a
  `genvar` loop over NTAP rather than written out nine times, so the tap-to-coefficient
  pairing cannot be mismatched by a typing error.
- **ReLU as a parameter, not a port.** `top` takes `parameter bit RELU = RELU_EN`. When 0
  the multiplexer is eliminated at elaboration. The regression instantiates two copies of
  the entire accelerator, RELU=0 and RELU=1, on identical stimulus.
- **Defensive write guard.** `coeff_reg` accepts a write only when `write_en && !busy &&
  write_addr < NTAP`. The address bus is 4 bits wide but only values 0-8 are meaningful;
  the guard makes the intent explicit rather than relying on synthesis to trim an
  unreachable decode.
- **Datapath modules hold no position state.** `window_gen` contains no counters and
  produces no valid signal; it applies whatever masks control_fsm presents. This is what
  allows it to be unit-tested in isolation by direct-driving `en` and the four flags
  (Section 9).

## 8.3 Register Inventory

The 441 routed flip-flops account as follows:

| Location | Registers | Bits |
|---|---|---|
| top (pipeline) | prod_r 9x16, row_r 3x18, pixel_out 16, valid chain 3 | 217 |
| window_gen | 9 tap registers plus line-buffer end stages | 117 |
| coeff_reg | 9 coefficients x 8 bits | 72 |
| control_fsm | in_cnt 10, out_r 5, out_c 5, drain_cnt 6, 4 flags, one-hot state | 35 |
| **Total** | | **441** |

The line buffers contribute 16 LUTs as SRLC32E shift registers rather than the 512
flip-flops a naive implementation would need; the flip-flops shown under window_gen are the
tap registers and the chain end stages Vivado kept in fabric registers.

## 8.4 Vendor Neutrality

The RTL contains no vendor primitives, no instantiated macros and no tool-specific
pragmas, with one exception: the `(* use_dsp = "no" *)` attribute on `mult8x8`. On another
vendor's tool this becomes the equivalent directive (`multstyle = "logic"` for Intel
Quartus, the corresponding Gowin setting) and nothing else changes. The design was
simulated in two independent simulators - ModelSim ASE for the functional regression and
Vivado xsim for the switching-activity capture - with identical results.

## 8.5 Build and Simulation Scripts

| Script | Purpose |
|---|---|
| sim/compile.do | compiles the package first, then RTL, then testbenches, into sim/work |
| sim/run.do | `all` runs the 22-run regression; `<kernel> [stall]` runs one case; `window` and `unit` run the window testbenches |
| sim/waves/*.do | one script per report figure: adds the right signals, sets radix and grid, places cursors, zooms |
| fpga/build.tcl | non-project flow: read RTL and XDC, synth with -max_dsp 0, opt/place/route, read SAIF, write all reports |
| fpga/saif.bat | re-runs tb_top under xsim and captures the windowed SAIF for power analysis |
| fpga/paths.tcl | reports the worst path terminating in each pipeline stage |
| fpga/pynq_z2.xdc | clock constraint, all 42 pin assignments, I/O false paths |
| golden_model/golden.py | generates the reference outputs, coefficient files and PNG renders |
| golden_model/hw_to_png.py | renders hardware outputs beside the input image for the demo figure |

## 8.6 Design Iterations

The implemented design is the third iteration. Each change was measured rather than assumed,
and one was reverted:

| # | Change | Rationale | Result |
|---|---|---|---|
| 1 | Remove in_cnt as redundant | out_r/out_c appeared to duplicate it | **Reverted** - consume runs during FILL, so the counters are offset by 34; the frame ran 1059 in / 1058 out instead of 1024/1024 |
| 2 | Register the edge flags | the flags fed the tap masks and multipliers combinationally | WNS +0.332 -> +0.742 ns, Fmax 130.4 -> 137.8 MHz, LUTs 882 -> 879, cost 4 FFs |
| 3 | Saturate by sign-extension test | replace two 20-bit comparators | ~2 LUTs saved; exposed that the clamp had never been tested, leading to satmax/satmin |
| 4 | SAIF-based power instead of vectorless | organiser requirement and accuracy | total power 0.181 -> 0.158 W, FoM 6.285e-3 -> 7.20e-3 |

Iteration 1 is reported because the counter-example is informative: `consume` is asserted in
IDLE and FILL as well as STREAM, so the input count leads the output position by exactly
FILL_CYCLES, and at the last consumed pixel the output position is (30, 29) - not a frame
corner, so the edge flags cannot express the terminal condition. The behaviour was modelled
before the RTL was trusted, and the change was withdrawn.

Sources: rtl/, sim/, fpga/, docs/notes/DESIGN_ITERATIONS.md.

**Table 8.1** - Module inventory (Section 8.1)

**Table 8.2** - Register inventory (Section 8.3)

**Table 8.3** - Design iterations (Section 8.6)
