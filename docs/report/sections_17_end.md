# 17. Assumptions

The specification permits missing information to be assumed provided the assumptions are
stated. The following are the complete set made in this design.

## 17.1 Functional Scope

- **Kernel size N = 3.** The specification asks for an N x N kernel without fixing N.
  KSIZE = 3 is assumed throughout (NTAP = 9, LB_DEPTH = IMG_W). Another N is a parameter
  rebuild with a corresponding change to the tap rows in window_gen, not a run-time option.
- **Image size fixed at 32 x 32.** The specified minimum. IMG_W and IMG_H are package
  parameters; the line-buffer depth follows IMG_W automatically, so a wider image is a
  rebuild rather than a redesign.
- **Zero-padded "same" convolution.** 1024 outputs per frame, one per input pixel, rather
  than "valid" convolution's 30 x 30 = 900. Chosen so that `valid_out` is gapless across the
  frame (Section 15.4).
- **Kernel orientation is cross-correlation.** Coefficients are applied unflipped:
  `tap[n] x coef[n]` with tap 0 at top-left, matching `write_addr = 3*row + col`. This is the
  CNN convention and is what the reference model computes, so the two agree by construction.
  A true mathematical convolution would require the caller to load the kernel rotated 180
  degrees.
- **Kernel set.** The five functional kernels demonstrated (identity, sobel_x, sobel_y,
  sharpen, laplacian) are standard image-processing masks. satmax and satmin are not
  filters; they exist to exercise the saturation paths.

## 17.2 Interface

- **No backpressure.** The core provides no `ready` signal. Flow control is source-side: the
  source presents exactly 1024 pixels per frame and holds the next frame until `busy` falls.
  `valid_in` may deassert on any cycle; the core stalls coherently.
- **`busy` falls three cycles before the final `valid_out`**, because the last window is
  already committed to the pipeline. A consumer must count `valid_out` pulses or wait for
  `frame_done`, not treat the falling edge of `busy` as end-of-data.
- **Coefficient writes are accepted only while `busy` is low.** The write port is ignored
  during a frame, so a kernel cannot change mid-frame.
- **Input is raster order, one pixel per cycle**, left-to-right then top-to-bottom, with
  arbitrary stalls permitted.
- **Reset is synchronous and active-low**, and is assumed to be held for at least one clock
  and released synchronously. A board-level design would add a two-flop synchroniser in the
  wrapper.

## 17.3 Analysis and Reporting

- **FoM power unit is watts.** The specification gives no unit; `report_power` reports
  watts.
- **FoM evaluated at 125 MHz**, the constrained and verified frequency and the clock at
  which the SAIF was captured (Section 16.2).
- **I/O timing is excluded from timing closure.** The core has no external interface timing
  contract; reported Fmax is the internal register-to-register limit (Section 13.2).
- **Power-analysis conditions are the Vivado defaults**: 25 C ambient, ThetaJA 11.5 C/W,
  250 LFM airflow, no heat sink, 10 x 10 inch medium board, commercial grade, typical
  process. No board-level power measurement was made.
- **COEF_FRAC is declared but not implemented.** The package carries the toggle for a
  Q1.7 coefficient format, but no shift or rounding stage exists in the RTL. The submitted
  build is Q8.0 integer and no results are claimed for Q1.7.

---

# 18. Bonus Features

| Bonus | Claimed | Evidence |
|---|---|---|
| One output pixel per cycle, pipelined | **Yes** | `valid_out` unbroken for 1024 consecutive cycles (Figure 11.3); 22/22 regression runs; 3-stage pipeline (Section 3) |
| Support for multiple kernels | **Yes** | 9 coefficients programmable through the write port; 5 functional kernels verified bit-exact; kernel reloaded between frames in the back-to-back run (Section 9.4) |
| ReLU activation | **Yes** | `RELU` parameter; a second full instance with RELU=1 runs on identical stimulus and is checked against ReLU reference outputs on all 7 kernels |
| Edge-detection demo | **Yes**, in simulation | Figures 18.1-18.3, rendered from `hw_out/` - the hardware outputs, not the reference model |
| Board demonstration | **No** | see below |

**On the board demonstration.** A bitstream (`fpga/top.bit`) was generated for the real
PYNQ-Z2 pinout, and every one of the 42 pins is assigned to a user-accessible connector -
Pmod A for pixel input, Pmod B for coefficient data, the Arduino header for control, the
Raspberry Pi header for the 16-bit output, SW0 for reset and LED0/1 for status. The design
is therefore implementable and loadable. It was not demonstrated on hardware: no board was
available, and a demonstration would additionally require a wrapper to drive the pixel
stream (from the Zynq PS over AXI, or a UART bridge) plus a reset synchroniser. This bonus
is **not claimed**.

**Figure 18.1** - docs/figures/edge_demo_sobel_x.png - input image (left) beside the
accelerator's sobel_x output (right), rendered directly from hw_out/sobel_x_out.hex

**Figure 18.2** - docs/figures/edge_demo_sobel_y.png - vertical gradient

