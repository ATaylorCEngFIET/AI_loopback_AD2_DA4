// Top-level module for Arty S7-100 ADC to DAC passthrough
// Target: Digilent Arty S7-100 (xc7s100fgga484-1)
// Clock: 12 MHz input -> 50 MHz via MMCM
// PmodDA4 on JA (SPI DAC)
// PmodAD2 on JB (I2C ADC)

module arty_s7_top (
    input wire clk,           // 12 MHz system clock
    input wire rst_btn,       // Reset button (active HIGH when pressed on Arty S7)
    
    // Status LEDs
    output wire [3:0] led,
    
    // I2C interface to PmodAD2 on JB
    output wire scl,
    inout wire sda,
    
    // SPI interface to PmodDA4 on JA
    output wire sck,
    output wire sdi,
    output wire sync_n
);

    // Internal signals
    wire clk_50mhz;
    wire clk_fb;
    wire pll_locked;
    wire rst_n_sync;
    wire rst_n = ~rst_btn;    // Invert: button is active HIGH, logic needs active LOW
    
    // MMCM: 12 MHz input -> 50 MHz output
    // VCO = 12 MHz * 50 = 600 MHz (CLKFBOUT_MULT_F)
    // Output = 600 MHz / 12 = 50 MHz (CLKOUT0_DIVIDE_F)
    MMCME2_BASE #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKFBOUT_MULT_F(50.0),     // 12 * 50 = 600 MHz VCO
        .CLKFBOUT_PHASE(0.0),
        .CLKIN1_PERIOD(83.333),     // 12 MHz = 83.333 ns
        .CLKOUT0_DIVIDE_F(12.0),    // 600 / 12 = 50 MHz
        .CLKOUT0_DUTY_CYCLE(0.5),
        .CLKOUT0_PHASE(0.0),
        .DIVCLK_DIVIDE(1),
        .REF_JITTER1(0.0),
        .STARTUP_WAIT("FALSE")
    ) mmcm_inst (
        .CLKOUT0(clk_50mhz),
        .CLKFBOUT(clk_fb),
        .LOCKED(pll_locked),
        .CLKIN1(clk),
        .PWRDWN(1'b0),
        .RST(~rst_n),
        .CLKFBIN(clk_fb)
    );
    
    // Synchronized reset
    reg [2:0] rst_sync;
    always @(posedge clk_50mhz or negedge rst_n) begin
        if (!rst_n)
            rst_sync <= 3'b000;
        else
            rst_sync <= {rst_sync[1:0], 1'b1};
    end
    assign rst_n_sync = rst_sync[2] & pll_locked;
    
    // Status LEDs
    // LED0: PLL locked / system running
    // LED1: ADC configured successfully (AD7991 ACKed config write)
    // LED2: DAC ready
    // LED3: Heartbeat
    
    wire adc_valid_led;
    wire adc_configured;
    wire [3:0] adc_state;
    wire dac_ready_led;
    reg [25:0] heartbeat_counter;
    
    always @(posedge clk_50mhz or negedge rst_n_sync) begin
        if (!rst_n_sync)
            heartbeat_counter <= 26'd0;
        else
            heartbeat_counter <= heartbeat_counter + 1'b1;
    end
    
    assign led[0] = pll_locked;
    assign led[1] = adc_configured;  // Shows if AD7991 ACKed the config
    assign led[2] = dac_ready_led;
    assign led[3] = heartbeat_counter[25];  // ~1 Hz blink at 50 MHz
    
    // Internal AXI Stream signals - marked for ILA debug
    (* mark_debug = "true" *) wire [11:0] adc_data;
    (* mark_debug = "true" *) wire adc_valid;
    (* mark_debug = "true" *) wire adc_ready;
    (* mark_debug = "true" *) wire [13:0] dac_data;
    (* mark_debug = "true" *) wire dac_valid;
    (* mark_debug = "true" *) wire dac_ready;
    
    // I2C SCL signal for debug (SDA is on IOBUF, can't probe directly)
    (* mark_debug = "true" *) wire scl_debug;
    assign scl_debug = scl;
    
    // ADC state machine debug
    (* mark_debug = "true" *) wire [3:0] adc_state_debug;
    assign adc_state_debug = adc_state;
    
    // Stretch valid/ready for LED visibility
    reg [19:0] adc_valid_stretch;
    reg [19:0] dac_ready_stretch;
    
    always @(posedge clk_50mhz or negedge rst_n_sync) begin
        if (!rst_n_sync) begin
            adc_valid_stretch <= 20'd0;
            dac_ready_stretch <= 20'd0;
        end else begin
            if (adc_valid)
                adc_valid_stretch <= 20'hFFFFF;
            else if (adc_valid_stretch != 0)
                adc_valid_stretch <= adc_valid_stretch - 1'b1;
                
            if (dac_ready)
                dac_ready_stretch <= 20'hFFFFF;
            else if (dac_ready_stretch != 0)
                dac_ready_stretch <= dac_ready_stretch - 1'b1;
        end
    end
    
    assign adc_valid_led = |adc_valid_stretch;
    assign dac_ready_led = |dac_ready_stretch;
    
    // Debug: SDA input value read by FPGA
    wire sda_debug;
    wire sda_oe_debug;
    wire [7:0] shift_debug;
    
    // Mark shift_debug for ILA
    (* mark_debug = "true" *) wire [7:0] shift_debug_ila;
    (* mark_debug = "true" *) wire sda_oe_debug_ila;
    assign shift_debug_ila = shift_debug;
    assign sda_oe_debug_ila = sda_oe_debug;
    
    // SDA separate signals for tristate control
    wire sda_o;   // Output value (always 0 for open-drain)
    wire sda_oe;  // Output enable (active high = drive low)
    
    // SDA tristate at top level: drive low when enabled, else high-Z
    assign sda = sda_oe ? sda_o : 1'bz;
    
    // Instantiate ADC module (I2C to PmodAD2 on JB)
    pmod_ad2 u_adc (
        .clk(clk_50mhz),
        .rst_n(rst_n_sync),
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
    
    // Instantiate DAC module (SPI to PmodDA4 on JA)
    pmod_da4 u_dac (
        .clk(clk_50mhz),
        .rst_n(rst_n_sync),
        .sck(sck),
        .sdi(sdi),
        .sync_n(sync_n),
        .s_axis_tdata(dac_data),
        .s_axis_tvalid(dac_valid),
        .s_axis_tready(dac_ready)
    );

endmodule
