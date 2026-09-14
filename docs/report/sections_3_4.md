# 3. Datapath

The datapath is the arithmetic half of the design. It receives nine masked 8-bit taps from
the window generator and nine 8-bit signed coefficients from the coefficient register, and
produces one 16-bit signed output pixel every clock. It holds no position state: every
counter, flag and frame decision lives in control_fsm, and the only control input the
datapath receives is the valid bit that travels alongside the data. All of it is in
rtl/top.sv apart from the multiplier cell (rtl/multiplier.sv).

## 3.1 Structure and Pipeline Stages

The chain from taps to output pixel is combinational arithmetic interrupted by three
register stages. Each stage is deliberately sized so that no stage does substantially more
work than its neighbours:

| Stage | Combinational logic before the register | Register | Width |
|---|---|---|---|
| 1 | 9 parallel 8u x 8s multipliers (mult8x8) | prod_r | 9 x 16b |
| 2 | 3 row adders, each summing 3 products | row_r | 3 x 18b |
| 3 | 1 final adder (3 row sums), saturation, ReLU mux | pixel_out | 16b |

- **Stage 1 - multiplication.** A generate loop instantiates nine mult8x8 cells, one per
  tap. Each computes `coef * signed'({1'b0, pix})`: the pixel is zero-extended to 9 bits so
  an unsigned 8-bit value multiplies correctly against a signed 8-bit coefficient. The nine
  16-bit products are registered into prod_r.
- **Stage 2 - row summation.** The nine products are summed in three groups of three,
  matching the three rows of the convolution window: `row_sum[0] = prod_r[0] + prod_r[1] +
  prod_r[2]` (taps a, b, c), `row_sum[1]` for d, e, f, and `row_sum[2]` for g, h, i. Each
  is an 18-bit signed 3-input addition, registered into row_r.
- **Stage 3 - accumulation and output conditioning.** The three row sums are added into the
  20-bit accumulator `acc`, narrowed to 16 bits by the saturation logic, passed through the
  ReLU multiplexer, and registered into pixel_out.

**Why the adder tree is 3 + 3 and not a flat 9-input sum or a binary tree.** Three
groups of three mirrors the window rows, so each partial sum is meaningful and the widths
fall out naturally (18 bits for 3 products, 20 bits for 3 row sums). It also balances the
two adder stages: a flat 9-input addition in one cycle would concentrate the whole carry
chain in a single stage, and a 2-1-2-1 binary tree would need four levels where three
suffice. The measured per-stage slack in Section 3.4 confirms the balance.

## 3.2 The Valid Chain

The three pipeline registers are free-running: they have no clock enable and clock on every
cycle regardless of valid_in. Correctness is maintained by propagating a valid bit through a
parallel register chain of identical depth:

```
win_valid  ->  v_prod  ->  v_row  ->  valid_out
(control)     (stage 1)   (stage 2)   (stage 3)
```

- When control_fsm asserts win_valid, the window currently at the taps is a real output
  position. Three cycles later the corresponding pixel appears on pixel_out with valid_out
  high.
- When valid_in drops, en deasserts and the window freezes, but the pipeline registers keep
  clocking. win_valid goes low, and that low bit propagates to valid_out exactly three
  cycles later, appearing as a bubble in the output stream rather than a corrupted pixel.
- Because the valid bit travels with the data rather than gating it, a stall of any length
  is handled without additional control logic. The regression asserts this invariant every
  cycle of every run: `valid_out` must equal `win_valid` delayed by exactly three
  (`lat_err = 0` across all 22 runs, including runs with roughly 500 randomly injected stall
  cycles).

**Design consequence.** Free-running pipeline registers cost no enable routing on a
144-bit-wide stage-1 register and remove en from the timing path of the entire arithmetic
section. The alternative - gating all three stages with en - would add a high-fanout enable
net across the widest registers in the design for no functional gain.

## 3.3 Multiplier Implementation

