# Power methodology and FoM

The organiser confirmed (WhatsApp, 11 Sep) that the power term in the FoM is **total
post-implementation power, static + dynamic**, and that the SAIF must represent **active
convolution processing, excluding long reset or idle periods**. They asked for five things
to be reported; this file is the source for that part of the report.

## The formula (confirmed against the competition PDF)

    FOM = Throughput / ( Power x ( LUTs + 50 x DSPs + 100 x BRAMs ) )

Throughput is in output pixels per cycle. No power unit is given in the PDF; watts is the
natural reading and is what is used below. **State the unit assumption in the report.**

## The five required items

| item | value |
|---|---|
| FPGA device and board | xc7z020clg400-1, PYNQ-Z2 (TUL), Zynq-7000, speed grade -1 |
| Operating frequency used in the FoM | 125 MHz (the constrained frequency, see note) |
| Static power | 0.107 W |
| Dynamic power | 0.074 W |
| Total power | 0.181 W |
| Simulation interval used for the SAIF | 145 ns to 10800 ns of tb_top (see below) |
| Implementation tool | Vivado 2025.2 |
| Power analysis tool | Vivado report_power |
| Functional simulation tool | ModelSim ASE 2020.1 (regression), Vivado xsim (SAIF) |

## Which frequency goes in the FoM

Throughput in the formula is per *cycle*, so it does not change with clock rate - but
dynamic power does, roughly linearly. Reporting the FoM at a higher frequency therefore
makes it worse, with nothing gained. The design closes at 125 MHz with WNS +0.742 ns
(Fmax 137.8 MHz), so:

- **FoM is computed at 125 MHz**, the constrained and reported operating frequency.
- Fmax 137.8 MHz is reported separately, under timing closure, not folded into the FoM.

Worth confirming with the organiser whether they expect the FoM at the achieved Fmax or at
a declared operating frequency - the two give different numbers and the question has been
raised in the group.

## SAIF interval

`fpga/saif_xsim.tcl` windows the capture rather than logging the whole run, because the
head of the testbench is reset and coefficient loading, which is exactly the idle period
the organiser said to exclude.

    tb_top timeline        0 ns   reset released after 4 cycles
                         ~50 ns   9 coefficient writes through the write port
                          145 ns  first pixel in, valid_in asserts   <- SAIF starts
                        10385 ns  last pixel in
                        10755 ns  last valid_out (1024th output)
                        10800 ns  SAIF stops

    logged interval: 145 ns - 10800 ns = 10.655 us at 125 MHz = 1332 cycles
    of which 1024 are outputs, 34 fill, 34 drain, 3 pipeline - no idle, no reset.

Scope logged: everything under `/tb_top/dut` - the datapath, window_gen, control_fsm and
coeff_reg.

## Status: SAIF not yet generated

xsim fails on this machine before running any design:

    Unknown error occured while verifying the digital signature. Error Code: -2146869232

This is not project-specific - a two-line $display testbench fails identically, and so does
`vivado -mode batch`, including the GUI's own synth_1 run (which spawns a batch child).
`vcd2saif` is not shipped in Vivado 2025.2, so VCD conversion is not available as a
fallback either.

**The 0.181 W above is therefore vectorless** (`Confidence Level: Low`), from Vivado's
default 12.5% toggle assumption, and does not yet meet the organiser's requirement.

To fix, in order of likelihood: run as Administrator; Internet Options > Advanced >
uncheck "Check for publisher's certificate revocation"; exclude C:\AMDDesignTools from
antivirus. Once xsim runs, `fpga\saif.bat` writes the SAIF and `fpga/build.tcl` reads it
automatically - re-run implementation and report_power, and confidence should rise to
High.

If it cannot be fixed before submission, report the vectorless number **and say so
plainly**, with the toggle assumption stated. A stated methodology limitation is
defensible; an unsupported number is not.

## Note on the I/O share of dynamic power

Of the 0.074 W dynamic, **0.059 W is I/O** - 80%. That is an artifact of exposing all 42
core ports at the device boundary. In a real system this core would sit inside a larger
design with those signals staying on-chip, so its dynamic power would be a small fraction
of what is reported here. Worth one sentence in the report: it is honest, and it explains
a number that otherwise looks high for 879 LUTs.
