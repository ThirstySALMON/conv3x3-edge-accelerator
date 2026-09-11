# end of frame: input stops, fsm drains the last 34 windows, exactly 1024 outputs, then DONE.
# note busy drops 3 cycles before the last valid_out.
# do sim/run.do sobel_x   then   do sim/waves/drain.do
do sim/waves/setup.do
add wave /tb_top/clk
add wave /tb_top/valid_in
add wave /tb_top/dut/u_cu/state
add wave -radix uns /tb_top/dut/u_cu/drain_cnt
add wave /tb_top/busy
add wave /tb_top/dut/win_valid
add wave /tb_top/valid_out
add wave -radix dec /tb_top/pixel_out
add wave /tb_top/dut/frame_done
wave cursor add -time 10385ns -name "last pixel in"
wave cursor add -time 10755ns -name "last pixel out"
wave zoom range 10300ns 10800ns
