# SSCS 2026 — Gold Award Battle Plan
**3×3 Edge-AI CNN Convolution Accelerator · Solo · Arty A7-100T**

- **Today:** Sat 22 Aug 2026
- **Report deadline:** Tue 15 Sep 2026 (**24 days**)
- **Results:** 30 Sep 2026
- **Constraint:** Orange internship holds weekdays 9–5. Real build time = weeknight evenings + full weekends.
- **Sim:** ModelSim (`vlog`/`vsim`) — full SystemVerilog, so no need to restrict constructs.
- **Board:** TBD → keep RTL 100% vendor-neutral; defer synth tool + DSP-suppression attribute until chosen.

---

## 1. North Star — how gold is actually won

Once a design is *correct*, the ranking is decided by the Figure of Merit:

```
FOM = Throughput / ( Power × ( LUTs + 50×DSPs + 100×BRAMs ) )
```

Every design choice serves this one equation. The thesis:

| Lever | Winning move | Why |
|---|---|---|
| Throughput (numerator) | **1 output pixel / cycle**, fully pipelined | Maxes numerator; also a named bonus |
| BRAMs (×100 penalty) | **Zero BRAM** — line buffers as FF shift registers | 2×32 pixels fits easily in FFs; deletes the ×100 term entirely |
| DSPs (×50 penalty) | **LUT-based MACs** (`use_dsp = "no"`) | 8-bit signed × 8-bit unsigned is small; kill the ×50 term |
| Power | Clean pipeline, no wasted toggling | Directly divides FOM |
| Correctness | Continuous check vs Python golden model | Gate to even be ranked |

**A correct design with 0 BRAM, ~0 DSP, 1 px/cycle, small LUT footprint beats teams who dump everything into DSP48s and BRAM.** That gap is the whole game.

---

## 1b. Interface & throughput contract (per clarifications)

- **External interface = 8-bit unsigned, one pixel/cycle.** This is the *only* mode the 1-px/cycle bonus is claimed under. Any wider bus (e.g. 24-bit/3-px) is a separate appendix design, never a substitute.
- **`valid_in` may stall mid-stream.** Every sequential element (line buffers, row/col counters, pipeline valid) has `en = valid_in`. During a stall: no shift, counters hold, window frozen, `valid_out` low. A stall is input starvation, **not** a design bubble.
- **Convolution = zero-padded / "same" (32×32 out), fixed-latency pipeline.** This is what sustains one output per cycle: a valid window exists for *every* pixel (edges muxed to zero), so `valid_out` is gapless across a frame. Valid-conv (30×30) is the fallback only — it bubbles 2 cycles/row and **forfeits the bonus**.
- **Report BOTH:** *peak* throughput (1 px/cycle fed continuously) and *average sustained* (over a full frame incl. fill + end-of-frame flush). Fill latency and inter-frame pauses do not count against sustained throughput.

## 2. Who does what

- **You (hands-on):** RTL authoring, sim/debug, Vivado synth/impl, timing closure, board demo, waveform capture, verifying every number.
- **Claude (leverage):** Golden model (✅ done), test-vector generation, self-checking TB scaffolding, FoM/power tooling, **all report drafting**, diagrams (block/FSM/datapath), bit-width analysis writeups, slide deck.

Documentation is what sinks solo teams. I carry the draft; you review and paste real numbers/screenshots. That is the structural advantage that makes solo-gold realistic.

---

## 3. Weekly deliverables

Each week has a **Technical track** (your hands) and a **Documentation track** (mostly me), a **weekend focus**, and a **GATE** you must pass to advance. If a gate is red, trigger the cut-list (§6).

### ✅ Week 0 — Done today (22 Aug)
- Workspace, Python golden model, 5 kernels (identity/sobel_x/sobel_y/sharpen/box_blur), ReLU variant, hex vectors (`_in`/`_kernel`/`_expected`), bit-width analysis (20-bit lossless acc → saturate to 16-bit signed).

---

### Week 1 — Foundation & the window engine (Sat 23 Aug → Fri 29 Aug)
**Goal: a correct 3×3 window streaming out in simulation. This is the module most teams get wrong.**

**Technical**
- `line_buffer.sv` — two 32-deep 8-bit FF shift registers (no BRAM), **clock-enabled by `valid_in`**.
- `window_gen.sv` — taps producing the 3×3 window + a `valid` strobe, with **row/col counters (also `valid_in`-gated) muxing zeros at padded edges**.
- `top` parameter block: `IMG_W/H`, `IN_W=8`, `COEF_W=8`, `ACC_W=22`, `OUT_W=16`, `BORDER=zero (same)`.
- Sim-only harness that streams a test image **with a deliberate `valid_in` stall injected mid-stream**, dumps the window stream; verify it matches golden *and* stays synchronized across the stall.

**Documentation** (I draft, you review)
- §Architecture overview + top-level block diagram.
- §Memory / line-buffer organization writeup (the "no BRAM" justification).
- §Fixed-point & bit-width analysis (input unsigned 8b, coeff signed 8b, 20b lossless acc, 16b saturated out — with the measured ranges from the golden run as evidence).

