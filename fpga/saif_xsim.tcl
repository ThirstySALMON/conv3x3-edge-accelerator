# runs inside xsim, started by saif.bat from the project root. logs toggles under the dut
# for the whole frame so report_power uses measured activity instead of its 12.5% guess.
# only the datapath nets are logged - logging every object was slow enough to look hung.
open_saif fpga/tb_top.saif
log_saif [get_objects /tb_top/dut/*]
log_saif [get_objects /tb_top/dut/u_wg/*]
log_saif [get_objects /tb_top/dut/u_cu/*]
log_saif [get_objects /tb_top/dut/u_cr/*]
run all
close_saif
quit
