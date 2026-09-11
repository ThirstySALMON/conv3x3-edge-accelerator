# which stage is actually the tightest? report_timing_summary only prints the single
# worst path, which hides whether the other two stages are close behind.
# open the routed design in the gui, then: source fpga/paths.tcl
puts "\n== worst 15 paths, whole design =="
report_timing -max_paths 15 -sort_by slack -path_type summary

puts "\n== stage 1: window/coeffs -> prod_r (9 multipliers) =="
report_timing -to [get_cells -hier -filter {NAME =~ *prod_r_reg*}] -max_paths 3 -path_type summary

puts "\n== stage 2: prod_r -> row_r (3 row adders) =="
report_timing -to [get_cells -hier -filter {NAME =~ *row_r_reg*}] -max_paths 3 -path_type summary

puts "\n== stage 3: row_r -> pixel_out (final add + saturate + relu) =="
report_timing -to [get_cells -hier -filter {NAME =~ *pixel_out_reg*}] -max_paths 3 -path_type summary
