# 12. FPGA Synthesis and Implementation Results

All results are post-route on **xc7z020clg400-1** (PYNQ-Z2, TUL), Vivado 2025.2, speed grade
-1, with a 125 MHz (8.000 ns) clock constraint. The reports referenced here are in
fpga/reports/.

## 12.1 Resource Utilization

| Resource | Used | Available | Utilization |
|---|---|---|---|
| Slice LUTs | **879** | 53200 | 1.65 % |
| - LUT as logic | 863 | 53200 | 1.62 % |
| - LUT as shift register | 16 | 17400 | 0.09 % |
| Slice registers (all flip-flops) | **441** | 106400 | 0.41 % |
| **DSPs** | **0** | 220 | **0 %** |
| **Block RAM tiles** | **0** | 140 | **0 %** |
| Bonded IOB | 42 | 125 | 33.60 % |
| BUFGCTRL | 1 | 32 | 3.13 % |

The two zeros are the design's central result. Under the Figure of Merit each DSP counts as
50 LUT-equivalents and each BRAM tile as 100, so the denominator is simply the 879 LUTs;
there is nothing else in it.

## 12.2 Utilization by Module

| Module | LUTs | Share | FFs |
|---|---|---|---|
| 9 x mult8x8 | 496 | 56 % | 0 |
| window_gen (incl. line buffers) | 132 | 15 % | 117 |
| coeff_reg | 120 | 14 % | 72 |
| top-level (adder tree, saturate, ReLU) | 90 | 10 % | 217 |
| control_fsm | 80 | 9 % | 35 |
| **Total** | **879** | | **441** |

These per-module figures are indicative rather than exact: Vivado combines LUTs across
hierarchy boundaries during optimisation, and its own report carries that caveat. The
total is exact. The distribution confirms where any further area work would have to go -
the multipliers are 56 % of the design, and they are irreducible while the coefficients
remain programmable.

## 12.3 Synthesis Versus Implementation

Post-synthesis utilisation reports **910 LUTs**; post-route reports **879**. The difference
is not a discrepancy: the synthesis figure is an estimate taken before `opt_design` removes
redundant logic and before placement packs pairs of small LUTs into shared LUT6 sites. The
post-route number is the one that corresponds to physical resources and the one used
throughout this report and in the Figure of Merit.

## 12.4 How Zero DSP and Zero BRAM Were Achieved

- **DSPs.** The `(* use_dsp = "no" *)` attribute on mult8x8, plus `-max_dsp 0` passed to
  synth_design as a second guard. The synthesis log confirms nine multipliers inferred as
  `8x9 Multipliers := 9` with no DSP mapping.
- **BRAM.** The line buffers are written as shift registers whose only read point is the
  final element, so Vivado infers **16 SRLC32E** primitives - two 8-bit-wide chains of eight
  - occupying 16 LUTs. The synthesis log's Static Shift Register Report shows both chains
  (length 30, width 8, 8 SRLC32E each). No memory primitive of any other kind appears in the
  design.

## 12.5 Design Rule Check

`report_drc` returns a single warning, **ZPS7-1: PS7 block required**. This is expected and
carries no consequence: the design is PL-only and never instantiates the Zynq processing
system, whereas Vivado's rule assumes a Zynq bitstream configures the PL from the PS. It
affects no utilisation, timing or power figure. A PL-only bitstream loads over JTAG
normally.

## 12.6 Reproducibility

The implementation was run twice by different routes - once through a non-project Tcl flow
and once through a Vivado project with Run Synthesis / Run Implementation - two days apart,
from the same RTL. Both produced **879 LUTs, 441 FFs, 0 DSP, 0 BRAM, WNS +0.742 ns**,
identical to the LUT and to the picosecond. Vivado is deterministic for fixed inputs and
settings; this was verified rather than assumed.

A bitstream (fpga/top.bit) was generated for the PYNQ-Z2 pinout, confirming the design is
implementable end to end.

Sources: fpga/reports/utilization.rpt, utilization_hier.rpt, synth_utilization.rpt,
synth.log, drc.rpt.

**Table 12.1** - Resource utilization (Section 12.1)

**Table 12.2** - Utilization by module (Section 12.2)

---

# 13. Timing Report

## 13.1 Summary

| Metric | Value |
|---|---|
| Clock constraint | 8.000 ns (125 MHz) |
| Worst negative slack (WNS) | **+0.742 ns** |
| Worst hold slack (WHS) | +0.153 ns |
| Worst pulse width slack | +3.020 ns |
| Failing endpoints | **0 of 602** (setup), 0 of 602 (hold) |
| Timing status | **All user specified timing constraints are met** |
| Maximum frequency | **137.8 MHz** |

