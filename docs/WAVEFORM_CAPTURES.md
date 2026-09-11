# Waveform captures for the report

One screenshot per claim. All of them come out of `tb_top` except the window ones.

    do sim/compile.do
    do sim/run.do sobel_x        (do sim/run.do sobel_x 1  for the stall capture)
    do sim/waves/latency.do      sets up signals, radix, grid, cursors, zoom
    File > Export > Image        cleaner than a screen grab, no window chrome

| # | capture | proves | script | run | status |
|---|---|---|---|---|---|
| 1 | fill latency | 37 cycles first `valid_in` -> first `valid_out` | `latency.do` | `sobel_x` | have: `Latency.PNG`, `busy_latency.PNG` |
| 2 | kernel load | coefficients are programmable, loaded while `busy` is low | `coeff.do` | `sobel_x` | have: `Coeff_loading.PNG` |
| 3 | throughput | `valid_out` solid high, new pixel every cycle - the 1 px/cycle bonus | `throughput.do` | `sobel_x` | have: `full_throughput.PNG` - make sure it is zoomed to ~30 cycles so single transitions are visible, not the whole frame |
| 4 | stall | window freezes on `valid_in` low, bubble reaches `valid_out` 3 cycles later, nothing lost | `stall.do` | `sobel_x 1` | take now |
| 5 | edges | zero padding: taps 2,5,8 masked at col 31, taps 0,3,6 at col 0, centre never | `edges.do` | `sobel_x` | take now |
| 6 | drain | input stops, FSM drains 34 more windows, exactly 1024 outputs, then DONE | `drain.do` | `sobel_x` | take now |
| 7 | fsm | IDLE > FILL > STREAM > DRAIN > DONE > IDLE over a frame, counters visible | `fsm.do` | `sobel_x` | have: `Full_run.PNG` - check `in_cnt`/`drain_cnt` are in it, otherwise retake |
| 8 | window taps | 3x3 window sliding, first and last valid windows | - | `window` / `unit` | have: `Window_generator_*.PNG` x3 |

So 4, 5, 6 are new and can be taken right now. Everything else is either done or a retake for legibility.

## Captions

Write the number you can read off the cursors into the caption, the judges should not have to trust the text.

1. Cursor 1 at `valid_in` rising (145 ns), cursor 2 at `valid_out` rising (515 ns). 370 ns = 37 cycles at 100 MHz: 34 for the window to fill (line buffer depth 32 + 2 tap shifts) + 3 datapath stages. Coefficient writes finish before the frame starts.
2. Nine `write_en` pulses with `write_addr` 0..8 and the sobel_x coefficients on `data_write`, `busy` low throughout. `coef_reg` fills up as they land.
3. Mid frame. `valid_out` stays high and `pixel_out` changes every cycle - sustained one output pixel per clock.
4. `valid_in` dropped for 3 cycles before pixel 300. `en` follows it, the taps hold their values, `win_valid` drops for the same 3 cycles and `valid_out` shows the same 3-cycle gap exactly 3 clocks later. No pixel lost or duplicated.
5. Output column 31 then column 0. `right_edge` zeros taps c, f, i; next cycle `left_edge` zeros a, d, g. Tap e (centre) is never masked. This is the zero padding.
6. Last pixel in at 10385 ns, FSM enters DRAIN and keeps `en` high with junk on the bus, `bottom_edge`/`right_edge` mask it. Output count reaches 1024 and `frame_done` asserts. `busy` drops 3 cycles before the final `valid_out` - the last outputs are already in the pipeline.
7. Full frame, zoomed out. State sequence with `in_cnt` counting to 1023 and `drain_cnt` to 33.

## ModelSim notes

- 2020.1 has no "cycles" timeline unit, only fs..hr. `setup.do` puts the timeline in ns with one gridline per 10 ns so cycles can be counted by eye.
- Never drag a cursor onto an edge. Click the signal, then Tab / Shift+Tab (find next / previous transition) - the cursor lands exactly on the edge and the delta is a whole number of cycles. A delta like 198.333 ns means a cursor is off an edge.
- The `.do` scripts put cursors at fixed times. Those times hold as long as the reset / coefficient-load prelude in `tb_top` doesn't change (first pixel at 145 ns).
- `pixel_out` in decimal, `state` as the enum name, taps in hex. Binary is unreadable at report size.
- Keep 6-9 signals per capture. Delete anything the caption doesn't mention.
