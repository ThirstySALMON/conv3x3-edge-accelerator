# 1. Accelerator Architecture

The accelerator applies a 3x3 same (zero-padded) convolution to a 32x32 grayscale image,
consuming one pixel and producing one output pixel per clock. Kernel coefficients are
programmable at run time. The input is 8-bit unsigned, coefficients are 8-bit signed, and
the output is 16-bit signed with saturation; ReLU is available as a build-time option.

## 1.1 Control and Datapath Split

The design separates position from data, and this separation is its principal
architectural decision.

**control_fsm** (rtl/control_unit.sv) owns every counter and flag in the design: the state
register, the input counter, the output row and column counters, the drain counter and the
four registered edge flags. It never sees a pixel.

**The datapath** - window_gen, coeff_reg, the nine multipliers and the adder tree - holds
data and no position state. window_gen contains no counters and produces no valid signal; it
shifts when told to and applies whatever masks it is given.

Only five signals cross the boundary: `en` and the four edge flags into window_gen, `busy`
into coeff_reg as a write lock, and `win_valid` into the valid chain. The benefit is
practical: window_gen can be unit-tested by direct-driving `en` and the flags with no FSM
present, and all stall behaviour lives in one module rather than being distributed across
every sequential element.

## 1.2 Processing Chain

```
input_in ──► window_gen ──► 9 taps ──► 9 multipliers ──► prod_r  (stage 1)
                                            ▲
             coeff_reg ──► 9 coefficients ──┘
                                     ──► 3 row adders ──► row_r  (stage 2)
                                     ──► final adder ──► saturate ──► ReLU ──► pixel_out (stage 3)
```

Window generation uses two 32-deep 8-bit line buffers in series - LB0 fed from input_in,
LB1 from LB0 - plus nine tap registers and combinational zero-padding masks (Section 6).
The arithmetic is three pipeline stages deep, with a valid bit travelling alongside the
data: `win_valid → v_prod → v_row → valid_out` (Section 3).

## 1.3 Frame Sequence

A frame passes through five states: **IDLE → FILL → STREAM → DRAIN → DONE**. FILL consumes
34 pixels while the window primes; STREAM consumes and outputs simultaneously for 990
cycles; DRAIN produces the final 34 outputs with no input remaining; DONE pulses
`frame_done`. Since a frame must consume 1024 pixels and produce 1024 outputs, the
consume-only and output-only cycle counts are necessarily equal - which is why FILL and
DRAIN are both 34 cycles (Section 4).

## 1.4 Interface

The core presents 42 pins:

| Group | Signals | Pins |
|---|---|---|
| Clock and reset | clk, rst_n (active-low, synchronous) | 2 |
| Pixel input | input_in[7:0], valid_in | 9 |
| Kernel write port | write_en, write_addr[3:0], data_write[7:0] | 13 |
| Pixel output | pixel_out[15:0] (signed), valid_out | 17 |
| Status | busy | 1 |

Coefficients are loaded through the write port with `write_addr = 3*row + col` (0 to 8,
row-major, matching the tap order); writes are ignored while `busy` is asserted, so a kernel
cannot change mid-frame but may be reloaded between frames.

There is no backpressure signal. `valid_in` may deassert on any cycle: `en` follows it,
freezing the line buffers, tap registers and counters together so the window stays coherent,
while the pipeline registers keep clocking and the valid chain carries the resulting bubble
to the output three cycles later. Flow control is therefore source-side - the source
presents exactly 1024 pixels per frame and holds the next until `busy` falls.

**Latency is 37 cycles** from the first accepted pixel to the first output: 34 window-fill
cycles plus 3 pipeline stages. **Throughput is 1.0 output pixel per cycle**, gapless within
a frame, or 0.965 averaged across a complete frame including fill and drain (1024 outputs
over 1061 cycles).

## 1.5 Design Decisions Serving the Figure of Merit

The Figure of Merit rewards throughput per cycle and penalises LUTs, DSP blocks at 50
LUT-equivalents each and block RAMs at 100. Three decisions follow from that weighting, and
each is quantified in Section 15.

**Nine parallel multipliers** consume the entire 3x3 window every cycle, giving one output
pixel per clock. A three-multiplier design would remove roughly 320 LUTs but cut throughput
to a third - the numerator is linear in throughput while the denominator falls only
sub-linearly, so full parallelism wins on this metric. It also claims the named
one-pixel-per-cycle bonus.

**Zero block RAM.** The line buffers hold 512 bits total. Vivado infers them as 16 SRLC32E
shift-register primitives occupying 16 LUTs, against the 100 LUT-equivalents a single BRAM
tile would cost - a tile that would be 1.4% occupied.

**Zero DSP blocks.** The `use_dsp = "no"` attribute plus `-max_dsp 0` at synthesis keeps all
nine multipliers in fabric at 496 LUTs, against the 450 LUT-equivalents nine DSP48E1 blocks
would count. Close to neutral on the denominator alone, but it keeps the design in one
fabric type with one power model, and leaves the RTL vendor-neutral apart from that single
attribute.

**Programmability was preserved over area.** Every kernel demonstrated uses only the
coefficients 0, ±1, ±2, ±4 and 5 - all implementable as shifts and adds. Hardcoding them
would save roughly 300 LUTs and improve the Figure of Merit by about 50%, but specification
item 3 requires programmable coefficients, and forfeiting a mandatory requirement to win a
tiebreaker metric is the wrong trade.

## 1.6 Summary of Results

| | |
|---|---|
| Device | xc7z020clg400-1 (PYNQ-Z2), Vivado 2025.2 |
| Resources | 879 LUTs, 441 FFs, **0 DSP, 0 BRAM** |
| Timing | WNS +0.742 ns at 125 MHz; Fmax 137.8 MHz; 0 failing endpoints |
| Power | 0.158 W total (0.107 static, 0.052 dynamic), SAIF-annotated |
| **Figure of Merit** | **7.20e-3** at 125 MHz |
| Verification | 22/22 regression runs pass; hardware outputs byte-identical to the reference model |

Details are in Sections 12 to 16; the verification methodology is in Section 9 and the
assumptions made are listed in Section 17.

**Table 1.1 - Design parameters** (from rtl/cnn_pkg.sv)
