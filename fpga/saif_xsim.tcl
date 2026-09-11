# runs inside xsim, started by saif.bat from the project root.
#
# the organiser asked for a saif that represents ACTIVE CONVOLUTION, not reset or idle.
# tb_top's frame is: 4 reset cycles, 9 coefficient writes, then 1024 gapless pixels and
# the drain. so skip the head and start logging once the frame is under way.
#
#   reset + coeff load ends ~145 ns (first pixel in)
#   1024 pixels + 34 drain + 3 pipeline = ~1061 cycles = ~10610 ns
#
# report the interval below in the submission, they asked for it explicitly.
set T_START  145
set T_END   10800

run ${T_START} ns
open_saif fpga/tb_top.saif
# recursive: non-recursive only annotated 19% of design nets and report_power fell back
# to probabilistic estimation for the rest. the whole run takes ~70s, so log everything.
log_saif [get_objects -r /tb_top/dut/*]
run [expr {$T_END - $T_START}] ns
close_saif
puts "saif interval: ${T_START} ns to ${T_END} ns, active convolution only"
quit
