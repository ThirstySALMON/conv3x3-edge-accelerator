# Presentation outline

Eleven slides. Bullets are what to say, not what to print verbatim.

Same verified corrections as docs/report/REPORT_OUTLINE.md apply here: STREAM is 990 cycles not
1024, the line buffers are 16 SRLC32E, throughput.PNG is a whole-frame capture.

---

## Short presentation - 11-slide outline

**Required by:** "Also to submit: ... a short presentation." Every number below is from the fact sheet; the slides are a compressed version of the report, in the report's order.

---

### Slide 1 - Title + one-line pitch
**Say:**
- Title: 3x3 programmable convolution accelerator, 32x32 grayscale, PYNQ-Z2 (xc7z020clg400-1).
- Pitch: one output pixel per clock, 0 DSP, 0 BRAM, 879 LUTs, 0.158 W at 125 MHz -> FoM 7.20e-3.
- Team / author name, IEEE SSCS Egypt 2026.
- Status line: 22/22 regression runs pass, timing met (WNS +0.742 ns), bitstream generated.
**Show:**
- Figure: docs/figures/edge_demo_sobel_x.png - input cat on the left, RTL hardware output on the right; the whole story in one image.

---

### Slide 2 - The problem and the spec
**Say:**
- Task: NxN convolution, stride 1, on a >= 32x32 single-channel image; judged on correctness, design quality, resources, latency, throughput, timing closure, power, and FoM = throughput / (Power x (LUTs + 50xDSPs + 100xBRAMs)).
- Chosen point: 3x3 same (zero-padded) convolution over 32x32 -> exactly 1024 outputs per frame.
- Precision: 8-bit unsigned pixels (Q8.0) - matches 8-bit grayscale sensors exactly, no scaling logic, narrowest lossless width (REQUIRED justification); 8-bit signed integer coefficients (Q8.0, COEF_FRAC toggle for Q1.7); 16-bit signed saturating output.
- Coefficients fully programmable through a 9-entry write port (write_addr = 3*row+col), so any 8-bit signed kernel works, not just the 5 shipped ones.
- Key assumptions stated up front: 32x32 fixed, raster input one pixel per cycle with stalls allowed, no ready signal (source holds the next frame until busy falls), FoM power in watts, FoM at 125 MHz.
**Show:**
- Table: Spec vs result (condensed Table 1) - columns Parameter | Spec | Result - rows: image 32x32, input 8u, kernel 8s, output 16s sat, stride 1, throughput 1.0 px/cycle, latency 37 cycles - source fpga/reports/RESULTS.md.

---

### Slide 3 - Architecture (block diagram)
**Say:**
- Five blocks: control_fsm, window_gen (+ two line buffers), coeff_reg, 9-multiplier MAC datapath, saturate/ReLU.
- Architectural claim: strict control/datapath split - window_gen holds no position state, control_fsm holds no data; control owns in_cnt, out_r/out_c, drain_cnt and the four edge flags.
- Interface is 42 pins: clk, rst_n (sync, active low), input_in[7:0] + valid_in, kernel write port (write_en, write_addr[3:0], data_write[7:0]), pixel_out[15:0] + valid_out, busy.
- Streaming, no handshake back-pressure: source streams exactly 1024 pixels, waits for busy to fall; stalls on valid_in are allowed anywhere.
- Latency 37 cycles = 34 window fill + 3 pipeline stages; 1024 outputs in 1061 cycles per frame (0.965 sustained), 1.0 peak.
**Show:**
- Diagram to draw: 5-box block diagram with en / edge flags[4] / coef[9] / win_valid / busy arrows - see docs/report/BLOCK_DIAGRAM_NOTES.md (the ASCII sketch in the "Block diagram" section).

---

