# questa run script, from project root after do sim/compile.do
# do sim/run.do all | kernels | window | unit | <kernel> [1]
# kernels writes hw_out/, second arg 1 on a single kernel injects stalls

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
