# Architecture — LOCKED
**3×3 Edge-AI CNN Convolution Accelerator · SSCS 2026 · solo**
*Single source of truth. If a chat, note, or diagram disagrees with this file, this file wins.*

Last locked: 25 Aug 2026.

---

## 0. How to read this
Every decision below is **final** unless deliberately reopened. Three columns of certainty:
- **Fixed** — set by spec or chosen and closed; do not revisit.
- **Derived** — forced by arithmetic; not a matter of taste.
- **Toggle** — a synthesis parameter with a locked default; alternate value is a rebuild, not a redesign.

---

## 1. The one equation everything serves
```
FOM = Throughput / ( Power × ( LUTs + 50×DSPs + 100×BRAMs ) )
```
Throughput = output pixels per cycle. Consequences that drove the locks below:
- **1 output pixel/cycle** → maximize numerator + claim the named bonus → **9 parallel MACs**.
- **0 BRAM** (×100 penalty) → line buffers are **FF/LUTRAM shift registers**, never block RAM.
- **~0 DSP** (×50 penalty) → multipliers forced to LUTs (vendor attribute, set at board choice).

---

## 2. Structural parameters (FIXED)

| Param | Value | Notes |
|---|---|---|
| `IMG_W` | 32 | fixed; larger allowed but frozen at 32 |
| `IMG_H` | 32 | fixed |
| Kernel | 3×3 | fixed size; coefficients programmable |
| `BORDER` | **zero / same** | 32×32 out (1024 outputs), gapless `valid_out`, sustains 1 px/cycle |
| Stride | 1 | spec-locked |

**Same-conv is primary, not valid-conv.** Valid (30×30) is retained ONLY as the Gate-1 fallback if the border logic can't be made correct in time. Same-conv is what makes the sustained-1-px/cycle bonus claim airtight; valid-conv deasserts `valid_out` 2 cycles per row boundary and forfeits *sustained* (not peak) throughput.

---

## 3. Precision (FIXED / DERIVED)

| Param | Value | Kind | Notes |
|---|---|---|---|
| `IN_W` | 8, unsigned (Q8.0) | Fixed | grayscale 0–255 |
| `COEF_W` | 8, signed | Fixed | spec-locked |
| `COEF_FRAC` | 0 (Q8.0 integer) | **Toggle** | DEFAULT. Rebuild at 7 → Q1.7 for normalized blur/Gaussian |
| `OUT_W` | 16, signed, **saturating** | Fixed | spec minimum; saturate (not wrap/truncate) |
| `RELU_EN` | 0 | **Toggle** | bonus stage, default off |
| `PROD_W` | 16, signed | Derived | 8u × 8s → range −32640..+32385 |
| `ACC_W` | **20**, signed | Derived | sum of 9 products, 9×255×128 = 293,760 → 20 bits lossless |

At `COEF_FRAC = 0` the shifter/rounder optimizes away entirely → leanest datapath, best FoM. This is the shipping build. Q1.7 vectors sit on the shelf for the optional rebuild.

**ACC_W = 20 is final.** Not 22 (an early guess), not 21 (indefensible from the math). The derivation is 9×255×128 = 293,760, which needs 20 bits signed, lossless.

---

## 4. Parallelism — N_MAC = 9 (LOCKED)

**9 MACs, fully parallel, one output pixel per cycle.** Decided against the 3-MAC (rows-parallel/columns-sequential, 1 output per 3 cycles) alternative.

Why: throughput triples (0.33 → 1.0 px/cycle) while the FoM denominator grows only ~1.5× (6 extra small multipliers on top of ~400 units of fixed logic). Net FoM ≈ **1.7–1.9× better** than 3-MAC in every mapping, AND it claims the sustained-1-px/cycle bonus. The 3-MAC "columns sequential" schedule is **superseded** — any note describing it is stale.

Structure: three row-MACs (each = 3 multipliers + adder tree, combinational), all 9 window pixels consumed at once, three row-partials summed into the 20-bit accumulator.

---

## 5. Interface (FIXED)

- **Input:** `pixel_in [7:0]` unsigned, one pixel/cycle, raster order, external bus strictly 8-bit.
  - **8-bit parallel, NOT serial/SIPO.** A serial front-end was considered and rejected: serial assembly latency destroys sustained throughput with no offsetting FoM saving. (If a future board forces a serial sensor, add a SIPO deserializer *wrapper* feeding the same 8-bit core.)
- **`valid_in`** is the gating signal. Every sequential element has `en = valid_in`. On a stall: no shift, counters hold, window frozen, `valid_out` low. A stall is input starvation, never a design bubble.
- **Output:** `pixel_out [15:0]` signed, streaming one pixel/cycle, `valid_out` gapless across a frame.
- **Kernel load:** small write-enable + addr + data port; 9 coefficients loaded before streaming.

---

## 6. Module map & the control/datapath split

