module top (
    input logic clk,
    input logic rst_n,
    
    input logic [IN_W -1 :0] input_in,
    input logic       valid_in,

    input logic       write_en,
    input logic [3:0] write_addr,
    input logic [7:0] data_write,

    output logic [15:0] pixel_out,
    output logic        valid_out,
    output logic        busy
);
    



endmodule