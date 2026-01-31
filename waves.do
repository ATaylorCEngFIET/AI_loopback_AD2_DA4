# Log all signals for post-simulation viewing
log -r /*

# Add testbench signals
add wave -divider {Clocks & Reset}
add wave /tb_adc_dac_passthrough/clk
add wave /tb_adc_dac_passthrough/rst_n

add wave -divider {I2C Bus}
add wave /tb_adc_dac_passthrough/scl
add wave /tb_adc_dac_passthrough/sda
add wave /tb_adc_dac_passthrough/sda_slave_out
add wave /tb_adc_dac_passthrough/sda_slave_oe

add wave -divider {I2C Slave State}
add wave /tb_adc_dac_passthrough/i2c_state
add wave /tb_adc_dac_passthrough/i2c_bit_count
add wave /tb_adc_dac_passthrough/i2c_tx_data
add wave /tb_adc_dac_passthrough/adc_test_value

add wave -divider {SPI Bus}
add wave /tb_adc_dac_passthrough/sck
add wave /tb_adc_dac_passthrough/sdi
add wave /tb_adc_dac_passthrough/sync_n

add wave -divider {SPI Capture}
add wave /tb_adc_dac_passthrough/spi_captured_data
add wave /tb_adc_dac_passthrough/spi_bit_counter

add wave -divider {DUT - Top Level}
add wave /tb_adc_dac_passthrough/dut/adc_data
add wave /tb_adc_dac_passthrough/dut/adc_valid
add wave /tb_adc_dac_passthrough/dut/adc_ready
add wave /tb_adc_dac_passthrough/dut/dac_data
add wave /tb_adc_dac_passthrough/dut/dac_valid
add wave /tb_adc_dac_passthrough/dut/dac_ready

add wave -divider {ADC Module (pmod_ad2)}
add wave /tb_adc_dac_passthrough/dut/u_adc/state
add wave /tb_adc_dac_passthrough/dut/u_adc/bit_counter
add wave /tb_adc_dac_passthrough/dut/u_adc/buffer
add wave /tb_adc_dac_passthrough/dut/u_adc/scl_out
add wave /tb_adc_dac_passthrough/dut/u_adc/sda_out

add wave -divider {DAC Module (pmod_da4)}
add wave /tb_adc_dac_passthrough/dut/u_dac/state
add wave /tb_adc_dac_passthrough/dut/u_dac/shift_reg
add wave /tb_adc_dac_passthrough/dut/u_dac/bit_counter

# Configure wave window
configure wave -namecolwidth 250
configure wave -valuecolwidth 100
WaveRestoreZoom {0 ns} {1 ms}
