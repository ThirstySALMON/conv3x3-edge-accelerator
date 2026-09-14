# shared wave window setup, 10ns clock, one gridline per cycle
view wave
delete wave *
configure wave -timelineunits ns
configure wave -gridauto off
configure wave -gridperiod 10ns
configure wave -gridoffset 0
configure wave -signalnamewidth 1
configure wave -namecolwidth 140
configure wave -valuecolwidth 70
