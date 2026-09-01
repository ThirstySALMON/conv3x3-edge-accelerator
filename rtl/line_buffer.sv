import cnn_pkg::*;

// One full row of vertical delay: DEPTH-deep, IN_W-wide FF/LUTRAM shift
// register. Deliberately NOT a BRAM (100x FoM penalty). en-gated so a
// stall freezes the whole pipeline coherently.
module line_buffer #(
    parameter int DEPTH = LB_DEPTH,
    parameter int WIDTH = IN_W
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] d_in,
    input  logic             en,

    output logic [WIDTH-1:0] d_out
);

    logic [WIDTH-1:0] sr [0:DEPTH-1];

    always_ff @(posedge clk) begin           // synchronous reset (intentional)
        if (!rst_n) begin
            for (int i = 0; i < DEPTH; i++)
                sr[i] <= '0;
        end else if (en) begin
            sr[0] <= d_in;
            for (int i = 1; i < DEPTH; i++)
                sr[i] <= sr[i-1];
        end
    end

    assign d_out = sr[DEPTH-1];              // oldest element falls out

endmodule
