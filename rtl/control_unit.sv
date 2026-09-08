import cnn_pkg::*;
module control_fsm (
    input  logic clk,
    input  logic rst_n,
    input  logic valid_in,

    output logic en,
    output logic win_valid,
    output logic top_edge,
    output logic bottom_edge,
    output logic left_edge,
    output logic right_edge,
    output logic busy,
    output logic frame_done
);

 typedef enum logic [2:0] {
        S_IDLE, S_FILL, S_STREAM, S_DRAIN, S_DONE
    } state_e;

    state_e state, next;

    logic [$clog2(NPIX)-1:0]         in_cnt;
    logic [$clog2(IMG_W)-1:0]        out_c;
    logic [$clog2(IMG_H)-1:0]        out_r;
    logic [$clog2(DRAIN_CYCLES)-1:0] drain_cnt;
    logic                            consume, out_adv, last_consume;

        always_comb begin
        case (state)
            S_DRAIN: en = 1'b1;
            S_DONE:  en = 1'b0;
            default: en = valid_in;
        endcase
    end

    assign top_edge    = (out_r == 0);
    assign bottom_edge = (out_r == IMG_H-1);
    assign left_edge   = (out_c == 0);
    assign right_edge  = (out_c == IMG_W-1);

    assign consume = en && (state != S_DRAIN);
    assign out_adv = en && (state == S_STREAM || state == S_DRAIN);

    
    assign last_consume = consume && (in_cnt == NPIX-1);


    assign win_valid  = out_adv;
    assign busy       = (state != S_IDLE) && (state != S_DONE);
    assign frame_done = (state == S_DONE);


    always_comb begin
        next = state;
        case (state)
            S_IDLE:   if (valid_in)                              next = S_FILL;
            S_FILL:   if (valid_in && in_cnt == FILL_CYCLES-1)   next = S_STREAM;
            S_STREAM: if (last_consume)                          next = S_DRAIN;
            S_DRAIN:  if (drain_cnt == DRAIN_CYCLES-1)           next = S_DONE;
            S_DONE:                                              next = S_IDLE;
            default:                                             next = S_IDLE;
        endcase
    end

     always_ff @(posedge clk) begin           // synchronous reset (intentional)
        if (!rst_n) begin
            state     <= S_IDLE;
            in_cnt    <= '0;
            out_r     <= '0;
            out_c     <= '0;
            drain_cnt <= '0;
        end else begin
            state <= next;

            if (consume)
                in_cnt <= (in_cnt == NPIX-1) ? '0 : in_cnt + 1;

            if (out_adv) begin
                if (out_c == IMG_W-1) begin
                    out_c <= '0;
                    out_r <= (out_r == IMG_H-1) ? '0 : out_r + 1;
                end else begin
                    out_c <= out_c + 1;
                end
            end

            drain_cnt <= (state == S_DRAIN) ? (drain_cnt + 1) : '0;
        end
    end

endmodule 