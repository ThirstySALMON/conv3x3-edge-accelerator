target: PYNQ-Z2, xc7z020clg400-1, 125 MHz board clock. no board on hand - this is for the
implementation numbers, the pinout is the real one so a bitstream would work if one turns up.

    pynq_z2.xdc     clock + all 42 pins + a nominal io budget
    saif.bat        runs tb_top in xsim, writes tb_top.saif (real switching activity for the power report)
    build.tcl       vivado -mode batch -source fpga/build.tcl   (from the project root)
    reports/        utilization, timing summary, power, drc, summary.txt with the table numbers

before the first run: fpga\saif.bat from a vivado command prompt, so the power report uses
real switching activity instead of the default toggle guess. build.tcl finds the saif by itself.

after a run, summary.txt must say DSPs 0 and BRAM 0. LUT as shift register should be 16:
vivado turns both line buffers into SRL32E because nothing reads the middle elements, so
they cost 16 LUTs instead of 512 FFs. that is the better result, leave it alone.

results are written up in reports/RESULTS.md - read that before the three .rpt files.
