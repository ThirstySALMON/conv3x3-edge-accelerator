# do sim/run.do all              everything: 5 kernels x (clean, stalls, random stalls), 2 frames back to back, relu build
# do sim/run.do kernels          the five kernels one after another through tb_top, writes hw_out/
# do sim/run.do sobel_x [1]      one kernel end to end, second arg 1 = inject stalls
# do sim/run.do window           taps / fsm / edge flags at top level
# do sim/run.do unit             window_gen on its own
# compile first (do sim/compile.do). run from the project root.

if {$argc < 1} { echo "usage: do sim/run.do all|kernels|window|unit|<kernel> \[stall\]"; return }
set what $1
set stall 0
if {$argc >= 2} { set stall $2 }
set kernels {identity sobel_x sobel_y sharpen laplacian}

proc run_tb {tb args} {
    eval vsim -quiet -onfinish stop -voptargs=+acc work.$tb $args
    run -all
}

switch -- $what {
    all     { run_tb tb_top_all }
    window  { run_tb tb_top_window }
    unit    { run_tb tb_window_gen_unit }
    kernels { foreach k $kernels { run_tb tb_top +KERNEL=$k; quit -sim } }
    default {
        if {[lsearch -exact $kernels $what] < 0} { echo "no kernel called $what"; return }
        run_tb tb_top +KERNEL=$what +STALL=$stall
    }
}
