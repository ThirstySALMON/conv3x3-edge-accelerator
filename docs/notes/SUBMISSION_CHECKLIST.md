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
      and the two benign warnings are written up in `docs/notes/POWER_METHODOLOGY.md`.
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
| 2 | Block diagram | drafted — **needs updating**, list in `docs/report/BLOCK_DIAGRAM_NOTES.md` |
| 3 | Datapath | TODO |
| 4 | FSM state diagram | TODO (diagram drawn, needs write-up) |
| 5 | Memory organization | drafted |
| 6 | Line-buffer / window-generation method | drafted |
| 7 | Fixed-point bit-width analysis | drafted |
| 8 | RTL implementation details | TODO |
| 9 | Testbench | TODO |
| 10 | Golden model | TODO |
| 11 | Waveform screenshots | PARTIAL — 8 in `docs/figures/waveforms/`, need stall / edges / drain (see `WAVEFORM_CAPTURES.md`) |
| 12 | FPGA synth results + timing report + power report | TODO |
| 13 | Design tradeoffs discussion | TODO — source material in `docs/notes/DESIGN_ITERATIONS.md` (profiling, the rejected in_cnt change, registered edge flags, saturation rework, why constant-coefficient multipliers were rejected) |

Plus: **Table 1** in the required format (every row, with units), and an
**assumptions** section (announcement instruction 4 explicitly allows assuming
missing information, provided it is stated).

---

## 3. Fri 11 Sep - done

Gate 2 closed, implemented on xc7z020, SAIF-annotated power, three design iterations,
all documented. Saturday was lost.

## 4-6. Sunday 13 and Monday 14

The step-by-step plan is in **`docs/notes/FINAL_TWO_DAYS.md`** - one clean flow pass, tag,
cleanup, report drafted and assembled Sunday; slides, proofread, package, submit Monday.
PYNQ-Z2 is a hard requirement, so no other device gets tried.

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