**Weekend focus (Sat/Sun):** get `window_gen` bit-exact in Icarus, `make lint` clean in Verilator, waves inspected in Surfer.

> **GATE 1 (by Fri 29 Aug):** 3×3 window stream matches golden windows byte-for-byte **including through an injected `valid_in` stall** (window stays synchronized). Lint clean. → If red: fall back to `valid` border (forfeits the sustained-throughput bonus but ships correct), freeze image at 32×32, drop parameterization.

---

### Week 2 — Datapath & first green correctness (Sat 30 Aug → Fri 5 Sep)
**Goal: full accelerator passes self-checking TB on all test kernels.**

**Technical**
- `mac3x3.sv` — 9 LUT-based signed×unsigned multipliers (`(* use_dsp = "no" *)`), adder tree, 22-bit accumulator.
- `saturate.sv` — 22b→16b signed saturation (documented). `relu.sv` — 1-mux bonus stage.
- `control_fsm.sv` — states: `LOAD_KERNEL → STREAM → FLUSH`. Kernel programmable via small load port.
- `top.sv` — wire it all, 1 px/cycle pipeline.
- `tb_top.sv` — self-checking: reads `_in`/`_kernel`, compares DUT vs `_expected`, prints PASS/FAIL + mismatch count.

**Documentation**
- §Datapath description + datapath diagram.
- §Control FSM description + FSM state diagram.
- §Verification methodology (golden model, vector flow, self-checking TB).

**Weekend focus:** all 5 kernels PASS in Icarus. Capture the first clean waveform screenshots (pipeline fill, one output pixel).

> **GATE 2 (by Fri 5 Sep):** self-checking TB reports 0 mismatches across all 5 kernels (valid border) + ReLU variant. → If red: freeze at 3 kernels for the report, defer ReLU, ship correctness first.

---

### Week 3 — FPGA flow, FoM optimization, bonuses (Sat 6 Sep → Fri 12 Sep)
**Goal: real Vivado numbers, optimized FoM, board demo.**

**Technical**
- Vivado project (Arty A7-100T), `.xdc` constraints, clock target (start 100 MHz, push Fmax).
- Synthesize + implement. Confirm **0 BRAM, ~0 DSP** in the utilization report — if DSPs appear, force `use_dsp="no"` and re-run.
- `report_timing_summary`, `report_utilization`, `report_power` → record LUTs, FFs, DSPs, BRAMs, Fmax, WNS, power.
- Compute FoM. Iterate: pipeline registering, trim critical path, retime if WNS negative.
- **Bonus:** board demo (stream image over UART — reuse your UART TX/RX), on-board ReLU/edge-detect visual.

**Documentation**
- §RTL implementation details.
- §FPGA synthesis & implementation results (util/timing/power tables).
- §FoM calculation + **Table 1** (required format) fully populated, with **both peak and average sustained throughput** rows.
- §Design tradeoffs discussion (LUT-mult vs DSP, padded-vs-valid and why padded, acc width, latency vs sustained throughput).

**Weekend focus:** timing closure (WNS ≥ 0), final FoM number, board demo recorded on video.

> **GATE 3 (by Fri 12 Sep):** WNS ≥ 0 at target clock, 0 BRAM confirmed, FoM computed, all result tables filled. → If red: drop Fmax to whatever closes timing, skip board demo, keep report-only submission (still complete).

---

### Week 4 — Report, slides, package & submit (Sat 13 Sep → Tue 15 Sep)
**Goal: submit a day early. Treat 15 Sep as the wall; aim for 14 Sep.**

**Technical**
- Freeze RTL. Final waveform screenshots at presentation quality.
- Regenerate golden vectors + final TB log for the appendix.
- Package: `rtl/`, `tb/`, `golden/`, `vectors/`, FPGA reports, input images, expected outputs.

**Documentation**
- I assemble the **full report** from your numbers: architecture, block/datapath/FSM diagrams, memory & line-buffer method, bit-width analysis, RTL details, testbench + golden, waveform screenshots, synth/timing/power, tradeoffs, **Table 1**.
- Short presentation deck (I draft, you narrate).
- Final proofread pass + assumptions section (spec explicitly allows assumptions — state them all).

**Weekend focus (Sat/Sun):** report 100% done Sunday night. Mon 14 = polish + submit. Tue 15 = untouched buffer.

> **GATE 4 (by Mon 14 Sep):** report + all source + slides submitted. Buffer day intact.

---

## 4. Daily cadence (fits the 9–5)

| Slot | When | Use |
|---|---|---|
| **Weeknight block** | ~2–2.5 hrs, 4 of 5 weeknights | One concrete task from the current week (e.g. "finish `mac3x3`") |
| **Weekend deep work** | 5–7 hrs Sat + Sun | The week's heavy lifting + the GATE |
| **15-min daily log** | end of each session | Update the checklist, note the one blocker |

