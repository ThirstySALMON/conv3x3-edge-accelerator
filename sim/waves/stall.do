# valid_in dropped for 3 cycles before pixel 300. window freezes, bubble shows up
# in valid_out 3 cycles later, nothing lost.
# do sim/run.do sobel_x 1   then   do sim/waves/stall.do
do sim/waves/setup.do
add wave /tb_top/clk
add wave /tb_top/valid_in
add wave -radix hex /tb_top/input_in
add wave /tb_top/dut/en
add wave -radix hex /tb_top/dut/tap_out
add wave /tb_top/dut/win_valid
add wave /tb_top/valid_out
add wave -radix dec /tb_top/pixel_out
wave cursor add -time 3165ns -name "valid_in drops"
wave cursor add -time 3195ns -name "bubble reaches valid_out"
wave zoom range 3080ns 3300ns
