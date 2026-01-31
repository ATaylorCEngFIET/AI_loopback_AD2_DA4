"""
ADC-DAC Passthrough Test using Analog Discovery 3
==================================================
Injects signals via W1 (Wavegen) into PmodAD2 (ADC)
Captures output from PmodDA4 (DAC) on Scope 1+

Hardware Connections:
- AD3 W1 (yellow) -> PmodAD2 A0 input (Vref to V+ on AD2)
- AD3 1+ (orange) -> PmodDA4 VOUTA output
- AD3 1- (orange/white) -> GND
- AD3 GND (black) -> Common GND

Note: PmodAD2 input range is 0-Vref (typically 0-2.5V or 0-3.3V)
      PmodDA4 output range is 0-2.5V (with internal 2.5V reference)
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
    print("Please install Digilent WaveForms software from:")
    print("https://digilent.com/shop/software/digilent-waveforms/")
    sys.exit(1)

# DWF Constants
DwfStateReady = c_int(0)
DwfStateConfig = c_int(4)
DwfStatePrefill = c_int(5)
DwfStateArmed = c_int(1)
DwfStateWait = c_int(7)
DwfStateTriggered = c_int(3)
DwfStateRunning = c_int(3)
DwfStateDone = c_int(2)

funcDC = c_int(0)
funcSine = c_int(1)
funcSquare = c_int(2)
funcTriangle = c_int(3)
funcRampUp = c_int(4)
funcRampDown = c_int(5)

trigsrcNone = c_int(0)
trigsrcAnalogIn = c_int(1)
trigsrcDetectorAnalogIn = c_int(1)


class AnalogDiscovery3:
    """Wrapper class for Analog Discovery 3 operations"""
    
    def __init__(self):
        self.hdwf = c_int()
        self.connected = False
        
    def connect(self):
        """Connect to the first available Analog Discovery device"""
        print("Opening Analog Discovery 3...")
        
        # Enumerate devices
        cDevices = c_int()
        dwf.FDwfEnum(c_int(0), byref(cDevices))
        
        if cDevices.value == 0:
            print("Error: No Digilent device found!")
            return False
        
        print(f"Found {cDevices.value} device(s)")
        
        # Get device name
        szDeviceName = create_string_buffer(64)
        dwf.FDwfEnumDeviceName(c_int(0), szDeviceName)
        print(f"Device: {szDeviceName.value.decode()}")
        
        # Open device
        dwf.FDwfDeviceOpen(c_int(-1), byref(self.hdwf))
        
        if self.hdwf.value == 0:
            szerr = create_string_buffer(512)
            dwf.FDwfGetLastErrorMsg(szerr)
            print(f"Error opening device: {szerr.value.decode()}")
            return False
        
        self.connected = True
        print("Device opened successfully!")
        return True
    
    def disconnect(self):
        """Disconnect from the device"""
        if self.connected:
            dwf.FDwfDeviceClose(self.hdwf)
            self.connected = False
            print("Device closed.")
    
    def setup_wavegen(self, channel=0, func=funcSine, frequency=1000.0, 
                      amplitude=1.0, offset=1.25):
        """
        Configure the waveform generator
        
        Args:
            channel: 0 for W1, 1 for W2
            func: Waveform function (funcSine, funcSquare, etc.)
            frequency: Signal frequency in Hz
            amplitude: Peak-to-peak amplitude in Volts
            offset: DC offset in Volts (for 0-2.5V range, use offset=1.25V with amp=1.25V)
        """
        print(f"Configuring Wavegen Ch{channel+1}: {frequency}Hz, {amplitude}Vpp, offset={offset}V")
        
        dwf.FDwfAnalogOutNodeEnableSet(self.hdwf, c_int(channel), c_int(0), c_int(1))
        dwf.FDwfAnalogOutNodeFunctionSet(self.hdwf, c_int(channel), c_int(0), func)
        dwf.FDwfAnalogOutNodeFrequencySet(self.hdwf, c_int(channel), c_int(0), c_double(frequency))
        dwf.FDwfAnalogOutNodeAmplitudeSet(self.hdwf, c_int(channel), c_int(0), c_double(amplitude))
        dwf.FDwfAnalogOutNodeOffsetSet(self.hdwf, c_int(channel), c_int(0), c_double(offset))
        
    def start_wavegen(self, channel=0):
        """Start the waveform generator"""
        dwf.FDwfAnalogOutConfigure(self.hdwf, c_int(channel), c_int(1))
        print(f"Wavegen Ch{channel+1} started")
        
    def stop_wavegen(self, channel=0):
        """Stop the waveform generator"""
        dwf.FDwfAnalogOutConfigure(self.hdwf, c_int(channel), c_int(0))
        print(f"Wavegen Ch{channel+1} stopped")
    
    def setup_scope(self, channel=0, range_v=5.0, offset=0.0, 
                    sample_rate=1e6, buffer_size=8192):
        """
        Configure the oscilloscope
        
        Args:
            channel: 0 for Ch1, 1 for Ch2
            range_v: Voltage range in Volts
            offset: Vertical offset in Volts
            sample_rate: Sample rate in Hz
            buffer_size: Number of samples to capture
        """
        print(f"Configuring Scope Ch{channel+1}: range={range_v}V, rate={sample_rate/1e6}MHz, samples={buffer_size}")
        
        # Enable channel
        dwf.FDwfAnalogInChannelEnableSet(self.hdwf, c_int(channel), c_int(1))
        dwf.FDwfAnalogInChannelRangeSet(self.hdwf, c_int(channel), c_double(range_v))
        dwf.FDwfAnalogInChannelOffsetSet(self.hdwf, c_int(channel), c_double(offset))
        
        # Configure acquisition
        dwf.FDwfAnalogInFrequencySet(self.hdwf, c_double(sample_rate))
        dwf.FDwfAnalogInBufferSizeSet(self.hdwf, c_int(buffer_size))
        
        # Set trigger
        dwf.FDwfAnalogInTriggerAutoTimeoutSet(self.hdwf, c_double(1.0))  # 1 second timeout
        dwf.FDwfAnalogInTriggerSourceSet(self.hdwf, trigsrcDetectorAnalogIn)
        dwf.FDwfAnalogInTriggerTypeSet(self.hdwf, c_int(0))  # Edge trigger
        dwf.FDwfAnalogInTriggerChannelSet(self.hdwf, c_int(channel))
        dwf.FDwfAnalogInTriggerLevelSet(self.hdwf, c_double(offset))
        dwf.FDwfAnalogInTriggerConditionSet(self.hdwf, c_int(0))  # Rising edge
        
        self.scope_buffer_size = buffer_size
        self.scope_sample_rate = sample_rate
        
    def capture_scope(self, channel=0, timeout=5.0):
        """
        Capture data from oscilloscope
        
        Args:
            channel: 0 for Ch1, 1 for Ch2
            timeout: Timeout in seconds
            
        Returns:
            tuple: (time_array, voltage_array)
        """
        print(f"Capturing Scope Ch{channel+1}...")
        
        # Start acquisition
        dwf.FDwfAnalogInConfigure(self.hdwf, c_int(1), c_int(1))
        
        # Wait for acquisition to complete
        sts = c_int()
        start_time = time.time()
        
        while True:
            dwf.FDwfAnalogInStatus(self.hdwf, c_int(1), byref(sts))
            if sts.value == DwfStateDone.value:
                break
            if time.time() - start_time > timeout:
                print("Warning: Capture timeout!")
                break
            time.sleep(0.01)
        
        # Read data
        rg = (c_double * self.scope_buffer_size)()
        dwf.FDwfAnalogInStatusData(self.hdwf, c_int(channel), rg, c_int(self.scope_buffer_size))
        
        # Create time array
        t = np.linspace(0, self.scope_buffer_size / self.scope_sample_rate, 
                        self.scope_buffer_size)
        v = np.array(list(rg))
        
        print(f"Captured {len(v)} samples")
        return t, v
    
    def capture_both_channels(self, timeout=5.0):
        """
        Capture data from both scope channels simultaneously
        
        Returns:
            tuple: (time_array, ch1_voltage_array, ch2_voltage_array)
        """
        print("Capturing both Scope channels...")
        
        # Enable both channels
        dwf.FDwfAnalogInChannelEnableSet(self.hdwf, c_int(-1), c_int(1))  # -1 for all channels
        
        # Start acquisition
        dwf.FDwfAnalogInConfigure(self.hdwf, c_int(1), c_int(1))
        
        # Wait for acquisition to complete
        sts = c_int()
        start_time = time.time()
        
        while True:
            dwf.FDwfAnalogInStatus(self.hdwf, c_int(1), byref(sts))
            if sts.value == DwfStateDone.value:
                break
            if time.time() - start_time > timeout:
                print("Warning: Capture timeout!")
                break
            time.sleep(0.01)
        
        # Read data from both channels
        rg1 = (c_double * self.scope_buffer_size)()
        rg2 = (c_double * self.scope_buffer_size)()
        dwf.FDwfAnalogInStatusData(self.hdwf, c_int(0), rg1, c_int(self.scope_buffer_size))
        dwf.FDwfAnalogInStatusData(self.hdwf, c_int(1), rg2, c_int(self.scope_buffer_size))
        
        # Create time array
        t = np.linspace(0, self.scope_buffer_size / self.scope_sample_rate, 
                        self.scope_buffer_size)
        v1 = np.array(list(rg1))
        v2 = np.array(list(rg2))
        
        print(f"Captured {len(v1)} samples per channel")
        return t, v1, v2


def run_passthrough_test(ad3, frequency=100.0, waveform=funcSine, 
                         amplitude=1.0, offset=1.25, duration=0.1):
    """
    Run a single passthrough test
    
    Args:
        ad3: AnalogDiscovery3 instance
        frequency: Test signal frequency in Hz
        waveform: Waveform type
        amplitude: Signal amplitude (Vpp/2)
        offset: DC offset to center signal in ADC range
        duration: Capture duration in seconds
        
    Returns:
        tuple: (time, input_signal, output_signal)
    """
    # Calculate sample rate and buffer size
    sample_rate = max(frequency * 100, 10000)  # At least 100 samples per cycle
    buffer_size = int(sample_rate * duration)
    buffer_size = min(buffer_size, 8192)  # Limit to device buffer
    
    # Setup waveform generator (W1 -> ADC input)
    ad3.setup_wavegen(channel=0, func=waveform, frequency=frequency,
                      amplitude=amplitude, offset=offset)
    
    # Setup scope to capture both input (W1 feedback) and output (DAC)
    # Ch1: DAC output (1+)
    # Ch2: Can be used for input monitoring if looped back
    ad3.setup_scope(channel=0, range_v=5.0, offset=0.0,
                    sample_rate=sample_rate, buffer_size=buffer_size)
    
    # Start waveform generator
    ad3.start_wavegen(channel=0)
    time.sleep(0.1)  # Let signal stabilize
    
    # Capture output
    t, v_out = ad3.capture_scope(channel=0)
    
    # Generate ideal input signal for comparison
    v_in = offset + amplitude * np.sin(2 * np.pi * frequency * t)
    
    return t, v_in, v_out


def plot_results(t, v_in, v_out, title="ADC-DAC Passthrough Test", 
                 save_path=None):
    """
    Plot input and output signals
    
    Args:
        t: Time array
        v_in: Input voltage array
        v_out: Output voltage array
        title: Plot title
        save_path: Optional path to save figure
    """
    fig, axes = plt.subplots(3, 1, figsize=(12, 10))
    
    # Plot input signal
    axes[0].plot(t * 1000, v_in, 'b-', linewidth=1, label='Input (W1 -> ADC)')
    axes[0].set_xlabel('Time (ms)')
    axes[0].set_ylabel('Voltage (V)')
    axes[0].set_title('Input Signal (Waveform Generator W1)')
    axes[0].grid(True, alpha=0.3)
    axes[0].legend(loc='upper right')
    axes[0].set_ylim(-0.5, 3.0)
    
    # Plot output signal
    axes[1].plot(t * 1000, v_out, 'r-', linewidth=1, label='Output (DAC -> Scope 1+)')
    axes[1].set_xlabel('Time (ms)')
    axes[1].set_ylabel('Voltage (V)')
    axes[1].set_title('Output Signal (DAC Output captured on Scope)')
    axes[1].grid(True, alpha=0.3)
    axes[1].legend(loc='upper right')
    axes[1].set_ylim(-0.5, 3.0)
    
    # Plot overlay
    axes[2].plot(t * 1000, v_in, 'b-', linewidth=1, alpha=0.7, label='Input')
    axes[2].plot(t * 1000, v_out, 'r-', linewidth=1, alpha=0.7, label='Output')
    axes[2].set_xlabel('Time (ms)')
    axes[2].set_ylabel('Voltage (V)')
    axes[2].set_title('Input vs Output Overlay')
    axes[2].grid(True, alpha=0.3)
    axes[2].legend(loc='upper right')
    axes[2].set_ylim(-0.5, 3.0)
    
    plt.suptitle(title, fontsize=14, fontweight='bold')
    plt.tight_layout()
    
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f"Plot saved to: {save_path}")
    
    plt.show()


def plot_frequency_response(frequencies, gains, phases, save_path=None):
    """
    Plot frequency response (Bode plot)
    """
    fig, axes = plt.subplots(2, 1, figsize=(10, 8))
    
    # Magnitude plot
    axes[0].semilogx(frequencies, 20 * np.log10(gains), 'b-o', linewidth=2, markersize=6)
    axes[0].set_xlabel('Frequency (Hz)')
    axes[0].set_ylabel('Gain (dB)')
    axes[0].set_title('Magnitude Response')
    axes[0].grid(True, which='both', alpha=0.3)
    axes[0].axhline(y=-3, color='r', linestyle='--', label='-3dB')
    axes[0].legend()
    
    # Phase plot
    axes[1].semilogx(frequencies, phases, 'r-o', linewidth=2, markersize=6)
    axes[1].set_xlabel('Frequency (Hz)')
    axes[1].set_ylabel('Phase (degrees)')
    axes[1].set_title('Phase Response')
    axes[1].grid(True, which='both', alpha=0.3)
    
    plt.suptitle('ADC-DAC Passthrough Frequency Response', fontsize=14, fontweight='bold')
    plt.tight_layout()
    
    if save_path:
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        print(f"Frequency response plot saved to: {save_path}")
    
    plt.show()


def calculate_metrics(v_in, v_out, t):
    """
    Calculate performance metrics
    """
    # RMS values
    rms_in = np.sqrt(np.mean((v_in - np.mean(v_in))**2))
    rms_out = np.sqrt(np.mean((v_out - np.mean(v_out))**2))
    
    # Gain
    gain = rms_out / rms_in if rms_in > 0 else 0
    
    # Cross-correlation for phase delay
    correlation = np.correlate(v_out - np.mean(v_out), 
                               v_in - np.mean(v_in), mode='full')
    lag = np.argmax(correlation) - len(v_in) + 1
    dt = t[1] - t[0]
    delay = lag * dt
    
    return {
        'rms_in': rms_in,
        'rms_out': rms_out,
        'gain': gain,
        'gain_db': 20 * np.log10(gain) if gain > 0 else -np.inf,
        'delay_us': delay * 1e6,
        'dc_in': np.mean(v_in),
        'dc_out': np.mean(v_out)
    }


def main():
    """Main test function"""
    print("=" * 60)
    print("ADC-DAC Passthrough Test")
    print("Using Analog Discovery 3")
    print("=" * 60)
    print()
    
    # Create AD3 instance
    ad3 = AnalogDiscovery3()
    
    try:
        # Connect to device
        if not ad3.connect():
            return
        
        print()
        print("-" * 60)
        print("Test 1: Sine Wave Passthrough (100 Hz)")
        print("-" * 60)
        
        # Run sine wave test
        t, v_in, v_out = run_passthrough_test(
            ad3, 
            frequency=100.0,
            waveform=funcSine,
            amplitude=1.0,      # 1V amplitude (2Vpp)
            offset=1.25,        # Center at 1.25V for 0-2.5V range
            duration=0.05       # 50ms capture
        )
        
        # Calculate metrics
        metrics = calculate_metrics(v_in, v_out, t)
        print(f"\nMetrics:")
        print(f"  Input RMS:  {metrics['rms_in']:.4f} V")
        print(f"  Output RMS: {metrics['rms_out']:.4f} V")
        print(f"  Gain:       {metrics['gain']:.4f} ({metrics['gain_db']:.2f} dB)")
        print(f"  Delay:      {metrics['delay_us']:.2f} µs")
        print(f"  DC In:      {metrics['dc_in']:.4f} V")
        print(f"  DC Out:     {metrics['dc_out']:.4f} V")
        
        # Plot results
        plot_results(t, v_in, v_out, 
                    title="100 Hz Sine Wave Passthrough",
                    save_path="test_sine_100hz.png")
        
        print()
        print("-" * 60)
        print("Test 2: Triangle Wave Passthrough (50 Hz)")
        print("-" * 60)
        
        # Run triangle wave test
        t, v_in, v_out = run_passthrough_test(
            ad3,
            frequency=50.0,
            waveform=funcTriangle,
            amplitude=1.0,
            offset=1.25,
            duration=0.1
        )
        
        # Generate actual triangle wave for input
        period = 1.0 / 50.0
        v_in = 1.25 + 1.0 * (2 * np.abs(2 * (t / period - np.floor(t / period + 0.5))) - 1)
        
        metrics = calculate_metrics(v_in, v_out, t)
        print(f"\nMetrics:")
        print(f"  Input RMS:  {metrics['rms_in']:.4f} V")
        print(f"  Output RMS: {metrics['rms_out']:.4f} V")
        print(f"  Gain:       {metrics['gain']:.4f} ({metrics['gain_db']:.2f} dB)")
        
        plot_results(t, v_in, v_out,
                    title="50 Hz Triangle Wave Passthrough",
                    save_path="test_triangle_50hz.png")
        
        print()
        print("-" * 60)
        print("Test 3: Frequency Sweep")
        print("-" * 60)
        
        # Frequency sweep test
        test_frequencies = [10, 20, 50, 100, 200, 500, 1000, 2000]
        gains = []
        phases = []
        
        for freq in test_frequencies:
            print(f"  Testing {freq} Hz...", end=" ")
            t, v_in, v_out = run_passthrough_test(
                ad3,
                frequency=freq,
                waveform=funcSine,
                amplitude=1.0,
                offset=1.25,
                duration=max(0.02, 5.0/freq)  # At least 5 cycles
            )
            
            metrics = calculate_metrics(v_in, v_out, t)
            gains.append(metrics['gain'])
            
            # Calculate phase from delay
            phase = -(metrics['delay_us'] * 1e-6) * freq * 360
            phases.append(phase % 360 - 180 if phase % 360 > 180 else phase % 360)
            
            print(f"Gain: {metrics['gain']:.3f} ({metrics['gain_db']:.1f} dB)")
        
        # Plot frequency response
        plot_frequency_response(test_frequencies, gains, phases,
                               save_path="test_frequency_response.png")
        
        print()
        print("=" * 60)
        print("All tests completed!")
        print("=" * 60)
        
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        
    finally:
        # Stop waveform generator and disconnect
        ad3.stop_wavegen(channel=0)
        ad3.disconnect()


if __name__ == "__main__":
    main()
