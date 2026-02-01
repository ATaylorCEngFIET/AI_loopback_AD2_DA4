set project_dir [file dirname [file normalize [info script]]]
set bitstream "$project_dir/adc_dac_passthrough/adc_dac_passthrough.runs/impl_1/arty_s7_top.bit"
open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target [lindex [get_hw_targets] 0]
set device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE $bitstream [current_hw_device]
program_hw_devices [current_hw_device]
close_hw_manager
exit