Fmax is derived as 1000 / (8.000 - 0.742) = 137.8 MHz: the clock period could be shortened
by the available slack before the first path fails. Setup, hold and pulse-width checks all
pass with margin; no timing exceptions beyond the I/O false paths described below.

## 13.2 I/O Path Exclusion

The XDC declares `set_false_path` on all inputs and all outputs, so the reported figures are
**core register-to-register timing**. This is a deliberate and necessary choice, and the
reasoning is recorded here because it affects how the numbers should be read.

- No external device clocks these pins. The accelerator is an IP core with no specified
  interface timing contract, so there is no external setup/hold requirement to constrain
  against.
- When a nominal 1 ns I/O budget was applied instead, **all 84 setup failures were I/O
  paths**, with WNS -5.166 ns. The worst had just **two logic levels** - one LUT and an
  output buffer - because the 3.3 V OBUF alone contributes 3.557 ns of an 8 ns period, and
  the clock path through a non-clock-capable pin (IBUF + BUFG) contributes 5.936 ns before
  any logic runs. Those are pad and clock-tree properties, not design properties.
- Excluding I/O is standard practice for a core delivered without a board-level interface
  specification. A system integrating this core would constrain its own I/O.

## 13.3 Critical Path

```
Source:      u_cu/bottom_edge_reg/C          (registered edge flag)
  -> tap zero-mux in window_gen
  -> mult8x8 (8u x 8s)
Destination: prod_r_reg[8][13]/D             (stage 1 pipeline register)

Data path delay 7.297 ns: logic 2.973 ns (41 %), routing 4.324 ns (59 %)
Logic levels: 7  (4 x CARRY4, LUT6, LUT5, LUT3)
```

- The binding path is the **arrival of a padding mask at a multiplier**, not the multiplier
  arithmetic itself. All fifteen of the worst paths in the design start at a registered edge
  flag and end in prod_r: 10 from bottom_edge_reg, 4 from top_edge_reg, 1 from
  right_edge_reg.
- **Routing dominates at 59 %.** `bottom_edge` drives 156 loads - three taps x eight bits
  of mask logic per multiplier row - and 1.517 ns of the path is that single net.
- The endpoints are taps i, c and f: the corner and edge taps masked by two flags at once,
  which therefore carry the most mask logic ahead of the multiply.

## 13.4 Stage Balance

| Stage | Endpoint | Worst slack |
|---|---|---|
| 1 - multipliers | prod_r | +0.742 ns |
| 2 - row adders | row_r | +3.799 ns |
| 3 - final add, saturate, ReLU | pixel_out | +2.666 ns |

Stage 1 binds; stages 2 and 3 retain 3.06 ns and 1.92 ns respectively. The pipeline is
balanced in the sense that matters - no stage is starved while another is critical - and
stage 3 in particular was measured rather than assumed to be non-critical before the
decision was taken to leave the final adder, saturation and ReLU in a single stage.

## 13.5 Identified but Not Implemented

Replicating the edge-flag registers per tap row (via a `max_fanout` attribute or explicit
duplicates) would reduce the 156-load net to roughly 24 loads per copy, at a cost of about
8 flip-flops - free under the Figure of Merit. The estimated gain is 0.5 to 1 ns. It was not
implemented: timing already closes with margin, Fmax does not appear in the Figure of Merit,
and the benefit is routing-dependent rather than structural. It is recorded here as a
characterised option rather than an oversight.

Sources: fpga/reports/timing_summary.rpt, fpga/reports/paths.rpt.

**Table 13.1** - Timing summary (Section 13.1)

**Table 13.2** - Per-stage slack (Section 13.4)

---

# 14. Power Report

Power is reported as **total post-implementation power, static plus dynamic**, from a
switching activity file captured over active convolution. The five items below are reported
explicitly as required.

## 14.1 Required Reporting Items

| Item | Value |
|---|---|
| **FPGA device and board** | xc7z020clg400-1, Zynq-7000, speed grade -1, on the TUL PYNQ-Z2 |
| **Operating frequency used in the FoM** | **125 MHz** (8.000 ns constraint) |
| **Static power** | 0.107 W |
| **Dynamic power** | 0.052 W |
| **Total power** | **0.158 W** |
| **SAIF simulation interval** | 145 ns to 10800 ns = 10.655 us, covering first pixel in to last pixel out; reset and coefficient load excluded |
| **Implementation tool** | Vivado 2025.2 (synthesis, implementation, report_power) |
| **Simulation tools** | Vivado xsim (SAIF capture), ModelSim ASE 2020.1 (functional regression) |

