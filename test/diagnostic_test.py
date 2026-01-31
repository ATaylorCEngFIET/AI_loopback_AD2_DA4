"""
ADC-DAC Passthrough Test - Diagnostic Version
==============================================
Tests ADC to DAC passthrough using Analog Discovery 3:
- Scope Ch1 (1+): DAC output from PmodDA4

Hardware Connections:
- AD3 W1 (yellow) -> PmodAD2 A0 input
- AD3 1+ (orange) -> PmodDA4 VOUTA output  
- AD3 GND (black) -> Common GND
"""

import sys
import time
import numpy as np
import matplotlib.pyplot as plt
from ctypes import *

# Try to import DWF library
try:
    if sys.platform.startswith("win"):
        dwf = cdll.dwf
    elif sys.platform.startswith("darwin"):
        dwf = cdll.LoadLibrary("/Library/Frameworks/dwf.framework/dwf")
    else:
        dwf = cdll.LoadLibrary("libdwf.so")
except OSError as e:
    print("Error: Could not load DWF library.")
    print("Please install Digilent WaveForms software.")
    sys.exit(1)

# DWF Constants
DwfStateDone = c_int(2)
funcSine = c_int(1)
funcSquare = c_int(2)
funcTriangle = c_int(3)
trigsrcNone = c_int(0)


class AD3Tester:
    """Simplified Analog Discovery 3 tester for diagnostics"""
    
    def __init__(self):
        self.hdwf = c_int()
        
    def connect(self):
        """Connect to AD3"""
        print("Connecting to Analog Discovery 3...")
        
        cDevices = c_int()
        dwf.FDwfEnum(c_int(0), byref(cDevices))
        
        if cDevices.value == 0:
            print("ERROR: No device found!")
            return False
            
        szName = create_string_buffer(64)
        dwf.FDwfEnumDeviceName(c_int(0), szName)
        print(f"Found: {szName.value.decode()}")
        
        dwf.FDwfDeviceOpen(c_int(-1), byref(self.hdwf))
        if self.hdwf.value == 0:
            szerr = create_string_buffer(512)
            dwf.FDwfGetLastErrorMsg(szerr)
            print(f"ERROR: {szerr.value.decode()}")
            return False
            
        print("Connected!")
        return True
        
    def disconnect(self):
        """Disconnect"""
        dwf.FDwfAnalogOutReset(self.hdwf, c_int(-1))
        dwf.FDwfDeviceClose(self.hdwf)
        print("Disconnected.")
        
    def generate_and_capture(self, frequency=100, amplitude=1.0, offset=1.25,
                             sample_rate=100000, num_samples=8192):
        """
        Generate waveform on W1 and capture on both scope channels
        """
        print(f"\n{'='*60}")
        print(f"Test: {frequency} Hz Sine Wave")
        print(f"  W1 Output: {offset-amplitude:.2f}V to {offset+amplitude:.2f}V")
        print(f"  Sample Rate: {sample_rate/1000:.1f} kHz")
        print(f"  Samples: {num_samples}")
        print(f"{'='*60}")
        
        # Configure W1 waveform generator
        print("\nConfiguring Waveform Generator W1...")
        dwf.FDwfAnalogOutNodeEnableSet(self.hdwf, c_int(0), c_int(0), c_int(1))
        dwf.FDwfAnalogOutNodeFunctionSet(self.hdwf, c_int(0), c_int(0), funcSine)
        dwf.FDwfAnalogOutNodeFrequencySet(self.hdwf, c_int(0), c_int(0), c_double(frequency))
        dwf.FDwfAnalogOutNodeAmplitudeSet(self.hdwf, c_int(0), c_int(0), c_double(amplitude))
        dwf.FDwfAnalogOutNodeOffsetSet(self.hdwf, c_int(0), c_int(0), c_double(offset))
        
        # Start wavegen
        dwf.FDwfAnalogOutConfigure(self.hdwf, c_int(0), c_int(1))
        print("W1 Started.")
        
        # Wait for output to stabilize
        time.sleep(0.5)
        
        # Configure oscilloscope - Ch1 only
        print("\nConfiguring Oscilloscope...")
        
        # Enable Ch1 with 5V range
        dwf.FDwfAnalogInChannelEnableSet(self.hdwf, c_int(0), c_int(1))  # Ch1
        dwf.FDwfAnalogInChannelRangeSet(self.hdwf, c_int(0), c_double(5.0))
        dwf.FDwfAnalogInChannelOffsetSet(self.hdwf, c_int(0), c_double(0.0))
        
        # Acquisition settings
        dwf.FDwfAnalogInFrequencySet(self.hdwf, c_double(sample_rate))
        dwf.FDwfAnalogInBufferSizeSet(self.hdwf, c_int(num_samples))
        
        # Trigger - auto (no external trigger)
        dwf.FDwfAnalogInTriggerSourceSet(self.hdwf, trigsrcNone)
        dwf.FDwfAnalogInTriggerAutoTimeoutSet(self.hdwf, c_double(2.0))
        
        # Start acquisition
        dwf.FDwfAnalogInConfigure(self.hdwf, c_int(1), c_int(1))
        print("Scope acquisition started...")
        
        # Wait for completion
        sts = c_int()
        timeout = time.time() + 5
        while time.time() < timeout:
            dwf.FDwfAnalogInStatus(self.hdwf, c_int(1), byref(sts))
            if sts.value == DwfStateDone.value:
                break
            time.sleep(0.01)
        
        if sts.value != DwfStateDone.value:
            print("WARNING: Capture timeout!")
        
        # Read data from Ch1
        ch1_data = (c_double * num_samples)()
        
        dwf.FDwfAnalogInStatusData(self.hdwf, c_int(0), ch1_data, c_int(num_samples))
        
        ch1 = np.array(list(ch1_data))
        t = np.linspace(0, num_samples / sample_rate, num_samples)
        
        # Generate ideal input waveform
        ideal_input = offset + amplitude * np.sin(2 * np.pi * frequency * t)
        
        # Calculate statistics
        print("\n--- Signal Statistics ---")
        print(f"Ch1 (DAC Output):  Min={ch1.min():.3f}V  Max={ch1.max():.3f}V  Mean={ch1.mean():.3f}V  RMS_AC={np.std(ch1):.4f}V")
        print(f"Expected Input:    Min={offset-amplitude:.3f}V  Max={offset+amplitude:.3f}V  Mean={offset:.3f}V")
        
        expected_pp = 2 * amplitude
        
        # Check DAC output
        ch1_pp = ch1.max() - ch1.min()
        if ch1_pp > 0.1:
            gain = ch1_pp / expected_pp
            print(f"\n✓ Ch1 (DAC) shows signal: {ch1_pp:.3f}Vpp")
            print(f"  -> Passthrough gain: {gain:.3f} ({20*np.log10(gain):.1f} dB)")
        else:
            print(f"\n✗ Ch1 shows weak/no signal: {ch1_pp:.3f}Vpp")
            print("  -> Check DAC output wiring to Scope 1+")
            print("  -> Verify FPGA LEDs indicate ADC activity")
        
        # Stop wavegen
        dwf.FDwfAnalogOutConfigure(self.hdwf, c_int(0), c_int(0))
        
        return t, ideal_input, ch1, frequency
    