- Nine instances of mult8x8, each a single-line behavioural multiplier carrying the
  `(* use_dsp = "no" *)` synthesis attribute. fpga/build.tcl additionally passes
  `-max_dsp 0` to synth_design as a second guard.
- Routed cost: 52-59 LUTs per instance, 496 LUTs for all nine - 56% of the 879-LUT design.
  Zero DSP48E1 blocks are inferred, confirmed in fpga/reports/utilization.rpt (DSPs: 0 of
  220) and in the synthesis log (`8x9 Multipliers := 9` under RTL Component Statistics,
  with no DSP mapping).
- The 8x9 description in the synthesis report reflects the zero-extension: an unsigned
  8-bit pixel presented as a 9-bit signed value against an 8-bit signed coefficient.
- **Vendor neutrality.** The use_dsp attribute is the only vendor-specific construct in the
  entire RTL. On a non-Xilinx target it is replaced by the equivalent directive
  (`multstyle = "logic"` on Intel, the Gowin equivalent) with no other source change.

## 3.4 Saturation and ReLU

Saturation narrows the 20-bit accumulator to the 16-bit signed output. The implementation
avoids two full-width magnitude comparisons:

```systemverilog
assign acc_top = acc[ACC_W-1 -: (ACC_W-OUT_W+1)];   // acc[19:15], 5 bits
assign fits    = (acc_top == '0) || (acc_top == '1);

if (fits)              sat = acc[OUT_W-1:0];
else if (acc[ACC_W-1]) sat = OUT_MIN[OUT_W-1:0];    // negative -> -32768
else                   sat = OUT_MAX[OUT_W-1:0];    // positive -> +32767
```

- **Principle.** A 20-bit signed value is representable in 16 bits if and only if its upper
  five bits are all copies of the sign bit. Testing `acc[19:15]` for all-zeros or all-ones
  therefore answers the saturation question exactly, using one 5-bit equality test in place
  of two 20-bit comparators and their carry chains.
- **Equivalence.** The rewrite was proven equivalent to the original two-comparison form
  over all 2^20 accumulator values before it entered the RTL, and is exercised in hardware
  simulation by the satmax and satmin kernels (Section 9), which drive every output to a
  clamp. Section 7 covers the arithmetic derivation.
- **ReLU.** A single multiplexer, `relu_out = (RELU && sat[15]) ? '0 : sat`. RELU is a
  module parameter defaulting to the package value RELU_EN = 0; when disabled the mux is
  removed entirely at elaboration and the stage reduces to a wire. The regression
  instantiates both builds on identical stimulus (Section 9).

## 3.5 Measured Stage Balance

fpga/reports/paths.rpt reports the worst path terminating in each pipeline register, which
shows directly whether the three stages are balanced:

| Stage | Endpoint register | Worst slack | Margin over stage 1 |
|---|---|---|---|
| 1 | prod_r | +0.742 ns | - |
| 2 | row_r | +3.799 ns | 3.06 ns |
| 3 | pixel_out | +2.666 ns | 1.92 ns |

- Stage 1 is the binding stage, as expected: it contains the multipliers.
- Stage 3 - the final adder, saturation and ReLU together - retains 1.92 ns of slack, so the
  output conditioning logic is not a limiting factor despite performing three operations.
  This measurement is what justified leaving the stage unsplit.
- Every one of the fifteen worst paths in the design starts at a registered edge flag in
  control_fsm and ends in prod_r (10 from bottom_edge_reg, 4 from top_edge_reg, 1 from
  right_edge_reg). The critical path is therefore the arrival of the padding masks at the
  multipliers, not the multiplier logic itself. Section 13 develops this.

Sources: rtl/top.sv, rtl/multiplier.sv, fpga/reports/paths.rpt, fpga/reports/utilization.rpt,
fpga/reports/synth.log.

**Figure 3.1** - Datapath with pipeline stage boundaries (docs/figures/Data_path.svg)

**Table 3.1** - Per-stage worst-case slack (above)

