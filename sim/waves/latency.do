# fill latency, first valid_in -> first valid_out = 37 cycles
# do sim/run.do sobel_x   then   do sim/waves/latency.do
do sim/waves/setup.do
add wave /tb_top/clk
add wave /tb_top/rst_n
add wave -radix hex /tb_top/input_in
add wave /tb_top/valid_in
add wave /tb_top/write_en
add wave /tb_top/busy
add wave /tb_top/valid_out
add wave -radix dec /tb_top/pixel_out
wave cursor add -time 145ns -name "first pixel in"
wave cursor add -time 515ns -name "first pixel out"
wave zoom range 90ns 600ns