### Slide 4 - Window generation and memory (0 BRAM)
**Say:**
- Two 32-deep 8-bit line buffers in series (LB0 from input, LB1 from LB0) feed 9 tap registers a..i row-major: tap[0..2] from LB1, tap[3..5] from LB0, tap[6..8] from input_in.
- Vivado inferred both line buffers as SRL32E shift registers: 16 LUTs, 0 FFs, 0 BRAM - this is where the FoM denominator is won (100 x BRAM term stays 0).
- Total on-chip storage: 2 x 32 x 8 bits of delay line + 72 bits of taps + 72 bits of coefficients; no memory block anywhere.
- Zero padding is combinational masking driven by registered edge flags: top -> taps 0,1,2; bottom -> 6,7,8; left -> 0,3,6; right -> 2,5,8; corners masked by both; tap[4] (centre) never zeroed.
- Fill = 34 cycles (32 line depth + 2 tap shifts) and drain = 34 cycles; consume-only cycles must equal output-only cycles so both totals are 1024.
**Show:**
- Figure: docs/figures/waveforms/Window_generator_producing_valid_taps.PNG - unit test, 3x3 window sliding across the taps, first valid windows.
- Figure: docs/figures/waveforms/edges.PNG - output col 31 then col 0: right_edge masks c,f,i then left_edge masks a,d,g, centre untouched.

---

### Slide 5 - Datapath and pipeline (0 DSP)
**Say:**
- 9 LUT multipliers 8u x 8s (use_dsp="no" + -max_dsp 0), 52-59 LUTs each, 496 total -> stage 1 register prod_r (9 x 16b) -> three 3-input row adders -> stage 2 register row_r (3 x 18b) -> one 3-input 20-bit adder -> saturate 20b->16b -> ReLU mux -> stage 3 register pixel_out.
- Bit widths derived, not guessed: product -32640..+32385 (16b), row sum -97920..+97155 (18b), accumulator -293760..+291465 (20b lossless; 19 bits are insufficient), output clamped to [-32768, +32767] (REQUIRED overflow/saturation explanation).
- Saturation is a sign-extension check: acc fits in 16b iff acc[19:15] are all equal, else clamp by sign bit - proven equivalent to two magnitude compares over all 2^20 values in Python, exercised in RTL by satmax/satmin kernels.
- Real kernels never saturate (widest: sobel_y, -898..+934); widths are set by the programmability requirement (any 8-bit signed coefficients).
- A valid bit travels with the data (win_valid -> v_prod -> v_row -> valid_out), registers free-running: a stall becomes a bubble three cycles later, never corruption. ReLU is a build-time parameter (default off).
**Show:**
- Diagram to draw: detailed datapath with the three dashed stage boundaries, valid chain level with the registers, "sat (top-bits check)", RELU toggle, LB0/LB1 SRL annotation, latency 37 - see docs/report/BLOCK_DIAGRAM_NOTES.md.
- Figure: docs/figures/waveforms/throughput.PNG - mid frame, valid_out solid high, pixel_out changes every cycle.

---

### Slide 6 - Control FSM and stall handling
**Say:**
- Five states: IDLE -> FILL (34 consume-only cycles) -> STREAM (1024 cycles, consume + output) -> DRAIN (34 output-only cycles, en forced high, input ignored) -> DONE (1 cycle, frame_done) -> IDLE.
- en = valid_in except DRAIN (1) and DONE (0); counters in_cnt (10b), out_r/out_c (5b each), drain_cnt (6b).
- Edge flags top/bottom/left/right are registered, computed one position ahead (nxt_r/nxt_c) - this took the comparator out of the multiplier path (slide 10).
- busy = not IDLE and not DONE; it falls 3 cycles before the final valid_out because the last window is already latched in the pipeline; kernel writes are ignored while busy.
- Stall example: valid_in dropped 3 cycles before pixel 300 -> en follows, taps hold, one 3-cycle bubble appears in valid_out exactly 3 cycles later; in every regression run bubbles equal STREAM stalls and lat_err = 0.
**Show:**
- Diagram to draw: FSM state diagram with per-state outputs (en, win_valid, edge flags registered, busy, frame_done) - see docs/report/BLOCK_DIAGRAM_NOTES.md.
- Figure: docs/figures/waveforms/stall.PNG - the 3-cycle stall before pixel 300 and its bubble.
- Figure: docs/figures/waveforms/drain.PNG (optional, if space) - DRAIN, 34 more outputs, frame_done, busy falling 3 cycles early.

---

