
`timescale 1ns/1ps
import cnn_pkg::*;

// everything in one run: each kernel clean / fixed stalls / random stalls, two
// frames back to back with a kernel swap in between, and a RELU=1 copy of top
// on the same stimulus. writes hw_out/<kernel>_out.hex and _relu_out.hex.
//   do sim/run.do all
module tb_top_all;

localparam string HEX = "golden_model/hex/";
// satmax/satmin are not real filters, they push the accumulator past +/-32767 so the
// saturation branches get exercised instead of only being argued about on paper.
string KERNELS [7] = '{"identity", "sobel_x", "sobel_y", "sharpen", "laplacian",
                       "satmax", "satmin"};

logic clk = 0, rst_n = 0;
logic [IN_W-1:0]    input_in;
logic               valid_in   = 0;
logic               write_en   = 0;
logic [3:0]         write_addr = 0;
logic [7:0]         data_write = 0;
logic signed [15:0] pix, pix_r;
logic               vo, vo_r, busy, busy_r;

top dut (
    .clk(clk), .rst_n(rst_n), .input_in(input_in), .valid_in(valid_in),
    .write_en(write_en), .write_addr(write_addr), .data_write(data_write),
    .pixel_out(pix), .valid_out(vo), .busy(busy)
);

top #(.RELU(1'b1)) dut_r (   // same thing with relu on
    .clk(clk), .rst_n(rst_n), .input_in(input_in), .valid_in(valid_in),
    .write_en(write_en), .write_addr(write_addr), .data_write(data_write),
    .pixel_out(pix_r), .valid_out(vo_r), .busy(busy_r)
);

always #5 clk = ~clk;

logic [7:0]  img [0:NPIX-1];
logic [15:0] exp_q[$], exp_rq[$];         // next expected outputs, one queue per dut
logic [15:0] hw [0:NPIX-1], hw_r [0:NPIX-1];
logic [15:0] e, er;

int cyc = 0, out_cnt, pix_err, pix_err_r, lat_err, bubbles, stall_cyc, stall_stream;
int first_out, last_out, runs = 0, fails = 0;
logic [2:0] wv_d = '0;
bit win_started;

always @(posedge clk) if (rst_n) begin
    cyc++;
    wv_d <= {wv_d[1:0], dut.win_valid};
    if (vo !== wv_d[2] || vo_r !== vo) lat_err++;
    if (dut.win_valid) win_started = 1;
    if (!valid_in && dut.u_cu.state == 2 && win_started) stall_stream++;   // 2 = S_STREAM. a stall before the first window only delays it
    if (vo) begin
        if (first_out < 0) first_out = cyc;
        else bubbles += cyc - last_out - 1;
        last_out = cyc;
        if (exp_q.size() == 0)
            pix_err++;                                        // more outputs than expected
        else begin
            e  = exp_q.pop_front();
            er = exp_rq.pop_front();
            if (out_cnt < NPIX) begin hw[out_cnt] = pix; hw_r[out_cnt] = pix_r; end
            if (pix !== e) begin
                if (pix_err < 5) $display("    mismatch %0d: got %0d exp %0d", out_cnt, pix, $signed(e));
                pix_err++;
            end
            if (pix_r !== er) begin
                if (pix_err_r < 5) $display("    relu mismatch %0d: got %0d exp %0d", out_cnt, pix_r, $signed(er));
                pix_err_r++;
            end
        end
        out_cnt++;
    end
end

task automatic clear_run();
    out_cnt = 0; pix_err = 0; pix_err_r = 0; lat_err = 0; bubbles = 0;
    stall_cyc = 0; stall_stream = 0; first_out = -1; last_out = -1; win_started = 0;
    exp_q.delete(); exp_rq.delete();
endtask

// coeffs through the port (only accepted while !busy), then queue up what we expect
task automatic load(input string k);
    logic [7:0]  c [0:NTAP-1];
    logic [15:0] g [0:NPIX-1];
    $readmemh({HEX, k, "_coef.hex"}, c);
    for (int i = 0; i < NTAP; i++) begin
        write_en <= 1; write_addr <= i; data_write <= c[i];
        @(posedge clk);
    end
    write_en <= 0;
    @(posedge clk);
    $readmemh({HEX, k, "_out.hex"}, g);      foreach (g[i]) exp_q.push_back(g[i]);
    $readmemh({HEX, k, "_relu_out.hex"}, g); foreach (g[i]) exp_rq.push_back(g[i]);
endtask

// 0 clean, 1 a few fixed stalls, 2 random: ~1 in 5 pixels held off 1-4 cycles
function automatic int stall_len(input int i, input int mode);
    if (mode == 1) case (i)
        10: return 2; 300: return 3; 511: return 1; 700: return 8; 1023: return 4;
        default: return 0;
    endcase
    if (mode == 2) return ($urandom % 5 == 0) ? $urandom % 4 + 1 : 0;
    return 0;
endfunction

task automatic stream(input int mode);
    for (int i = 0; i < NPIX; i++) begin
        repeat (stall_len(i, mode)) begin
            valid_in <= 0; input_in <= 8'hA5; stall_cyc++;
            @(posedge clk);
        end
        valid_in <= 1; input_in <= img[i];
        @(posedge clk);
    end
    valid_in <= 0; input_in <= 8'hA5;
endtask

task automatic finish_frame();
    wait (!busy);
    repeat (8) @(posedge clk);       // last 3 outputs are still in the pipe when busy drops
endtask

task automatic report(input string name, input int nframes, input bit check_bubbles);
    bit ok = out_cnt == nframes*NPIX && pix_err == 0 && pix_err_r == 0 && lat_err == 0
             && exp_q.size() == 0 && (!check_bubbles || bubbles == stall_stream);
    runs++;
    if (!ok) fails++;
    $display("  %-34s out=%0d err=%0d relu_err=%0d stalls=%0d bubbles=%0d/%0d lat_err=%0d  %s",
             name, out_cnt, pix_err, pix_err_r, stall_cyc, bubbles, stall_stream, lat_err,
             ok ? "ok" : "FAIL");
endtask

task automatic dump(input string k);
    int fh;
    fh = $fopen({"hw_out/", k, "_out.hex"}, "w");
    if (fh) begin foreach (hw[i]) $fdisplay(fh, "%04h", hw[i]); $fclose(fh); end
    fh = $fopen({"hw_out/", k, "_relu_out.hex"}, "w");
    if (fh) begin foreach (hw_r[i]) $fdisplay(fh, "%04h", hw_r[i]); $fclose(fh); end
endtask

initial begin
    $readmemh({HEX, "image.hex"}, img);
    $dumpfile("sim/out/tb_top_all.vcd");
    $dumpvars(0, tb_top_all);
    void'($urandom(1));

    repeat (4) @(posedge clk);
    rst_n <= 1;
    @(posedge clk);

    $display("--------------------------------------------------------------");
    foreach (KERNELS[k])
        for (int mode = 0; mode < 3; mode++) begin
            clear_run();
            load(KERNELS[k]);
            stream(mode);
            finish_frame();
            report({KERNELS[k], mode == 0 ? "" : mode == 1 ? " +stalls" : " +random stalls"}, 1, 1);
            if (mode == 0) dump(KERNELS[k]);
        end

    // two frames with no idle gap. new coeffs go in the moment busy drops,
    // while frame 1's last three outputs are still coming out.
    clear_run();
    load("sobel_x");
    stream(0);
    wait (!busy);
    load("sharpen");
    stream(0);
    finish_frame();
    report("sobel_x -> sharpen, back to back", 2, 0);

    $display("--------------------------------------------------------------");
    $display("  %0d runs, %0d failed   %s", runs, fails, fails == 0 ? "PASS" : "FAIL");
    $display("--------------------------------------------------------------");
    $finish(2);
end

endmodule
