
`timescale 1ns/1ps
import cnn_pkg::*;

// window_gen + control_fsm checked at the top level: taps, raster position,
// edge flags, gapless win_valid. pixel_out is not checked here
module tb_top_window;

logic  clk = 0;
logic  rst_n = 0;

logic [IN_W-1:0]  input_in;
logic             valid_in;
logic             write_en   = 1'b0;    // coefficients irrelevant here
logic [3:0]       write_addr = 4'd0;
logic [7:0]       data_write = 8'd0;
logic [15:0]      pixel_out;            
logic             valid_out;            
logic             busy;

top dut (
    .clk(clk), .rst_n(rst_n),
    .input_in(input_in), .valid_in(valid_in),
    .write_en(write_en), .write_addr(write_addr), .data_write(data_write),
    .pixel_out(pixel_out), .valid_out(valid_out), .busy(busy)
);

localparam real CLK_PERIOD = 10;
always #(CLK_PERIOD/2) clk=~clk;

initial begin
    $dumpfile("sim/out/tb_top_window.vcd");
    $dumpvars(0, tb_top_window);
end

// golden windows: NPIX lines x 9 bytes, row-major tap order
logic [7:0] gwin [0:NPIX*9-1];
initial $readmemh("golden_model/vectors/hramp_windows_same.hex", gwin);

int  cyc            = 0;   // cycles since reset release
int  win_cnt        = 0;   
int  tap_err        = 0;
int  pos_err        = 0;
int  gap_err        = 0;
int  first_win_cyc  = -1;
int  first_con_cyc  = -1;
int  last_win_cyc   = -1;
int  exp_r, exp_c;

function automatic string sname(input logic [2:0] s);
    case (s)
        3'd0: sname = "IDLE  ";
        3'd1: sname = "FILL  ";
        3'd2: sname = "STREAM";
        3'd3: sname = "DRAIN ";
        3'd4: sname = "DONE  ";
        default: sname = "??????";
    endcase
endfunction

logic [2:0] prev_state = 3'd0;
always @(posedge clk) if (rst_n) begin
    if (dut.u_cu.state !== prev_state)
        $display("  [cyc %4d] FSM %s -> %s   (in_cnt=%0d drain_cnt=%0d busy=%0b)",
                 cyc, sname(prev_state), sname(dut.u_cu.state),
                 dut.u_cu.in_cnt, dut.u_cu.drain_cnt, busy);
    prev_state = dut.u_cu.state;
end

// scoreboard, runs every win_valid cycle
always @(posedge clk) if (rst_n) begin
    cyc = cyc + 1;
    if (dut.en && first_con_cyc < 0) first_con_cyc = cyc;
    if (dut.win_valid) begin
        if (first_win_cyc < 0) first_win_cyc = cyc;
        else if (cyc != last_win_cyc + 1) begin
            gap_err = gap_err + 1;
            $display("  GAP: win %0d at cyc %0d, previous at %0d", win_cnt, cyc, last_win_cyc);
        end
        last_win_cyc = cyc;

        exp_r = win_cnt / IMG_W;
        exp_c = win_cnt % IMG_W;

        if (win_cnt < NPIX) begin
            for (int k = 0; k < NTAP; k++)
                if (dut.tap_out[k] !== gwin[win_cnt*9 + k]) begin
                    if (tap_err < 20)
                        $display("  TAP MISMATCH win %0d (r=%0d,c=%0d) tap%0d: got %02h exp %02h",
                                 win_cnt, exp_r, exp_c, k, dut.tap_out[k], gwin[win_cnt*9+k]);
                    tap_err = tap_err + 1;
                end

            if (dut.u_cu.out_r !== exp_r[$clog2(IMG_H)-1:0] ||
                dut.u_cu.out_c !== exp_c[$clog2(IMG_W)-1:0]) begin
                if (pos_err < 20)
                    $display("  POS MISMATCH win %0d: fsm(r,c)=(%0d,%0d) exp (%0d,%0d)",
                             win_cnt, dut.u_cu.out_r, dut.u_cu.out_c, exp_r, exp_c);
                pos_err = pos_err + 1;
            end

            if (dut.top_edge    !== (exp_r == 0)        ||
                dut.bottom_edge !== (exp_r == IMG_H-1)  ||
                dut.left_edge   !== (exp_c == 0)        ||
                dut.right_edge  !== (exp_c == IMG_W-1)) begin
                if (pos_err < 20)
                    $display("  EDGE MISMATCH win %0d (r=%0d,c=%0d): T/B/L/R=%0b%0b%0b%0b",
                             win_cnt, exp_r, exp_c,
                             dut.top_edge, dut.bottom_edge, dut.left_edge, dut.right_edge);
                pos_err = pos_err + 1;
            end
        end
        win_cnt = win_cnt + 1;
    end
end

integer i;                              

initial begin
    logic [7:0] in_hex[0:NPIX-1];
    $readmemh("golden_model/vectors/hramp_in.hex" , in_hex);

    rst_n = 0;
    repeat (4) @(posedge clk);
    rst_n <= 1;

    // stream the frame gapless, one pixel per cycle
    valid_in <= 1'b0;
    input_in <= 8'h00;
    @(posedge clk);

    for (i = 0; i < NPIX; i++) begin
        input_in <= in_hex[i];
        valid_in <= 1'b1;
        @(posedge clk);
    end

    // garbage on the bus during drain, bottom/right edge flags must mask it
    valid_in <= 1'b0;
    input_in <= 8'hA5;
    @(posedge clk);

    // let the FSM drain and retire
    i = 0;
    while (!dut.frame_done && i < 4*NPIX) begin
        @(posedge clk);
        i = i + 1;
    end
    repeat (4) @(posedge clk);

    $display("--------------------------------------------------------------");
    $display("  WINDOW GENERATION @ TOP");
    $display("  windows produced : %0d   (expected %0d)", win_cnt, NPIX);
    $display("  fill latency     : %0d cycles from first en to first win_valid (FILL_CYCLES = %0d)",
             first_win_cyc - first_con_cyc, FILL_CYCLES);
    $display("  last  win_valid  : cycle %0d", last_win_cyc);
    $display("  throughput       : %0d windows over %0d cycles",
             win_cnt, (last_win_cyc - first_win_cyc + 1));
    $display("  tap errors       : %0d", tap_err);
    $display("  position/edge err: %0d", pos_err);
    $display("  win_valid gaps   : %0d", gap_err);
    if (win_cnt == NPIX && tap_err == 0 && pos_err == 0 && gap_err == 0)
        $display("  PASS: taps + FSM correct, %0d gapless windows.", NPIX);
    else
        $display("  FAIL");
    $display("--------------------------------------------------------------");

    $finish(2);
end

endmodule