---

# 4. Control FSM

control_fsm (rtl/control_unit.sv) owns all frame-position state in the design. It sequences
one frame through five states, generates the clock enable and the four zero-padding flags
for the window generator, produces the valid strobe that enters the datapath's valid chain,
and reports frame status on busy and frame_done. It never sees pixel data.

## 4.1 States and Transitions

| State | Entered when | Duration | en | win_valid | busy | Role |
|---|---|---|---|---|---|---|
| IDLE | reset, or after DONE | until valid_in | valid_in | 0 | 0 | waiting for a frame |
| FILL | valid_in asserts | 34 consume-only cycles | valid_in | 0 | 1 | priming the window |
| STREAM | in_cnt == FILL_CYCLES-1 | 990 cycles | valid_in | valid_in | 1 | consume and output |
| DRAIN | last input consumed | 34 output-only cycles | 1 (forced) | 1 | 1 | flushing the pipeline |
| DONE | drain_cnt == DRAIN_CYCLES-1 | 1 cycle | 0 | 0 | 0 | frame_done pulse |

- **en** equals valid_in in every state except DRAIN, where it is forced high (no input
  remains but the window must keep shifting), and DONE, where it is low.
- **consume** = en && state != DRAIN; **out_adv** = en && (state == STREAM || state ==
  DRAIN); **win_valid** = out_adv.
- **busy** = (state != IDLE) && (state != DONE).
- **frame_done** = (state == DONE), a single-cycle pulse.

**A note on STREAM's duration.** STREAM lasts 990 cycles, not 1024. The consume counter
runs during IDLE and FILL as well, so 34 pixels have already been ingested by the time
STREAM is entered; it consumes the remaining 990. Outputs, however, are produced in both
STREAM and DRAIN - 990 + 34 = 1024. The distinction matters when reading the state
durations off a waveform: 1024 is the count of inputs and of outputs, not the length of any
single state.

## 4.2 Frame Bookkeeping

The FILL and DRAIN lengths are not tuning parameters; they are forced by a counting
argument. Every enabled cycle is exactly one of three kinds:

- **consume-only** (FILL): a pixel enters, no output is produced - the window is not yet
  complete.
- **consume and output** (STREAM): steady state.
- **output-only** (DRAIN): no pixel remains, but windows still complete as the pipeline
  shifts.

Since a frame must consume 1024 pixels and produce 1024 outputs, the consume-only and
output-only cycle counts must be equal. Hence `DRAIN_CYCLES = FILL_CYCLES = 34`, and the
frame occupies 34 + 990 + 34 = 1058 enabled cycles plus 3 pipeline stages = 1061 cycles
from first pixel accepted to last pixel out.

FILL_CYCLES itself is 34 = LB_DEPTH + 2: 32 shifts for a pixel to traverse LB0, one to
reach tap f, one more to shift into the centre tap e. Section 6 derives this.

During DRAIN the input bus carries whatever the source leaves on it; the testbench
deliberately drives 0xA5. This data shifts into the bottom tap row, but every window
produced during DRAIN lies on the bottom or right edge of the frame, where bottom_edge and
right_edge mask exactly those taps to zero. No stale data reaches an output.

## 4.3 Registered Edge Flags

The four padding flags are registered outputs, computed for the *next* output position:

```systemverilog
always_comb begin              // next position
    nxt_c = out_c;  nxt_r = out_r;
    if (out_adv) begin
        if (out_c == IMG_W-1) begin nxt_c = '0; nxt_r = (out_r == IMG_H-1) ? '0 : out_r+1; end
        else                        nxt_c = out_c + 1;
    end
end
                               // registered, so they are valid on the cycle they are used
top_edge <= (nxt_r == 0);      bottom_edge <= (nxt_r == IMG_H-1);
left_edge <= (nxt_c == 0);     right_edge <= (nxt_c == IMG_W-1);
```

