# Implementation results

xc7z020clg400-1 (PYNQ-Z2), Vivado 2025.2, 125 MHz target, routed.
Regenerate: `vivado -mode batch -source fpga/build.tcl` from the project root.

| | value | |
|---|---|---|
| LUTs | **882** | 1.66% of 53200. 16 of them are shift registers (the line buffers) |
| FFs | 437 | 0.41% of 106400 |
| DSPs | **0** | `use_dsp="no"` + `-max_dsp 0`, all 9 multipliers in LUTs |
| BRAM | **0** | line buffers are fabric, never block RAM |
| WNS | **+0.332 ns** | at 8.000 ns. 0 failing endpoints, constraints met |
| WHS | +0.152 ns | 0 failing endpoints |
| Fmax | **130.4 MHz** | 1000 / (8.000 - 0.332) |
| Power | **0.181 W** | dynamic 0.074, static 0.107 |
| Throughput | 1.0 px/cycle | 0.965 sustained per frame (1024 outputs / 1061 cycles) |
| Latency | 37 cycles | 34 window fill + 3 datapath |

FoM = 1.0 / (0.181 x 882) = **6.27e-3**, denominator = 882 + 50x0 + 100x0.
Formula and power units still need checking against the competition pdf.

## Line buffers came out as SRLs

Vivado inferred SRL32E for both line buffers even with the synchronous reset, because
nothing reads the intermediate elements - only `sr[DEPTH-1]`. 16 LUTs instead of 512 FFs.
That is the better outcome for the FoM: LUT-as-shift-register should be 16, not 0.
(An earlier note in the docs said to keep it at 0 - that was wrong and is now corrected.)

## Timing: io paths are excluded

With a nominal 1 ns io budget all 84 setup failures were io paths, WNS -5.166 ns. The
worst was 2 logic levels - one LUT2 and an OBUF - where the 3v3 output pad alone is
3.557 ns and the clock path (IBUF + BUFG, H16 is not a clock-capable pin) is 5.936 ns.
Nothing external clocks these pins, so `pynq_z2.xdc` false-paths io and reports the core
register-to-register Fmax instead. State this in the timing section of the report.

## Critical path

    u_cu/out_c_reg[4] -> right_edge -> tap zero mux -> multiplier -> prod_r[8][13]
    8 levels (4x CARRY4, 2x LUT6, LUT5, LUT4), 7.633 ns, 62% of it routing

Not the multiplier alone: the column counter feeds the edge comparator, which feeds the
tap masking, which feeds the multiply, all in one cycle. Registering the edge flags one
cycle ahead in control_fsm would cut roughly 2 ns, but Fmax is not in the FoM and timing
already closes, so it was left alone. Worth a line in the tradeoffs section.

## Power confidence

The 0.181 W above is vectorless (Vivado assumes 12.5% toggle). Note io is 0.059 W of the
0.074 W dynamic - 80% of dynamic power is pad switching, an artifact of exposing 42 pins
on a core that would normally sit inside a larger design. `fpga/saif.bat` reruns tb_top in
xsim and writes real switching activity; build.tcl picks it up and report_power then says
High confidence.

## Where the LUTs went (from utilization_hier.rpt, baseline build)

| block | LUTs | % | note |
|---|---|---|---|
| 9 x mult8x8 | 485 | 54% | irreducible while coefficients stay programmable |
| control_fsm | 165 | 19% | too big for 5 states + 3 counters, see below |
| coeff_reg | 96 | 11% | write-address decoder, 9x8 storage is only 72 FFs |
| window_gen | 96 | 11% | 80 logic + 16 SRL (the two line buffers) |
| top glue | 89 | 10% | adder tree, saturate, relu mux |
| total | 890 | | 882 in the flat report, the hierarchy double-counts boundary LUTs |

### control_fsm: in_cnt is NOT removable (tried it, it breaks)

It looks like `in_cnt` (10 bits, only used for `last_consume = consume && in_cnt ==
NPIX-1`) duplicates out_r/out_c, and that the STREAM exit could reuse bottom_edge &&
right_edge instead. It cannot. `consume` is asserted during FILL as well as STREAM, so
the input count leads the output position by exactly FILL_CYCLES: at the last consumed
pixel the output position is (30, 29), not a corner. Making that substitution runs the
frame to 1059 consumed / 1058 out instead of 1024 / 1024.

Expressing it as `out_r == 30 && out_c == 29` would work but trades one 10-bit compare
for two 5-bit compares and silently breaks if FILL_CYCLES ever changes. Not worth it.

So the 165 LUTs are not a redundant counter. They are the four edge comparators plus the
en / consume / out_adv fanout, and a one-hot state register that Vivado replicated
(`FSM_onehot_state_reg[0]_replica` appears in the critical path). The comparators are
real work: each drives 24 tap zero-muxes in window_gen.

### coeff_reg at 96 LUTs

9 registers of 8 bits is 72 FFs and should be almost no LUTs. The 96 are the 4-bit
write-address decoder fanning out to 9 byte-wide enables. Could be narrowed (3-bit addr,
or a shift-in chain instead of addressed writes) but the write port shape is part of the
documented interface, so it was left alone.

## Change: edge flags registered (needs re-measuring in the GUI)

Vivado's own critical path was

    out_c_reg[4] -> right_edge -> tap zero mux -> multiplier -> prod_r[8][13]
    8 levels, 7.633 ns, 62% routing

ie. the column counter, the edge comparator, the tap masking and the multiply all in one
cycle. The four edge flags are now registered in control_fsm, computed from the *next*
output position (nxt_r / nxt_c) so they are valid on the cycle they are used. That takes
the comparator and its fanout out of the multiplier path for free - 4 FFs, no extra LUTs,
no change to latency or to the interface.

Verified: `do sim/run.do all` 16/16, and tb_top_window reports 0 position/edge errors
against the golden raster positions for all 1024 windows.

NOT YET RE-SYNTHESISED - batch vivado does not run on this machine (signature error), so
re-run implementation in the GUI and update the table below. Expect WNS to improve by
roughly 1.5-2 ns; LUT count should be about the same, the logic moved rather than shrank.

| | baseline | with registered edge flags |
|---|---|---|
| LUTs | 882 | ? |
| FFs | 437 | ~441 |
| WNS at 8 ns | +0.332 ns | ? |
| Fmax | 130.4 MHz | ? |
| power | 0.181 W | ? |
| FoM | 6.27e-3 | ? |

If WNS improves a lot, the 125 MHz constraint is no longer the limit - re-run with a
tighter create_clock to find the real Fmax for the report.
