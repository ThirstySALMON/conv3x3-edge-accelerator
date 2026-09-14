# per-stage worst paths, since report_timing_summary only shows the single worst
# with the implemented design open:  source fpga/paths.tcl
# writes fpga/reports/paths.rpt and echoes it
set f fpga/reports/paths.rpt
set fh [open $f w]

foreach {title filt} {
    "worst 15 paths, whole design"                          {}
    "stage 1: window/coeffs -> prod_r (9 multipliers)"     {*prod_r_reg*}
    "stage 2: prod_r -> row_r (3 row adders)"              {*row_r_reg*}
    "stage 3: row_r -> pixel_out (final add + sat + relu)" {*pixel_out_reg*}
} {
    puts $fh "\n== $title =="
    if {$filt eq ""} {
        puts $fh [report_timing -max_paths 15 -sort_by slack -path_type summary -return_string]
    } else {
        puts $fh [report_timing -to [get_cells -hier -filter "NAME =~ $filt"] -max_paths 3 -path_type summary -return_string]
    }
}
close $fh
puts [read [set r [open $f]]]
close $r
puts "written $f"
