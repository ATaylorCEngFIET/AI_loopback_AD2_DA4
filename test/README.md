# ADC-DAC Passthrough Test Suite

## Overview
This test suite uses an Analog Discovery 3 (AD3) to verify the FPGA ADC-DAC passthrough design.

## Hardware Connections

### Analog Discovery 3 to Pmod Connections

| AD3 Pin | Wire Color | Connect To | Description |
|---------|------------|------------|-------------|
| W1 | Yellow | PmodAD2 A0 | Waveform generator output -> ADC input |
| 1+ | Orange | PmodDA4 VOUTA | Scope Ch1+ captures DAC output |
| 1- | Orange/White | GND | Scope Ch1 ground reference |
| GND | Black | Common GND | System ground |

### Pmod Pin Reference

**PmodAD2 (I2C ADC on JB):**
- A0: Analog input channel 0 (connect W1 here)
- V+: Connect to AD3's V+ or external 3.3V for reference
- GND: Connect to common ground

**PmodDA4 (SPI DAC on JA):**
- VOUTA: DAC channel A output (connect Scope 1+ here)
- GND: Connect to common ground

## Software Requirements

1. **Digilent WaveForms** - Install from: https://digilent.com/shop/software/digilent-waveforms/
2. **Python 3.8+** with packages listed in requirements.txt

## Installation

```bash
cd c:\hdl_renesas\ai\test
pip install -r requirements.txt
```

## Running the Tests

```bash
python adc_dac_test.py
```

## Tests Performed

### Test 1: Sine Wave Passthrough (100 Hz)
- Injects a 100 Hz sine wave centered at 1.25V
- Captures DAC output and compares with input
- Calculates gain, delay, and DC offset

### Test 2: Triangle Wave Passthrough (50 Hz)
- Injects a 50 Hz triangle wave
- Tests linearity of the ADC-DAC chain

### Test 3: Frequency Sweep
- Sweeps from 10 Hz to 2000 Hz
- Generates Bode plot (magnitude and phase)
- Identifies bandwidth limitations

## Expected Results

- **Gain**: Should be close to 1.0 (0 dB) if ADC and DAC have same voltage reference
- **Delay**: System latency through I2C read, FPGA processing, and SPI write
- **DC Offset**: Should track the input DC offset

## Output Files

- `test_sine_100hz.png` - Sine wave test results
- `test_triangle_50hz.png` - Triangle wave test results  
- `test_frequency_response.png` - Bode plot

## Troubleshooting

1. **No device found**: Ensure WaveForms software is installed and AD3 is connected via USB
2. **Flat output signal**: Check DAC connections and FPGA programming
3. **No output variation**: Verify ADC is receiving the input signal
4. **Gain too low/high**: Check voltage reference settings on Pmod modules
