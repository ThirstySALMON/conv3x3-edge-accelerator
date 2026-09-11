(* use_dsp = "no" *)
module mult8x8 (
  input  logic signed [7:0] coef,
  input  logic        [7:0] pix,
  output logic signed [15:0] prod
);
  assign prod = coef * signed'({1'b0, pix});
endmodule