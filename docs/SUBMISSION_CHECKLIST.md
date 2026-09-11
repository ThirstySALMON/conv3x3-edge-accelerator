# Submission Checklist — SSCS Egypt 2026

**Deadline: Tue 15 Sep 2026. Submit Mon 14; treat Tue 15 as untouched buffer.**
Written Fri 11 Sep. Supersedes the weekly schedule in `SSCS2026_Gold_Plan.md`
(its Week 1–4 gates are past; the architecture decisions there and in
`ARCHITECTURE_LOCKED.md` still stand).

Ordered by dependency: correctness evidence unlocks the FPGA numbers, and the
numbers unlock the report. Do not reorder.

---

## 0. Blocking check — do this first

- [ ] **Recover the FoM formula from the original PDF.** The Markdown
      conversion of the announcement dropped it: line 40 reads "report the
      following Figure of Merit:" followed by nothing. Confirm the formula AND
      the power units (mW vs W shifts the result by 1000x). Our docs assume:
      `FOM = Throughput / (Power x (LUTs + 50*DSPs + 100*BRAMs))`,
      throughput in output pixels per cycle.

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
| 2 | Block diagram | drafted |
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
| 13 | Design tradeoffs discussion | TODO |

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
- [ ] Cleanup: delete the `taps` debug port from `rtl/top.sv` (and the four
      TB connections); make `rtl/coeff_reg.sv` reset synchronous like every
      other module; rerun `do sim/run.do all`
- [ ] Close ModelSim, delete the old root `work/`, `transcript`, `*.vcd`,
      `vsim.wlf` (all gitignored now, the library lives in `sim/work`)
- [ ] Commit

## 4. Sat 12 Sep — Vivado + freeze

- [ ] Project: `rtl/*.sv` as SystemVerilog, top = `top`, part
      `xc7a100tcsg324-1` (Arty A7-100T); XDC with
      `create_clock -period 10.000 [get_ports clk]`
- [ ] Uncomment `(* use_dsp = "no" *)` in `rtl/multiplier.sv`
- [ ] Synth + impl; save `report_utilization`, `report_timing_summary`,
      `report_power` as files (deliverable #9)
- [ ] **Must-be-zero checks:** DSP = 0, BRAM = 0, **LUT-as-Shift-Register = 0**.
      If the line buffers infer SRLC32E they count as LUTs in the FoM
      denominator instead of free FFs. The synchronous reset in `line_buffer`
      is what blocks SRL inference — keep it.
- [ ] Power: SAIF-based, not vectorless. Run the TB in xsim, dump SAIF,
      `read_saif` on the implemented design, then `report_power`. State the
      method in the report; show static vs dynamic separately.
- [ ] Sweep the clock constraint (100 -> 150 -> 200 MHz) for real Fmax. Add a
      pipeline stage ONLY if WNS < 0 — FFs are free in the FoM.
- [ ] Compute FoM
- [ ] **Tag the commit** (`v1.0-submission`) so every reported number is
      reproducible from one frozen RTL state
- [ ] Capture the missing waveforms — stall, edges, drain — with
      `sim/waves/*.do` (see `WAVEFORM_CAPTURES.md`); retake throughput zoomed in
- [ ] Render `hw_out/sobel_x_out.hex` to PNG next to the cat (reuse `save_png`
      from `golden.py`) — satisfies the edge-detection demo bonus in simulation

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
| Verification status | 16/16 regression runs pass: 5 kernels x 1024 px bit-exact vs Python golden, fixed + random stalls, 2 frames back to back, ReLU build |

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