**Figure 18.3** - docs/figures/edge_demo_laplacian.png - Laplacian edge response

---

# 19. Conclusion

A 3x3 convolution accelerator with programmable coefficients was designed, verified and
implemented on a Zynq-7000 xc7z020, meeting every mandatory specification and claiming four
of the five bonus features.

**Results.** 879 LUTs, 441 flip-flops, **zero DSP blocks and zero block RAMs**, 1.65 % of
the target device. Timing closes at the 125 MHz constraint with +0.742 ns of slack, giving
a maximum frequency of 137.8 MHz with no failing endpoints. Total power is 0.158 W from a
switching-activity file captured over active convolution. The Figure of Merit is
**7.20e-3**.

**Correctness.** The accelerator produces one output pixel per clock, gapless within a
frame, at a latency of 37 cycles. Its output is byte-identical to an independently written
Python reference model across 22 regression runs covering seven kernels, three stall
regimes, both ReLU builds and a back-to-back frame pair with a kernel change between them.
The comparison is exact rather than tolerance-based, and is independently checkable by
diffing the fourteen `hw_out/` files against the reference outputs.

**What the design does well.** The two structural decisions that dominate the Figure of
Merit are keeping the line buffers in fabric shift registers (16 LUTs as SRLC32E, avoiding a
100-LUT-equivalent BRAM penalty) and forcing the nine multipliers into LUTs (avoiding 450
LUT-equivalents of DSP penalty). The strict control/datapath split - every counter and flag
in one module, every arithmetic element in the others - made both the unit testing and the
stall behaviour straightforward, and the free-running pipeline with a travelling valid bit
handles arbitrary input stalls with no additional control logic.

**What was learned.** Three findings are worth recording. First, measurement beat design:
capturing a proper switching-activity file improved the Figure of Merit by 14.6 %, against
roughly 0.3 % from the RTL optimisations, because the design's own logic accounts for only
about 6 % of the power term while static power and I/O account for 95 %. Second, an
optimisation that bought nothing in its own terms - the saturation rewrite, which saved
2 LUTs and no timing - was the change that exposed an untested path in the design, because
no real kernel ever reaches the clamp. Third, the counter that looked redundant was not:
modelling the change before trusting it caught a frame-accounting error that would have
produced 1059 inputs and 1058 outputs, and the offset that made it wrong is the same
asymmetry that makes the fill and drain lengths equal.

**Characterised but not implemented.** Replicating the edge-flag registers to break a
156-load net (estimated 0.5-1 ns), reducing output drive strength from 12 mA to 4 mA
(estimated ~10 % of total power), and constant-coefficient multipliers (roughly 50 % FoM
improvement, rejected because it forfeits the mandatory programmability requirement).

---

# Appendix A - Submitted Files

| Deliverable | Path | Contents |
|---|---|---|
| RTL source | `rtl/` | 7 SystemVerilog files, 417 lines |
| Testbenches | `tb/` | 4 testbenches: full regression, single kernel, window integration, window unit |
| Golden model | `golden_model/golden.py` | Python/NumPy reference, 80 lines |
| Input test image | `golden_model/hex/image.hex`, `golden_model/cat.png` | 32 x 32 grayscale, 1024 lines of 8-bit hex |
| Coefficient files | `golden_model/hex/<kernel>_coef.hex` | 7 kernels, 9 lines each, write-port order |
| Expected outputs | `golden_model/hex/<kernel>_out.hex`, `_relu_out.hex` | 14 files, 1024 lines of 16-bit hex |
| **Hardware outputs** | `hw_out/` | 14 files produced by the RTL; byte-identical to the expected outputs |
| Window vectors | `golden_model/vectors/` | 5 patterns, 1024 windows each, for window-level checking |
| FPGA reports | `fpga/reports/` | utilization, utilization_hier, synth_utilization, synth.log, timing_summary, paths, power, drc, io |
| Constraints | `fpga/pynq_z2.xdc` | clock, 42 pin assignments, I/O false paths |
| Bitstream | `fpga/top.bit` | xc7z020clg400-1, PL-only |
| Build scripts | `fpga/build.tcl`, `fpga/saif.bat`, `fpga/paths.tcl` | implementation flow, SAIF capture, per-stage timing |
| Simulation scripts | `sim/compile.do`, `sim/run.do`, `sim/waves/` | compile order, regression driver, one script per waveform figure |
| Figures | `docs/figures/` | 10 waveform captures, 3 edge-detection renders |
| Presentation | submitted separately | 11 slides |

**Reproducing the results**

```
do sim/compile.do
do sim/run.do all                              22 runs, regenerates hw_out/

cd golden_model && python golden.py hex/image.hex     regenerates the reference files

fpga\saif.bat                                  captures the SAIF (Vivado xsim)
vivado -mode tcl                               then: source fpga/build.tcl
```

`sim/run.do all` runs the full regression and writes all 14 hardware output files.
`fpga/build.tcl` performs synthesis, implementation and all reports, reading the SAIF
automatically if it is present.
