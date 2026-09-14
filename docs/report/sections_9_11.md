# 9. Testbench and Verification

Specification item 8 requires the design to be verified against a golden reference model,
with test cases, expected outputs, hardware outputs and a comparison showing correctness.
This section presents all four. The headline result is that **every output the hardware
produces is byte-identical to the reference model**, across seven kernels, three stall
regimes, two ReLU builds and a back-to-back frame pair - 22 runs, 0 failures.

## 9.1 Verification Strategy

Verification proceeds bottom-up, so that a failure is localised before integration:

| Level | Testbench | Scope | What it proves |
|---|---|---|---|
| Unit | tb/tb_window_gen_unit.sv | window_gen alone, en and flags direct-driven | tap shifting, stall freeze, edge and corner masking |
| Integration | tb/tb_top_window.sv | control_fsm + window_gen inside top | window contents, raster position, edge flags, gapless win_valid, fill latency |
| System (single) | tb/tb_top.sv | full accelerator, one kernel | pixel_out against golden, latency, throughput, writes hw_out/ |
| System (regression) | tb/tb_top_all.sv | full accelerator, all cases | the 22-run matrix below |

## 9.2 Test Cases

**Input image.** A photograph converted to 32x32 8-bit grayscale
(golden_model/cat.png -> golden_model/hex/image.hex). A natural image is used in preference
to a synthetic pattern because it exercises the full 0-255 input range with no structural
regularity that could mask an indexing error.

**Kernels.** Seven, each loaded through the real write port:

| Kernel | Coefficients | Purpose |
|---|---|---|
| identity | centre 1, rest 0 | passes the image through; any window misalignment shows immediately |
| sobel_x | [-1 0 1; -2 0 2; -1 0 1] | horizontal gradient, signed output |
| sobel_y | [-1 -2 -1; 0 0 0; 1 2 1] | vertical gradient, exercises the other sign pattern |
| sharpen | [0 -1 0; -1 5 -1; 0 -1 0] | mixed-sign with a large centre weight |
| laplacian | [0 1 0; 1 -4 1; 0 1 0] | negative centre weight |
| satmax | all +127 | forces positive saturation on all 1024 outputs |
| satmin | all -128 | forces negative saturation on all 1024 outputs |

**Stall regimes.** Each kernel is run three ways:

- **Clean** - valid_in held high for all 1024 pixels.
- **Fixed stalls** - valid_in deasserted at five chosen points totalling 18 cycles: before
  pixel 10 (2 cycles, during FILL), 300 (3), 511 (1, at a row boundary), 700 (8) and 1023
  (4, immediately before the last pixel). These positions probe the FILL/STREAM boundary,
  a row wrap, a long stall, and the final pixel.
- **Random stalls** - approximately one pixel in five preceded by a 1-4 cycle stall, giving
  roughly 500 stall cycles per run.

**Back-to-back frames.** One additional run streams sobel_x, swaps the kernel to sharpen the
moment busy falls, and streams a second frame immediately, producing 2048 outputs checked
against two different references.

## 9.3 Checks Applied Every Cycle

- **Pixel equality.** Each valid_out pixel is compared against the corresponding golden
  value; any mismatch is reported with its raster position and counted.
- **ReLU equality.** A second instance of the entire accelerator with `RELU=1` runs on the
  same stimulus, compared against the ReLU reference outputs.
- **Latency invariant.** `valid_out` must equal `win_valid` delayed by exactly three cycles,
  checked on every clock of every run. This is the strongest single assertion in the
  suite: it fails if any pipeline stage drops, duplicates or reorders a valid bit.
- **Bubble accounting.** The number of gaps in valid_out must equal the number of stall
  cycles that occurred while the FSM was in STREAM. Stalls during FILL delay the first
  output rather than creating a bubble, and are excluded.
- **Output count.** Exactly 1024 outputs per frame (2048 for the back-to-back run).

## 9.4 Regression Results

| Kernel | Clean | Fixed stalls | Random stalls |
|---|---|---|---|
| identity | pass | pass, 18 stalls / 16 bubbles | pass, 558 stalls / 534 bubbles |
| sobel_x | pass | pass, 18 / 16 | pass, 502 / 476 |
| sobel_y | pass | pass, 18 / 16 | pass, 551 / 523 |
| sharpen | pass | pass, 18 / 16 | pass, 493 / 479 |
| laplacian | pass | pass, 18 / 16 | pass, 498 / 480 |
| satmax | pass | pass, 18 / 16 | pass, 555 / 538 |
| satmin | pass | pass, 18 / 16 | pass, 537 / 512 |
| sobel_x -> sharpen back-to-back | pass, 2048 outputs | - | - |

