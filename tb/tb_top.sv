
`timescale 1ns/1ps
import cnn_pkg::*;

// one frame through top, diffed against the golden hex, output saved to hw_out/<kernel>_out.hex
//   vsim work.tb_top +KERNEL=sobel_x            (default)
//   vsim work.tb_top +KERNEL=sharpen +STALL=1   drops valid_in a few times mid frame
module tb_top;

string kernel = "sobel_x";
int    stall  = 0;

logic clk = 0, rst_n = 0;
logic [IN_W-1:0]    input_in;
logic               valid_in   = 0;
logic               write_en   = 0;
logic [3:0]         write_addr = 0;
logic [7:0]         data_write = 0;
logic signed [15:0] pixel_out;
logic               valid_out, busy;

top dut (
    .clk(clk), .rst_n(rst_n),
    .input_in(input_in), .valid_in(valid_in),
    .write_en(write_en), .write_addr(write_addr), .data_write(data_write),
    .pixel_out(pixel_out), .valid_out(valid_out), .busy(busy)
);

always #5 clk = ~clk;

logic [7:0]  img  [0:NPIX-1];
logic [7:0]  coef [0:NTAP-1];
logic [15:0] gold [0:NPIX-1];
logic [15:0] hw   [0:NPIX-1];

int cyc = 0, out_cnt = 0, pix_err = 0, lat_err = 0;
int bubbles = 0, stall_cyc = 0, stall_stream = 0;
int first_in = -1, first_out = -1, last_out = -1;
int fh;
logic [2:0] wv_d = '0;      // win_valid delayed 1..3
bit win_started = 0;

// stalls to inject before pixel i when +STALL=1
function automatic int stall_len(input int i);
    if (!stall) return 0;
    case (i)
        10:      return 2;   // still filling, no bubble expected
        300:     return 3;
        511:     return 1;   // row boundary
        700:     return 8;
        1023:    return 4;   // right before the last pixel
        default: return 0;
    endcase
endfunction

always @(posedge clk) if (rst_n) begin
    cyc++;
    wv_d <= {wv_d[1:0], dut.win_valid};
    if (valid_out !== wv_d[2]) lat_err++;                   // valid_out is win_valid 3 cycles later, always
    if (dut.win_valid) win_started = 1;
    if (!valid_in && dut.u_cu.state == 2 && win_started) stall_stream++;   // 2 = S_STREAM. a stall before the first window only delays it
    if (valid_in && first_in < 0) first_in = cyc;
    if (valid_out) begin
        if (first_out < 0) first_out = cyc;
        else bubbles += cyc - last_out - 1;
        last_out = cyc;
        if (out_cnt < NPIX) begin
            hw[out_cnt] = pixel_out;
            if (pixel_out !== gold[out_cnt]) begin
                if (pix_err < 10)
                    $display("  mismatch %0d (r%0d c%0d): got %0d exp %0d", out_cnt,
                             out_cnt/IMG_W, out_cnt%IMG_W, pixel_out, $signed(gold[out_cnt]));
                pix_err++;
            end
        end
        out_cnt++;
    end
end

initial begin
    if (!$value$plusargs("KERNEL=%s", kernel)) kernel = "sobel_x";
    void'($value$plusargs("STALL=%d", stall));
    $readmemh("golden_model/hex/image.hex", img);
    $readmemh({"golden_model/hex/", kernel, "_coef.hex"}, coef);
    $readmemh({"golden_model/hex/", kernel, "_out.hex"},  gold);
    $dumpfile("sim/out/tb_top.vcd");
    $dumpvars(0, tb_top);

    repeat (4) @(posedge clk);
    rst_n <= 1;
    @(posedge clk);

    // coeffs go in before the frame, the port is locked while busy
    for (int i = 0; i < NTAP; i++) begin
        write_en <= 1; write_addr <= i; data_write <= coef[i];
        @(posedge clk);
    end
    write_en <= 0;
    @(posedge clk);

    for (int i = 0; i < NPIX; i++) begin
        repeat (stall_len(i)) begin           // hold valid_in low with junk on the bus
            valid_in <= 0; input_in <= 8'hA5; stall_cyc++;
            @(posedge clk);
        end
        valid_in <= 1; input_in <= img[i];
        @(posedge clk);
    end
    valid_in <= 0; input_in <= 8'hA5;         // junk during drain, the edge masks have to hide it

    wait (!busy);
    repeat (8) @(posedge clk);                // last 3 outputs are still in the pipe when busy drops

    fh = $fopen({"hw_out/", kernel, "_out.hex"}, "w");
    if (fh) begin
        for (int i = 0; i < NPIX; i++) $fdisplay(fh, "%04h", hw[i]);
        $fclose(fh);
    end else
        $display("  couldn't open hw_out/, nothing written");

    $display("--------------------------------------------------------------");
    $display("  tb_top  kernel=%0s  stall=%0d", kernel, stall);
    $display("  outputs      : %0d / %0d", out_cnt, NPIX);
    $display("  latency      : %0d cycles, first valid_in -> first valid_out", first_out - first_in);
    $display("  throughput   : %0d outputs in %0d cycles", out_cnt, last_out - first_out + 1);
    $display("  stalls       : %0d injected, %0d in STREAM, %0d bubbles in valid_out",
             stall_cyc, stall_stream, bubbles);
    $display("  pixel errors : %0d", pix_err);
    if (out_cnt == NPIX && pix_err == 0 && bubbles == stall_stream && lat_err == 0)
        $display("  PASS");
    else
        $display("  FAIL  (lat_err=%0d)", lat_err);
    $display("--------------------------------------------------------------");
    $finish(2);
end

endmodule