## 14.2 Power Breakdown

| Component | Power (W) | Share of total |
|---|---|---|
| Static (device) | 0.107 | 68 % |
| I/O | 0.042 | 27 % |
| Clocks | 0.004 | 3 % |
| Signals | 0.003 | 2 % |
| Slice logic | 0.003 | 2 % |
| **Total** | **0.158** | |

Two observations follow directly from this table and shape the tradeoff discussion in
Section 15:

- **Static power is 68 % of the total** and is a property of the device, not the design. It
  is what a 53200-LUT part draws while holding a 879-LUT design.
- **I/O is 27 %** - 42 pads switching at 125 MHz. In a deployed system this core would sit
  inside a larger design with these signals staying on-chip, so this component would largely
  disappear. It is an artifact of presenting a core's full interface at the device boundary.
- The design's own logic, clocks and signals together account for about **6 %** of the power
  term. This is the honest context for the optimisation work in Section 15.

## 14.3 Switching Activity Methodology

The organiser's clarification required the SAIF to represent active convolution and to
exclude long reset or idle periods. The capture is therefore windowed rather than taken over
the whole simulation:

- tb_top is re-run under Vivado xsim with the sobel_x kernel. Logging starts at 145 ns - the
  first accepted pixel, after the 4 reset cycles and the 9 coefficient writes - and stops at
  10800 ns, just after the final output.
- The recorded interval is 10.655 us: 1024 outputs plus fill, drain and pipeline, with no
  idle time and no reset activity.
- The SAIF records 2380 nets beneath the DUT hierarchy, logged recursively.
- It is read into the routed design with
  `read_saif fpga/tb_top.saif -strip_path tb_top/dut` before `report_power`.

**Confidence and its limit.** report_power reports **Medium** confidence, annotating 414 of
2229 design nets (19 %). This is a naming ceiling rather than a coverage gap: the SAIF
carries RTL signal names, while the routed netlist consists largely of synthesis-generated
internal nets (names such as `prod_r_reg[8][11]_i_1_n_0`) that never existed in the RTL and
that no RTL-level simulation can annotate. Logging recursively rather than one level deep
more than doubled the SAIF - 1087 to 2380 nets - and changed the matched count by exactly
zero, which confirms the diagnosis. The nets that do match are the ones that determine
power: the I/O, taps, products, accumulator and pipeline registers. Vivado propagates
probabilistically through the combinational nets between them, which is its designed
behaviour. High confidence would require post-implementation timing simulation against a
netlist-level testbench, which was outside the submitted scope.

**Effect of measuring properly.** Vectorless estimation - Vivado's default 12.5 % toggle
assumption, Low confidence - gave 0.181 W with 0.074 W dynamic. The SAIF-annotated figure is
0.158 W with 0.052 W dynamic, 30 % lower on the dynamic component and 13 % lower overall.
This single change improved the Figure of Merit by 14.6 %, more than every RTL optimisation
in the project combined.

Two warnings appear on every `read_saif` and are both benign: Vivado declines to take clock
activity from a SAIF and uses the `create_clock` constraint instead (which is correct), and
a high-fanout reset heuristic misreads `rst_n`, which the SAIF shows held high with zero
toggles for the entire window - reset was released before capture began.

Sources: fpga/reports/power.rpt, fpga/tb_top.saif, fpga/saif.bat, fpga/saif_xsim.tcl.

**Table 14.1** - Required power reporting items (Section 14.1)

**Table 14.2** - Power breakdown by component (Section 14.2)

---

# 15. Discussion of Design Tradeoffs

Every decision below was taken against the Figure of Merit, which rewards throughput per
cycle and penalises LUTs, DSPs (x50), BRAMs (x100) and power.

## 15.1 Nine Parallel MACs Rather Than Three or One

Nine multipliers consume the entire 3x3 window every cycle, giving 1.0 output pixel per
cycle. The alternatives were considered and rejected:

- **Three MACs** (one row per cycle, one output per three cycles) would remove six
  multipliers - roughly 312 to 354 LUTs by the measured 52-59 LUTs each - reducing the
  denominator to about 60 % while cutting throughput to one third. The FoM would fall by
  roughly half.
- **One MAC** (nine cycles per output) is worse still by the same arithmetic.
- Nine MACs also claims the named one-pixel-per-cycle bonus.

The FoM numerator is linear in throughput while the denominator falls only sub-linearly as
multipliers are removed, so full parallelism is correct for this metric.

## 15.2 LUT Multipliers Rather Than DSP Blocks