**Datapath modules are "dumb" — they hold no frame-position knowledge. The control unit owns all position state.**

| Module | Role | Owns |
|---|---|---|
| `line_buffer.sv` | depth-**32** × 8-bit shift register, `en`-gated | just the delay line |
| `window_gen.sv` | 2 line buffers + 9 tap regs + border zero-muxes | shifts pixels, applies masks — **no counters** |
| `mac3x3.sv` | 9 LUT-multipliers + adder tree + 20-bit accum | the arithmetic |
| `saturate.sv` | 20→16 signed saturation | clamp |
| `relu.sv` | 1-mux bonus stage (`RELU_EN`) | optional clip |
| `control_fsm.sv` | **row/col counters, fill tracking, edge flags, `valid_out`** | ALL position/timing state |
| `top.sv` | wires it together, 1 px/cycle pipeline | — |

**Interface between control and window_gen:** control drives `en` and the four edge flags (`top/bottom/left/right`); window_gen ORs them per-tap and applies the zero-mux. window_gen has NO `valid_out` and NO counters. This keeps stall/freeze logic in one place (single source of truth) and lets the window_gen be unit-tested by direct-driving `en` + flags.

---

## 7. Line buffer depth = 32 (LOCKED — corrected)

**Depth = `IMG_W` = 32.** NOT 29.

The line buffer carries one *full row* of vertical delay (32 pixels). The horizontal tap shift registers move *sideways within a row* and do NOT contribute to row-to-row delay — those are independent axes. An earlier "IMG_W−3 = 29" figure was WRONG (it belongs to a different topology where taps sit inside the delay chain). Verified by sweep: only depth 32 produces a vertically-aligned 3×3 window; depth 29 yields a skewed parallelogram that fails the golden diff on every interior pixel.

Any diagram labeled "Line Buffer (29×8)" must be corrected to **32×8**.

---

## 8. Window tap mapping (must match golden model)

Row-major, index → position:
```
tap[0] tap[1] tap[2]     a b c   (top row,    from line buffer 1)
tap[3] tap[4] tap[5]  =  d e f   (middle row, from line buffer 0)
tap[6] tap[7] tap[8]     g h i   (bottom row, from pixel_in)
```
`tap[4]` = center = `w11`, **never zeroed**. Golden windows are emitted in this order, output raster order, 1024 windows.

Border zeroing (combinational, from control's edge flags):
```
top_edge    → tap 0,1,2 = 0
bottom_edge → tap 6,7,8 = 0
left_edge   → tap 0,3,6 = 0
right_edge  → tap 2,5,8 = 0
```
Corners: two flags fire at once (sequential `if`s = OR behavior); the corner tap is zeroed by both. Center never zeroed.

---

## 9. Verification chain

- **Golden model (Python):** `window_model_same.py` (window-level, DONE + self-checked). Output-level model (image+kernel → 16-bit saturated pixels) still TODO for full-accelerator verification.
- **Test images:** hramp, vramp, impulse, random, ring (ring/impulse are the border/indexing stress cases).
- **Vectors:** `<name>_in.hex` (1024 × 8-bit), `<name>_windows_same.hex` (1024 × 9 bytes row-major).
- **Unit TB:** `tb_window_gen_unit.sv` — direct-drives `en`/flags, shadow-model prediction, stall + corner tests. Proves datapath in isolation.
- **Integration TB:** streams full frame via control, diffs vs golden — this is **Gate 1**.
- **Reset style:** synchronous (`rst_n` sampled on posedge clk), intentional. Keep consistent across all modules.

---

## 10. Superseded — do NOT resurrect these
These were locked early then reversed. Listed so a stale note doesn't reintroduce them:
- ❌ Valid convolution as primary → **now same/zero-pad** (valid is fallback only)
- ❌ Single MAC / 9 cycles per output → **now 9-MAC, 1/cycle**
- ❌ 3-MAC "columns sequential" candidate → **rejected, 9-MAC chosen**
- ❌ BRAM line buffers → **now FF/LUTRAM, 0 BRAM**
- ❌ Line buffer depth 29 (IMG_W−3) → **now 32 (IMG_W)**
- ❌ ACC_W 22 or 21 → **now 20**
- ❌ Serial/SIPO input → **now 8-bit parallel**

---

## 11. Still genuinely open (not locked)
- **Board** → TBD; RTL stays vendor-neutral. Decides the LUT-multiplier-suppression attribute (`use_dsp="no"` / `multstyle="logic"` / Gowin equiv) and unlocks real synth/timing/power numbers.
- **Pipeline register depth** → build with clean stage boundaries (window→MAC→accum→sat, one register per major block), synthesize, then deepen ONLY where the timing report flags the critical path (expected: inside the MAC). FFs are free in FoM.
- **Fill-latency offset / `valid_out` start timing** → lives in `control_fsm`, confirm exact value against the golden diff.
- **Output-level golden model + RELU vectors** → write when MAC/saturate are ready.
