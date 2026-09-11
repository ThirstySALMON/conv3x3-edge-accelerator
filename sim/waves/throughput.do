# steady state, valid_out solid high and a new pixel every cycle
# do sim/run.do sobel_x   then   do sim/waves/throughput.do
do sim/waves/setup.do
add wave /tb_top/clk
add wave /tb_top/valid_in
add wave -radix hex /tb_top/input_in
add wave /tb_top/busy
add wave /tb_top/valid_out
add wave -radix dec /tb_top/pixel_out
wave zoom range 3000ns 3300ns
