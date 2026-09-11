# Submission Checklist — SSCS Egypt 2026

**Deadline: Tue 15 Sep 2026. Submit Mon 14; treat Tue 15 as untouched buffer.**
Written Fri 11 Sep. Supersedes the weekly schedule in `SSCS2026_Gold_Plan.md`
(its Week 1–4 gates are past; the architecture decisions there and in
`ARCHITECTURE_LOCKED.md` still stand).

Ordered by dependency: correctness evidence unlocks the FPGA numbers, and the
numbers unlock the report. Do not reorder.

---

## 0. Blocking check — do this first

- [x] **FoM formula confirmed** against the PDF (11 Sep):
      `FOM = Throughput / (Power x (LUTs + 50*DSPs + 100*BRAMs))`,
      throughput in output pixels per cycle. No power unit is stated in the
      PDF - watts assumed, say so in the report.
- [x] **SAIF generated and applied.** 145-10800 ns, active convolution only.
      Power 0.181 -> 0.158 W, Medium confidence. FoM 7.20e-3. Method, interval
      and the two benign warnings are written up in `docs/POWER_METHODOLOGY.md`.
- [x] **FoM frequency: 125 MHz.** Organiser left it to the team. Reasons in
      `POWER_METHODOLOGY.md`. Fmax 137.8 MHz reported separately under timing.

Every FoM number in the report is untrustworthy until this is confirmed.

---

## 1. What must be submitted

One report + a package of supporting files + a short presentation.

| # | Deliverable | Status |
|---|---|---|
| 1 | Main report (13 required sections, see §2) | ~3 of 13 drafted in `Architecture_Report_Draft.docx` |
| 2 | Short presentation (slide deck) | NOT STARTED |
| 3 | RTL source files | DONE — 7 files in `rtl/` |
| 4 | Testbench | DONE — `tb_top_all.sv` regression (5 kernels x clean/stalls/random, 2 frames, ReLU), `tb_top.sv` per kernel, `tb_top_window.sv`, unit |
| 5 | Golden model | DONE — `golden_model/golden.py` |
| 6 | Input test images / feature maps | DONE — `hex/image.hex` + 5 vector patterns |
| 7 | Expected output files | DONE — 5x `hex/<kernel>_out.hex` |
| 8 | Hardware output files | DONE — `hw_out/<kernel>_out.hex` + `_relu_out.hex`, byte-identical to golden |
| 9 | FPGA reports (utilization, timing, power) | NOT RUN |

---

## 2. The 13 mandatory report sections

The announcement enumerates these; use as the table of contents.

| # | Section | Status |
|---|---|---|
| 1 | Accelerator architecture | drafted |
| 2 | Block diagram | drafted — **needs updating**, list in `docs/BLOCK_DIAGRAM_NOTES.md` |
| 3 | Datapath | TODO |
| 4 | FSM state diagram | TODO (diagram drawn, needs write-up) |
| 5 | Memory organization | drafted |
| 6 | Line-buffer / window-generation method | drafted |
| 7 | Fixed-point bit-width analysis | drafted |
| 8 | RTL implementation details | TODO |
| 9 | Testbench | TODO |
| 10 | Golden model | TODO |
| 11 | Waveform screenshots | PARTIAL — 8 in `docs/waveforms/`, need stall / edges / drain (see `WAVEFORM_CAPTURES.md`) |
| 12 | FPGA synth results + timing report + power report | TODO |
| 13 | Design tradeoffs discussion | TODO — source material in `docs/DESIGN_ITERATIONS.md` (profiling, the rejected in_cnt change, registered edge flags, saturation rework, why constant-coefficient multipliers were rejected) |

Plus: **Table 1** in the required format (every row, with units), and an
**assumptions** section (announcement instruction 4 explicitly allows assuming
missing information, provided it is stated).

---

## 3. Fri 11 Sep — Gate 2: prove correctness end-to-end