**22 runs, 0 failures.** In every run: 0 pixel errors, 0 ReLU errors, 0 latency-invariant
violations, and bubble count exactly equal to STREAM stall count. In the fixed-stall runs 18
cycles are injected but only 16 fall in STREAM - the other 2 occur during FILL and correctly
produce no bubble, delaying the first output to cycle 39 instead of 37.

## 9.5 Hardware Outputs and the Comparison

The system testbenches write every pixel the RTL produces to `hw_out/<kernel>_out.hex` and
`hw_out/<kernel>_relu_out.hex` - 14 files, 1024 lines each, one 16-bit hexadecimal value per
line in output raster order. These are the hardware outputs the specification asks for; they
are captured from `pixel_out` during simulation, not copied from the model.

The comparison is exact and independently checkable. Every one of the 14 files is
**byte-identical** to its counterpart in `golden_model/hex/`, which a reviewer can confirm
without running the design:

```
diff hw_out/sobel_x_out.hex golden_model/hex/sobel_x_out.hex     (no output = identical)
```

This is a stronger claim than a tolerance-based comparison: the fixed-point hardware
reproduces the integer reference model exactly, for every pixel of every kernel, because
both perform the same lossless integer arithmetic with the same saturation rule.

Sources: tb/tb_top_all.sv, tb/tb_top.sv, tb/tb_top_window.sv, tb/tb_window_gen_unit.sv,
hw_out/, golden_model/hex/.

**Table 9.1** - Regression matrix (Section 9.4)

---

# 10. Golden Reference Model

The reference model is `golden_model/golden.py`, 80 lines of Python using NumPy. It defines
correctness for the entire project: every hardware output is compared against it, and it
also generates the coefficient files the testbenches load through the write port.

## 10.1 What the Model Computes

```python
for y in range(32):
    for x in range(32):
        acc = 0
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                iy, ix = y + dy, x + dx
                if 0 <= iy < 32 and 0 <= ix < 32:      # zero padding
                    acc += int(img[iy, ix]) * int(k[dy+1, dx+1])
        acc = max(-32768, min(32767, acc))             # saturate
        if relu and acc < 0: acc = 0                   # optional ReLU
        out[y, x] = acc
```

- **Zero padding by omission.** Out-of-range neighbours are skipped, which is arithmetically
  identical to multiplying a zero pixel by its coefficient. This mirrors the hardware, where
  the edge flags force those taps to zero.
- **Python integers during accumulation** - unbounded, so the model cannot itself overflow.
  The clamp to [-32768, +32767] is applied explicitly afterwards, matching the hardware's
  20-bit-to-16-bit saturation.
- **Cross-correlation orientation.** The kernel is applied unflipped: `tap[n] x coef[n]`
  with tap 0 at top-left. This is the CNN convention and matches the hardware's
  `write_addr = 3*row + col` ordering. Stated as an assumption in Section 17.
- **Independence.** The model was written from the specification, not derived from the RTL,
  so agreement between them is evidence rather than tautology.

## 10.2 Generated Files

Running `python golden.py hex/image.hex` regenerates, for each of the seven kernels:

| File | Contents | Used by |
|---|---|---|
| hex/image.hex | 1024 lines, 8-bit hex, the input image | testbench stimulus |
| hex/`<k>`_coef.hex | 9 lines, 8-bit hex two's complement, write-port order | loaded through write_en/write_addr/data_write |
| hex/`<k>`_out.hex | 1024 lines, 16-bit hex two's complement | reference for pixel comparison |
| hex/`<k>`_relu_out.hex | 1024 lines, same format, ReLU applied | reference for the RELU=1 instance |
| png/`<k>`.png | normalised render | visual inspection |

Emitting the coefficient files from the same source as the expected outputs removes a class
of error: the kernel the hardware is programmed with and the kernel the reference used are
by construction the same nine numbers.

## 10.3 Window-Level Model

An earlier model, `golden_model/vectors/`, checks one level lower: for five synthetic
patterns (hramp, vramp, impulse, random, ring) it emits the expected 3x3 window at every
output position, 1024 windows of 9 bytes each. `tb_top_window.sv` compares the tap registers
against these directly, which isolates window-generation faults from arithmetic faults.
Impulse and ring are the strongest border and indexing cases: an impulse at a known position
makes any misalignment immediately visible.

Sources: golden_model/golden.py, golden_model/hex/, golden_model/vectors/.

