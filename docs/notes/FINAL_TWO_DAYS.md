# Sunday 13 and Monday 14 - the last two days

Deadline Tuesday 15. Submit Monday. Tuesday stays untouched.

The RTL is frozen: 879 LUTs, 441 FFs, 0 DSP, 0 BRAM, WNS +0.742 ns at 125 MHz, 0.158 W
SAIF-annotated, FoM 7.20e-3, regression 22/22. PYNQ-Z2 (xc7z020clg400-1) is a hard
requirement - no other device gets tried. Today the report is the critical path, not the
design. Do not open the RTL unless the regression fails.

Split: Amir runs the tools and draws; Claude drafts text. Both at once.

---

## Sunday 13

### Morning - one clean pass through the flow (~2 h)

> Status Sunday evening: steps 1, 2 and 4 done - regression 22/22, project-flow
> implementation reproduced the Friday numbers exactly (879 / 441 / 0 / 0, WNS +0.742,
> 0.158 W, FoM 7.20e-3), docs updated. Step 3 (DRIVE 4) skipped by decision - no
> experiments on the submission build. Next: tag, cleanup, then the report.

**1. Regression** (5 min). ModelSim, project root:

    do sim/compile.do
    do sim/run.do all          -> 22 runs, 0 failed

If it fails, stop and say so. It has not changed since it last passed.

**2. Vivado.** The GUI crashed since Friday (hs_err dump), so the routed design is gone.
Reopen it and run the in-memory flow in the Tcl console:

    cd C:/Users/HP/Desktop/conv3x3-edge-accelerator
    read_verilog -sv {rtl/cnn_pkg.sv rtl/line_buffer.sv rtl/window_gen.sv rtl/control_unit.sv rtl/coeff_reg.sv rtl/multiplier.sv rtl/top.sv}
    read_xdc fpga/pynq_z2.xdc
    synth_design -top top -part xc7z020clg400-1 -max_dsp 0
    opt_design
    place_design
    route_design
    read_saif fpga/tb_top.saif -strip_path tb_top/dut
    report_utilization -file fpga/reports/utilization.rpt
    report_utilization -hierarchical -file fpga/reports/utilization_hier.rpt
    report_timing_summary -file fpga/reports/timing_summary.rpt
    report_power -file fpga/reports/power.rpt
    report_drc -file fpga/reports/drc.rpt
    source fpga/paths.tcl
    write_checkpoint -force fpga/reports/routed.dcp

Expect 879 LUTs, 0 DSP, 0 BRAM, WNS about +0.74, power about 0.158 W. Paste the summary
lines and the paths.tcl printout to Claude. The two read_saif warnings are benign, see
POWER_METHODOLOGY.md.

**3. One experiment, 20 minutes, then stop.** Append to fpga/pynq_z2.xdc:

    set_property DRIVE 4 [get_ports {pixel_out[*] valid_out busy}]

Re-run from read_xdc down. If total power drops, keep the line. If not, delete it. Either
way the number goes in the tradeoffs section as a measured result. I/O is 27% of the
power, this is the one cheap lever left.

**4. Numbers into the docs.** Send the final numbers; Claude updates RESULTS.md,
POWER_METHODOLOGY.md, DESIGN_ITERATIONS.md and Table 1 in the checklist, and commits.

**5. Tag.**

    git tag v1.0-submission

**6. Cleanup.** Close ModelSim and Vivado first, then delete: root work/, transcript,
*.vcd, vsim.wlf, conv.cr.mti, xsim.dir/, .Xil/, *.jou, *.log, hs_err_pid*.dmp. All are
gitignored. `git status` must come back empty.

### Morning, in parallel - Claude drafts the report

The six missing sections - datapath, FSM, RTL implementation details, testbench, golden
model, tradeoffs - plus the power methodology block and the assumptions section. Written
as markdown to paste into the docx, figure and table placeholders named after the files in
docs/figures/waveforms/. Sources: DESIGN_ITERATIONS.md, POWER_METHODOLOGY.md, RESULTS.md,
ARCHITECTURE_LOCKED.md, the RTL itself.

### Afternoon - diagrams and review (~3 h)

