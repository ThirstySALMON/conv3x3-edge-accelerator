# Design iterations

What was changed after the first implementation run, why, and what it cost or bought.
Written as it happened, including the change that did not work.

Baseline is commit `8860e7a`: xc7z020clg400-1, 882 LUTs, 437 FFs, 0 DSP, 0 BRAM,
WNS +0.332 ns at 125 MHz, 0.181 W, FoM 6.27e-3.

---

## 0. Where the baseline actually spent its LUTs

`report_utilization -hierarchical` on the routed design:

| block | LUTs | % |
|---|---|---|
| 9 x mult8x8 | 485 | 54% |
| control_fsm | 165 | 19% |
| coeff_reg | 96 | 11% |
| window_gen | 96 | 11% (80 logic + 16 SRL) |
| adder tree / saturate / relu | 89 | 10% |

The FoM denominator is `LUTs + 50*DSPs + 100*BRAMs` and DSPs and BRAMs are already 0, so
every remaining point of FoM is a LUT. That makes the multipliers the obvious target and
control_fsm the surprising one - 165 LUTs is a lot for 5 states and 3 counters.

The multipliers are not reducible while the coefficients stay programmable. Every kernel
in the golden model (identity, sobel, sharpen, laplacian) is made only of 0, +/-1, +/-2,
+/-4, 5, so hardcoding them would collapse the datapath to shifts and adds and save
roughly 300 LUTs - a 3-4x FoM improvement. It was rejected: announcement item 3 requires
the coefficients to be programmable, and forfeiting a mandatory spec to win a tiebreaker
metric is the wrong trade. Recorded here because the analysis is worth stating.

---

## 1. Rejected: removing in_cnt from control_fsm (tried, broke the design)

**Idea.** `in_cnt` is a 10-bit counter to 1023 whose only job is the STREAM -> DRAIN
trigger, `last_consume = consume && (in_cnt == NPIX-1)`. out_r and out_c already count
the same frame, so it looked like the trigger could reuse `bottom_edge && right_edge` and
the counter plus its 10-bit comparator could go.

**Why it is wrong.** `consume` is asserted during FILL as well as STREAM. Inputs therefore
lead outputs by exactly FILL_CYCLES, and at the last consumed pixel the output position is
(30, 29) - not a corner, so the edge flags cannot express it. Modelling the modified FSM
in Python before trusting it gave 1059 consumed / 1058 out instead of 1024 / 1024.

**Outcome.** Reverted. `in_cnt` stays. The 165 LUTs in control_fsm are not a redundant
counter - they are the four edge comparators (each driving 24 tap zero-muxes in
window_gen), the en / consume / out_adv fanout, and a one-hot state register that Vivado
replicated to meet timing.

Kept in this document deliberately: the reasoning was plausible and the counter-example is
the useful part.

---

## 2. Registered the edge flags

**Why.** The baseline critical path was not the multiplier on its own:

    u_cu/out_c_reg[4] -> right_edge -> tap zero mux -> multiplier -> prod_r[8][13]
    8 levels (4x CARRY4, 2x LUT6, LUT5, LUT4), 7.633 ns, 62% routing

The column counter, the edge comparator, the tap masking and the multiply were all in one
cycle, and the comparator net had fanout 127.

**Change.** `top/bottom/left/right_edge` are now registers in control_fsm, computed from
the *next* output position (nxt_r / nxt_c) so they are valid on the cycle they are used.

**Cost.** 4 FFs. No extra LUTs - the logic moved, it did not grow. Latency, throughput and
the module interface are unchanged.

**Verified.** `do sim/run.do all` passes, and tb_top_window checks the flags against the
expected raster position on every one of the 1024 windows - 0 position/edge errors.

---

## 3. Saturation by sign-extension check instead of magnitude compares

**Why.** Stage 3 was doing, in one cycle, a 3-input 20-bit add followed by *two* 20-bit
signed magnitude comparisons:

```systemverilog
if      (acc > OUT_MAX) sat = OUT_MAX;   // 20-bit compare, carry chain
else if (acc < OUT_MIN) sat = OUT_MIN;   // 20-bit compare, carry chain
else                    sat = acc[15:0];
```

report_timing_summary only prints the single worst path per clock group, so it could not
show whether this stage was close behind stage 1 or far from it. Rather than assume, the
cheaper form was worth taking regardless of the ranking.

**Change.** A 20-bit value fits in 16 bits signed exactly when its top bits are all copies
of bit 15. So test `acc[19:15]` for all-zeros or all-ones, and clamp by the sign bit when
it fails:

```systemverilog
assign acc_top = acc[ACC_W-1 -: (ACC_W-OUT_W+1)];   // acc[19:15]
assign fits    = (acc_top == '0) || (acc_top == '1);
```

Two carry chains become one 5-bit equality test, about 2 LUTs.

**Verified.** Exhaustively equivalent to the original over all 2^20 accumulator values
(checked in Python, 0 mismatches), then in RTL against the golden model.

**And the verification gap it exposed.** None of the five real kernels ever saturates -
the widest accumulator range is sobel_y at [-898, +934], nowhere near +/-32767. Both
saturation branches were therefore completely untested, before and after this change. Two
kernels were added to the golden model for this: `satmax` (all +127) and `satmin`
(all -128), which clamp on all 1024 outputs including the zero-padded borders. The
regression went from 16 runs to 22, all passing.

That is the more important outcome of this iteration. The optimisation is small; finding
that the saturation logic had never been exercised is not.

---

## 4. Power from a SAIF instead of the vectorless guess

