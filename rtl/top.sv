import cnn_pkg::*;

module top (
    input logic clk,
    input logic rst_n,
    
    input logic [IN_W -1 :0] input_in,
    input logic       valid_in,

    input logic       write_en,
    input logic [3:0] write_addr,
    input logic [7:0] data_write,

    logic [IN_W-1:0] taps [0:NTAP-1], // comment out , for debug 

    output logic [15:0] pixel_out,
    output logic        valid_out,
    output logic        busy
);



logic top_edge;
logic bottom_edge;
logic right_edge;
logic left_edge;

logic en;
logic win_valid;
logic [IN_W-1:0] tap_out [0:NTAP-1];   
logic frame_done;


control_fsm u_cu(  // Control FSM 
     .clk(clk),
     .rst_n(rst_n),
     .valid_in(valid_in),

     .en(en),
     .win_valid(win_valid),
     .top_edge(top_edge),
     .bottom_edge(bottom_edge),
     .left_edge(left_edge),
     .right_edge(right_edge),
     .busy(busy),
     .frame_done(frame_done)
);


window_gen u_wg(  // Window generator
    .clk(clk),
    .rst_n(rst_n),
    .input_in(input_in),

    .top_edge(top_edge),
    .left_edge(left_edge),
    .right_edge(right_edge),
    .bottom_edge(bottom_edge),

    .en(en),

    .tap_out(tap_out)
);

assign taps = tap_out; // comment out , for debug




endmodule