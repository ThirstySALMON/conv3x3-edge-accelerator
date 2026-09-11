# whole frame: IDLE -> FILL -> STREAM -> DRAIN -> DONE -> IDLE with the counters
# do sim/run.do sobel_x   then   do sim/waves/fsm.do
do sim/waves/setup.do
add wave /tb_top/clk
add wave /tb_top/valid_in
add wave /tb_top/dut/u_cu/state
add wave -radix uns /tb_top/dut/u_cu/in_cnt
add wave -radix uns /tb_top/dut/u_cu/out_r
add wave -radix uns /tb_top/dut/u_cu/drain_cnt
add wave /tb_top/busy
add wave /tb_top/valid_out
add wave /tb_top/dut/frame_done
wave zoom full
