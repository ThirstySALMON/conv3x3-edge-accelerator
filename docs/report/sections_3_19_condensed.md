# 3. Datapath

The datapath is the arithmetic half of the design: nine masked 8-bit taps and nine 8-bit
signed coefficients in, one 16-bit signed pixel out, every clock. It holds no position
state - the only control it receives is the valid bit travelling alongside the data. All of
it is rtl/top.sv apart from the multiplier cell.

## 3.1 Pipeline Stages

| Stage | Combinational logic | Register | Width |
|---|---|---|---|
| 1 | 9 parallel 8u x 8s multipliers | prod_r | 9 x 16 b |
| 2 | 3 row adders, 3 products each | row_r | 3 x 18 b |
| 3 | final 3-input adder, saturation, ReLU mux | pixel_out | 16 b |

- Each multiplier computes `coef * signed'({1'b0, pix})`, zero-extending the unsigned pixel
  to 9 bits so a signed x unsigned product forms correctly.
- Products are summed in three groups of three matching the window rows: taps a,b,c then
  d,e,f then g,h,i. This mirrors the convolution structure, makes each partial sum
  meaningful, and balances the two adder stages - a flat 9-input sum would concentrate the
  whole carry chain in one stage.
- The three row sums feed the 20-bit accumulator, which is narrowed to 16 bits by the
  saturation logic described in Section 7.3.

## 3.2 The Valid Chain

The pipeline registers are free-running - no clock enable. Correctness is carried by a
parallel valid chain of identical depth:

```
win_valid  ->  v_prod  ->  v_row  ->  valid_out
(control)     (stage 1)   (stage 2)   (stage 3)
```

When valid_in drops, `en` deasserts and the window freezes, but the pipeline keeps clocking.
win_valid goes low and that gap reaches valid_out exactly three cycles later - a bubble in
the output stream, never a corrupted pixel. Because the valid bit travels with the data
rather than gating it, a stall of any length needs no extra control logic, and a
high-fanout enable is kept off the widest registers in the design. The regression asserts
this invariant on every cycle of every run.

## 3.3 Multiplier Implementation

Nine instances of `mult8x8`, each carrying `(* use_dsp = "no" *)`. Routed cost is 52-59 LUTs each, **496 LUTs for all nine - 56% of the
design** - with zero DSP blocks inferred. The attribute is the only vendor-specific
construct in the entire RTL; on another vendor's tool it becomes the equivalent directive
and nothing else changes.

## 3.4 Measured Stage Balance

fpga/reports/paths.rpt reports the worst path terminating in each pipeline register:

| Stage | Endpoint | Worst slack |
|---|---|---|
| 1 - multipliers | prod_r | **+0.742 ns** |
| 2 - row adders | row_r | +3.799 ns |
| 3 - final add, saturate, ReLU | pixel_out | +2.666 ns |

Stage 1 binds, as expected. Stage 3 retains 1.92 ns despite performing three operations,
which is the measurement that justified leaving the final adder, saturation and ReLU
together rather than splitting them. Every one of the fifteen worst paths starts at a
registered edge flag and ends in prod_r, so the critical path is the arrival of the padding
masks at the multipliers, not the multiplier logic - developed in Section 13.3.

**Figure 3.1** - Datapath with pipeline stage boundaries

---

# 4. Control FSM

control_fsm (rtl/control_unit.sv) owns all frame-position state: it sequences one frame
through five states, generates the clock enable and the four padding flags, produces the
valid strobe, and reports status on busy and frame_done. It never sees pixel data.

## 4.1 States and Transitions

| State | Entered when | Duration | en | win_valid | busy |
|---|---|---|---|---|---|
| IDLE | reset, or after DONE | until valid_in | valid_in | 0 | 0 |
| FILL | valid_in asserts | 34 consume-only cycles | valid_in | 0 | 1 |
| STREAM | in_cnt == 33 | 990 cycles | valid_in | valid_in | 1 |
| DRAIN | last input consumed | 34 output-only cycles | 1 (forced) | 1 | 1 |
| DONE | drain_cnt == 33 | 1 cycle | 0 | 0 | 0 |

`en` equals valid_in everywhere except DRAIN, where it is forced high (no input remains but
the window must keep shifting), and DONE. `busy` = not IDLE and not DONE; `frame_done` is a
one-cycle pulse in DONE.

**On STREAM's duration.** STREAM lasts 990 cycles, not 1024. The consume counter runs during
IDLE and FILL too, so 34 pixels are already ingested when STREAM is entered; it consumes the
remaining 990. Outputs come from STREAM and DRAIN together: 990 + 34 = 1024. When reading
state durations off a waveform, 1024 is the count of inputs and of outputs, not the length of
any state.

## 4.2 Frame Bookkeeping

Every enabled cycle is consume-only (FILL), consume-and-output (STREAM), or output-only
(DRAIN). A frame must consume 1024 pixels and produce 1024 outputs, so the consume-only and
output-only counts must be **equal** - hence `DRAIN_CYCLES = FILL_CYCLES = 34`, and the
frame occupies 34 + 990 + 34 = 1058 enabled cycles plus 3 pipeline stages = **1061 cycles**
from first pixel in to last pixel out.

FILL_CYCLES = 34 = LB_DEPTH + 2: thirty-two shifts to traverse LB0, one to reach tap f, one
to shift into centre tap e. During DRAIN the input bus carries whatever the source leaves on
it, but every window produced in DRAIN lies on the bottom or right edge, where the masks
force exactly those taps to zero - no stale data reaches an output.

## 4.3 Registered Edge Flags