- **Motivation.** In the original design the flags were combinational functions of out_r and
  out_c, placing a comparator between the counter and the tap masks, which feed the
  multipliers. The whole chain - counter, comparator, mask, multiply - sat in one cycle.
- **Result.** Computing the flags one position ahead and registering them removed the
  comparator from the datapath path. Worst negative slack improved from +0.332 ns to
  +0.742 ns and Fmax from 130.4 MHz to 137.8 MHz, at a cost of 4 flip-flops and no
  additional LUTs.
- **Correctness.** The flags must hold values matching the position being output, not the
  position being computed. tb_top_window checks this every cycle against the expected
  raster position for all 1024 windows of a frame: 0 position errors, 0 edge-flag errors.
- Reset initialises the flags to position (0, 0): top_edge and left_edge high, bottom_edge
  and right_edge low.

## 4.4 Stall Semantics

A stall is input starvation, never a design bubble. Behaviour depends on the state:

| Stall occurs in | Effect |
|---|---|
| FILL | The fill is extended by the stall length; the first output is delayed accordingly. No bubble appears at the output because no outputs have started. |
| STREAM | en deasserts, freezing line buffers, taps and counters together. win_valid drops, and the bubble reaches valid_out exactly 3 cycles later. No pixel is lost or duplicated. |
| DRAIN | Ignored - en is forced high; the input bus is not consumed in this state. |

This is asserted numerically in the regression: the count of output bubbles equals the count
of stall cycles that occurred in STREAM, for every run (Section 9). A run with two stall
cycles during FILL reports a latency of 39 rather than 37, which is the expected and correct
consequence.

## 4.5 Frame-to-Frame Contract

The core has no ready signal; flow control is source-side:

- The source presents exactly 1024 pixels per frame with valid_in, stalling freely.
- **busy** falls when the FSM reaches DONE, which is three cycles before the final
  valid_out - the last window has already been latched into the pipeline. A consumer must
  therefore count valid_out pulses, or wait for frame_done, rather than treating the falling
  edge of busy as end-of-data.
- **Coefficient writes** are accepted only while busy is low (coeff_reg additionally guards
  `write_addr < NTAP`). A new kernel may therefore be loaded in the window between busy
  falling and the next frame starting - including while the previous frame's final outputs
  are still emerging from the pipeline.
- This is verified directly: the regression's back-to-back run streams sobel_x, swaps the
  kernel to sharpen the moment busy falls, and streams a second frame immediately. All 2048
  outputs match their respective golden references, confirming that the kernel swap does not
  disturb the draining tail of the first frame.

## 4.6 Counters

| Counter | Width | Increment condition | Purpose |
|---|---|---|---|
| in_cnt | 10 b | consume | FILL exit at 33, STREAM exit at 1023 |
| out_c | 5 b | out_adv | output column, drives left/right_edge |
| out_r | 5 b | out_adv, on column wrap | output row, drives top/bottom_edge |
| drain_cnt | 6 b | state == DRAIN | DRAIN exit at 33 |

Vivado encodes the five states one-hot and replicates the state register to meet timing;
the routed control_fsm occupies 80 LUTs and 35 flip-flops.

Sources: rtl/control_unit.sv, fpga/reports/utilization_hier.rpt, tb/tb_top_window.sv,
tb/tb_top_all.sv, docs/notes/DESIGN_ITERATIONS.md.

**Figure 4.1** - FSM state diagram (states, transition conditions, and per-state outputs)

**Figure 4.2** - docs/figures/waveforms/fsm.PNG - one frame traversing all five states,
with in_cnt, out_r and drain_cnt driving the transitions

**Figure 4.3** - docs/figures/waveforms/stall.PNG - valid_in deasserted mid-frame: the taps
freeze and the bubble reaches valid_out three cycles later

**Figure 4.4** - docs/figures/waveforms/drain.PNG - end of frame: DRAIN produces the final
34 outputs, busy falls three cycles before the last valid_out

**Table 4.1** - State and output table (Section 4.1)