### Slide 7 - Verification: regression matrix, hardware vs golden
**Say:**
- Golden model golden_model/golden.py (numpy): zero-padded same conv, integer accumulate, clamp to 16-bit signed, optional ReLU; input cat.png resized to 32x32 grayscale -> hex/image.hex; emits per-kernel coef/out/relu_out hex plus PNGs.
- 7 kernels: identity, sobel_x, sobel_y, sharpen, laplacian, plus satmax (all +127) and satmin (all -128) added specifically to exercise both clamp branches.
- Regression tb_top_all.sv: 22 runs, all pass = 7 kernels x {clean, fixed stalls, random stalls} + one back-to-back run (sobel_x then sharpen, kernel swapped while frame 1 drains, 2048 outputs); two DUTs per stimulus, RELU=0 and RELU=1, each diffed against its own golden.
- Stall coverage: fixed stalls at pixels 10, 300, 511, 700, 1023 (18 cycles, 16 in STREAM, 16 bubbles observed); random ~1 in 5 pixels held 1-4 cycles, ~500 stall cycles per run; every cycle checks valid_out == win_valid delayed by exactly 3.
- Hardware outputs: hw_out/ holds 14 files (7 kernels x normal/relu), 1024 lines each, all byte-identical to golden_model/hex/; plus tb_top_window.sv (1024 windows vs golden vectors, fill latency 34) and tb_window_gen_unit.sv (shift, stall freeze, edges, corners).
**Show:**
- Table: Regression matrix - columns Kernel | Clean | Fixed stalls | Random stalls | RELU=0 | RELU=1 - 7 rows all "pass" + the back-to-back row - source tb/tb_top_all.sv log.
- Figure: docs/figures/edge_demo_sobel_y.png or docs/figures/edge_demo_laplacian.png - RTL output rendered from hw_out/, identical to golden PNG.

---