def plot_diagnostic(t, ideal_input, ch1, freq, save_path="diagnostic_plot.png"):
    """Create diagnostic plot"""
    fig, axes = plt.subplots(3, 1, figsize=(14, 10))
    
    # Limit to first portion for clarity
    n_show = min(len(t), int(10 / freq * t[-1] / t[1]))  # Show ~10 cycles
    t_ms = t[:n_show] * 1000
    
    # Ideal input
    axes[0].plot(t_ms, ideal_input[:n_show], 'b-', linewidth=1.5)
    axes[0].set_ylabel('Voltage (V)')
    axes[0].set_title(f'Ideal Input Signal (W1: {freq} Hz Sine Wave)')
    axes[0].grid(True, alpha=0.3)
    axes[0].set_ylim(-0.5, 3.0)
    axes[0].axhline(y=0, color='k', linewidth=0.5)
    
    # Ch1 - DAC output
    axes[1].plot(t_ms, ch1[:n_show], 'r-', linewidth=1)
    axes[1].set_ylabel('Voltage (V)')
    axes[1].set_title('Scope Ch1 (1+ pin) - DAC Output')
    axes[1].grid(True, alpha=0.3)
    axes[1].set_ylim(-0.5, 3.0)
    axes[1].axhline(y=0, color='k', linewidth=0.5)
    
    # Overlay comparison
    axes[2].plot(t_ms, ideal_input[:n_show], 'b-', linewidth=1, alpha=0.7, label='Ideal Input')
    axes[2].plot(t_ms, ch1[:n_show], 'r-', linewidth=1, alpha=0.7, label='DAC Output (Ch1)')
    axes[2].set_xlabel('Time (ms)')
    axes[2].set_ylabel('Voltage (V)')
    axes[2].set_title('Input vs Output Comparison')
    axes[2].grid(True, alpha=0.3)
    axes[2].set_ylim(-0.5, 3.0)
    axes[2].legend(loc='upper right')
    axes[2].axhline(y=0, color='k', linewidth=0.5)
    
    plt.suptitle(f'ADC-DAC Passthrough Diagnostic - {freq} Hz', fontsize=14, fontweight='bold')
    plt.tight_layout()
    
    plt.savefig(save_path, dpi=150, bbox_inches='tight')
    print(f"\nPlot saved: {save_path}")
    plt.show()


def main():
    print("=" * 60)
    print("ADC-DAC Passthrough Test - Diagnostic Mode")
    print("=" * 60)
    print()
    print("Connection Guide:")
    print("  W1 (Yellow)  -> PmodAD2 A0 (ADC input)")
    print("  1+ (Orange)  -> PmodDA4 VOUTA (DAC output)")
    print("  GND (Black)  -> Common ground")
    print()
    
    tester = AD3Tester()
    
    try:
        if not tester.connect():
            return
        
        # Run test at different frequencies
        # ADC sample rate is ~3.5 kHz (I2C limited), so use low frequencies
        # to get smooth waveforms (need 20+ samples/cycle)
        for freq in [5, 10, 20]:
            t, ideal_input, ch1, f = tester.generate_and_capture(
                frequency=freq,
                amplitude=1.0,
                offset=1.25,
                sample_rate=max(freq * 200, 10000),
                num_samples=8192
            )
            
            plot_diagnostic(t, ideal_input, ch1, f, 
                          save_path=f"diagnostic_{freq}hz.png")
            
            input("\nPress Enter to continue to next test...")
            
        print("\n" + "=" * 60)
        print("Diagnostic tests completed!")
        print("=" * 60)
        
    except Exception as e:
        print(f"\nError: {e}")
        import traceback
        traceback.print_exc()
        
    finally:
        tester.disconnect()


if __name__ == "__main__":
    main()
