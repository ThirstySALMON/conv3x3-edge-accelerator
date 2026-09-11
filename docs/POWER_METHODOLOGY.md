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
| Operating frequency used in the FoM | **125 MHz** (decided 11 Sep, see note) |
| Static power | 0.107 W |
| Dynamic power | 0.052 W |
| Total power | **0.158 W** |
| Power confidence | Medium, SAIF-annotated (was Low / vectorless at 0.181 W) |
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

The organiser was asked and left the choice to the team. **125 MHz it is**, for three
reasons: it is the constraint the design was implemented and verified against; the SAIF
came from the same clock, so power and frequency are self-consistent; and going lower
than the board clock would read as gaming the metric.

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

## SAIF: generated, annotated, result

`fpga\saif.bat` (xsim, after the signature error was cleared by running elevated) writes
`fpga/tb_top.saif`: 145-10800 ns, DURATION 10,655,000 ps, 2380 nets under /tb_top/dut,
logged recursively. Read into the routed design with

    read_saif fpga/tb_top.saif -strip_path tb_top/dut
    report_power

| | vectorless | SAIF |
|---|---|---|
| dynamic | 0.074 W | **0.052 W** (-30%) |
| static | 0.107 W | 0.107 W |
| total | 0.181 W | **0.158 W** (-13%) |
| confidence | Low | **Medium** |
| FoM | 6.285e-3 | **7.20e-3** (+14.6%) |

**Why only Medium, and why 19% of nets annotated.** `Design nets matched = 414 of 2229`.
The SAIF carries RTL names (prod_r, tap_out, row_sum); the routed netlist is mostly
synthesis-invented names like prod_r_reg[8][11]_i_1_n_0 - internal LUT-to-LUT nets that
never existed in RTL, so no RTL simulation can annotate them. Logging recursively doubled
the SAIF (1087 -> 2380 nets) and changed the match count by exactly zero, which confirms
this is a naming ceiling and not a coverage problem. The 414 that do match are the
boundary and register nets - I/O, taps, products, accumulator, pipeline registers - which
are the high-activity nets that set the power; Vivado propagates probabilistically through
the combinational nets between them, which is what it is designed to do. That dynamic
power moved by 30% shows the annotation took.

High confidence would need a post-implementation timing simulation with a netlist-level
testbench, which the organiser did not ask for.

**Two warnings from read_saif, both benign, will reappear on every run:**
- "Simulation is not consistent with clock constraints on net clk" - Vivado ignores SAIF
  clock activity and uses create_clock instead. The TB clock is 10 ns, the constraint
  8 ns; the constraint wins, which is what we want.
- "high-fanout reset nets asserted for excessive periods" - false positive. In the SAIF,
  rst_n is high (deasserted) for the whole window with zero toggles, i.e. reset was
  released before capture began. The heuristic guesses the wrong polarity for a constant
  high-fanout net.

## Note on the I/O share of dynamic power

Of the 0.074 W dynamic, **0.059 W is I/O** - 80%. That is an artifact of exposing all 42
core ports at the device boundary. In a real system this core would sit inside a larger
design with those signals staying on-chip, so its dynamic power would be a small fraction
of what is reported here. Worth one sentence in the report: it is honest, and it explains
a number that otherwise looks high for 879 LUTs.
