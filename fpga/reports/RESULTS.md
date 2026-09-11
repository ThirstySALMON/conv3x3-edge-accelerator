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
