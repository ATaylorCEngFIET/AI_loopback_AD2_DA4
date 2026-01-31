## Arty S7-50 Master XDC for ADC/DAC Passthrough
## PmodDA4 on JA, PmodAD2 on JB  
## Part: xc7s50csga324-1 (Arty S7 board uses CSG324 package)
## Reference: Digilent Arty-S7-50 Master XDC

## Clock signal - 12 MHz on-board oscillator
set_property -dict { PACKAGE_PIN F14   IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -add -name sys_clk_pin -period 83.333 -waveform {0 41.667} [get_ports { clk }];

## Reset button (active HIGH when pressed) - BTN0  
set_property -dict { PACKAGE_PIN G15   IOSTANDARD LVCMOS33 } [get_ports { rst_btn }];

## LEDs (active high) - LD0-LD3
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports { led[0] }];
set_property -dict { PACKAGE_PIN F13   IOSTANDARD LVCMOS33 } [get_ports { led[1] }];
set_property -dict { PACKAGE_PIN E13   IOSTANDARD LVCMOS33 } [get_ports { led[2] }];
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { led[3] }];

##Pmod Header JA - PmodDA4 (SPI DAC)
## Pin 1 = SYNC_N, Pin 2 = SDI, Pin 4 = SCK
set_property -dict { PACKAGE_PIN L17   IOSTANDARD LVCMOS33 } [get_ports { sync_n }];   # JA1 - SYNC (active low)
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { sdi }];      # JA2 - SDI (MOSI)
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { sck }];      # JA4 - SCK

##Pmod Header JB - PmodAD2 (I2C ADC)
## Pin 3 = SCL, Pin 4 = SDA
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { scl }];      # JB3 - SCL
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { sda }];      # JB4 - SDA

## Slow slew for I2C
set_property SLEW SLOW [get_ports { sda }];
set_property SLEW SLOW [get_ports { scl }];

## Pull-up resistors for I2C open-drain
set_property PULLUP TRUE [get_ports { sda }];
set_property PULLUP TRUE [get_ports { scl }];
