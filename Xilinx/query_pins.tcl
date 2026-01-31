# Query package pins for xc7s100fgga484-1
# Open project
open_project "C:/hdl_renesas/ai/Xilinx/adc_dac_passthrough/adc_dac_passthrough.xpr"
open_run synth_1

# Get all package pins
puts "=== CLOCK CAPABLE PINS ==="
foreach pin [get_package_pins -filter {IS_CLOCK_CAPABLE_IO == 1}] {
    puts "$pin"
}

puts ""
puts "=== ALL PACKAGE PINS STARTING WITH E, F, G, H, L, M, N, P, R, T ==="
foreach pin [get_package_pins] {
    set name [get_property NAME $pin]
    if {[regexp {^[EFGHLMNPRT][0-9]+$} $name]} {
        puts "$name"
    }
}

exit
