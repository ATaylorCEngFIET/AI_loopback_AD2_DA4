@echo off
REM Compile all Verilog files with full visibility
vlog +acc pmod_ad2.v pmod_da4.v adc_dac_passthrough.v tb_adc_dac_passthrough.v

REM Launch QuestaSim GUI with full signal access
vsim -gui -voptargs=+acc work.tb_adc_dac_passthrough -do waves.do
