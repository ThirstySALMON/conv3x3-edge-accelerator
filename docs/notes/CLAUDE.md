# CLAUDE.md — Project Handoff
**SSCS 2026 · 3×3 Edge-AI CNN Convolution Accelerator · solo entrant**

Read this first. It's the state of the project so a fresh Claude session (any client) can continue without re-deriving decisions. If anything here conflicts with `ARCHITECTURE_LOCKED.md`, that file is the deeper reference — this is the working summary.

---

## 0. What this project is
FPGA-based accelerator that does a **3×3 same-convolution** over a **32×32** grayscale image, one channel, for an IEEE SSCS Egypt 2026 student design competition. Solo entrant competing against teams. Deadline **15 Sep 2026**; results 30 Sep. Graded on correctness + a **Figure of Merit**:

```
FOM = Throughput / ( Power × ( LUTs + 50×DSPs + 100×BRAMs ) )
```
Throughput = output pixels/cycle. Every design choice serves this equation. Awards: Gold $350 / Silver $250 / Bronze $150.

**Working split:** the human (Amir) authors ALL RTL, runs sim/synth/verification. Claude does golden model, tooling, report drafting, diagrams, reviews RTL before compile. Amir prefers step-by-step guidance not blind code dumps, concise code with minimal comments, and catches errors — be explicit about uncertainty, correct mistakes fast, don't defend wrong claims.

---

## 1. Architecture — LOCKED (do not reopen without reason)

| Decision | Value |
|---|---|
| Image | 32×32 fixed |
| Kernel | 3×3, programmable coefficients |
| Convolution | **Same / zero-padded** (32×32 out, 1024 outputs, gapless valid_out) |
| **N_MAC** | **9, fully parallel, 1 output pixel/cycle** |
| Input | 8-bit unsigned, **8-bit parallel** (NOT serial/SIPO), 1 pixel/cycle |
| Coeff | 8-bit signed, **Q8.0 integer** default (Q1.7 = rebuild-only toggle) |
| Product | 16-bit signed |
| **Accumulator** | **20-bit signed** (lossless: 9×255×128 = 293,760 needs exactly 20) |
| Output | 16-bit signed, **saturating** |
| ReLU | off by default (`RELU_EN=0`, bonus toggle) |
| **Line buffer depth** | **32** (= IMG_W), NOT 29 |
| BRAM / DSP | **0 BRAM, ~0 DSP** — FF/LUTRAM line buffers, LUT multipliers (the whole FoM strategy) |
| Reset | **synchronous** (rst_n sampled on posedge clk), consistent everywhere |
| Control/datapath | **split, locked** — see §2 |

### Things already decided AND REVERSED — do NOT resurrect:
- ❌ valid-conv as primary → now same/zero-pad (valid = last-resort fallback only)
- ❌ single-MAC or 3-MAC "columns sequential" → now 9-MAC parallel (~1.7–1.9× better FoM + claims the sustained-1px/cycle bonus)
- ❌ BRAM line buffers → now fabric, 0 BRAM
- ❌ line buffer depth 29 (IMG_W−3) → now 32. (Verified by sweep: only depth 32 gives a vertically-aligned 3×3 window; 29 gives a skewed parallelogram that fails the golden diff on every interior pixel. The horizontal tap regs move sideways and add NO vertical delay — the full row delay is in the line buffer.)
- ❌ ACC_W 22 or 21 → now 20
- ❌ serial/SIPO input → now 8-bit parallel

---

## 2. Control / datapath separation (LOCKED — core principle)

**Datapath modules are "dumb": no counters, no frame-position knowledge. Control owns ALL position state.**

- `window_gen.sv` (datapath): 2 line buffers + 9 tap regs + border zero-muxes. Shifts on `en`, masks taps per edge flags. Has **NO counters, NO valid_out.**
- `control_fsm.sv` (control, NOT YET WRITTEN): owns row/col counters, fill tracking, the 4 edge flags (top/bottom/left/right), and generates `valid_out`. Drives window_gen via `en` + the 4 flags.
- **Interface:** control → window_gen sends `en` and `{top,left,right,bottom}_edge`. window_gen ORs them per-tap and applies the mux. One enable (= valid_in) gates every sequential element, so a stall freezes the whole pipeline coherently.

Why: keeps stall logic in one place (single source of truth), and lets window_gen be unit-tested by direct-driving en + flags.

### Window tap mapping (must match golden model)
Row-major: `tap[0..2]=a,b,c` (top, from LB1), `tap[3..5]=d,e,f` (middle, from LB0), `tap[6..8]=g,h,i` (bottom, from input_in). **tap[4]=center=w11, never zeroed.**
Border zeroing: top→0,1,2 · bottom→6,7,8 · left→0,3,6 · right→2,5,8. Corners: two flags fire at once (use separate `if`s = OR behavior), corner tap zeroed by both.

### Input cascade
`input_in` → tap i AND → LB0. `LB0 out` → tap f AND → LB1. `LB1 out` → tap c. (0 / 1-row / 2-row delays.)

---

## 3. What's BUILT and its status

### Golden model — DONE, working
- `golden/golden.py` (~60 lines): full-system model. Same-conv, integer accumulate, saturate to 16-bit signed, optional ReLU. Loads any image (auto grayscale + resize to 32×32) OR generates random. Writes `hex/image.hex` + `hex/<kernel>_out.hex` (RTL diffs against these) AND `png/*.png` (viewable, normalized). Kernels: identity, sobel_x, sobel_y, sharpen, laplacian.
  - Run: `python3 golden.py photo.png` or `python3 golden.py` (random).
