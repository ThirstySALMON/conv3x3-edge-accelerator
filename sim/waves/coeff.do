# kernel load through the write port, before the frame while busy is low
# do sim/run.do sobel_x   then   do sim/waves/coeff.do
do sim/waves/setup.do
add wave /tb_top/clk
add wave /tb_top/rst_n
add wave /tb_top/write_en
add wave -radix uns /tb_top/write_addr
add wave -radix dec /tb_top/data_write
add wave -radix dec /tb_top/dut/u_cr/coef_reg
add wave /tb_top/busy
add wave /tb_top/valid_in
wave zoom range 30ns 170ns
