# Block diagram: what to change before it goes in the report

Against the hand-drawn datapath diagram from the start of the project. The datapath itself
is still right - 9 multipliers, 9x16b register, 3 adders, 3x18b register, adder, saturate,
relu, output register - so this is a list of corrections and annotations, not a redraw.

The announcement asks for a block diagram AND a datapath diagram as separate sections.
Suggest two figures: a 5-box block diagram showing the control / datapath split, and the
existing detailed drawing updated as the datapath figure.

## Corrections (the drawing is wrong without these)

1. **Edge flags come out of registers now.** top/bottom/left/right_edge leave control_fsm
   from flip-flops, computed one position ahead (nxt_r / nxt_c). Draw a register on each
   of the four arrows into the window generator. This is the change that moved the critical
   path off the comparator.

2. **Saturate block is a sign-extension check, not two comparators.** If the block has
   any internal detail, it is: acc[19:15] all-equal -> pass acc[15:0], else clamp by sign
   bit. Label it "sat (top-bits check)" or similar.

3. **valid chain runs alongside the three register stages.** The three valid_out reg boxes
   are correct in count but should sit level with the 9x16b, 3x18b and output registers -
   the point is the valid bit travels with the data through the same three stages.

## Annotations (the drawing is incomplete without these)

4. **LB0 / LB1: "inferred as 2 x SRL32E, 16 LUTs, 0 BRAM".** The FoM story lives here.
   Keep them drawn as 32x8 delay lines, add the annotation.

5. **ReLU: mark as RELU parameter, default off.** Otherwise a reader assumes it is always
   in the path.

6. **Draw the three pipeline stage boundaries** as dashed vertical lines through the
   datapath: after the multipliers, after the row adders, after saturate/relu. Label them
   stage 1/2/3. Table 1 has a "pipeline stages" row and this is the picture for it.

7. **Latency 37 = 34 fill + 3 stages**, written on the figure near the output.

8. **Control unit outputs:** en, win_valid, 4 edge flags (registered), busy, frame_done.
   The drawing only shows busy leaving. frame_done is internal to top but worth showing.

9. **I/O count: 42 pins**, clk + rst_n + 8 in + 1 valid_in + 13 write port + 16 out +
   valid_out + busy. Mention at the boundary - it explains why I/O is 27% of the power.

## Block diagram (new figure, 5 boxes)

    input_in, valid_in --> [ window_gen ] --taps[9]--> [ 9 x mult + adder tree ] --> [ sat / relu ] --> pixel_out
                               ^   ^                          ^                                          valid_out
                               |   |                          |
                       en   edge flags[4]               coef[9]
                               |   |                          |
    valid_in --------> [ control_fsm ] --busy--> [ coeff_reg ] <-- write_en / write_addr / data_write
                              |
                              +--> win_valid --> (3-stage valid chain) --> valid_out
                              +--> busy, frame_done

The control / datapath split is the architectural claim: window_gen holds no position
state, control_fsm holds no data. Say so in the caption.

## FSM diagram

States and transitions are unchanged: IDLE -> FILL (valid_in) -> STREAM (in_cnt == 33)
-> DRAIN (last consume) -> DONE -> IDLE. Only the outputs changed: the edge flags are
registered outputs of the FSM rather than combinational decodes of out_r / out_c. If the
diagram lists outputs per state, note that.
