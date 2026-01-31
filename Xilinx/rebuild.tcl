# Rebuild script
open_project adc_dac_passthrough/adc_dac_passthrough.xpr
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "Build complete!"
exit
