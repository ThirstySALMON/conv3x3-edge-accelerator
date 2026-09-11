# row boundary: output 31 (right edge) then 32 (left edge). taps 2,5,8 then 0,3,6 forced to zero,
# centre tap[4] never touched.
# do sim/run.do sobel_x   then   do sim/waves/edges.do
do sim/waves/setup.do
add wave /tb_top/clk
add wave -radix uns /tb_top/dut/u_cu/out_r
add wave -radix uns /tb_top/dut/u_cu/out_c
add wave /tb_top/dut/top_edge
add wave /tb_top/dut/bottom_edge
add wave /tb_top/dut/left_edge
add wave /tb_top/dut/right_edge
add wave /tb_top/dut/win_valid
add wave -radix hex -expand /tb_top/dut/tap_out
wave cursor add -time 795ns -name "col 31, right_edge"
wave cursor add -time 805ns -name "col 0, left_edge"
wave zoom range 740ns 880ns