The four padding flags are registered outputs computed for the *next* output position:

```systemverilog
top_edge    <= (nxt_r == 0);       bottom_edge <= (nxt_r == IMG_H-1);
left_edge   <= (nxt_c == 0);       right_edge  <= (nxt_c == IMG_W-1);
```

Originally they were combinational functions of the position counters, putting counter,
comparator, mask and multiplier in one cycle. Computing them one position ahead and
registering them removed the comparator from the datapath path: **WNS improved from
+0.332 ns to +0.742 ns and Fmax from 130.4 to 137.8 MHz, for 4 flip-flops and no extra
LUTs.** The flags must still match the position being output; tb_top_window verifies this
against the expected raster position for all 1024 windows - 0 position errors, 0 edge-flag
errors.

## 4.4 Stall Semantics and the Frame Contract

A stall is input starvation, never a design bubble:

| Stall in | Effect |
|---|---|
| FILL | fill is extended; the first output is delayed, no bubble (no outputs have started) |
| STREAM | en deasserts; buffers, taps and counters freeze together; the bubble reaches valid_out 3 cycles later |
| DRAIN | ignored - en is forced high, no input is consumed |

The regression asserts numerically that output bubbles equal STREAM stall cycles in every
run. A run with two stall cycles during FILL reports latency 39 rather than 37, which is the
correct consequence.

The core has no ready signal; flow control is source-side. The source presents 1024 pixels
per frame and holds the next until busy falls. **busy falls three cycles before the final
valid_out** - the last window is already in the pipeline - so a consumer must count
valid_out pulses or wait for frame_done. Coefficient writes are accepted only while busy is
low, which allows a kernel reload in the gap between frames even while the previous frame's
tail is still emerging. The back-to-back regression run does exactly this and all 2048
outputs match.

## 4.5 Counters

| Counter | Width | Increments on | Purpose |
|---|---|---|---|
| in_cnt | 10 b | consume | FILL exit at 33, STREAM exit at 1023 |
| out_c / out_r | 5 b each | out_adv | output position, drives the four edge flags |
| drain_cnt | 6 b | state == DRAIN | DRAIN exit at 33 |

Vivado encodes the five states one-hot and replicates the state register for timing; routed
control_fsm is 80 LUTs and 35 flip-flops.

**Figure 4.1** - FSM state diagram

**Figure 4.2** - fsm.PNG - one frame through all five states

---

# 7. Fixed-Point Bit-Width Analysis

Every width is derived from the input and coefficient formats rather than chosen. Every
stage is lossless up to the final narrowing; the only place information is discarded is the
deliberate saturation at the output.

## 7.1 Input Precision and Its Justification

The input is **8-bit unsigned, Q8.0** (0 to 255).

- **Matches the source exactly.** 8-bit grayscale is the native output of essentially every
  image sensor and the standard single-channel feature-map format; 8 bits unsigned carries
  it with no loss and no scaling.
- **Narrower loses data** - 7 bits would discard the LSB of every pixel. **Wider gains
  nothing** - the data contains no information beyond 8 bits, while widening nine
  multipliers, the pipeline and the external interface.
- **Q8.0 needs no scaling hardware.** With zero fractional bits the arithmetic is pure
  integer: no alignment shifts, no rounding, and the convolution result is exact.

Coefficients are 8-bit signed integer (Q8.0, -128 to +127), fixed by specification item 4.
`COEF_FRAC` is declared in the package as a Q1.7 toggle but has no implementing logic; the
submitted build is Q8.0 and no Q1.7 results are claimed.

## 7.2 Width Derivation

| Stage | Format | Worst-case range | Width | Derivation |
|---|---|---|---|---|
| Pixel | unsigned Q8.0 | 0 .. 255 | 8 b | 8-bit grayscale |
| Coefficient | signed Q8.0 | -128 .. +127 | 8 b | specification item 4 |
| Product | signed | -32640 .. +32385 | 16 b | 255 x -128, 255 x +127 |
| Row sum (3) | signed | -97920 .. +97155 | 18 b | 3 x product range |
| Accumulator (9) | signed | -293760 .. +291465 | 20 b | 9 x product range |
| Output | signed | -32768 .. +32767 | 16 b | item 6, saturated |

**ACC_W = 20, not 19.** The accumulator must hold 9 x 255 x 128 = 293760. A 19-bit signed
value reaches only 262143 - insufficient; 20 bits reaches 524287. This is the most
consequential width in the design: too narrow and interior pixels wrap silently. Every
stage up to the accumulator is lossless; no truncation or rounding occurs anywhere.

## 7.3 Overflow and Saturation Handling

Specification item 6 requires this to be explained. The design **saturates** rather than
wrapping or truncating: a result outside the 16-bit signed range is clamped to +32767 or
-32768. Wrapping would turn a bright edge into a dark one - a silent, visually catastrophic
failure - whereas saturation degrades gracefully and is the standard fixed-point image
convention.

The clamp is a sign-extension test, not two magnitude comparisons. A 20-bit signed value is
representable in 16 bits **if and only if its upper five bits all equal the sign bit**:

```
acc_top = acc[19:15]
fits    = (acc_top == 5'b00000) || (acc_top == 5'b11111)

fits          -> sat = acc[15:0]      pass through
acc[19] == 1  -> sat = -32768         negative overflow
otherwise     -> sat = +32767         positive overflow
```

