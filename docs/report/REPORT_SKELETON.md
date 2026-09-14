# 3x3 CNN Convolution Accelerator for Edge-AI Vision
### IEEE SSCS Egypt Chapter - 2026 Student Design Competition

<!--
HOW TO USE THIS FILE
Write your prose under each heading. The headings are already in the order the
announcement lists the deliverables, so do not reorder them.

For each section, REPORT_OUTLINE.md has a matching block telling you what to say and
which figure to place. Read the corrections banner at the top of that file first.

Figure and table numbers are pre-assigned - keep them, they are referenced across
sections. Delete these HTML comments before exporting to PDF.

Target: 25-35 pages including figures. Export to PDF as docs/report/SSCS2026_Report.pdf
-->

**Team:** <name>  **University:** <university>  **Date:** September 2026

---

## Abstract

<!-- 150 words. What it is, the headline numbers, the FoM. Write this LAST. -->

---

## 1. Accelerator Architecture

<!-- outline: section 1. What it does, the control/datapath split, the three FoM levers,
     the parameter table, headline results forward-referenced. -->

**Table 1.1** - Design parameters (from `rtl/cnn_pkg.sv`)

---

## 2. Block Diagram

<!-- outline: section 2. -->

**Figure 2.1** - Top-level block diagram
<!-- DRAW THIS - 5 boxes, see BLOCK_DIAGRAM_NOTES.md -->

---

## 3. Datapath

<!-- outline: section 3. Stage by stage with widths, the valid chain, why 3+3 adders. -->

**Figure 3.1** - Datapath with pipeline stage boundaries
<!-- UPDATE THE EXISTING DRAWING - see BLOCK_DIAGRAM_NOTES.md -->

**Table 3.1** - Per-stage worst-case slack (from `fpga/reports/paths.rpt`)

---

## 4. Control FSM

<!-- outline: section 4. Five states, the registered edge flags, stall semantics,
     the frame contract. State durations are 34 / 990 / 34 / 1. -->

**Figure 4.1** - FSM state diagram
<!-- UPDATE THE EXISTING DRAWING -->

**Figure 4.2** - `docs/figures/waveforms/fsm.PNG` - one frame through all five states

**Table 4.1** - State / output table

---

## 5. Memory Organization

<!-- outline: section 5. The memory table, SRL inference, the no-BRAM argument. -->

**Table 5.1** - Storage elements and their implementation

---

## 6. Window Generation

<!-- outline: section 6. Line-buffer cascade, tap map, zero-padding masks,
     why depth 32, fill latency 34 = 32 + 2. -->

**Table 6.1** - Tap map (a..i, source, delay)

**Table 6.2** - Zero-padding masks per edge flag

**Figure 6.1** - `docs/figures/waveforms/edges.PNG` - masking at a row boundary

**Figure 6.2** - `docs/figures/waveforms/Window_generator_producing_valid_taps.PNG`

---

## 7. Fixed-Point Bit-Width Analysis

<!-- outline: section 7. REQUIRED: justify input precision (spec item 2) and explain
     overflow/saturation handling (spec item 6). -->

**Table 7.1** - Bit widths: stage, format, range, width, derivation

**Table 7.2** - Measured accumulator range per kernel vs the worst case

---

## 8. RTL Implementation Details

<!-- outline: section 8. Module by module, coding decisions, the scripts. -->

**Table 8.1** - Module inventory: file, module, role, ports

---

## 9. Testbench

<!-- outline: section 9. REQUIRED (spec item 8): test cases, expected outputs,
     hardware outputs, comparison showing correctness. -->

**Table 9.1** - Regression matrix, all 22 runs

---

## 10. Golden Reference Model

<!-- outline: section 10. What golden.py computes, the kernels, file formats,
     how to regenerate. -->

**Table 10.1** - Kernels and their coefficient matrices

---

## 11. Waveform Screenshots

<!-- outline: section 11. One figure per capture, in this order. -->

**Figure 11.1** - `docs/figures/waveforms/latency.PNG` - 37-cycle fill latency
**Figure 11.2** - `docs/figures/waveforms/kernel_load.PNG` - 9 coefficient writes
**Figure 11.3** - `docs/figures/waveforms/throughput.PNG` - 1024 gapless outputs
**Figure 11.4** - `docs/figures/waveforms/stall.PNG` - stall freeze and bubble
**Figure 11.5** - `docs/figures/waveforms/drain.PNG` - end of frame
**Figure 11.6** - `docs/figures/waveforms/Window_generator_producing_last_valid_taps.PNG`

---

## 12. FPGA Synthesis and Implementation Results

<!-- outline: section 12. REQUIRED (spec item 9): LUTs, FFs, DSPs, BRAMs. -->

**Table 12.1** - Resource utilization (post-route)

**Table 12.2** - Utilization by module

---

## 13. Timing Report

<!-- outline: section 13. REQUIRED: maximum frequency, timing status.
     State the I/O exclusion and why. -->

**Table 13.1** - Timing summary: WNS, WHS, endpoints, Fmax

---

## 14. Power Report

<!-- outline: section 14. REQUIRED - the organiser's five items, each explicitly:
     device and board / frequency used in the FoM / static, dynamic, total /
     SAIF interval / tools. -->

**Table 14.1** - Power breakdown by component

---

## 15. Design Tradeoffs

<!-- outline: section 15. Include the iteration that failed - it reads as rigour. -->

**Table 15.1** - Design iterations: change, rationale, before/after

---

## 16. Figure of Merit

<!-- outline: section 16. The formula, the substitution, the frequency choice,
     the watts assumption. -->

**Table 16.1** - REQUIRED TABLE FORMAT (the announcement's Table 1)

| Parameter | Specification | Team Result | Units | Comments |
|---|---|---|---|---|
| Input image size | | | | |
| Input precision | | | | |
| Kernel precision | | | | |
| Architecture type | | | | |
| Multipliers / MACs | | | | |
| Pipeline stages | | | | |
| Latency | | | | |
| Throughput | | | | |
| FPGA utilization | | | | |
| Maximum frequency | | | | |
| Power estimate | | | | |
| Verification status | | | | |
| FOM | | | | |

<!-- fill from fpga/reports/RESULTS.md; the outline has every cell -->

---

## 17. Assumptions

<!-- outline: section 17. REQUIRED by instruction 4. Do not forget the three the
     critic flagged: kernel size N = 3, cross-correlation orientation,
     power-analysis conditions. -->

---

## 18. Bonus Features Claimed

<!-- outline: section 18. Each bonus with the evidence, and an explicit line that
     the board demo is not claimed. -->

**Figure 18.1** - `docs/figures/edge_demo_sobel_x.png` - input vs RTL output

---

## 19. Conclusion

<!-- outline: section 19. -->

---

## Appendix A - Submitted Files

<!-- outline: appendix. Map each required deliverable to its path in the zip. -->