Protect sleep and one rest block — a 24-day sprint fails on burnout, not on hours. Skipping a weeknight is fine; skipping a GATE is not.

---

## 5. Accountability system

1. **Weekly GATE (go/no-go):** each Friday, the gate is a binary, *measurable* pass/fail above. No "mostly working."
2. **Definition of Done per artifact:** RTL = lints clean + passes TB; report section = has its diagram/table + real numbers, no `TODO`.
3. **Daily checkbox** in your Notion dashboard — one line per session: `date | task | done? | blocker`.
4. **Burndown:** track modules remaining (10 RTL files) + report sections remaining (14). The line should fall every week.
5. **End-of-week check-in with me:** paste your gate status + any red item. I re-plan the next week around reality, not the ideal.
6. **The cut-list is the safety valve** (§6) — behind schedule means *cut scope*, never *skip verification or the report*.

---

## 6. Cut-list (drop in this order if behind)

Correctness and the report are never cut. Everything else is negotiable:
1. Board demo (bonus) — drop first.
2. Parameterized image size → freeze 32×32.
3. Extra kernels → keep 3 (identity, sobel_x, sharpen).
4. ReLU bonus → defer.
5. Fmax push → accept the clock that closes timing.
6. Padded/same conv → fall back to `valid` (30×30) **only as a last resort** — it forfeits the sustained-1/cycle bonus, so protect this above kernels and Fmax.

A complete, correct, well-documented **minimum** design beats an ambitious broken one every time.

---

## 7. Resources

**Your toolchain**
- ModelSim (`vlog` compile, `vsim` run, built-in wave viewer) — full SystemVerilog, use richer constructs freely (interfaces, structs, assertions if useful).
- Synth/impl/power tool **chosen once the board is known**: Vivado (Xilinx/AMD), Quartus (Intel/Altera), or Gowin EDA (Tang). Only this step yields BRAM/DSP/timing/power numbers.
- **Keep RTL vendor-neutral** — no vendor primitives. The one vendor-specific piece is the "force LUT multiplier" attribute (Xilinx `use_dsp="no"` vs Quartus `multstyle="logic"` vs Gowin equivalent); pick it after the board is decided.

**Reusable from your own repos**
- UART TX/RX → the board-demo image streaming path.
- Self-checking TB pattern from your prior projects → base for `tb_top`.
- Line-buffer / windowing intuition from your I2C/graphics SoC work.

**Reference docs (search by title once board is known)**
- If Xilinx: *Vivado UG901 (Synthesis)* for `use_dsp`, *UG949 (UltraFast Methodology)* for timing, *UG907 (Power)* for `report_power`; board reference manual for `.xdc`/clocking.
- If Intel: *Quartus Prime Handbook* — `multstyle`, TimeQuest/Timing Analyzer, Power Analyzer.
- If Gowin (Tang): *Gowin EDA* synthesis/timing/power docs + board pinout.
- Line-buffer convolution architecture — search "FPGA line buffer sliding window convolution" for the canonical shift-register design.

**Provided by me on demand**
- Golden model + vectors (done), TB scaffolding, FoM/power spreadsheet, every report section, all diagrams, slide deck.

---

## 8. Risk register

| Risk | Likelihood | Mitigation |
|---|---|---|
| Window generator off-by-one | High | Bit-exact vs golden windows in Week 1 before any MAC work |
| Window desyncs on a `valid_in` stall | High | `en = valid_in` on all state; TB injects a stall in Week 1 to prove sync |
| Boundary bubbles silently forfeit the bonus | Med | Padded/same conv + fixed-latency pipeline; assert `valid_out` gapless in TB |
| DSPs inferred despite intent | Med | Vendor LUT-multiplier attribute, verify in util report, re-run |
| Timing won't close at target clock | Med | Pipeline registering; drop clock as last resort (FoM still fine) |
| Internship crunch eats a week | Med | Weekend deep-work carries; cut-list absorbs slippage |
| Report left too late | High (classic solo failure) | Docs drafted *in parallel* every week, not at the end |
| Board undecided too long | Med | RTL stays vendor-neutral; only synth step waits — decide by start of Week 3 |

---

## 9. FoM optimization checklist (Week 3)

- [ ] Utilization report shows **BRAMs = 0**
- [ ] Utilization report shows **DSPs = 0** (or justified minimum)
- [ ] **Peak** throughput = 1 output pixel/cycle confirmed in waveform (continuous feed)
- [ ] **Average sustained** throughput measured over a full frame (fill + flush counted)
- [ ] `valid_out` verified **gapless** during active processing (no 2-cycle deassertions)
- [ ] WNS ≥ 0 (timing met) at reported clock
- [ ] Power from `report_power` recorded
- [ ] FoM computed and sanity-checked vs the equation
- [ ] Table 1 fully populated with real numbers + units

---

### The one-line strategy to remember
**Get the window right, keep it lean (0 BRAM, 0 DSP, 1 px/cycle), verify continuously, and document every week — not at the end.**
