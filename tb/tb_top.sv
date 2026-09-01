
module tb_top;
logic  clk = 0;
input rst_n = 0;



localparam real CLK_PERIOD = 10;
always #(CLK_PERIOD/2) clk=~clk;

initial begin
    $dumpfile("tb_top.vcd");
    $dumpvars(0, tb_top);
end


initial begin




    /* 
    1.load vectors from chosen file (1024 elements for 32* 32) 
    2. go through the reset sequence for the module 
    3. initialize with selected coefficients 
    4. stream the data and record throughput /latency in cycles 
    5. save outputs to file 
    6 compare with golden model 
    7. Output statistics to a file with a specific format and to a TCL console 
*/


   // 1.load inputs and verification 
    logic [7:0] in_hex[0:1023];
    logic [7:0] golden_hex[0:1023];
    $readmemh("golden_model/vectors/hramp_in.hex" , in_hex);
    // TODO: automate file loading 
    $readmemh("" , golden_hex);
    //

    rst_n = 0;
    repeat (4) @(posedge clk);
    rst_n <= 1;

    


















    $finish(2);
end

endmodule
