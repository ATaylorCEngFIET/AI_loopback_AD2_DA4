# Get valid package pins for Arty S7-100
puts "Clock capable pins:"
foreach pin [get_package_pins -filter {IS_GLOBAL_CLK_PIN}] {
    puts $pin
}
puts "\nAll IO banks:"
foreach bank [get_iobanks] {
    puts "$bank"
}
exit
