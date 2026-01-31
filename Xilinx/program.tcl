# Program FPGA with bitstream
open_hw_manager
connect_hw_server -allow_non_jtag

# List available targets
puts "Available hardware targets:"
foreach target [get_hw_targets] {
    puts "  Target: $target"
}

# Open the first available target
open_hw_target [lindex [get_hw_targets] 0]

# Get device
set device [lindex [get_hw_devices xc7s*] 0]
current_hw_device $device
refresh_hw_device $device

# Program bitstream with debug probes
set_property PROGRAM.FILE {C:/hdl_renesas/ai/Xilinx/adc_dac_passthrough/adc_dac_passthrough.runs/impl_1/arty_s7_top.bit} $device
set_property PROBES.FILE {C:/hdl_renesas/ai/Xilinx/reports/debug_probes.ltx} $device
program_hw_devices $device

puts "FPGA programmed successfully!"
close_hw_manager
exit
