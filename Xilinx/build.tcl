# Vivado Build Script - Synthesize, Implement, and Generate Bitstream
# Usage: vivado -mode batch -source build.tcl
#
# This script assumes the project has already been created with create_project.tcl

set project_dir [file dirname [file normalize [info script]]]
set project_name "adc_dac_passthrough"

# Open existing project
open_project "$project_dir/$project_name/$project_name.xpr"

# Run Synthesis
puts "Starting Synthesis..."
reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}
puts "Synthesis completed successfully!"

# Open synthesized design and insert ILA
puts "Inserting ILA debug core..."
open_run synth_1
source "$project_dir/insert_ila.tcl"

# Create directory for checkpoints and reports
file mkdir "$project_dir/reports"

# Run Implementation from checkpoint (opt_design, place_design, route_design)
puts "Starting Implementation..."
opt_design

# Write debug probes file for hardware manager (must be after opt_design)
write_debug_probes -force "$project_dir/reports/debug_probes.ltx"
place_design
route_design

puts "Implementation completed successfully!"

# Generate Bitstream
puts "Generating Bitstream..."
file mkdir "$project_dir/$project_name/$project_name.runs/impl_1"
write_bitstream -force "$project_dir/$project_name/$project_name.runs/impl_1/arty_s7_top.bit"
puts "Bitstream generation completed!"

# Report timing and utilization
puts ""
puts "=========================================="
puts "Build Complete!"
puts "=========================================="
report_utilization -file "$project_dir/reports/utilization.txt"
report_timing_summary -file "$project_dir/reports/timing_summary.txt"

puts ""
puts "Bitstream: $project_dir/$project_name/$project_name.runs/impl_1/arty_s7_top.bit"
puts "Debug Probes: $project_dir/reports/debug_probes.ltx"
puts "Reports saved to: $project_dir/reports/"
puts ""

close_project
