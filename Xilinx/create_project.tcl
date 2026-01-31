# Vivado Project Creation Script for Arty S7 ADC/DAC Passthrough
# Target: Digilent Arty S7-50 (xc7s50csga324-1) - NOT xc7s100fgga484
# Note: The Arty S7 board uses CSG324 package, not FGG484
# 
# Usage: 
#   Open Vivado, go to Tools -> Run Tcl Script, select this file
#   OR run from command line: vivado -mode batch -source create_project.tcl

# Set project parameters
set project_name "adc_dac_passthrough"
set project_dir [file dirname [file normalize [info script]]]
set rtl_dir "$project_dir/rtl"
set parent_dir [file dirname $project_dir]
set constraints_dir "$project_dir/constraints"

# Create project - using xc7s50csga324-1 (Arty S7 board)
create_project $project_name "$project_dir/$project_name" -part xc7s50csga324-1 -force

# Set project properties
set_property target_language Verilog [current_project]
set_property simulator_language Verilog [current_project]

# Add RTL source files from local rtl folder
add_files -norecurse [glob -directory $rtl_dir *.v]

# Add shared Pmod modules from parent folder
add_files -norecurse "$parent_dir/pmod_ad2.v"
add_files -norecurse "$parent_dir/pmod_da4.v"
update_compile_order -fileset sources_1

# Set top module
set_property top arty_s7_top [current_fileset]

# Add constraints file
add_files -fileset constrs_1 -norecurse "$constraints_dir/arty_s7_100.xdc"

# Set synthesis and implementation strategies
set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_ExplorePostRoutePhysOpt [get_runs impl_1]

# Create simulation fileset (optional - add testbench here if needed)
# create_fileset -simset sim_1
# set_property top tb_arty_s7_top [get_filesets sim_1]

puts "=========================================="
puts "Project created successfully!"
puts "Project: $project_name"
puts "Target:  xc7s50csga324-1 (Arty S7)"
puts ""
puts "PmodDA4 (SPI DAC) on JA connector"
puts "PmodAD2 (I2C ADC) on JB connector"
puts ""
puts "To build:"
puts "  1. Click 'Run Synthesis'"
puts "  2. Click 'Run Implementation'"
puts "  3. Click 'Generate Bitstream'"
puts "=========================================="