The obvious form - `if (acc > 32767) ... else if (acc < -32768) ...` - synthesises to two
20-bit comparators with two carry chains. The sign-extension test is one 5-bit equality
check, roughly two LUTs, with no carry chain. **The two were proven equivalent over the
complete 20-bit space - all 1,048,576 values, zero mismatches - before the change entered
the RTL**, so the equivalence is a proof rather than evidence.

Real kernels never reach the clamp, so it was verified with two synthetic kernels: **satmax**
(all +127) and **satmin** (all -128), each driving all 1024 outputs to a clamp including the
zero-padded borders. Both are checked against the golden model in every regression run.

## 7.4 Measured Range Against Designed Range

| Kernel | Coefficients | Measured accumulator range | Saturates |
|---|---|---|---|
| identity | 0, 1 | 41 .. 255 | no |
| sobel_x | 0, +/-1, +/-2 | -715 .. +875 | no |
| sobel_y | 0, +/-1, +/-2 | -898 .. +934 | no |
| sharpen | 0, +/-1, 5 | -169 .. +557 | no |
| laplacian | 0, +/-1, -4 | -357 .. +241 | no |
| satmax / satmin | +127 / -128 | clamped, all 1024 outputs | by construction |

The widest real excursion uses about 0.3% of the accumulator range. This is correct rather
than over-engineered: the write port accepts **any** 8-bit signed coefficient set, so the
datapath must be lossless for the worst case a user can program, not merely for the kernels
demonstrated. Narrowing to fit these five would break programmability, a mandatory
requirement.

---

# 8. RTL Implementation Details

417 lines of SystemVerilog across seven files, plus four testbenches and the build scripts.

| File | Module | Role | Lines |
|---|---|---|---|
| rtl/cnn_pkg.sv | cnn_pkg | every design parameter, imported by all modules | 33 |
| rtl/line_buffer.sv | line_buffer | one image row of delay, en-gated shift register | 31 |
| rtl/window_gen.sv | window_gen | 2 line buffers, 9 tap registers, zero-pad masks | 64 |
| rtl/control_unit.sv | control_fsm | five-state FSM, counters, registered edge flags | 106 |
| rtl/coeff_reg.sv | coeff_reg | 9 x 8-bit coefficient store, write-locked by busy | 34 |
| rtl/multiplier.sv | mult8x8 | one 8u x 8s LUT multiplier | 8 |
| rtl/top.sv | top | instantiation, adder tree, saturation, ReLU, pipeline | 141 |

## 8.1 Coding Decisions

- **Single parameter source.** Every width, depth and derived constant lives in `cnn_pkg`;
  no module declares a literal another must match. Changing IMG_W propagates to the line
  buffer depth, counter widths and the fill/drain lengths automatically.
- **Synchronous reset everywhere**, active-low, tested inside the clocked block. A
  consistent style avoids mixed reset domains and does not block SRL inference in the line
  buffers, because only their final element is read.
- **Clock enable on window state only.** Line buffers, taps and FSM counters are gated by
  `en`; the three datapath registers are free-running with correctness carried by the valid
  chain (Section 3.2). This keeps a high-fanout enable off the widest registers.
- **Generate loop for the multipliers**, so the tap-to-coefficient pairing cannot be
  mismatched by a typing error.
- **ReLU as a parameter, not a port** - when 0 the multiplexer is eliminated at elaboration.
  The regression instantiates both builds on identical stimulus.
- **Defensive write guard**: `write_en && !busy && write_addr < NTAP`. The address bus is 4
  bits but only 0-8 are meaningful.
- **Datapath modules hold no position state**, which is what allows window_gen to be
  unit-tested by direct-driving `en` and the flags.

## 8.2 Register Inventory

| Location | Registers | Bits |
|---|---|---|
| top (pipeline) | prod_r 9x16, row_r 3x18, pixel_out 16, valid chain 3 | 217 |
| window_gen | 9 tap registers plus line-buffer end stages | 117 |
| coeff_reg | 9 coefficients x 8 bits | 72 |
| control_fsm | counters, 4 flags, one-hot state | 35 |
| **Total** | | **441** |

The line buffers contribute 16 LUTs as SRLC32E rather than the 512 flip-flops a naive
implementation would need.

## 8.3 Scripts

`sim/compile.do` compiles package-first into sim/work; `sim/run.do all` drives the 22-run
regression; `sim/waves/*.do` reproduces one report figure each. `fpga/build.tcl` runs the
non-project flow through to all reports; `fpga/saif.bat` captures the windowed SAIF;
`fpga/paths.tcl` reports per-stage timing. `golden_model/golden.py` generates every
reference file.

---

# 9. Testbench and Verification

Specification item 8 requires verification against a golden model with test cases, expected
outputs, hardware outputs and a comparison. The result: **every output the hardware produces
is byte-identical to the reference model** across 22 runs, 0 failures.

## 9.1 Strategy and Test Cases

Verification is bottom-up so a failure is localised before integration:

| Level | Testbench | Proves |
|---|---|---|
| Unit | tb_window_gen_unit.sv | tap shifting, stall freeze, edge and corner masking |
| Integration | tb_top_window.sv | window contents, raster position, edge flags, gapless win_valid, fill latency |
| System | tb_top.sv | pixel_out vs golden for one kernel; writes hw_out/ |
| Regression | tb_top_all.sv | the full matrix below |

**Input**: a photograph reduced to 32x32 8-bit grayscale - a natural image exercises the
full 0-255 range with no regularity that could mask an indexing error.

**Seven kernels**, each loaded through the real write port: identity (any misalignment shows
immediately), sobel_x, sobel_y, sharpen, laplacian, plus satmax and satmin to force
saturation.