Nine DSP48E1 blocks would count 9 x 50 = 450 against the 496 LUTs the multipliers actually
occupy - close to neutral on the denominator alone. The decision rests on the surrounding
factors:

- An 8u x 8s product uses a small fraction of a 25x18 DSP48E1; the remaining capacity is
  wasted but fully counted.
- Keeping the design in a single fabric type gives one consistent power model and one
  placement domain.
- The RTL stays vendor-neutral apart from one attribute.

## 15.3 Fabric Line Buffers Rather Than BRAM

The line buffers hold 2 x 32 x 8 = 512 bits. A single 18 kbit BRAM tile would store this in
1.4 % of its capacity while adding 100 LUT-equivalents to the denominator, against the 16
LUTs the SRLC32E chains actually cost. The denominator would rise from 879 to 963, a 9.6 %
FoM loss for no functional benefit. This is the clearest case in the design where the FoM's
weighting points the same way as good engineering.

## 15.4 Same Convolution Rather Than Valid

Zero-padded "same" convolution produces 32x32 = 1024 outputs with `valid_out` gapless across
the entire frame. Valid convolution would produce 30x30 = 900 outputs and would deassert
`valid_out` at each row boundary, forfeiting the sustained one-pixel-per-cycle claim. The
cost of "same" is the edge-flag logic and the masking multiplexers - part of the 132 LUTs in
window_gen - which is modest against a 12 % larger output and an uninterrupted output
stream.

## 15.5 Registered Edge Flags

Originally the four padding flags were combinational functions of the position counters,
placing counter, comparator, mask and multiplier in a single cycle. Registering them - and
computing them one position ahead so they remain correct - moved the comparator off the
datapath path.

| | Before | After |
|---|---|---|
| WNS | +0.332 ns | +0.742 ns |
| Fmax | 130.4 MHz | 137.8 MHz |
| LUTs | 882 | 879 |
| FFs | 437 | 441 |

Cost: 4 flip-flops, free under the FoM. This bought timing headroom rather than area, and
the FoM barely moved - which is itself the useful finding, discussed in 15.9.

## 15.6 Saturation by Sign-Extension Test

Replacing two 20-bit magnitude comparators with a 5-bit equality test saved roughly 2 LUTs
and removed two carry chains from stage 3. Per-stage measurement afterwards showed stage 3
had 1.92 ns of slack and had never been the bottleneck, so the change bought no timing.

It was kept regardless, for a reason that turned out to matter more than the LUTs:
**writing it exposed that the saturation logic had never been tested.** The widest real
kernel is sobel_y at -898 to +934, nowhere near the +/-32767 clamp, so every passing test to
that point had exercised only the pass-through branch. The satmax and satmin kernels were
added in response, taking the regression from 16 runs to 22 and covering both clamp
directions on 2048 pixels. The optimisation was marginal; the coverage gap it revealed was
not.

## 15.7 The Iteration That Was Reverted

`in_cnt` is a 10-bit counter whose only consumer is the STREAM-to-DRAIN transition, and
`out_r`/`out_c` appeared to carry the same information. Removing it and deriving the
terminal condition from the edge flags looked like a free saving of a counter and a 10-bit
comparator.

It is wrong. `consume` is asserted during IDLE and FILL as well as STREAM, so the input
count leads the output position by exactly FILL_CYCLES. At the last consumed pixel the
output position is (30, 29) - not a frame corner - so no combination of edge flags can
express the condition. Modelling the modified FSM before trusting it showed the frame
running 1059 inputs and 1058 outputs instead of 1024 and 1024.

The change was withdrawn. It is reported because the counter-example is the useful artifact:
the two counters are offset, not redundant, and that offset is the same 34-cycle asymmetry
that makes FILL and DRAIN equal.

## 15.8 Constant-Coefficient Multipliers: Available and Rejected

Every kernel demonstrated uses only the values 0, +/-1, +/-2, +/-4 and 5 - all powers of two
or trivial sums, implementable as shifts and adds with no multiplier at all. Hardcoding them
would remove roughly 300 of the 496 multiplier LUTs, taking the denominator from 879 to
about 580 and improving the FoM by roughly 50 %.

It was rejected. Specification item 3 requires the kernel coefficients to be programmable or
configurable, and a hardcoded kernel forfeits a mandatory requirement to win a tiebreaker
metric. The analysis is reported because knowing the size of the option is part of
justifying the decision not to take it.

## 15.9 Where the Power Actually Goes

The breakdown in Section 14.2 reframes the optimisation problem: static power is 68 % of the
FoM's power term and I/O is 27 %, leaving the design's own logic at about **6 %**. Every RTL
optimisation in Section 15.5 and 15.6 was competing for a share of that 6 %, while the SAIF
measurement in 15.10 addressed the whole term at once.

