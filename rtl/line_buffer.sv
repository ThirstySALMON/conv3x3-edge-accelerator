module line_buffer (
    input logic clk,
    input logic rst_n,
    input logic [7:0] d_in,
    input logic en,

    output logic [7:0] d_out

);

logic [7:0] sr [0:31];

integer i;
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (i =0 ;i < 32 ;i++ ) begin
                sr[i] <= '0;
            end

        end else if (en) begin
           
            sr[0] <= d_in;
            for (  i =  1 ; i < 32  ; i++ ) begin
                sr[i] <= sr[i-1]; 
            end


        end
    

    end

    assign d_out = sr[31];

endmodule
    