**Three stall regimes**: clean; fixed stalls totalling 18 cycles at five chosen points
(during FILL, at a row boundary, a long stall, and immediately before the last pixel); and
random stalls, roughly one pixel in five held 1-4 cycles, about 500 stall cycles per run.

**Back-to-back frames**: sobel_x, kernel swapped to sharpen the moment busy falls, second
frame immediately - 2048 outputs against two references.

## 9.2 Checks Applied Every Cycle

- **Pixel equality** against the golden value, reported with raster position.
- **ReLU equality** - a second full instance with RELU=1 on the same stimulus.
- **Latency invariant**: `valid_out` must equal `win_valid` delayed by exactly three. This
  is the strongest assertion in the suite - it fails if any stage drops, duplicates or
  reorders a valid bit.
- **Bubble accounting**: gaps in valid_out must equal stall cycles that occurred in STREAM.
- **Output count**: exactly 1024 per frame.

## 9.3 Results

| Kernel | Clean | Fixed stalls | Random stalls |
|---|---|---|---|
| identity | pass | pass, 18 stalls / 16 bubbles | pass, 558 / 534 |
| sobel_x | pass | pass, 18 / 16 | pass, 502 / 476 |
| sobel_y | pass | pass, 18 / 16 | pass, 551 / 523 |
| sharpen | pass | pass, 18 / 16 | pass, 493 / 479 |
| laplacian | pass | pass, 18 / 16 | pass, 498 / 480 |
| satmax | pass | pass, 18 / 16 | pass, 555 / 538 |
| satmin | pass | pass, 18 / 16 | pass, 537 / 512 |
| sobel_x -> sharpen | pass, 2048 outputs | - | - |

**22 runs, 0 failures**: 0 pixel errors, 0 ReLU errors, 0 latency violations, bubbles exactly
equal to STREAM stalls throughout. Of the 18 injected fixed-stall cycles only 16 fall in
STREAM; the other 2 occur during FILL and correctly produce no bubble, delaying the first
output to cycle 39.

## 9.4 Hardware Outputs and the Comparison

The testbenches write every pixel the RTL produces to `hw_out/<kernel>_out.hex` and
`_relu_out.hex` - 14 files, 1024 lines each, captured from `pixel_out` during simulation and
not copied from the model. Every one is **byte-identical** to its counterpart in
`golden_model/hex/`, which a reviewer can confirm without running the design:

```
diff hw_out/sobel_x_out.hex golden_model/hex/sobel_x_out.hex     (no output = identical)
```

This is stronger than a tolerance comparison: the fixed-point hardware reproduces the integer
reference exactly, for every pixel of every kernel, because both perform the same lossless
integer arithmetic with the same saturation rule.

---

# 10. Golden Reference Model

`golden_model/golden.py`, 80 lines of Python and NumPy, defines correctness for the project
and also generates the coefficient files the testbenches load.

```python
for y in range(32):
    for x in range(32):
        acc = 0
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                iy, ix = y + dy, x + dx
                if 0 <= iy < 32 and 0 <= ix < 32:      # zero padding
                    acc += int(img[iy, ix]) * int(k[dy+1, dx+1])
        acc = max(-32768, min(32767, acc))             # saturate
        if relu and acc < 0: acc = 0
        out[y, x] = acc
```

- **Zero padding by omission** - skipping out-of-range neighbours is arithmetically identical
  to multiplying a zero pixel, mirroring the hardware's masked taps.
- **Unbounded Python integers during accumulation**, so the model cannot itself overflow; the
  clamp is applied explicitly afterwards.
- **Cross-correlation orientation**: the kernel is applied unflipped, matching
  `write_addr = 3*row + col`. Stated as an assumption in Section 17.
- **Written from the specification, not from the RTL**, so agreement is evidence rather than
  tautology.

