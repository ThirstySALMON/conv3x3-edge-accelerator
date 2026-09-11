# runs inside xsim, started by saif.bat from the project root. logs toggles on everything
# under the dut for the whole frame, so report_power uses measured activity instead of
# its 12.5% default guess.
open_saif fpga/tb_top.saif
log_saif [get_objects -r /tb_top/dut/*]
run all
close_saif
quit
