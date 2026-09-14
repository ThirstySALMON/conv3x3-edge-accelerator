# compile everything, in order. run from the project root:  do sim/compile.do
# cnn_pkg must go first - importers resolve it from the library, not the file list

if {![file isdirectory sim/work]} { vlib sim/work }
vmap work sim/work
file mkdir sim/out

vlog -work work -sv rtl/cnn_pkg.sv
vlog -work work -sv rtl/line_buffer.sv
vlog -work work -sv rtl/window_gen.sv
vlog -work work -sv rtl/control_unit.sv
vlog -work work -sv rtl/coeff_reg.sv
vlog -work work -sv rtl/multiplier.sv
vlog -work work -sv rtl/top.sv

vlog -work work -sv tb/tb_window_gen_unit.sv
vlog -work work -sv tb/tb_top_window.sv
vlog -work work -sv tb/tb_top.sv
vlog -work work -sv tb/tb_top_all.sv

echo "compile.do: done"
