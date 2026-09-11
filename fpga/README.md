vivado goes here. target: arty a7-100t, xc7a100tcsg324-1, 100 MHz.

    arty.xdc          clock + pins
    reports/          utilization, timing summary, power - copied out of the run for the report

multipliers must land in LUTs: uncomment use_dsp="no" in rtl/multiplier.sv before synth,
and check the utilization report says 0 DSP, 0 BRAM, 0 LUT-as-shift-register.
