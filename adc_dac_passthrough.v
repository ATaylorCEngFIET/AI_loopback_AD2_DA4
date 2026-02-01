// Top-level module for ADC to DAC passthrough
// Maps 12-bit ADC data to upper 12 bits of 14-bit DAC

module adc_dac_passthrough (
    input wire clk,           // 50 MHz system clock
    input wire rst_n,         // Active low reset
    
    // I2C interface to PmodAD2 (ADC)
    output wire scl,
    inout wire sda,
    
    // SPI interface to PmodDA4 (DAC)
    output wire sck,
    output wire sdi,
    output wire sync_n
);

    // AXI Stream signals between ADC and DAC
    wire [11:0] adc_data;
    wire adc_valid;
    wire adc_ready;
    
    wire [13:0] dac_data;
    wire dac_valid;
    wire dac_ready;
    
    // Debug signals (optional)
    wire adc_configured;
    wire [3:0] adc_state;
    wire sda_debug;
    wire sda_oe_debug;
    wire [7:0] shift_debug;
    
    // SDA separate signals for tristate control
    wire sda_o;   // Output value (always 0 for open-drain)
    wire sda_oe;  // Output enable (active high = drive low)
    
    // SDA tristate at top level: drive low when enabled, else high-Z
    assign sda = sda_oe ? sda_o : 1'bz;
    
    // Instantiate ADC module
    pmod_ad2 u_adc (
        .clk(clk),
        .rst_n(rst_n),
        .scl(scl),
        .sda_i(sda),
        .sda_o(sda_o),
        .sda_oe(sda_oe),
        .m_axis_tdata(adc_data),
        .m_axis_tvalid(adc_valid),
        .m_axis_tready(adc_ready),
        .configured_out(adc_configured),
        .state_out(adc_state),
        .sda_debug(sda_debug),
        .sda_oe_debug(sda_oe_debug),
        .shift_debug(shift_debug)
    );
    
    // Map 12-bit ADC to 14-bit DAC (upper 12 bits, lower 2 bits zero)
    assign dac_data = {adc_data[11:0], 2'b00};
    assign dac_valid = adc_valid;
    assign adc_ready = dac_ready;
    
    // Instantiate DAC module
    pmod_da4 u_dac (
        .clk(clk),
        .rst_n(rst_n),
        .sck(sck),
        .sdi(sdi),
        .sync_n(sync_n),
        .s_axis_tdata(dac_data),
        .s_axis_tvalid(dac_valid),
        .s_axis_tready(dac_ready)
    );

endmodule