The remaining levers are consequently not RTL levers: the device (static power is set by the
die, and PYNQ-Z2 was a fixed requirement here) and the I/O standard and drive strength on the
42 pads. Reducing output drive from the default 12 mA to 4 mA was identified as a plausible
~10 % power saving but was not applied to the submitted build, which is reported
unmodified.

## 15.10 Measurement as an Optimisation

The largest single Figure of Merit improvement in the project came from measuring power
correctly rather than from changing the design: replacing Vivado's vectorless 12.5 % toggle
assumption with a SAIF captured over active convolution moved the FoM from 6.285e-3 to
7.20e-3, a gain of 14.6 % with the RTL untouched. For comparison, the registered edge flags
and the saturation rewrite together moved the FoM by about 0.3 %.

**Table 15.1** - Design iterations and their measured effect (Section 8.6)

---

# 16. Figure of Merit

## 16.1 Computation

```
FOM = Throughput / ( Power x ( LUTs + 50 x DSPs + 100 x BRAMs ) )

    = 1.0 / ( 0.158 x ( 879 + 50 x 0 + 100 x 0 ) )
    = 1.0 / ( 0.158 x 879 )
    = 1.0 / 138.9
    = 7.20e-3
```

| Term | Value | Source |
|---|---|---|
| Throughput | 1.0 output pixel/cycle | gapless valid_out, Figure 11.3 |
| Power | 0.158 W total at 125 MHz | report_power, SAIF-annotated |
| LUTs | 879 | post-route utilization |
| DSPs | 0 | x50 term contributes nothing |
| BRAMs | 0 | x100 term contributes nothing |
| **FoM** | **7.20e-3** | |

## 16.2 Stated Interpretations

- **Power unit.** The specification gives no unit for the power term. Watts are assumed, as
  reported by `report_power`. Had milliwatts been intended, the value scales by 1000.
- **Frequency.** The FoM is evaluated at **125 MHz**, the constrained and verified operating
  frequency, which is also the clock at which the SAIF was captured - so power and frequency
  are self-consistent. The organiser confirmed the choice of frequency is the team's.
  Reporting at the achieved Fmax of 137.8 MHz would raise dynamic power while throughput,
  being per-cycle, would not change - making the FoM worse. Fmax is therefore reported under
  timing closure (Section 13) and is deliberately not folded into this metric.
- **Throughput.** Taken as peak sustained throughput within a frame, 1.0 output pixel per
  cycle, which the specification's "output pixels per cycle" describes. Averaged over a
  complete frame including fill and drain the figure is 0.965; both are reported in Table 1.

## 16.3 Required Summary Table

**Table 1 (required format)**

| Parameter | Specification | Team Result | Units | Comments |
|---|---|---|---|---|
| Input image size | min 32 x 32, grayscale | 32 x 32 | pixels | single channel, fixed |
| Input precision | fixed-point unsigned | 8, unsigned Q8.0 | bits | matches 8-bit grayscale exactly (Section 7.1) |
| Kernel precision | 8-bit signed | 8, signed Q8.0 | bits | programmable via write port, 9 coefficients |
| Architecture type | N x N convolution, stride 1 | streaming line-buffer sliding window, 9 parallel MACs, zero-padded same convolution | - | 3 pipeline stages after the window |
| Multipliers / MACs | - | 9 | multipliers | fully parallel, LUT-based, 0 DSP |
| Pipeline stages | - | 3 | stages | products, row sums, output |
| Latency | - | 37 | cycles | 34 window fill + 3 pipeline |
| Throughput | output pixels per cycle | 1.0 peak / 0.965 sustained | px/cycle | gapless in-frame; sustained over 1061 cycles |
| FPGA utilization | LUTs, FFs, DSPs, BRAMs | 879 LUTs, 441 FFs, 0 DSP, 0 BRAM | - | 1.65 % of xc7z020 LUTs; 16 LUTs are SRL |
| Maximum frequency | - | 137.8 | MHz | WNS +0.742 ns at 125 MHz constraint |
| Power estimate | - | 0.158 total (0.107 static, 0.052 dynamic) | W | SAIF-annotated at 125 MHz, Medium confidence |
| Verification status | vs golden model | 22/22 runs pass, 0 mismatches | - | 7 kernels, 3 stall regimes, 2 ReLU builds, back-to-back frames; hw_out/ byte-identical to golden |
| FOM | Throughput / (Power x (LUTs + 50 DSP + 100 BRAM)) | **7.20e-3** | px/(cycle x W x LUT) | at 125 MHz; watts assumed |
