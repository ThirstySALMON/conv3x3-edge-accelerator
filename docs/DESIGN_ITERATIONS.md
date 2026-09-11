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

## Status

| | baseline | after 2 + 3 |
|---|---|---|
| regression | 16/16 | **22/22** (saturation now covered) |
| LUTs | 882 | to be re-measured |
| FFs | 437 | ~441 |
| WNS at 8 ns | +0.332 ns | to be re-measured |
| Fmax | 130.4 MHz | to be re-measured |
| FoM | 6.27e-3 | to be re-measured |

Re-implementation has to be done in the Vivado GUI: batch mode fails on this machine with
"Unknown error occured while verifying the digital signature. Error Code: -2146869232",
on any design including a two-line $display, so it is the install and not the project.

`fpga/paths.tcl` reports the worst paths per pipeline stage rather than only the global
worst, which is what should be run after re-implementing to see whether the bottleneck
has moved from stage 1 to stage 3 or stayed put.