### Slide 8 - Implementation results: utilization, timing, critical path
**Say:**
- Device xc7z020clg400-1 (PYNQ-Z2, Zynq-7000, speed -1), Vivado 2025.2, constraint 125 MHz (8.000 ns, the board's Ethernet-PHY clock on H16).
- Routed: 879 slice LUTs (863 logic + 16 shift register), 441 FFs, 0 DSP, 0 BRAM, 42 IOB, 1 BUFG; reproduced identically by two flows two days apart.
- Where the LUTs sit (indicative, Vivado merges across hierarchy): 9 multipliers 496, control_fsm 80, coeff_reg 120, window_gen 132 (116 + 16 SRL), adder tree/saturate/ReLU 90.
- Timing: WNS +0.742 ns, WHS +0.153 ns, 0 failing endpoints of 602 -> Fmax = 1000/(8.000-0.742) = 137.8 MHz (core register-to-register; I/O paths false-pathed because nothing external clocks the pins - the 3.3 V OBUF alone is 3.557 ns).
- Critical path: u_cu/bottom_edge_reg -> tap zero mux -> multiplier -> prod_r[8][13], 7 logic levels, 7.297 ns, 59% routing, bottom_edge fanout 156 (1.517 ns on that net). Per-stage slack: stage 1 +0.742, stage 2 +3.799, stage 3 +2.666 - the multipliers bind.
**Show:**
- Table: Utilization + timing - columns Resource | Used | and Metric | Value - source fpga/reports/utilization.rpt, fpga/reports/timing_summary.rpt, fpga/reports/paths.rpt.
- Figure: docs/figures/waveforms/latency.PNG - first valid_in at 145 ns to first valid_out at 515 ns = 370 ns = 37 cycles.

---

### Slide 9 - Power and FoM
**Say:**
- Organiser's five items: (1) device/board xc7z020clg400-1 on PYNQ-Z2; (2) FoM frequency 125 MHz; (3) power static 0.107 W + dynamic 0.052 W = total 0.158 W; (4) SAIF interval 145 ns to 10800 ns = 10.655 us = 1332 cycles at the 10 ns TB clock, first pixel in to last pixel out, reset and coefficient load excluded, no idle; (5) tools Vivado 2025.2 synth/impl/report_power, xsim for the SAIF, ModelSim ASE 2020.1 for the regression.
- Dynamic breakdown: I/O 0.042, clocks 0.004, slice logic 0.003, signals 0.003 - static is 68% of total, I/O pads 27%, the design's own logic about 6%. Confidence: Medium.
- SAIF annotated 414 of 2229 nets (19%) - a naming ceiling: the unmatched nets are synthesis-invented internals; the I/O, taps, products, accumulator and pipeline registers are all matched.
- FoM = 1.0 / (0.158 x (879 + 50x0 + 100x0)) = 1.0 / 138.9 = 7.20e-3 at 125 MHz (the constrained, verified clock the SAIF came from; power scales with clock while throughput is per cycle, so a higher clock only lowers the FoM).
- Vectorless estimate had been 0.181 W / FoM 6.285e-3; measuring properly gained 14.6% with no RTL change.
**Show:**
- Table: Power - columns Component | W - rows static 0.107, I/O 0.042, clocks 0.004, logic 0.003, signals 0.003, total 0.158 - source fpga/reports/power.rpt.
- The FoM line, large, as its own text box: 1.0 / (0.158 x 879) = 7.20e-3.

---

### Slide 10 - Design iterations and tradeoffs (including the one that failed)
**Say:**
- Baseline: 882 LUTs, WNS +0.332 ns, vectorless 0.181 W.
- Failed: removing in_cnt as "redundant" - consume runs during FILL, so inputs lead outputs by 34 and the last consume lands at output (30,29), not a corner; the modified FSM ran 1059/1058 instead of 1024/1024 - reverted, in_cnt stays.
- Registered edge flags: comparator left the multiplier path; WNS +0.332 -> +0.742 ns, Fmax 130.4 -> 137.8 MHz, LUTs 882 -> 879, cost 4 FFs.
- Saturation as a top-bits check instead of two 20-bit compares (~2 LUTs cheaper, proven over 2^20 values) - bought no timing (stage 3 had 1.9 ns spare) but exposed that the clamp had never been exercised -> satmax/satmin kernels, regression 16 -> 22 runs.
- Rejected on principle: constant-coefficient multipliers would cut ~300 LUTs (all real kernels are 0, +-1, +-2, +-4, 5) but forfeit mandatory programmability. SAIF power over vectorless: FoM +14.6%, the largest single gain in the project.
**Show:**
- Table: Iterations - columns Change | LUTs | WNS | Fmax | Power | FoM | Outcome - rows baseline, in_cnt removal (reverted), registered flags, top-bits sat, SAIF power - source docs/notes/DESIGN_ITERATIONS.md.

---

### Slide 11 - Bonuses claimed, what was not done, conclusion
**Say:**
- Bonuses claimed: one-output-pixel-per-cycle pipelined architecture (throughput waveform + TB), multiple kernels (programmable, 5 real kernels verified, reloadable between frames via the back-to-back run), ReLU (parameter, verified on all 7 kernels), edge-detection demo in simulation from hardware outputs.
- Not claimed: board demonstration - bitstream fpga/top.bit is generated for the real PYNQ-Z2 pinout, but a demo needs a wrapper (pixel source via PS or UART, reset synchroniser).
- Identified but not done: replicating the edge-flag registers to cut the fanout-156 net (est. 0.5-1 ns), I/O DRIVE 4 on outputs (est. ~10% power); timing already closes and Fmax is not in the FoM.
- Known caveat: DRC warning ZPS7-1 "PS7 block required", expected for PL-only Zynq, no effect on any number.
- Conclusion: every mandatory spec met and verified 22/22 against the golden model; 879 LUTs / 0 DSP / 0 BRAM, 137.8 MHz Fmax, 0.158 W measured, FoM 7.20e-3 at 125 MHz.
**Show:**
- Figure: docs/figures/waveforms/fsm.PNG - the whole frame IDLE-FILL-STREAM-DRAIN-DONE with in_cnt/drain_cnt, as the closing picture.
- Figure: docs/figures/waveforms/kernel_load.PNG (small inset) - 9 write_en pulses, write_addr 0..8, busy low: the programmable-kernel bonus in one shot.

**Avoid (all slides):**
- Do not say High confidence on power (it is Medium); do not fold Fmax into the FoM (FoM is at 125 MHz); do not claim a board demo; do not present the per-block LUT split as exact; do not quote the 910 post-synthesis LUTs as the result (879 post-route is the number); do not say I/O timing was met (it was excluded by set_false_path, with the reason).

**Sources:** fpga/reports/RESULTS.md, fpga/reports/utilization.rpt, fpga/reports/timing_summary.rpt, fpga/reports/paths.rpt, fpga/reports/power.rpt, docs/notes/DESIGN_ITERATIONS.md, docs/notes/POWER_METHODOLOGY.md, docs/report/BLOCK_DIAGRAM_NOTES.md, docs/notes/WAVEFORM_CAPTURES.md, tb/tb_top_all.sv, golden_model/golden.py.