**Why.** The organiser confirmed (11 Sep) the FoM power term must be total
post-implementation power with the switching activity from a SAIF covering active
convolution only. The 0.181 W in the baseline was the Vivado default 12.5% toggle
assumption, Low confidence.

**What.** tb_top rerun in xsim with SAIF capture windowed to 145-10800 ns - first pixel in
to last pixel out, 1332 cycles, reset and coefficient load excluded. Read into the routed
design and report_power rerun. Details and the two benign warnings are in
docs/notes/POWER_METHODOLOGY.md.

**Result.** Dynamic 0.074 -> 0.052 W, total 0.181 -> **0.158 W**, confidence Low ->
Medium. FoM 6.285e-3 -> **7.20e-3, +14.6%**, with no change to the RTL at all. The
largest single FoM gain in the project came from measuring properly, not from design.

**What it also showed.** Of the 0.158 W, static is 0.107 (68%) and I/O pads are 0.042
(27%). The logic of the design itself is about 0.009 W - 6% of the power term. Every RTL
optimisation above moved that 6%. The remaining levers are the device (static power is a
property of the die) and the I/O standard / drive strength on the 42 pads.

## Status

Re-implemented 11 Sep 18:06, routed, xc7z020clg400-1.

| | baseline | after 2 + 3 | |
|---|---|---|---|
| regression | 16/16 | **22/22** | saturation branches now covered |
| LUTs | 882 | **879** | -3 |
| FFs | 437 | 441 | +4, the registered edge flags |
| LUT as shift reg | 16 | 16 | line buffers, unchanged |
| DSP / BRAM | 0 / 0 | **0 / 0** | |
| WNS at 8 ns | +0.332 ns | **+0.742 ns** | **+0.410 ns** |
| Fmax | 130.4 MHz | **137.8 MHz** | **+5.6%** |
| power | 0.181 W vectorless | **0.158 W SAIF** | -13%, Medium confidence |
| FoM | 6.264e-3 | **7.20e-3** | **+14.9%** overall, almost all from the SAIF |

The two changes bought timing, not area, which is what was predicted: LUT count is flat
(-3) because the logic moved rather than shrank, and the FoM barely shifts because power
and LUTs both stayed put. The 5.6% Fmax gain is the real result, and it goes to the
"timing closure" criterion rather than the FoM.

### The critical path moved, but only within stage 1

    baseline:  out_c_reg[4] -> right_edge -> tap mux -> multiplier -> prod_r[8][13]
               8 levels, 7.633 ns, 62% routing
    now:       bottom_edge_reg -> tap mux -> multiplier -> prod_r[8][13]
               7 levels, 7.297 ns, 59% routing

The comparator is gone from the path - it now starts at the *registered* flag - but the
destination is still `prod_r`, so stage 1 (the multipliers) remains the binding stage.
Note `bottom_edge` has fanout 156 and spends 1.517 ns on the net into window_gen: the
flag is registered but it still drives 24 tap muxes across the die, and that routing is
now the largest single term in the path.

### Per-stage slack, measured (fpga/paths.tcl on the routed design)

| stage | worst slack | headroom over stage 1 |
|---|---|---|
| 1: window/coeffs -> prod_r (9 multipliers) | **+0.742 ns** | - |
| 3: row_r -> pixel_out (add + saturate + relu) | +2.666 ns | 1.92 ns |
| 2: prod_r -> row_r (3 row adders) | +3.799 ns | 3.06 ns |

So the saturate stage was never the constraint - it has nearly 2 ns spare. The top-bits
rewrite in section 3 bought no timing at all. It is kept because it is 2 LUTs cheaper,
proven equivalent over the full input range, and because writing it is what exposed that
the saturation branches had never been exercised.

### Every one of the 15 worst paths starts at an edge flag

    bottom_edge_reg -> prod_r[8][*]    9 of the top 15
    top_edge_reg    -> prod_r[2][*]    4
    right_edge_reg  -> prod_r[5][13]   1

None start at coeff_reg or at the tap registers. The binding constraint is not the
multiplier logic, it is when the edge flags arrive at the multipliers. The endpoints are
taps i, c and f - the corner/edge taps masked by two flags at once, so they carry the most
mask logic ahead of the multiply.

Registering the flags removed the comparator from the path; what is left is fanout.
`bottom_edge` drives 156 loads and 1.517 ns of the 7.297 ns path is that one net. The next
step, if timing ever needs it, is replicating the edge-flag registers per tap row
(`max_fanout` attribute, or explicit duplicates with dont_touch) so each copy drives ~24
loads instead of 156 - about 8 FFs, free in the FoM, maybe 0.5-1 ns.

Not done: timing already closes, Fmax is not in the FoM, and the gain is routing-dependent
rather than structural. Recorded as identified-and-quantified.

### Where the LUTs sit now

| block | baseline | now | |
|---|---|---|---|
| 9 x mult8x8 | 485 | 496 | +11 |
| control_fsm | 165 | **80** | **-85**, the edge comparators left |
| coeff_reg | 96 | 120 | +24 |
| window_gen | 96 | 132 | +36, 116 logic + 16 SRL |
| top glue | 89 | 90 | +1 |

control_fsm more than halved, but the work reappeared in window_gen and the multipliers -
Vivado combines LUTs across the hierarchy boundary (the report says so in a footnote), so
these per-block numbers move around between runs without the total changing. The total
went 882 -> 879. Read the per-block split as indicative, not exact.

The batch flow still fails on this machine ("Unknown error occured while verifying the
digital signature. Error Code: -2146869232") - including the GUI's own synth_1 run, which
spawns a batch child. These numbers came from running the flow in the GUI Tcl console.
