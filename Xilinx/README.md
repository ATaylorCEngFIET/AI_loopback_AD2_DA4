# ADC to DAC Passthrough - Arty S7-100 Project

## Target Hardware
- **FPGA**: Digilent Arty S7-100 (Xilinx xc7s100fgga484-1)
- **Clock**: 100 MHz on-board oscillator

## Pmod Connections
| Pmod    | Connector | Function               |
|---------|-----------|------------------------|
| PmodDA4 | JA        | SPI DAC (AD5628)       |
| PmodAD2 | JB        | I2C ADC (AD7991)       |

### JA Pinout (PmodDA4 - SPI)
| JA Pin | Signal  | FPGA Pin | Description |
|--------|---------|----------|-------------|
| 1      | SDI     | L17      | SPI MOSI    |
| 2      | -       | L18      | Not used    |
| 3      | SCK     | M14      | SPI Clock   |
| 4      | SYNC_N  | N14      | Chip Select |

### JB Pinout (PmodAD2 - I2C)
| JB Pin | Signal | FPGA Pin | Description |
|--------|--------|----------|-------------|
| 1      | SCL    | P17      | I2C Clock   |
| 2      | SDA    | P18      | I2C Data    |

## Project Structure
```
Xilinx/
├── rtl/
│   └── arty_s7_top.v     # Top-level module
├── constraints/
│   └── arty_s7_100.xdc   # Pin assignments & timing
├── reports/              # Build reports
├── create_project.tcl    # Create Vivado project
├── build.tcl             # Build bitstream
├── program_fpga.tcl      # Program FPGA
└── README.md             # This file

Parent folder (../):
├── pmod_ad2.v            # I2C ADC driver (shared)
└── pmod_da4.v            # SPI DAC driver (shared)
```

## Building the Project

### Option 1: GUI Mode
1. Open Vivado
2. Go to **Tools → Run Tcl Script**
3. Select `create_project.tcl`
4. Click **Run Synthesis**, then **Run Implementation**, then **Generate Bitstream**

### Option 2: Command Line
```batch
cd Xilinx
vivado -mode batch -source create_project.tcl
vivado -mode batch -source build.tcl
```

## Programming the FPGA

### Option 1: GUI Mode
1. Open Hardware Manager in Vivado
2. Connect to target
3. Program device with `arty_s7_top.bit`

### Option 2: Command Line
```batch
vivado -mode batch -source program_fpga.tcl
```

## User Interface
| LED  | Function           |
|------|--------------------|
| LED0 | System running     |
| LED1 | ADC data valid     |
| LED2 | DAC ready          |
| LED3 | Heartbeat (~1 Hz)  |

| Button | Function     |
|--------|--------------|
| BTN0   | Reset (low)  |

## Design Notes
- 100 MHz input clock divided to 50 MHz internally for timing compatibility
- I2C runs at 1 MHz SCL frequency
- SPI runs at 1 MHz SCK frequency
- 12-bit ADC data mapped to upper 12 bits of 14-bit DAC
- Continuous ADC sampling with ~1ms interval
