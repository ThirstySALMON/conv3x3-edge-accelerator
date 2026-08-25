module window_gen (

    input logic rst_n,
    input logic clk,

    input logic [7:0] input_in,
   

    // used for padding , inputs from control unit 
    input logic top_edge,
    input logic left_edge,
    input logic right_edge,
    input logic bottom_edge,

    //clock gate 
    input logic en,

    output logic [7:0] tap_out[0:8]
);

logic [7:0] tap_reg[0 : 8]; // 9 tap registers
logic [7:0] in_f; // signal to from lb0 to tap f and lb1
logic [7:0] in_c; // signal to from lb1 to tap c

line_buffer LB0 (
    .clk(clk),
    .rst_n(rst_n),
    .d_in(input_in),
    .en(en),
    .d_out(in_f)
);

line_buffer LB1 (
    .clk(clk),
    .rst_n(rst_n),
    .d_in(in_f),
    .en(en),
    .d_out(in_c)
);

always_ff @( posedge clk  ) begin 
    if (!rst_n) begin 
        for (int i = 0 ; i < 9 ; i++ ) begin
            tap_reg[i] <= '0;
        end
    end
    else if (en) begin 
        tap_reg[0] <= tap_reg[1]; //a <- b
        tap_reg[1] <= tap_reg[2]; // b<- c
        tap_reg[2] <= in_c; // c <- lb1 

        tap_reg[3] <= tap_reg[4]; //d <- e
        tap_reg[4] <= tap_reg[5]; // e<- f
        tap_reg[5] <= in_f;

        tap_reg[6] <= tap_reg[7]; // g <- h
        tap_reg[7] <= tap_reg[8]; // h <- i
        tap_reg[8] <= input_in;   // i <- current pixel
    end 
    
end




always_comb begin

    
    for (int i = 0; i < 9; i++) begin
        tap_out[i] = tap_reg[i];
    end

    
    if (top_edge) begin
        tap_out[0] = '0;
        tap_out[1] = '0;
        tap_out[2] = '0;
    end

    
    if (bottom_edge) begin
        tap_out[6] = '0;
        tap_out[7] = '0;
        tap_out[8] = '0;
    end

    
    if (left_edge) begin
        tap_out[0] = '0;
        tap_out[3] = '0;
        tap_out[6] = '0;
    end

 
    if (right_edge) begin
        tap_out[2] = '0;
        tap_out[5] = '0;
        tap_out[8] = '0;
    end

end


    


endmodule