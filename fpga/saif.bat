@echo off
rem switching activity (saif) for the vivado power report, rerun in xsim since modelsim ase has no power command
rem run from the project root: fpga\saif.bat -> writes fpga\tb_top.saif, picked up by build.tcl
rem one kernel is enough, toggle rate comes from the pixel stream not the coefficients

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

rem run from project root so the tb finds golden_model/ and hw_out/; xsim.dir/ and .Xil/ are gitignored
call xvlog -sv --nolog rtl\cnn_pkg.sv rtl\line_buffer.sv rtl\window_gen.sv ^
    rtl\control_unit.sv rtl\coeff_reg.sv rtl\multiplier.sv rtl\top.sv tb\tb_top.sv || exit /b 1

rem rtl has no `timescale but xsim insists once any module has one, so default it here
call xelab --nolog -debug typical --timescale 1ns/1ps tb_top -s tb_top_saif || exit /b 1

rem no --runall, the tcl drives the run so it can window the saif; forward slashes because tcl eats backslashes
call xsim tb_top_saif --nolog --tclbatch fpga/saif_xsim.tcl || exit /b 1

if exist fpga\tb_top.saif (echo ok: fpga\tb_top.saif) else (echo saif was not written & exit /b 1)
