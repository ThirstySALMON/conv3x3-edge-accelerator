@echo off
rem switching activity for the vivado power report - modelsim ase has no power command, so
rem tb_top is rerun in xsim. from the project root:  fpga\saif.bat
rem writes fpga\tb_top.saif, build.tcl reads it on its own. one kernel is enough, the
rem toggle rate is set by the pixel stream not the coefficients.

setlocal
if not exist "%XILINX_VIVADO%\bin\xvlog.bat" (
  if exist "C:\AMDDesignTools\2025.2\Vivado\settings64.bat" call "C:\AMDDesignTools\2025.2\Vivado\settings64.bat"
)
where xvlog >nul 2>&1 || (
  echo xvlog not found. run this from a vivado command prompt, or fix the path above.
  exit /b 1
)

if not exist sim\out mkdir sim\out
if not exist hw_out mkdir hw_out

rem everything runs from the project root so the tb finds golden_model/ and hw_out/ as usual.
rem xsim litters xsim.dir/ and .Xil/ here, both gitignored.
call xvlog -sv --nolog rtl\cnn_pkg.sv rtl\line_buffer.sv rtl\window_gen.sv ^
    rtl\control_unit.sv rtl\coeff_reg.sv rtl\multiplier.sv rtl\top.sv tb\tb_top.sv || exit /b 1

rem the rtl has no `timescale (modelsim does not need one) but xsim insists once any
rem module has one, so set the default here instead of touching eight files.
call xelab --nolog -debug typical --timescale 1ns/1ps tb_top -s tb_top_saif || exit /b 1

rem no --runall: the tcl script drives the run itself so it can window the saif
call xsim tb_top_saif --nolog --tclbatch fpga\saif_xsim.tcl || exit /b 1

if exist fpga\tb_top.saif (echo ok: fpga\tb_top.saif) else (echo saif was not written & exit /b 1)
