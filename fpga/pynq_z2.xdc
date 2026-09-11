## PYNQ-Z2, xc7z020clg400-1. 42 pins.
## clk = 125 MHz from the ethernet PHY, SW0 = reset, PmodA = pixel in, PmodB = coeff data,
## arduino header = control, RPi header = pixel out, LED0/1 = valid_out / busy.
## no board on hand, this is for implementation numbers. a real demo wants a 2-flop
## synchronizer on rst_n in a wrapper - the core uses it as a synchronous reset.

## clock
set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports clk]
create_clock -period 8.000 -name clk -waveform {0.000 4.000} [get_ports clk]

## SW0 up = run, down = reset. rst_n is active low and the switch is not inverted, so no logic needed
set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS33 } [get_ports rst_n]
set_false_path -from [get_ports rst_n]

## control, arduino header
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS33 } [get_ports {write_addr[0]}]
set_property -dict { PACKAGE_PIN U12 IOSTANDARD LVCMOS33 } [get_ports {write_addr[1]}]
set_property -dict { PACKAGE_PIN U13 IOSTANDARD LVCMOS33 } [get_ports {write_addr[2]}]
set_property -dict { PACKAGE_PIN V13 IOSTANDARD LVCMOS33 } [get_ports {write_addr[3]}]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS33 } [get_ports valid_in]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS33 } [get_ports write_en]

## pixel in, PmodA
set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports {input_in[0]}]
set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 } [get_ports {input_in[1]}]
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports {input_in[2]}]
set_property -dict { PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 } [get_ports {input_in[3]}]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {input_in[4]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {input_in[5]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {input_in[6]}]
set_property -dict { PACKAGE_PIN W19 IOSTANDARD LVCMOS33 } [get_ports {input_in[7]}]

## coefficient data, PmodB
set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports {data_write[0]}]
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports {data_write[1]}]
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports {data_write[2]}]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {data_write[3]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {data_write[4]}]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports {data_write[5]}]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {data_write[6]}]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports {data_write[7]}]

## pixel out, raspberry pi header
set_property -dict { PACKAGE_PIN F19 IOSTANDARD LVCMOS33 } [get_ports {pixel_out[0]}]
set_property -dict { PACKAGE_PIN V10 IOSTANDARD LVCMOS33 } [get_ports {pixel_out[1]}]
set_property -dict { PACKAGE_PIN V8  IOSTANDARD LVCMOS33 } [get_ports {pixel_out[2]}]
set_property -dict { PACKAGE_PIN W10 IOSTANDARD LVCMOS33 } [get_ports {pixel_out[3]}]
set_property -dict { PACKAGE_PIN B20 IOSTANDARD LVCMOS33 } [get_ports {pixel_out[4]}]
set_property -dict { PACKAGE_PIN W8  IOSTANDARD LVCMOS33 } [get_ports {pixel_out[5]}]
set_property -dict { PACKAGE_PIN V6  IOSTANDARD LVCMOS33 } [get_ports {pixel_out[6]}]
set_property -dict { PACKAGE_PIN Y6  IOSTANDARD LVCMOS33 } [get_ports {pixel_out[7]}]
set_property -dict { PACKAGE_PIN B19 IOSTANDARD LVCMOS33 } [get_ports {pixel_out[8]}]
set_property -dict { PACKAGE_PIN U7  IOSTANDARD LVCMOS33 } [get_ports {pixel_out[9]}]
set_property -dict { PACKAGE_PIN C20 IOSTANDARD LVCMOS33 } [get_ports {pixel_out[10]}]
set_property -dict { PACKAGE_PIN Y8  IOSTANDARD LVCMOS33 } [get_ports {pixel_out[11]}]
set_property -dict { PACKAGE_PIN A20 IOSTANDARD LVCMOS33 } [get_ports {pixel_out[12]}]
set_property -dict { PACKAGE_PIN Y9  IOSTANDARD LVCMOS33 } [get_ports {pixel_out[13]}]
set_property -dict { PACKAGE_PIN U8  IOSTANDARD LVCMOS33 } [get_ports {pixel_out[14]}]
set_property -dict { PACKAGE_PIN W6  IOSTANDARD LVCMOS33 } [get_ports {pixel_out[15]}]

## LEDs
set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports valid_out]
set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports busy]

## nothing external clocks these pins - there is no board and no interface timing contract,
## so io paths are excluded and what gets reported is the core register-to-register Fmax.
## with an invented 1ns io budget instead, all 84 failures were pad delay: the 3v3 OBUF
## alone is 3.5ns of an 8ns period. say this in the timing section of the report.
set_false_path -from [all_inputs] -to [all_registers]
set_false_path -from [all_registers] -to [all_outputs]
set_false_path -from [get_ports rst_n]
