target: PYNQ-Z2, xc7z020clg400-1, 125 MHz board clock. no board on hand - this is for the
implementation numbers, the pinout is the real one so a bitstream would work if one turns up.

    pynq_z2.xdc     clock + all 42 pins + a nominal io budget
    saif.bat        runs tb_top in xsim, writes tb_top.saif (real switching activity for the power report)
    build.tcl       vivado -mode batch -source fpga/build.tcl   (from the project root)
    reports/        utilization, timing summary, power, drc, summary.txt with the table numbers

power: build.tcl sets toggle rates by hand (see the comment next to report_power) because
xsim does not run on this machine - "Unknown error occured while verifying the digital
signature. Error Code: -2146869232", on any design, including a two line $display. saif.bat
is left in place for a machine where xsim works; build.tcl uses fpga/tb_top.saif if it finds
one and falls back to the manual numbers otherwise. report_power says Low confidence either
way unless a saif is present - say which method was used in the report.

after a run, summary.txt must say DSPs 0 and BRAM 0. LUT as shift register should be 16:
vivado turns both line buffers into SRL32E because nothing reads the middle elements, so
they cost 16 LUTs instead of 512 FFs. that is the better result, leave it alone.

results are written up in reports/RESULTS.md - read that before the three .rpt files.
