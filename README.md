# 3x3 CNN convolution accelerator - SSCS Egypt 2026

32x32 grayscale in, 3x3 programmable kernel, zero-padded (same) convolution, stride 1,
one output pixel per cycle. 8-bit unsigned pixels, 8-bit signed coefficients, 20-bit
accumulate, 16-bit saturated output, optional ReLU.

    rtl/           the design. cnn_pkg.sv holds every parameter, top.sv wires it up
    tb/            testbenches (see the header of each)
    sim/           modelsim scripts, run them from this directory
    golden_model/  python reference, input image, expected outputs, coefficient files
    hw_out/        what the RTL produced in simulation - diffs clean against golden_model/hex
    fpga/          vivado constraints and reports
    docs/          report, architecture notes, checklists, waveform screenshots

Run it:

    vsim -c -do "do sim/compile.do; do sim/run.do all; quit -f"

or in the modelsim gui, from the project root:

    do sim/compile.do
    do sim/run.do all            full regression
    do sim/run.do sobel_x        one kernel, for looking at waves
    do sim/waves/latency.do      then screenshot

Regenerate the golden files after changing a kernel in golden.py:

    cd golden_model && python golden.py hex/image.hex