- [x] Coefficients through the real write port in IDLE — `tb_top.sv`, `tb_top_all.sv`
- [x] `pixel_out` diffed against golden for all 5 kernels — 0 mismatches
- [x] `hw_out/<kernel>_out.hex` written, identical to golden (deliverable #8)
- [x] Stall injection: fixed set + random ~20%, bubbles == STREAM stalls, `valid_out` == `win_valid` delayed 3 every cycle
- [x] Two back-to-back frames with a kernel swap while frame 1's tail is still draining — 2048 outputs clean
- [x] Latency 37 cycles (39 with 2 FILL stalls), 1024 outputs in 1024 cycles — `do sim/run.do sobel_x`
- [x] ReLU build (`top #(.RELU(1))`) diffed against `_relu_out.hex` on all 5 kernels
- [ ] Confirm the 5 kernel definitions in `golden.py` are the intended ones —
      `CLAUDE.md` flags them as assumptions. If any change: rerun
      `python golden.py hex/image.hex` then `do sim/run.do all`
- [x] Cleanup: `taps` debug port removed from `rtl/top.sv` and all TBs;
      `rtl/coeff_reg.sv` reset is synchronous and `write_addr` is range-guarded;
      `do sim/run.do all` still 16/16
- [ ] Close ModelSim, delete the old root `work/`, `transcript`, `*.vcd`,
      `vsim.wlf` (all gitignored now, the library lives in `sim/work`)
- [ ] Commit

## 4. Sat 12 Sep — one last pass through the flow, then freeze (revised 11 Sep evening)

The RTL is done. Tomorrow is one clean run of everything on the final RTL, the numbers
copied into the docs, a tag, and cleanup. Do not open the RTL unless the regression fails.

- [ ] `do sim/compile.do` then `do sim/run.do all` -> 22/22. Last sim before the freeze.
- [ ] Vivado GUI, in this order:
      1. One experiment, constraint only: add
         `set_property DRIVE 4 [get_ports {pixel_out[*] valid_out busy}]`
         to `fpga/pynq_z2.xdc`, re-implement, `read_saif` + `report_power`. Keep it if
         total power drops - 4 mA is plenty for a header pin and I/O is 27% of the power.
      2. Re-implement on the final XDC.
      3. `read_saif fpga/tb_top.saif -strip_path tb_top/dut`, then utilization,
         utilization -hierarchical, timing_summary, power, drc into `fpga/reports/`.
      4. `source fpga/paths.tcl` and keep the printout - per-stage slack for the report.
- [ ] Check: DSP 0, BRAM 0, LUT-as-SRL 16, WNS >= 0, power confidence Medium.
- [ ] Copy the final numbers into `fpga/reports/RESULTS.md`, `docs/POWER_METHODOLOGY.md`
      and Table 1 below. Commit.
- [ ] `git tag v1.0-submission`
- [ ] Cleanup: close ModelSim and Vivado, delete root `work/`, `transcript`, `*.vcd`,
      `vsim.wlf`, `conv.cr.mti`, `xsim.dir/`, `.Xil/`, `*.jou`, `*.log` (all gitignored).
      `git status` must be clean.
- [ ] Block diagram + FSM diagram updated per `docs/BLOCK_DIAGRAM_NOTES.md`.
- [ ] Waveforms: anything still missing from `docs/WAVEFORM_CAPTURES.md`; retake
      throughput zoomed to ~30 cycles.
- [ ] Render `hw_out/sobel_x_out.hex` next to the input image as PNGs - the edge-detection
      bonus, in simulation.
- [ ] **Only if PYNQ-Z2 is not a hard requirement:** one extra implementation on
      `xc7a35tcpg236-1` (Basys 3), clock constraint only, for the tradeoffs section.
      Static power is 68% of the FoM power term and is set by the die, not the RTL; a
      35T is roughly 0.07 W static against 0.107 W here. Report both if done, submit the
      one that is defensible. Unconstrained I/O defaults to a different IOSTANDARD, so
      compare logic + static, not the I/O line.

## 5. Sun 13 Sep — write the report

- [ ] Sections 3, 4, 8, 9, 10, 13 (datapath, FSM, RTL details, testbench,
      golden model, tradeoffs)
- [ ] Insert waveform screenshots (§11) and the three FPGA reports (§12)
- [ ] Fill Table 1 completely — every row, with units
- [ ] Assumptions section: frame-gap handling (no `ready` signal), `busy`
      falling 3 cycles before the last `valid_out`, kernel choices, power
      methodology, image size frozen at 32x32
- [ ] State bonus claims explicitly: 1 px/cycle pipelined, multiple kernels
      (5 verified, reloadable between frames), ReLU, edge-detection demo
- [ ] Draft the slide deck (deliverable #2)

## 6. Mon 14 Sep — package and submit

- [ ] Proofread; confirm no `TODO` and no placeholder numbers survive
- [ ] Package: `rtl/`, `tb/`, `golden_model/`, `vectors/`, `hw_out/`, FPGA
      reports, report, slides
- [ ] Submit

---

## 7. Table 1 rows fillable before synthesis

| Parameter | Value |
|---|---|
| Input image size | 32 x 32, grayscale single channel |
| Input precision | 8-bit unsigned (Q8.0) |
| Kernel precision | 8-bit signed integer (Q8.0), programmable |
| Architecture type | Streaming line-buffer window + 9 parallel LUT MACs, zero-padded same-conv, stride 1 |
| Multipliers / MACs | 9 (fully parallel, LUT-based, 0 DSP) |
| Pipeline stages | Window (2x32 line buffers + 3x3 taps) + 3 register stages (products, row sums, output) |
| Latency | 37 cycles (34 fill + 3 pipeline) |
| Throughput | 1.0 px/cycle peak; ~0.965 sustained per frame |
| Verification status | 22/22 regression runs pass: 7 kernels x 1024 px bit-exact vs Python golden (5 real + satmax/satmin covering both saturation branches), fixed + random stalls, 2 frames back to back, ReLU build |
| FPGA utilization | **879 LUTs** (16 as SRL), **441 FFs**, 0 DSP, 0 BRAM — xc7z020clg400-1 |
| Maximum frequency | **137.8 MHz** (WNS +0.742 ns at 125 MHz, timing met) — true Fmax needs a tighter constraint |
| Power estimate | **0.158 W** total (0.052 dynamic, 0.107 static) at 125 MHz — SAIF-annotated, Medium confidence |
| FOM | **7.20e-3** = 1.0 / (0.158 x 879) — formula confirmed against the PDF, watts assumed |

Remaining rows (FPGA utilization, max frequency, power estimate, FOM) come
from §4.

---

## 8. Known design notes to carry into the report

- `busy` falls at DONE, 3 cycles before the final `valid_out`. Safe for the
  coefficient write-lock (the last window is already latched in `prod_r`), but
  any consumer must key off `valid_out`, not `busy`, for end-of-frame.
- Pixels presented during DRAIN are shifted through but not counted; the
  bottom/right edge masks zero them out of every remaining window.
- Saturation is applied at the 20-bit -> 16-bit narrowing stage
  (`OUT_MAX` / `OUT_MIN` clamp, not wrap) — announcement item 6 requires this
  to be explained.
