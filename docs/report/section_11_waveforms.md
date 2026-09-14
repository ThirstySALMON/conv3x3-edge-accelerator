# 11. Waveform Screenshots

Every capture below comes from ModelSim running the submitted RTL. The timeline is in
nanoseconds and the grid is set to one line per 10 ns clock period, so cycles can be counted
off the picture directly. Cursors were snapped to clock edges rather than dragged, which is
why the deltas come out as whole numbers of cycles.

Each figure can be regenerated with `do sim/waves/<script>.do` after running the
corresponding simulation.

## 11.1 Fill Latency

**Figure 11.1** - docs/figures/waveforms/Latency.PNG

*The first pixel is accepted at 145 ns and the first output appears at 515 ns. The 370 ns
between the cursors is 37 clock cycles: 34 to fill the window and 3 for the pipeline. The
nine coefficient writes are visible to the left of the first cursor, completed while busy is
still low.*

This is the number quoted in Table 1 for latency. It is worth noting what it is measured
from - the first *accepted* pixel, not the first clock after reset - because the coefficient
load happens before streaming begins and is not part of the latency figure.

## 11.2 Kernel Load

**Figure 11.2** - docs/figures/waveforms/kernel_load.PNG

*Nine consecutive write_en pulses with write_addr stepping 0 through 8 and the sobel_x
coefficients on data_write. busy is low throughout, which is the condition coeff_reg
requires before it will accept a write.*

The specification asks for programmable coefficients. This shows them arriving through the
actual write port during simulation rather than being loaded by an initial block, which is
the distinction that matters.

## 11.3 Sustained Throughput

**Figure 11.3** - docs/figures/waveforms/throughput.PNG

*The whole frame. valid_out goes high at 515 ns and stays high until 10755 ns without a
single break - 10240 ns, or 1024 consecutive clock cycles, one output pixel per clock for
the entire frame.*

This is the evidence behind the one-pixel-per-cycle bonus claim. An unbroken bar is a
stronger demonstration than a zoomed view of a few cycles would be, since a gap anywhere in
the frame would show up as a notch.

## 11.4 Stall Behaviour

**Figure 11.4** - docs/figures/waveforms/stall.PNG

*valid_in is deasserted for three cycles just before pixel 300. en follows it down, the nine
tap registers hold their values, and win_valid drops. Three cycles later the same three-cycle
gap appears in valid_out.*

Nothing is lost and nothing is repeated - the stall simply becomes a bubble that travels
through the pipeline alongside the data. The three-cycle offset between the input gap and
the output gap is the pipeline depth, and the testbench checks that relationship on every
cycle of every run.

## 11.5 Border Padding

**Figure 11.5** - docs/figures/waveforms/edges.PNG

*A row boundary. At output column 31 right_edge is asserted and taps c, f and i read zero.
One cycle later out_c wraps to 0, left_edge asserts instead, and taps a, d and g read zero.
The centre tap is never masked.*

This is zero-padded "same" convolution as it actually happens: the masks are combinational,
driven by flags the FSM registers one position ahead, so the correct taps are already zeroed
on the cycle the window is used.

## 11.6 End of Frame

**Figure 11.6** - docs/figures/waveforms/drain.PNG

*The last input pixel arrives at 10385 ns. The FSM moves into DRAIN and keeps producing
outputs for 34 more cycles with no input at all, reaching exactly 1024 outputs before
frame_done pulses.*

busy falls three cycles before the final valid_out, which looks wrong at first glance but is
not: by then the last window has already been latched into the pipeline and only has to
travel through it. A consumer should count valid_out pulses or watch frame_done rather than
treat the falling edge of busy as the end of the data.

## 11.7 Frame Sequence

**Figure 11.7** - docs/figures/waveforms/fsm.PNG

*One complete frame through IDLE, FILL, STREAM, DRAIN, DONE and back to IDLE, with in_cnt,
out_r and drain_cnt visible as the counters that drive each transition.*

The state durations are 34, 990, 34 and 1 enabled cycles. STREAM is 990 rather than 1024
because the input counter is already at 34 when the state is entered - the fill cycles
consumed pixels too. Outputs come from STREAM and DRAIN together, 990 + 34, which is where
the 1024 comes from.

## 11.8 Window Generator Unit Test

**Figures 11.8 to 11.10** - docs/figures/waveforms/Window_generator_producing_valid_taps.PNG,
_valid_taps2.PNG, _last_valid_taps.PNG

*The 3x3 window sliding across the image in the direct-driven unit testbench: the first
complete window, an interior window part way through the frame, and the final window.*

These come from the unit testbench, where en and the four edge flags are driven by hand with
no FSM present. That isolation is the point - if the taps are wrong here, the fault is in
window_gen and not in the control logic.

## Capture Index

| Figure | File | Simulation run | Script | Cursors |
|---|---|---|---|---|
| 11.1 | Latency.PNG | sobel_x | latency.do | 145 / 515 ns |
| 11.2 | kernel_load.PNG | sobel_x | coeff.do | - |
| 11.3 | throughput.PNG | sobel_x | throughput.do | 515 / 10755 ns |
| 11.4 | stall.PNG | sobel_x, +STALL=1 | stall.do | 3165 / 3195 ns |
| 11.5 | edges.PNG | sobel_x | edges.do | 795 / 805 ns |
| 11.6 | drain.PNG | sobel_x | drain.do | 10385 / 10755 ns |
| 11.7 | fsm.PNG | sobel_x | fsm.do | - |
| 11.8-11.10 | Window_generator_*.PNG | unit testbench | - | - |