- Block diagram and FSM diagram, per docs/report/BLOCK_DIAGRAM_NOTES.md. Three corrections, six
  annotations, one new 5-box block figure. About an hour.
- Review the drafted sections. Every number in them comes from RESULTS.md; if a number
  changed this morning, say which and Claude fixes the text.
- Edge-detection PNGs: Claude writes a small script that renders hw_out/sobel_x_out.hex
  beside the input image; run it once. That is the edge-detection bonus, in simulation.
- Optional, 15 min, last thing: retake the seven tb_top waveforms with the sim/waves/*.do
  scripts so every figure is from the tagged RTL. Not needed for correctness - see below -
  but it removes a reviewer question.

### Evening - assemble (~2 h)

Sections into the docx in the order the announcement lists them. Figures in. Table 1
filled from RESULTS.md. Commit. Report complete tonight, rough is fine.

---

## Monday 14

**1. Slides** (1 h). Claude drafts about ten: problem, architecture, datapath, FSM,
verification, results, FoM, tradeoffs, bonuses, conclusion. Review, fix, done.

**2. Proofread the report against this list** (1 h):

- all 13 sections from the announcement present, in its order
- Table 1: every row, with units
- no TODO, no placeholder number, every number matches RESULTS.md
- assumptions section present (the announcement says to state them)
- bonus claims stated in so many words: 1 px/cycle pipelined, 5 kernels programmable,
  ReLU, edge detection in simulation
- the five power-reporting items the organiser asked for (device+board, frequency,
  static/dynamic/total, SAIF interval, tools)
- timing section says I/O paths are excluded and why
- FoM section says watts are assumed for the power unit

**3. Package** (30 min). From the tag, no junk:

    git archive --format=zip -o conv3x3_submission.zip v1.0-submission

Put the report PDF and the slides next to it. That zip already holds rtl/, tb/, sim/,
golden_model/ (model, input image, expected outputs, coefficient files), hw_out/ (the
hardware outputs), fpga/ (xdc, scripts, reports), docs/ (notes, waveforms), README.md.

**4. Submit Monday.**

---

## Do the waveforms need retaking?

No, not for correctness. They were captured Friday 09:22-09:30 and three RTL commits
landed after them:

| commit | change | visible in any waveform? |
|---|---|---|
| 8860e7a | coeff_reg write_addr guard | no - addresses 0..8 only, same as before |
| 5060a8b | edge flags registered | no - same values on the same cycles, proven by tb_top_window (0 position/edge errors) |
| aad79fc | saturate via top bits | no - same outputs for every acc value, proven exhaustively |

Latency is still 37, bubbles still land 3 cycles late, the FSM sequence is unchanged, the
regression is 22/22 on the frozen RTL. The pictures would come out pixel-identical.

If there is spare time at the end of Sunday, retaking the seven tb_top captures with the
sim/waves/*.do scripts takes about 15 minutes and lets the report say every waveform is
from v1.0-submission. edges.PNG is the one whose signal source actually changed, so if
only one gets retaken, that one. The three window_gen unit captures are untouched by any
of this.

## Will the current XDC run on a real PYNQ-Z2?

The bitstream would load and the logic would run. Every one of the 42 pins is the board's
real package pin from the official constraints, all on 3.3 V banks with LVCMOS33, and
H16 is the 125 MHz clock from the Ethernet PHY, which runs from power-up without the PS
being configured. A PL-only bitstream loads over JTAG. write_bitstream is one command.

What it does not give is a demo, because nothing on the board drives the 42 pins:

- input_in / valid_in / the write port are header pins with no source behind them. A real
  source would be the PS (ARM) through an AXI block design, or a UART bridge - either is
  a separate wrapper project, not a constraint change.
- rst_n comes straight from SW0 into a synchronous reset with no synchroniser. Fine for
  implementation numbers (set_false_path); on hardware you would put two flops on it in
  the wrapper.
- set_false_path on all inputs and outputs means there is no timing contract at the pins.
  Correct for a core with no external interface, but a wrapper would constrain its own
  I/O.

So: implementation-ready, demo needs a wrapper. Board demo is an optional bonus and is
not on the plan for these two days. Say exactly this in the report - it is honest and it
answers the question before a judge asks it.
