# synth + impl for the pynq-z2 part, no project, no clicking. from the project root:
#   vivado -mode batch -source fpga/build.tcl
# reports land in fpga/reports/. if fpga/tb_top.saif exists (run fpga/saif.bat first) the power
# report uses real switching activity instead of the vivado default toggle guess.

set part xc7z020clg400-1
set out  fpga/reports
file mkdir $out

read_verilog -sv [list rtl/cnn_pkg.sv rtl/line_buffer.sv rtl/window_gen.sv \
                       rtl/control_unit.sv rtl/coeff_reg.sv rtl/multiplier.sv rtl/top.sv]
read_xdc fpga/pynq_z2.xdc

# -max_dsp 0 on top of the use_dsp attribute, the 9 multipliers have to stay in LUTs
synth_design -top top -part $part -max_dsp 0
report_utilization -file $out/synth_utilization.rpt

opt_design
place_design
route_design

report_utilization    -file $out/utilization.rpt
report_utilization    -hierarchical -file $out/utilization_hier.rpt
report_timing_summary -file $out/timing_summary.rpt
report_drc            -file $out/drc.rpt

if {[file exists fpga/tb_top.saif]} {
    read_saif fpga/tb_top.saif -strip_path tb_top/dut
    puts "power: using fpga/tb_top.saif"
} else {
    puts "power: no saif found, vectorless estimate"
}
report_power -file $out/power.rpt

write_checkpoint -force $out/routed.dcp
# write_bitstream -force fpga/top.bit     ;# only if a board turns up

# pull the table numbers out so nobody has to read three reports
set u [report_utilization -return_string]
set p [report_power -return_string]
proc grab {txt re} { if {[regexp $re $txt -> v]} { return $v } else { return "?" } }
set luts  [grab $u {\|\s*Slice LUTs\*?\s*\|\s*(\d+)}]
set ffs   [grab $u {\|\s*Slice Registers\s*\|\s*(\d+)}]
set srl   [grab $u {\|\s*LUT as Shift Register\s*\|\s*(\d+)}]
set lutm  [grab $u {\|\s*LUT as Memory\s*\|\s*(\d+)}]
set dsps  [grab $u {\|\s*DSPs\s*\|\s*(\d+)}]
set brams [grab $u {\|\s*Block RAM Tile\s*\|\s*(\d+)}]
set ptot  [grab $p {Total On-Chip Power \(W\)\s*\|\s*([\d.]+)}]
set pdyn  [grab $p {Dynamic \(W\)\s*\|\s*([\d.]+)}]
set pstat [grab $p {Device Static \(W\)\s*\|\s*([\d.]+)}]
set wns   [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set whs   [get_property SLACK [get_timing_paths -max_paths 1 -hold]]
set period 8.000
set fmax  [expr {1000.0 / ($period - $wns)}]

set s ""
append s "part            $part\n"
append s "LUTs            $luts   (as shift reg: $srl - expect 16, the line buffers)\n"
append s "FFs             $ffs\n"
append s "DSPs            $dsps   (must be 0)\n"
append s "BRAM tiles      $brams  (must be 0)\n"
append s "WNS / WHS       $wns / $whs ns at $period ns\n"
append s "Fmax            [format %.1f $fmax] MHz\n"
append s "power           total $ptot W  (dynamic $pdyn, static $pstat)\n"
if {$luts ne "?" && $ptot ne "?"} {
    set denom [expr {$luts + 50*$dsps + 100*$brams}]
    append s "FoM             [format %.4g [expr {1.0 / ($ptot * $denom)}]]   = 1 px/cycle / ($ptot W x $denom)   <- check formula + units against the pdf\n"
}
puts "\n== summary ==\n$s"
set fh [open $out/summary.txt w]
puts $fh $s
close $fh
