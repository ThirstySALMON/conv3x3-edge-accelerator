import cnn_pkg::*;
module coeff_reg (

    input  logic clk,
    input  logic rst_n,
    input  logic [3:0] write_addr,

    input  logic [COEF_W-1:0] data_write,
    input  logic       write_en,
    input  logic       busy,

    output logic [COEF_W-1:0] coef_out [0:NTAP-1]    
);


logic [COEF_W-1:0] coef_reg [0:NTAP-1];


always_ff @(posedge clk) begin
    if (!rst_n) begin
        for (int i=0; i<NTAP; i++) begin
            coef_reg[i] <= '0;
        end
    end else if (write_en && !busy) begin
        coef_reg[write_addr] <= data_write;
    end
end

assign coef_out = coef_reg;
 



endmodule 