**Table 10.1** - Kernel definitions (Section 9.2)

---

# 11. Waveform Screenshots

All captures are from ModelSim on the submitted RTL, with the timeline in nanoseconds and
one gridline per 10 ns clock period so cycles can be counted directly. Cursor deltas are
snapped to clock edges. Each figure is reproduced by `do sim/waves/<name>.do` after the
corresponding run.

**Figure 11.1 - Fill latency** (docs/figures/waveforms/Latency.PNG)
Cursor 1 at 145 ns marks the first accepted pixel (valid_in rising, busy asserting); cursor
2 at 515 ns marks the first output (valid_out rising). The delta is 370 ns = **37 cycles** =
34 window fill + 3 pipeline stages. The nine coefficient write pulses are visible before
145 ns, while busy is still low.

**Figure 11.2 - Kernel load** (docs/figures/waveforms/kernel_load.PNG)
Nine consecutive write_en pulses with write_addr stepping 0 through 8 and the sobel_x
coefficients on data_write, all while busy is low. Demonstrates the programmable-coefficient
requirement being exercised through the real port rather than by initialisation.

**Figure 11.3 - Sustained throughput** (docs/figures/waveforms/throughput.PNG)
The whole frame. valid_out is a single unbroken high interval between 515 ns and 10755 ns -
10240 ns = **1024 consecutive cycles**, one output pixel per clock with no gap anywhere in
the frame. This is the evidence for the one-pixel-per-cycle bonus claim.

**Figure 11.4 - Stall freeze and bubble** (docs/figures/waveforms/stall.PNG)
valid_in is deasserted for 3 cycles before pixel 300. en follows it low, the nine tap
registers hold their values unchanged, and win_valid drops. Exactly 3 cycles later the
matching gap appears in valid_out. No pixel is lost, duplicated or corrupted - the stall
becomes a bubble that travels through the pipeline with the data.

**Figure 11.5 - Border masking** (docs/figures/waveforms/edges.PNG)
A row boundary: at output column 31 right_edge is high and taps c, f, i read zero; on the
next cycle out_c wraps to 0, left_edge asserts, and taps a, d, g read zero instead. The
centre tap e is never masked. This is zero-padded "same" convolution in operation.

**Figure 11.6 - End of frame** (docs/figures/waveforms/drain.PNG)
The last input pixel enters at 10385 ns. The FSM moves to DRAIN and continues producing
outputs for 34 further cycles with no input, completing exactly 1024 outputs before
frame_done pulses. busy falls three cycles before the final valid_out, because the last
window is already committed to the pipeline.

**Figure 11.7 - Full frame FSM traversal** (docs/figures/waveforms/fsm.PNG)
One complete frame through IDLE, FILL, STREAM, DRAIN, DONE and back to IDLE, with in_cnt,
out_r and drain_cnt visible as the transition drivers. State durations are 34 / 990 / 34 / 1
enabled cycles; the frame spans 1061 cycles from first pixel in to last pixel out.

**Figures 11.8 to 11.10 - Window generator unit test**
(docs/figures/waveforms/Window_generator_producing_valid_taps.PNG, _valid_taps2.PNG,
_last_valid_taps.PNG)
The 3x3 window sliding across the image in the direct-driven unit testbench: the first valid
window, an interior window mid-frame, and the final window of the frame. Captured before the
final retake and unchanged by subsequent commits, which affected only comment text and the
edge-flag registration that tb_top_window verifies independently.

**Table 11.1 - Capture index**

| Figure | File | Run | Script | Cursors | Proves |
|---|---|---|---|---|---|
| 11.1 | Latency.PNG | sobel_x | latency.do | 145 / 515 ns | 37-cycle latency |
| 11.2 | kernel_load.PNG | sobel_x | coeff.do | - | 9 writes, addr 0-8 |
| 11.3 | throughput.PNG | sobel_x | throughput.do | 515 / 10755 ns | 1024 gapless outputs |
| 11.4 | stall.PNG | sobel_x +STALL=1 | stall.do | 3165 / 3195 ns | bubble 3 cycles later |
| 11.5 | edges.PNG | sobel_x | edges.do | 795 / 805 ns | c,f,i then a,d,g masked |
| 11.6 | drain.PNG | sobel_x | drain.do | 10385 / 10755 ns | drain, busy early |
| 11.7 | fsm.PNG | sobel_x | fsm.do | - | 34 / 990 / 34 / 1 |
| 11.8-11.10 | Window_generator_*.PNG | unit | - | - | window sliding |
