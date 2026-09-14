# runs inside xsim, started by saif.bat from the project root
# saif window covers active convolution only: reset + 9 coeff writes end ~145 ns,
# 1024 px + 34 drain + 3 pipeline = ~1061 cycles = ~10610 ns
set T_START  145
set T_END   10800

run ${T_START} ns
open_saif fpga/tb_top.saif
# -r: non-recursive only annotated 19% of nets, report_power went probabilistic for the rest
log_saif [get_objects -r /tb_top/dut/*]
run [expr {$T_END - $T_START}] ns
close_saif
puts "saif interval: ${T_START} ns to ${T_END} ns, active convolution only"
quit
