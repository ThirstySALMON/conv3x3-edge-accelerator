# 3x3 CNN convolution accelerator - SSCS Egypt 2026

32x32 grayscale in, 3x3 programmable kernel, zero-padded (same) convolution, stride 1,
one output pixel per cycle. 8-bit unsigned pixels, 8-bit signed coefficients, 20-bit
accumulate, 16-bit saturated output, ReLU as a build parameter.

    rtl/           the design. cnn_pkg.sv holds every parameter, top.sv wires it up
    tb/            testbenches, each says how to run it at the top
    sim/           modelsim scripts, run them from this directory
    golden_model/  python reference, input image, expected outputs, coefficient files
    hw_out/        what the RTL produced in simulation, byte-identical to golden_model/hex
    fpga/          vivado constraints, scripts, bitstream, reports
    docs/          notes, waveform screenshots, edge-detection renders

simulate:

    do sim/compile.do
    do sim/run.do all            22 runs, 7 kernels x 3 stall modes + back to back frames
    do sim/run.do sobel_x        one kernel, for waves
    do sim/waves/latency.do      then export the wave window

regenerate the golden files after changing a kernel in golden.py:

    cd golden_model && python golden.py hex/image.hex

implementation: see fpga/README.md. numbers: fpga/reports/RESULTS.md.
