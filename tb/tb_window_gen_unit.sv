
`timescale 1ns/1ps

module tb_window_gen_unit;

    
    localparam int LB_DEPTH = 32;      
                                      
    localparam int IN_W     = 8;

    logic clk = 0, rst_n;
    logic [IN_W-1:0] input_in;
    logic top_edge, left_edge, right_edge, bottom_edge;
    logic en;
    logic [IN_W-1:0] tap_out [0:8];

    integer errors = 0;

    always #5 clk = ~clk;   // 100 MHz

    window_gen dut (
        .rst_n(rst_n), .clk(clk), .input_in(input_in),
        .top_edge(top_edge), .left_edge(left_edge),
        .right_edge(right_edge), .bottom_edge(bottom_edge),
        .en(en), .tap_out(tap_out)
    );

  
    logic [IN_W-1:0] s_lb0 [0:LB_DEPTH-1];   // input -> lb0 -> in_f
    logic [IN_W-1:0] s_lb1 [0:LB_DEPTH-1];   // in_f  -> lb1 -> in_c
    logic [IN_W-1:0] s_tap [0:8];            // raw taps (before edge zeroing)

    // apply one shift step to the shadow, given the current input pixel
    task automatic shadow_step(input logic [IN_W-1:0] pix);
        logic [IN_W-1:0] in_f, in_c;
        int k;
        begin
            // line buffer outputs are the OLDEST element (about to fall out)
            in_f = s_lb0[LB_DEPTH-1];
            in_c = s_lb1[LB_DEPTH-1];
            // shift line buffers (index 0 is newest)
            for (k = LB_DEPTH-1; k > 0; k--) begin
                s_lb0[k] = s_lb0[k-1];
                s_lb1[k] = s_lb1[k-1];
            end
            s_lb0[0] = pix;      // input -> lb0
            s_lb1[0] = in_f;     // lb0 out -> lb1
            // shift tap rows (newest column at index 2/5/8)
            s_tap[0] = s_tap[1]; s_tap[1] = s_tap[2]; s_tap[2] = in_c;
            s_tap[3] = s_tap[4]; s_tap[4] = s_tap[5]; s_tap[5] = in_f;
            s_tap[6] = s_tap[7]; s_tap[7] = s_tap[8]; s_tap[8] = pix;
        end
    endtask

    task automatic shadow_clear();
        int k;
        begin
            for (k = 0; k < LB_DEPTH; k++) begin s_lb0[k] = '0; s_lb1[k] = '0; end
            for (k = 0; k < 9; k++) s_tap[k] = '0;
        end
    endtask

    // compare DUT taps against shadow, with the SAME edge zeroing applied to the
    // shadow so we test shift + mux together.
    task automatic check_taps(input string tag,
                              input logic te, input logic be,
                              input logic le, input logic re);
        logic [IN_W-1:0] exp [0:8];
        int k;
        begin
            for (k = 0; k < 9; k++) exp[k] = s_tap[k];
            if (te) begin exp[0]='0; exp[1]='0; exp[2]='0; end
            if (be) begin exp[6]='0; exp[7]='0; exp[8]='0; end
            if (le) begin exp[0]='0; exp[3]='0; exp[6]='0; end
            if (re) begin exp[2]='0; exp[5]='0; exp[8]='0; end
            for (k = 0; k < 9; k++) begin
                if (tap_out[k] !== exp[k]) begin
                    errors++;
                    $display("  MISMATCH [%s] tap %0d: got %02h exp %02h",
                             tag, k, tap_out[k], exp[k]);
                end
            end
        end
    endtask

    // drive one cycle with given controls, keep the shadow in lockstep
    task automatic step(input logic [IN_W-1:0] pix, input logic do_en,
                        input logic te, input logic be,
                        input logic le, input logic re);
        begin
            input_in = pix; en = do_en;
            top_edge = te; bottom_edge = be; left_edge = le; right_edge = re;
            @(posedge clk);
            if (do_en) shadow_step(pix);   // DUT shifts only when en
            #1; // let combinational tap_out settle after the edge
        end
    endtask

    integer i;
    logic [IN_W-1:0] held [0:8];

    initial begin
        // ---- reset (synchronous): hold rst_n low across a few edges ----
        rst_n = 0; en = 0; input_in = 0;
        top_edge = 0; bottom_edge = 0; left_edge = 0; right_edge = 0;
        shadow_clear();
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk); #1;

        // ================= TEST 1: shift correctness on a ramp =================
        // Stream enough pixels to fully populate both line buffers + taps, then
        // check every cycle. Values chosen so each pixel is distinct mod 256.
        for (i = 0; i < 3*LB_DEPTH + 20; i++) begin
            step(i[7:0], 1'b1, 0,0,0,0);
            check_taps("T1-shift", 0,0,0,0);
        end
        $display("TEST 1 (shift correctness): done, errors so far = %0d", errors);

        // ================= TEST 2: stall freeze =================
        // Snapshot taps, drop en for 5 cycles, confirm nothing moves, then resume.
        for (i = 0; i < 9; i++) held[i] = tap_out[i];
        for (i = 0; i < 5; i++) begin
            step(8'hEE, 1'b0, 0,0,0,0);   // en low: DUT must freeze
            for (int k = 0; k < 9; k++) begin
                if (tap_out[k] !== held[k]) begin
                    errors++;
                    $display("  MISMATCH [T2-stall cyc %0d] tap %0d: got %02h exp %02h (frozen)",
                             i, k, tap_out[k], held[k]);
                end
            end
        end
        // resume: one enabled step should shift again normally
        step(8'hAB, 1'b1, 0,0,0,0);
        check_taps("T2-resume", 0,0,0,0);
        $display("TEST 2 (stall freeze): done, errors so far = %0d", errors);

        // ================= TEST 3: single-edge zeroing =================
        step(8'h11, 1'b1, /*top*/1,0,0,0);  check_taps("T3-top",    1,0,0,0);
        step(8'h22, 1'b1, 0,/*bot*/1,0,0);  check_taps("T3-bottom", 0,1,0,0);
        step(8'h33, 1'b1, 0,0,/*left*/1,0); check_taps("T3-left",   0,0,1,0);
        step(8'h44, 1'b1, 0,0,0,/*right*/1);check_taps("T3-right",  0,0,0,1);
        // center tap must be nonzero-capable: verify tap 4 tracks the shadow
        if (tap_out[4] !== s_tap[4]) begin
            errors++; $display("  MISMATCH [T3-center] tap4 got %02h exp %02h",
                               tap_out[4], s_tap[4]);
        end
        $display("TEST 3 (single-edge zeroing): done, errors so far = %0d", errors);

        // ================= TEST 4: corner overlap =================
        step(8'h55, 1'b1, /*T*/1,0,/*L*/1,0); check_taps("T4-topleft",     1,0,1,0);
        step(8'h66, 1'b1, /*T*/1,0,0,/*R*/1); check_taps("T4-topright",    1,0,0,1);
        step(8'h77, 1'b1, 0,/*B*/1,/*L*/1,0); check_taps("T4-botleft",     0,1,1,0);
        step(8'h88, 1'b1, 0,/*B*/1,0,/*R*/1); check_taps("T4-botright",    0,1,0,1);
        // explicit corner sanity: top-left must zero tap0 (both), tap1,2 (top),
        // tap3,6 (left); center tap4 must still equal shadow.
        step(8'h99, 1'b1, 1,0,1,0);
        if (tap_out[0]!==0 || tap_out[1]!==0 || tap_out[2]!==0 ||
            tap_out[3]!==0 || tap_out[6]!==0) begin
            errors++; $display("  MISMATCH [T4-corner-zeros] tl corner not fully zeroed");
        end
        if (tap_out[4] === 0 && s_tap[4] !== 0) begin
            errors++; $display("  MISMATCH [T4-center] center wrongly zeroed at corner");
        end
        $display("TEST 4 (corner overlap): done, errors so far = %0d", errors);

        // ---- verdict ----
        if (errors == 0)
            $display("\nPASS: window_gen unit tests all clean (shift, stall, edges, corners).");
        else
            $display("\nFAIL: %0d total mismatches.", errors);
        $finish;
    end

endmodule