- `golden/patterns.py`: generates synthetic test images into `samples/` (vsplit, box, diag, circle, checker) — known-answer inputs, better for verification than photos.
- `golden/window_model_same.py`: window-LEVEL golden model (older, pairs with `vectors/*_windows_same.hex`). Still valid for window_gen verification.
- `golden/measure_ranges.py`: measured accumulator ranges for the report bit-width evidence.
- ⚠️ **Kernel coefficient values in golden.py are ASSUMPTIONS.** Confirm they match Amir's intended kernels before trusting output numbers or report tables.

### RTL — partial (Amir authors)
- `rtl/window_gen.sv`: dumb window generator, WRITTEN by Amir, reviewed. Ports: `clk, rst_n, input_in[7:0], top/left/right/bottom_edge, en, tap_out[0:8]`. Uses `line_buffer` submodule (Amir's, depth must be **32**). Synchronous reset (intentional). **Passes its unit TB.**
- `rtl/line_buffer.sv`: authored by Amir (not in this repo snapshot — lives on Amir's machine). Depth 32, 8-bit, en-gated shift register.
- **`control_fsm.sv` — NOT WRITTEN YET. This is the next RTL task.**
- Also not yet written: `mac3x3.sv` (9 LUT-mults + adder tree + 20-bit acc), `saturate.sv`, `relu.sv`, `top.sv`.

### Testbenches
- `tb/tb_window_gen_unit.sv`: direct-drive UNIT test of window_gen (shift correctness via shadow model, stall-freeze, single-edge zeroing, corner overlap). **PASSES.** `LB_DEPTH=32`.
- `tb/tb_window_gen.sv`: full-frame test that diffs against `vectors/*_windows_same.hex`. Has a `FILL_PIXELS` offset that is UNVERIFIED — must be confirmed against a golden diff (see §5).

### Vectors — generated
`vectors/*_in.hex` and `vectors/*_windows_same.hex` for hramp, vramp, impulse, random, ring (1024 windows each, row-major).

### Report — 3 sections drafted
- `report/Architecture_Report_Draft.docx`: §Architecture overview + top-level diagram, §Memory/line-buffer (no-BRAM justification), §Fixed-point & bit-width analysis (with measured-range table). Diagram embedded (`report/toplevel.png`, LB0/LB1 = 32×8). ⚠️ Bit-width Table 3 numbers are from the assumed kernels — regenerate from Amir's real golden model before submitting.

---

## 4. Verification chain (how correctness is proven)
1. Golden model (Python) produces expected hex.
2. Feed same image into RTL in ModelSim (`vlog`/`vsim`).
3. Diff RTL output vs golden hex, byte-for-byte. Match = correct.
- Unit-test dumb modules in isolation first (direct-drive), THEN integrate with control, THEN full-frame golden diff. One unknown at a time.
- Tools: ModelSim (sim), Verilator (lint), Surfer (waves). Board TBD → RTL stays vendor-neutral; the LUT-multiplier-suppression attribute (`use_dsp="no"` / `multstyle="logic"` / Gowin equiv) waits for board choice.
- Waveforms: not needed for correctness (self-checking TBs are stronger). Capture 2–3 clean screenshots at the END for the report (required deliverable): window sliding, stall freeze, a border cycle.

---

## 5. NEXT STEPS (in order)
1. **Write `control_fsm.sv`** — row/col counters (en-gated), fill tracking, the 4 edge flags, `valid_out`. This is the immediate task. It drives the already-working window_gen.
2. **Resolve the fill-latency offset** — run `tb_window_gen.sv` (or a control+window integration TB) against `vectors/ring_windows_same.hex`. If windows are individually correct but shifted, it's purely the `FILL_PIXELS` / valid_out start timing — adjust in control, not in window_gen. Ring + impulse are the best border/indexing stress cases.
3. **Write `mac3x3.sv`** — 9 LUT multipliers (8u × 8s), adder tree, 20-bit signed accumulator. Instantiate 3 row-MACs (3 mults + adder each), sum the 3 row-partials. Build combinational first, pipeline later only where synth flags the critical path (expect inside the MAC). FFs are free in FoM.
4. `saturate.sv` (20→16 signed clamp) + `relu.sv` (1-mux).
5. `top.sv` wiring, full-accelerator self-checking TB diffing vs `hex/<kernel>_out.hex`.
6. Synthesis (once board chosen): confirm 0 BRAM, ~0 DSP, get LUTs/FFs/Fmax/WNS/power, compute FoM.
7. Finish report: remaining sections (datapath, FSM, verification methodology, RTL details, synth results, FoM table with BOTH peak and sustained throughput, tradeoffs), waveform screenshots, slides.

---

## 6. Gates / schedule
- GATE 1 (window stream bit-exact incl. stall) — window_gen unit test PASSES; full-frame golden diff pending control_fsm.
- GATE 2: full accelerator passes self-checking TB on all kernels.
- GATE 3: WNS ≥ 0, 0 BRAM confirmed, FoM computed, tables filled.
- GATE 4: report + source + slides submitted (aim 14 Sep, 15 = buffer).
- Cut-list if behind (never cut correctness or report): board demo → param image size → extra kernels (keep 3) → ReLU → Fmax push → same-conv fallback to valid (last resort, forfeits sustained bonus).

---

## 7. Key numbers to never get wrong
- Line buffer depth = **32**
- Accumulator = **20-bit signed** (9×255×128 = 293,760; 19 bits insufficient)
- Product = 16-bit signed; Output = 16-bit signed saturating
- 9 MACs, 1 output pixel/cycle
- 0 BRAM, ~0 DSP (this is the entire FoM edge)
- Window taps row-major, center = tap[4], never zeroed
