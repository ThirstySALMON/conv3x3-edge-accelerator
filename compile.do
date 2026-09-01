# ============================================================================
# compile.do - compile the design in dependency order.
#
# cnn_pkg MUST be compiled first: line_buffer.sv and window_gen.sv both do a
# file-scope `import cnn_pkg::*;` and use LB_DEPTH / IN_W in their parameter
# port lists. ModelSim resolves that against the *library*, not the file list,
# so a package that is not already in `work` gives:
#     (vlog-13006) Could not find the package (cnn_pkg)
#     (vlog-2730)  Undefined variable: 'LB_DEPTH'
#
# Usage (from the project root, in the ModelSim transcript):
#     do compile.do
# ============================================================================

if {![file isdirectory work]} { vlib work }
vmap work work

# ---- package first, always ----
vlog -work work -sv rtl/cnn_pkg.sv

# ---- RTL ----
vlog -work work -sv rtl/line_buffer.sv
vlog -work work -sv rtl/window_gen.sv

# ---- testbenches ----
vlog -work work -sv tb/tb_window_gen_unit.sv

echo "compile.do: done."