For each kernel it emits `<k>_coef.hex` (9 lines, write-port order), `<k>_out.hex` and
`<k>_relu_out.hex` (1024 lines each, 16-bit two's complement), plus PNG renders. Emitting the
coefficients from the same source as the expected outputs removes a class of error: the
kernel the hardware is programmed with and the kernel the reference used are the same nine
numbers by construction.

A second, window-level model (`golden_model/vectors/`) emits the expected 3x3 window at every
output position for five synthetic patterns, letting tb_top_window isolate
window-generation faults from arithmetic faults. Impulse and ring are the strongest indexing
cases.

---

# 11. Waveform Screenshots

All captures are from ModelSim on the submitted RTL, timeline in nanoseconds with one
gridline per 10 ns clock, cursors snapped to clock edges. Each is reproduced by
`do sim/waves/<script>` after the corresponding run.

| Figure | File | Script | Cursors | What it proves |
|---|---|---|---|---|
| 11.1 | Latency.PNG | latency.do | 145 / 515 ns | 370 ns = **37 cycles**: 34 fill + 3 pipeline; coefficient writes visible before, while busy is low |
| 11.2 | kernel_load.PNG | coeff.do | - | nine write_en pulses, write_addr 0-8, coefficients on data_write, busy low - programmability through the real port |
| 11.3 | throughput.PNG | throughput.do | 515 / 10755 ns | valid_out one unbroken interval of 10240 ns = **1024 consecutive cycles**, one pixel per clock with no gap |
| 11.4 | stall.PNG | stall.do | 3165 / 3195 ns | valid_in low 3 cycles; en follows, taps hold, the matching bubble reaches valid_out exactly 3 cycles later |
| 11.5 | edges.PNG | edges.do | 795 / 805 ns | column 31: right_edge masks taps c, f, i; next cycle column 0: left_edge masks a, d, g; centre tap never masked |
| 11.6 | drain.PNG | drain.do | 10385 / 10755 ns | last input in, DRAIN produces 34 more outputs, frame_done pulses, busy falls 3 cycles early |
| 11.7 | fsm.PNG | fsm.do | - | one frame through IDLE, FILL, STREAM, DRAIN, DONE with in_cnt, out_r, drain_cnt driving the transitions |
| 11.8-11.10 | Window_generator_*.PNG | unit test | - | the 3x3 window sliding: first valid window, an interior window, the last window of the frame |

---

# 12. FPGA Synthesis and Implementation Results

Post-route on **xc7z020clg400-1** (PYNQ-Z2), Vivado 2025.2, speed grade -1, 125 MHz
(8.000 ns) constraint.

| Resource | Used | Available | Utilization |
|---|---|---|---|
| Slice LUTs | **879** | 53200 | 1.65 % |
| - as logic | 863 | | |
| - as shift register | 16 | 17400 | 0.09 % |
| Slice registers | **441** | 106400 | 0.41 % |
| **DSPs** | **0** | 220 | **0 %** |
| **Block RAM tiles** | **0** | 140 | **0 %** |
| Bonded IOB | 42 | 125 | 33.60 % |
| BUFGCTRL | 1 | 32 | 3.13 % |

The two zeros are the central result: each DSP counts 50 LUT-equivalents in the Figure of
Merit and each BRAM tile 100, so the denominator is simply the 879 LUTs.

| Module | LUTs | Share | FFs |
|---|---|---|---|
| 9 x mult8x8 | 496 | 56 % | 0 |
| window_gen (incl. line buffers) | 132 | 15 % | 117 |
| coeff_reg | 120 | 14 % | 72 |
| top-level (adder tree, saturate, ReLU) | 90 | 10 % | 217 |
| control_fsm | 80 | 9 % | 35 |

Per-module figures are indicative - Vivado combines LUTs across hierarchy boundaries - but
the total is exact. The distribution shows where any further area work would have to go: the
multipliers are 56%, and they are irreducible while coefficients remain programmable.

**Synthesis versus implementation.** Post-synthesis reports 910 LUTs, post-route 879. The
synthesis figure is an estimate taken before `opt_design` removes redundant logic and
placement packs small LUTs into shared LUT6 sites; the post-route number corresponds to
physical resources and is used throughout.

**How the zeros were achieved.** DSPs: the `use_dsp = "no"` attribute alone - the synthesis log
for the submitted run records nine multipliers inferred with no DSP mapping and DSPs = 0 of 220. BRAM: the line buffers
read only their final element, so Vivado infers **16 SRLC32E** primitives - two 8-bit-wide
chains of eight - occupying 16 LUTs. No other memory primitive appears anywhere.

**DRC.** One warning, ZPS7-1 "PS7 block required" - expected for a PL-only Zynq design that
never instantiates the processing system, and affecting no reported figure.

**Reproducibility.** The implementation was run twice by different routes - a non-project Tcl
flow and a Vivado project - two days apart from the same RTL, producing identical results to
the LUT and the picosecond. A bitstream was generated for the PYNQ-Z2 pinout.

---

# 13. Timing Report

| Metric | Value |
|---|---|
| Clock constraint | 8.000 ns (125 MHz) |
| Worst negative slack | **+0.742 ns** |
| Worst hold slack | +0.153 ns |
| Failing endpoints | **0 of 602** setup, 0 of 602 hold |
| Timing status | **All constraints met** |
| Maximum frequency | **137.8 MHz** |

Fmax = 1000 / (8.000 - 0.742): the period could shorten by the available slack before the
first path fails.

## 13.1 I/O Path Exclusion

The XDC declares `set_false_path` on all inputs and outputs, so the figures are **core
register-to-register timing**. No external device clocks these pins - the accelerator is an
IP core with no interface timing contract, so there is no external requirement to constrain
against. When a nominal 1 ns I/O budget was applied instead, **all 84 setup failures were
I/O paths** (WNS -5.166 ns), the worst with just two logic levels, because the 3.3 V output
buffer alone contributes 3.557 ns of an 8 ns period and the clock path through a
non-clock-capable pin contributes 5.936 ns before any logic runs. Those are pad and
clock-tree properties, not design properties. A system integrating this core would constrain
its own I/O.

## 13.2 Critical Path

```
u_cu/bottom_edge_reg  ->  tap zero-mux  ->  mult8x8  ->  prod_r_reg[8][13]
7.297 ns: logic 2.973 (41%), routing 4.324 (59%) | 7 levels: 4 x CARRY4, LUT6, LUT5, LUT3
```

The binding path is the **arrival of a padding mask at a multiplier**, not the arithmetic.
All fifteen worst paths start at a registered edge flag and end in prod_r (10 from
bottom_edge, 4 from top_edge, 1 from right_edge). Routing dominates at 59%: `bottom_edge`
drives 156 loads - three taps x eight bits of mask logic per row - and 1.517 ns of the path
is that one net. The endpoints are the corner and edge taps masked by two flags at once,
which carry the most mask logic ahead of the multiply.

**Identified but not implemented.** Replicating the edge-flag registers per tap row would cut
the 156-load net to roughly 24 loads per copy for about 8 flip-flops - free under the FoM -
with an estimated 0.5-1 ns gain. It was not implemented: timing already closes with margin,
Fmax does not enter the Figure of Merit, and the benefit is routing-dependent rather than
structural.

---

# 14. Power Report

Power is total post-implementation power, static plus dynamic, from a switching-activity file
captured over active convolution.

| Required item | Value |
|---|---|
| **Device and board** | xc7z020clg400-1, Zynq-7000, speed -1, TUL PYNQ-Z2 |
| **Frequency used in the FoM** | **125 MHz** |
| **Static power** | 0.107 W |
| **Dynamic power** | 0.052 W |
| **Total power** | **0.158 W** |
| **SAIF interval** | 145 ns to 10800 ns = 10.655 us: first pixel in to last pixel out, reset and coefficient load excluded |
| **Tools** | Vivado 2025.2 (implementation, report_power); xsim (SAIF); ModelSim ASE 2020.1 (regression) |

| Component | Power (W) | Share |
|---|---|---|
| Static (device) | 0.107 | 68 % |
| I/O | 0.042 | 27 % |
| Clocks | 0.004 | 3 % |
| Signals | 0.003 | 2 % |
| Slice logic | 0.003 | 2 % |
| **Total** | **0.158** | |

Two observations shape Section 15. **Static power is 68%** and is a property of the device,
not the design - what a 53200-LUT part draws while holding an 879-LUT design. **I/O is 27%**:
42 pads switching at 125 MHz, an artifact of presenting a core's full interface at the device
boundary; in a deployed system these signals would stay on-chip. The design's own logic,
clocks and signals together account for about **6%** of the power term.

## 14.1 Switching Activity Methodology

The SAIF is windowed rather than taken over the whole simulation, as the organiser's
clarification requires. tb_top is re-run under xsim with sobel_x; logging starts at 145 ns -
after reset and the nine coefficient writes - and stops at 10800 ns, just past the final
output. The interval covers 1024 outputs plus fill, drain and pipeline, with no idle time.
It is read into the routed design with `read_saif -strip_path tb_top/dut` before
`report_power`.

**Confidence is Medium**, annotating 414 of 2229 nets (19%). This is a naming ceiling, not a
coverage gap: the SAIF carries RTL signal names while the routed netlist consists largely of
synthesis-generated internal nets that never existed in the RTL. Logging recursively rather
than one level deep more than doubled the SAIF - 1087 to 2380 nets - and changed the matched
count by exactly zero, confirming the diagnosis. The nets that do match are the ones that
determine power: I/O, taps, products, accumulator and pipeline registers, with Vivado
propagating probabilistically between them. High confidence would require post-implementation
timing simulation against a netlist-level testbench, outside the submitted scope.

**Effect.** Vectorless estimation - Vivado's default 12.5% toggle assumption - gave 0.181 W
with 0.074 W dynamic. The SAIF figure is 0.158 W with 0.052 W dynamic: 30% lower dynamic,
13% lower overall, and a **14.6% improvement in the Figure of Merit** from measurement alone.

---

# 15. Discussion of Design Tradeoffs

## 15.1 Parallelism: Nine MACs

Nine multipliers consume the whole window every cycle, giving 1.0 output pixel per cycle.
Three MACs (one row per cycle) would remove six multipliers - roughly 312-354 LUTs at the
measured 52-59 each - cutting the denominator to about 60% while cutting throughput to one
third, so the FoM would fall by roughly half. One MAC is worse by the same arithmetic. The
numerator is linear in throughput while the denominator falls only sub-linearly, so full
parallelism is correct for this metric; it also claims the named bonus.

## 15.2 Zero DSP and Zero BRAM

Nine DSP48E1 blocks would count 450 against the 496 LUTs the multipliers occupy - close to
neutral on the denominator alone. The decision rests on the surroundings: an 8u x 8s product
uses a fraction of a 25x18 DSP48E1 with the remainder wasted but fully counted, and keeping
one fabric type gives one power model and one placement domain.

The line buffers are clearer cut. They hold 512 bits; a single 18 kbit BRAM tile would store
this in 1.4% of its capacity while adding 100 LUT-equivalents against the 16 LUTs the
SRLC32E chains cost. The denominator would rise 879 to 963 - a 9.6% FoM loss for no
functional benefit.

## 15.3 Same Convolution Rather Than Valid

Zero-padded "same" convolution produces 1024 outputs with `valid_out` gapless across the
frame. Valid convolution would produce 900 and would deassert `valid_out` at each row
boundary, forfeiting the sustained one-pixel-per-cycle claim. The cost is the edge-flag logic
and masking multiplexers, part of window_gen's 132 LUTs - modest against a 12% larger output
and an uninterrupted stream.

## 15.4 Two Changes, One Reverted

**Registered edge flags** (Section 4.3) bought +0.410 ns of slack and 7.4 MHz for four
flip-flops. **Saturation by sign-extension test** (Section 7.3) saved about 2 LUTs and,
measured afterwards, no timing at all - stage 3 had 1.92 ns of slack and had never been the
bottleneck. It was kept for a reason that mattered more: writing it exposed that **the
saturation logic had never been tested**, since the widest real kernel is nowhere near the
clamp. The satmax and satmin kernels were added in response, taking the regression from 16
runs to 22. The optimisation was marginal; the coverage gap it revealed was not.

**The reverted change.** `in_cnt` is a 10-bit counter whose only consumer is the STREAM-to-
DRAIN transition, and `out_r`/`out_c` appeared to carry the same information. Removing it and
deriving the terminal condition from the edge flags looked free. It is wrong: `consume` is
asserted during IDLE and FILL as well as STREAM, so the input count leads the output position
by exactly FILL_CYCLES, and at the last consumed pixel the output position is (30, 29) - not
a corner, so no combination of edge flags can express it. Modelling the change before
trusting it showed the frame running 1059 inputs and 1058 outputs instead of 1024 and 1024.
The counters are offset, not redundant - and that offset is the same 34-cycle asymmetry that
makes FILL and DRAIN equal.

## 15.5 Constant-Coefficient Multipliers: Available and Rejected

Every kernel demonstrated uses only 0, +/-1, +/-2, +/-4 and 5 - all implementable as shifts
and adds with no multiplier. Hardcoding them would remove roughly 300 of the 496 multiplier
LUTs, taking the denominator from 879 to about 580 and improving the FoM by roughly 50%. It
was rejected: specification item 3 requires programmable coefficients, and forfeiting a
mandatory requirement to win a tiebreaker metric is the wrong trade. The size of the option
is reported because knowing it is part of justifying the decision not to take it.

## 15.6 Where the Power Actually Goes

The breakdown in Section 14 reframes the problem: static power is 68% of the FoM's power term
and I/O is 27%, leaving the design's own logic at about **6%**. Every RTL optimisation above
was competing for a share of that 6%, while the SAIF measurement addressed the whole term at
once - 14.6% against roughly 0.3%. The remaining levers are consequently not RTL levers: the
device (fixed here by requirement) and the I/O drive strength on the 42 pads, where reducing
from 12 mA to 4 mA was identified as a plausible ~10% saving but not applied to the submitted
build.

---

# 16. Figure of Merit

```
FOM = Throughput / ( Power x ( LUTs + 50 x DSPs + 100 x BRAMs ) )
    = 1.0 / ( 0.158 x ( 879 + 0 + 0 ) )
    = 1.0 / 138.9
    = 7.20e-3
```

**Stated interpretations.** The specification gives no power unit; **watts** are assumed, as
reported by `report_power`. The FoM is evaluated at **125 MHz** - the constrained and
verified frequency, and the clock at which the SAIF was captured, so power and frequency are
self-consistent. The organiser confirmed the frequency choice is the team's; reporting at the
achieved 137.8 MHz would raise dynamic power while throughput, being per-cycle, would not
change, making the FoM worse. Fmax is therefore reported under timing closure and
deliberately not folded into this metric.

**Table 1 - required format**

| Parameter | Specification | Team Result | Units | Comments |
|---|---|---|---|---|
| Input image size | min 32 x 32 grayscale | 32 x 32 | pixels | single channel, fixed |
| Input precision | fixed-point unsigned | 8, unsigned Q8.0 | bits | matches 8-bit grayscale exactly |
| Kernel precision | 8-bit signed | 8, signed Q8.0 | bits | 9 coefficients, programmable via write port |
| Architecture type | N x N, stride 1 | streaming line-buffer sliding window, 9 parallel MACs, zero-padded same convolution | - | 3 pipeline stages after the window |
| Multipliers / MACs | - | 9 | multipliers | fully parallel, LUT-based, 0 DSP |
| Pipeline stages | - | 3 | stages | products, row sums, output |
| Latency | - | 37 | cycles | 34 window fill + 3 pipeline |
| Throughput | output px/cycle | 1.0 peak / 0.965 sustained | px/cycle | gapless in-frame; sustained over 1061 cycles |
| FPGA utilization | LUTs, FFs, DSPs, BRAMs | 879 LUTs, 441 FFs, 0 DSP, 0 BRAM | - | 1.65 % of device; 16 LUTs are SRL |
| Maximum frequency | - | 137.8 | MHz | WNS +0.742 ns at the 125 MHz constraint |
| Power estimate | - | 0.158 total (0.107 static, 0.052 dynamic) | W | SAIF-annotated at 125 MHz, Medium confidence |
| Verification status | vs golden model | 22/22 pass, 0 mismatches | - | 7 kernels, 3 stall regimes, 2 ReLU builds; hw_out/ byte-identical to golden |
| FOM | Throughput / (Power x (LUTs + 50 DSP + 100 BRAM)) | **7.20e-3** | px/(cycle x W x LUT) | at 125 MHz; watts assumed |

---

# 17. Assumptions

The specification permits missing information to be assumed provided it is stated.

**Functional scope.** Kernel size **N = 3** is assumed (the specification says N x N without
fixing N); another N is a parameter rebuild with a change to window_gen's tap rows, not a
run-time option. Image size is fixed at 32 x 32, the specified minimum. Convolution is
**zero-padded "same"** (1024 outputs) rather than valid (900), chosen so valid_out is gapless.
The kernel is applied **unflipped (cross-correlation**, the CNN convention), matching
`write_addr = 3*row + col` and what the reference model computes; a true mathematical
convolution would require the caller to load the kernel rotated 180 degrees. The five
functional kernels are standard image-processing masks; satmax and satmin are not filters but
saturation tests.

**Interface.** No backpressure: the core provides no `ready`, and flow control is source-side
- the source presents exactly 1024 pixels per frame and holds the next until busy falls.
`busy` falls three cycles before the final `valid_out`, so a consumer must count valid_out
pulses or wait for frame_done. Coefficient writes are accepted only while busy is low, so a
kernel cannot change mid-frame. Input is raster order, one pixel per cycle, with arbitrary
stalls permitted. Reset is synchronous and active-low, assumed held at least one clock; a
board-level design would add a two-flop synchroniser in the wrapper.

**Analysis and reporting.** The FoM power unit is **watts**; the FoM is evaluated at **125
MHz**. I/O timing is excluded from timing closure, so reported Fmax is the internal
register-to-register limit. Power-analysis conditions are the Vivado defaults (25 C ambient,
ThetaJA 11.5 C/W, 250 LFM, no heat sink, commercial grade, typical process); no board-level
measurement was made. `COEF_FRAC` is declared for a Q1.7 format but has no implementing logic
and no results are claimed for it.

---

# 18. Bonus Features

| Bonus | Claimed | Evidence |
|---|---|---|
| One output pixel per cycle, pipelined | **Yes** | valid_out unbroken for 1024 consecutive cycles (Figure 11.3); 22/22 regression runs |
| Multiple kernels | **Yes** | 9 coefficients programmable through the write port; 5 functional kernels verified bit-exact; kernel reloaded between frames in the back-to-back run |
| ReLU activation | **Yes** | RELU parameter; a second full instance with RELU=1 checked against ReLU references on all 7 kernels |
| Edge-detection demo | **Yes**, in simulation | Figures 18.1-18.3, rendered from hw_out/ - the hardware outputs, not the model |
| Board demonstration | **No** | see below |

A bitstream (`fpga/top.bit`) was generated for the real PYNQ-Z2 pinout, with all 42 pins
assigned to user-accessible connectors - Pmod A for pixel input, Pmod B for coefficient data,
the Arduino header for control, the Raspberry Pi header for the 16-bit output, SW0 for reset
and LED0/1 for status. The design is therefore implementable and loadable. It was not
demonstrated on hardware: no board was available, and a demonstration would additionally need
a wrapper to drive the pixel stream and a reset synchroniser. **This bonus is not claimed.**

**Figures 18.1-18.3** - edge_demo_sobel_x.png, edge_demo_sobel_y.png,
edge_demo_laplacian.png: the input image beside the accelerator's own output, rendered
directly from hw_out/.

---

# 19. Conclusion

A 3x3 convolution accelerator with programmable coefficients was designed, verified and
implemented on a Zynq-7000 xc7z020, meeting every mandatory specification and claiming four
of the five bonus features.

**Results.** 879 LUTs, 441 flip-flops, **zero DSP blocks and zero block RAMs**, 1.65% of the
device. Timing closes at 125 MHz with +0.742 ns of slack, giving 137.8 MHz maximum frequency
with no failing endpoints. Total power is 0.158 W from a switching-activity file captured over
active convolution. **The Figure of Merit is 7.20e-3.** The accelerator produces one output
pixel per clock, gapless within a frame, at 37 cycles of latency, and its output is
byte-identical to an independently written reference model across 22 regression runs covering
seven kernels, three stall regimes, both ReLU builds and a back-to-back frame pair.

**What the design does well.** The two structural decisions that dominate the Figure of Merit
are keeping the line buffers in fabric shift registers - 16 LUTs as SRLC32E, avoiding a
100-LUT-equivalent BRAM penalty - and forcing the nine multipliers into LUTs, avoiding 450
LUT-equivalents of DSP penalty. The strict control/datapath split made both unit testing and
stall behaviour straightforward, and the free-running pipeline with a travelling valid bit
handles arbitrary input stalls with no additional control logic.

**What was learned.** Measurement beat design: capturing a proper switching-activity file
improved the Figure of Merit by 14.6% against roughly 0.3% from the RTL optimisations,
because the design's own logic accounts for only about 6% of the power term. An optimisation
that bought nothing in its own terms - the saturation rewrite - was the change that exposed an
untested path, because no real kernel reaches the clamp. And the counter that looked redundant
was not: modelling the change before trusting it caught a frame-accounting error, and the
offset that made it wrong is the same asymmetry that makes the fill and drain lengths equal.

**Characterised but not implemented.** Replicating the edge-flag registers to break a 156-load
net (estimated 0.5-1 ns); reducing output drive strength from 12 mA to 4 mA (estimated ~10% of
total power); and constant-coefficient multipliers (roughly 50% FoM improvement, rejected
because it forfeits mandatory programmability).

---

# Appendix A - Submitted Files

| Deliverable | Path | Contents |
|---|---|---|
| RTL source | `rtl/` | 7 SystemVerilog files, 417 lines |
| Testbenches | `tb/` | regression, single kernel, window integration, window unit |
| Golden model | `golden_model/golden.py` | Python/NumPy reference, 80 lines |
| Input image | `golden_model/hex/image.hex`, `cat.png` | 32 x 32 grayscale, 1024 lines |
| Coefficients | `golden_model/hex/<k>_coef.hex` | 7 kernels, 9 lines each, write-port order |
| Expected outputs | `golden_model/hex/<k>_out.hex`, `_relu_out.hex` | 14 files, 1024 lines each |
| **Hardware outputs** | `hw_out/` | 14 files from the RTL, byte-identical to the above |
| Window vectors | `golden_model/vectors/` | 5 patterns, 1024 windows each |
| FPGA reports | `fpga/reports/` | utilization (+hier, +synth), synth.log, timing_summary, paths, power, drc, io |
| Constraints, bitstream | `fpga/pynq_z2.xdc`, `fpga/top.bit` | clock, 42 pins, I/O false paths; PL-only bitstream |
| Scripts | `fpga/build.tcl`, `saif.bat`, `paths.tcl`, `sim/` | implementation flow, SAIF capture, per-stage timing, simulation |
| Figures | `docs/figures/` | 10 waveform captures, 3 edge-detection renders |

**Reproducing the results**

```
do sim/compile.do
do sim/run.do all                                 22 runs, regenerates hw_out/
cd golden_model && python golden.py hex/image.hex  regenerates the reference files
fpga\saif.bat                                     captures the SAIF
vivado -mode tcl   then   source fpga/build.tcl   synthesis, implementation, all reports
```
