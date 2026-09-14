target: PYNQ-Z2, xc7z020clg400-1, 125 MHz board clock (H16). all 42 pins are the real
ones, so top.bit would load on the board - it just has nothing driving the pins, a demo
needs a wrapper.

    pynq_z2.xdc     clock, all 42 pins, io false-pathed (no external timing contract)
    saif.bat        reruns tb_top in xsim, writes tb_top.saif for the power report
    build.tcl       whole flow, no project:  vivado -mode tcl  then  source fpga/build.tcl
    paths.tcl       worst paths per pipeline stage, implemented design open
    top.bit         bitstream, PL only
    reports/        utilization (+hier, +synth), timing, paths, power, drc, io, synth.log

order: saif.bat first, then build.tcl (it picks the saif up by itself), then paths.tcl.

sanity after a run: DSP 0, BRAM 0, LUT as shift register 16 (the two line buffers, that
is the good outcome), WNS >= 0. the one DRC warning is ZPS7-1, expected for a PL-only zynq
design.

reports/RESULTS.md has the numbers written up; read that before the .rpt files.
