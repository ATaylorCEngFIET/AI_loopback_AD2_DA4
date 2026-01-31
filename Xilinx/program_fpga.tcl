# Program FPGA Script
# Usage: vivado -mode batch -source program_fpga.tcl

set project_dir [file dirname [file normalize [info script]]]
set bitstream "$project_dir/adc_dac_passthrough/adc_dac_passthrough.runs/impl_1/arty_s7_top.bit"

# Open Hardware Manager
open_hw_manager

# Connect to hardware server
connect_hw_server -allow_non_jtag
open_hw_target

# Get the FPGA device
set device [lindex [get_hw_devices] 0]
current_hw_device $device

# Set programming file
set_property PROGRAM.FILE $bitstream $device

# Program the device
puts "Programming FPGA with: $bitstream"
program_hw_devices $device

puts "=========================================="
puts "FPGA programmed successfully!"
puts "=========================================="

close_hw_target
disconnect_hw_server
close_hw_manager
