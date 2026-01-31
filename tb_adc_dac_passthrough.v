// Testbench for ADC to DAC passthrough design
// Self-checking testbench with proper I2C slave model for AD7991
// Tests: Config write + Repeated Start + 2-byte read

`timescale 1ns/1ps

module tb_adc_dac_passthrough;

    // Clock and reset
    reg clk;
    reg rst_n;
    
    // I2C interface (ADC)
    wire scl;
    wire sda;
    
    // SPI interface (DAC)
    wire sck;
    wire sdi;
    wire sync_n;
    
    // I2C slave model signals
    reg sda_slave_out;
    reg sda_slave_oe;
    assign sda = sda_slave_oe ? sda_slave_out : 1'bz;
    
    // I2C pullup resistors
    pullup(sda);
    pullup(scl);
    
    // Test data
    reg [11:0] adc_test_value;
    integer error_count;
    integer test_count;
    
    // Captured SPI data
    reg [31:0] spi_captured_data;
    reg [5:0] spi_bit_counter;
    
    // Expected value queue (simple FIFO for expected ADC values)
    reg [11:0] expected_queue [0:7];
    integer expected_head, expected_tail;
    
    // I2C protocol tracking
    reg [7:0] i2c_addr_received;
    reg [7:0] i2c_config_received;
    reg i2c_config_written;
    reg i2c_read_started;
    
    // DUT
    adc_dac_passthrough dut (
        .clk(clk),
        .rst_n(rst_n),
        .scl(scl),
        .sda(sda),
        .sck(sck),
        .sdi(sdi),
        .sync_n(sync_n)
    );
    
    // Monitor AXI Stream transactions
    always @(posedge clk) begin
        if (dut.adc_valid && dut.adc_ready) begin
            $display("[%0t] AXI Stream: ADC->DAC transfer, data=0x%03h", 
                     $time, dut.adc_data);
        end
    end
    
    // Clock generation - 50 MHz
    initial begin
        clk = 0;
        forever #10 clk = ~clk;  // 20ns period = 50 MHz
    end
    
    //=========================================================================
    // I2C Slave Model - simulates AD7991 with address 0x29
    //=========================================================================
    
    // State machine states
    localparam I2C_IDLE       = 0;
    localparam I2C_GET_ADDR   = 1;
    localparam I2C_ACK_ADDR   = 2;
    localparam I2C_GET_CONFIG = 3;
    localparam I2C_ACK_CONFIG = 4;
    localparam I2C_SEND_BYTE1 = 5;
    localparam I2C_GET_ACK1   = 6;
    localparam I2C_SEND_BYTE2 = 7;
    localparam I2C_GET_NACK   = 8;
    
    reg [3:0] i2c_state;
    reg [3:0] i2c_bit_cnt;
    reg [7:0] i2c_shift_reg;
    reg [15:0] i2c_tx_data;
    reg scl_prev, sda_prev;
    reg ack_clock_seen;  // Track if we've seen the ACK clock cycle
    
    // START/STOP detection
    wire i2c_start = scl && scl_prev && sda_prev && !sda;  // SDA falls while SCL high
    wire i2c_stop  = scl && scl_prev && !sda_prev && sda;  // SDA rises while SCL high
    wire scl_rise  = scl && !scl_prev;
    wire scl_fall  = !scl && scl_prev;
    
    initial begin
        sda_slave_out = 1'b1;
        sda_slave_oe = 1'b0;
        i2c_state = I2C_IDLE;
        i2c_bit_cnt = 0;
        i2c_shift_reg = 0;
        i2c_config_written = 0;
        i2c_read_started = 0;
        adc_test_value = 12'hA5A;  // Test pattern
        scl_prev = 1;
        sda_prev = 1;
        ack_clock_seen = 0;
    end
    
    // Sample previous values
    always @(posedge clk) begin
        scl_prev <= scl;
        sda_prev <= sda;
    end
    
    // I2C state machine
    always @(posedge clk) begin
        if (!rst_n) begin
            i2c_state <= I2C_IDLE;
            sda_slave_oe <= 1'b0;
            i2c_bit_cnt <= 0;
        end else begin
            
            // START condition - reset to address phase
            if (i2c_start) begin
                $display("[%0t] I2C: START detected", $time);
                i2c_state <= I2C_GET_ADDR;
                i2c_bit_cnt <= 0;
                sda_slave_oe <= 1'b0;
            end
            
            // STOP condition - return to idle
            else if (i2c_stop) begin
                $display("[%0t] I2C: STOP detected", $time);
                i2c_state <= I2C_IDLE;
                sda_slave_oe <= 1'b0;
            end
            
            // SCL rising edge - sample SDA (master sending data)
            else if (scl_rise) begin
                case (i2c_state)
                    I2C_GET_ADDR: begin
                        i2c_shift_reg <= {i2c_shift_reg[6:0], sda};
                        if (i2c_bit_cnt == 7) begin
                            i2c_addr_received <= {i2c_shift_reg[6:0], sda};
                            $display("[%0t] I2C: Address byte = 0x%02h (7-bit: 0x%02h, R/W=%b)", 
                                     $time, {i2c_shift_reg[6:0], sda}, 
                                     {i2c_shift_reg[6:0], sda} >> 1,
                                     sda);
                            // Prepare ACK immediately - drive low before master samples
                            if ({i2c_shift_reg[6:0], sda} == 8'h52 || {i2c_shift_reg[6:0], sda} == 8'h53) begin
                                sda_slave_oe <= 1'b1;
                                sda_slave_out <= 1'b0;  // ACK
                            end
                            i2c_state <= I2C_ACK_ADDR;
                            i2c_bit_cnt <= 0;
                            ack_clock_seen <= 1'b0;  // Will be set on the ACK clock rise
                        end else begin
                            i2c_bit_cnt <= i2c_bit_cnt + 1;
                        end
                    end
                    
                    I2C_ACK_ADDR: begin
                        // This is the ACK clock rising edge - just mark it seen
                        ack_clock_seen <= 1'b1;
                    end
                    
                    I2C_GET_CONFIG: begin
                        i2c_shift_reg <= {i2c_shift_reg[6:0], sda};
                        if (i2c_bit_cnt == 7) begin
                            i2c_config_received <= {i2c_shift_reg[6:0], sda};
                            $display("[%0t] I2C: Config byte = 0x%02h", 
                                     $time, {i2c_shift_reg[6:0], sda});
                            // Prepare ACK immediately
                            sda_slave_oe <= 1'b1;
                            sda_slave_out <= 1'b0;  // ACK
                            i2c_state <= I2C_ACK_CONFIG;
                            i2c_bit_cnt <= 0;
                            i2c_config_written <= 1'b1;
                            ack_clock_seen <= 1'b0;  // Will be set on ACK clock rise
                        end else begin
                            i2c_bit_cnt <= i2c_bit_cnt + 1;
                        end
                    end
                    
                    I2C_ACK_CONFIG: begin
                        // This is the ACK clock rising edge - mark it seen
                        ack_clock_seen <= 1'b1;
                    end
                    
                    I2C_GET_ACK1: begin
                        // Master sends ACK (SDA low) after first byte
                        if (sda == 1'b0) begin
                            $display("[%0t] I2C: Master ACK received after byte 1", $time);
                            i2c_state <= I2C_SEND_BYTE2;
                            i2c_bit_cnt <= 0;
                            // Drive first bit of byte 2 immediately
                            sda_slave_oe <= 1'b1;
                            sda_slave_out <= i2c_tx_data[7];
                            ack_clock_seen <= 1'b0;  // Skip first scl_fall
                        end else begin
                            $display("[%0t] I2C: ERROR - expected ACK, got NACK after byte 1", $time);
                            i2c_state <= I2C_IDLE;
                        end
                    end
                    
                    I2C_SEND_BYTE2: begin
                        // First rising edge after ACK - mark clock seen
                        ack_clock_seen <= 1'b1;
                    end
                    
                    I2C_GET_NACK: begin
                        // Master sends NACK (SDA high) after last byte
                        if (sda == 1'b1) begin
                            $display("[%0t] I2C: Master NACK received after byte 2 (end of read)", $time);
                        end else begin
                            $display("[%0t] I2C: Unexpected ACK after byte 2", $time);
                        end
                        i2c_state <= I2C_IDLE;
                    end
                endcase
            end
            
            // SCL falling edge - drive SDA for next bit
            else if (scl_fall) begin
                case (i2c_state)
                    I2C_ACK_ADDR: begin
                        // Only process after the ACK clock has been seen (not on data bit 7 fall)
                        if (ack_clock_seen) begin
                            // After ACK clock, determine next state
                            if (i2c_addr_received == 8'h52) begin
                                // Write address - release SDA, expect config byte
                                $display("[%0t] I2C: ACK sent for write address, waiting for config", $time);
                                sda_slave_oe <= 1'b0;
                                i2c_state <= I2C_GET_CONFIG;
                            end else if (i2c_addr_received == 8'h53) begin
                                // Read address - start sending data
                                $display("[%0t] I2C: ACK sent for read address, sending data", $time);
                                i2c_state <= I2C_SEND_BYTE1;
                                i2c_bit_cnt <= 0;
                                // AD7991 format: [X X CH1 CH0 D11 D10 D9 D8] [D7..D0]
                                i2c_tx_data <= {4'b0000, adc_test_value};
                                i2c_read_started <= 1'b1;
                                // Push expected value to queue
                                expected_queue[expected_tail] <= adc_test_value;
                                expected_tail <= (expected_tail + 1) % 8;
                                // Drive first data bit
                                sda_slave_oe <= 1'b1;
                                sda_slave_out <= i2c_tx_data[15];
                            end else begin
                                // Wrong address - release SDA
                                $display("[%0t] I2C: NACK - wrong address 0x%02h", $time, i2c_addr_received);
                                sda_slave_oe <= 1'b0;
                                i2c_state <= I2C_IDLE;
                            end
                        end
                        // else: still waiting for ACK clock, keep holding ACK
                    end
                    
                    I2C_ACK_CONFIG: begin
                        if (ack_clock_seen) begin
                            $display("[%0t] I2C: ACK sent for config byte, waiting for restart", $time);
                            sda_slave_oe <= 1'b0;
                            // Stay idle waiting for STOP or repeated START
                            i2c_state <= I2C_IDLE;
                        end
                        // else: still waiting for ACK clock
                    end
                    
                    I2C_GET_CONFIG: begin
                        // Release SDA during config reception
                        sda_slave_oe <= 1'b0;
                    end
                    
                    I2C_SEND_BYTE1: begin
                        // Send high byte MSB first
                        if (i2c_bit_cnt < 7) begin
                            i2c_bit_cnt <= i2c_bit_cnt + 1;
                            sda_slave_oe <= 1'b1;
                            sda_slave_out <= i2c_tx_data[14 - i2c_bit_cnt];
                        end else begin
                            // Last bit sent, release for ACK
                            sda_slave_oe <= 1'b0;
                            i2c_state <= I2C_GET_ACK1;
                        end
                    end
                    
                    I2C_SEND_BYTE2: begin
                        // Send low byte MSB first
                        // Skip the first scl_fall (ACK clock falling edge)
                        if (ack_clock_seen) begin
                            if (i2c_bit_cnt < 7) begin
                                i2c_bit_cnt <= i2c_bit_cnt + 1;
                                sda_slave_oe <= 1'b1;
                                sda_slave_out <= i2c_tx_data[6 - i2c_bit_cnt];
                            end else begin
                                // Last bit sent, release for NACK
                                sda_slave_oe <= 1'b0;
                                i2c_state <= I2C_GET_NACK;
                            end
                        end
                        // else: ignore first scl_fall (ACK clock)
                    end
                    
                    default: begin
                        // Keep current SDA state
                    end
                endcase
            end
        end
    end
    
    //=========================================================================
    // SPI Monitor (captures data sent to DAC) - MSB first
    //=========================================================================
    
    always @(posedge sck) begin
        if (!sync_n) begin
            spi_captured_data[31 - spi_bit_counter] <= sdi;
            spi_bit_counter <= spi_bit_counter + 1;
        end
    end
    
    always @(negedge sync_n) begin
        spi_captured_data <= 32'd0;
        spi_bit_counter <= 6'd0;
    end
    
    // Check SPI transactions
    reg [11:0] expected_value;
    always @(posedge sync_n) begin
        if (test_count > 0 && expected_head != expected_tail) begin
            #100;
            
            // Pop expected value from queue
            expected_value = expected_queue[expected_head];
            expected_head = (expected_head + 1) % 8;
            
            $display("[%0t] SPI Transaction %0d:", $time, test_count);
            $display("  Captured: 0x%08h", spi_captured_data);
            $display("  Command:  0x%01h", spi_captured_data[31:28]);
            $display("  Address:  0x%01h", spi_captured_data[27:24]);
            $display("  Data:     0x%04h (14-bit)", spi_captured_data[19:6]);
            $display("  Expected: 0x%04h (from ADC value 0x%03h)", {expected_value[11:0], 2'b00}, expected_value);
            
            // Check command (should be 0x3 for write and update)
            if (spi_captured_data[31:28] != 4'h3) begin
                $display("ERROR: Expected command 0x3, got 0x%01h", spi_captured_data[31:28]);
                error_count = error_count + 1;
            end
            
            // Check address (channel 0)
            if (spi_captured_data[27:24] != 4'h0) begin
                $display("ERROR: Expected address 0x0, got 0x%01h", spi_captured_data[27:24]);
                error_count = error_count + 1;
            end
            
            // Check data mapping
            if (spi_captured_data[19:6] != {expected_value[11:0], 2'b00}) begin
                $display("ERROR: Data mismatch!");
                $display("  Expected: 0x%04h", {expected_value[11:0], 2'b00});
                $display("  Got:      0x%04h", spi_captured_data[19:6]);
                error_count = error_count + 1;
            end else begin
                $display("PASS: Data correctly mapped from ADC to DAC");
            end
            
            $display("");
        end
        test_count = test_count + 1;
    end
    
    //=========================================================================
    // Main test sequence
    //=========================================================================
    
    initial begin
        $display("========================================");
        $display("ADC-DAC Passthrough Testbench");
        $display("I2C Protocol: Config Write + Repeated Start + Read");
        $display("========================================");
        $display("");
        
        error_count = 0;
        test_count = 0;
        expected_head = 0;
        expected_tail = 0;
        
        // Initialize
        rst_n = 0;
        #100;
        rst_n = 1;
        $display("[%0t] Reset released", $time);
        
        // Wait for config write to complete
        wait (i2c_config_written);
        $display("[%0t] Config write complete (0x%02h)", $time, i2c_config_received);
        
        // Wait for first read
        wait (i2c_read_started);
        $display("[%0t] First read started", $time);
        
        // Test 1: Default test value (0xA5A)
        $display("[%0t] Test 1: ADC value = 0x%03h", $time, adc_test_value);
        wait (test_count >= 1);
        #10000;
        
        // Test 2: Different value
        adc_test_value = 12'h123;
        $display("[%0t] Test 2: ADC value = 0x%03h", $time, adc_test_value);
        wait (test_count >= 2);
        #10000;
        
        // Test 3: Maximum value
        adc_test_value = 12'hFFF;
        $display("[%0t] Test 3: ADC value = 0x%03h (max)", $time, adc_test_value);
        wait (test_count >= 3);
        #10000;
        
        // Test 4: Minimum value
        adc_test_value = 12'h000;
        $display("[%0t] Test 4: ADC value = 0x%03h (min)", $time, adc_test_value);
        wait (test_count >= 4);
        #10000;
        
        // Report results
        $display("");
        $display("========================================");
        $display("Test Results");
        $display("========================================");
        $display("Tests completed: %0d", test_count - 1);
        $display("Errors found:    %0d", error_count);
        
        if (error_count == 0) begin
            $display("");
            $display("*** ALL TESTS PASSED ***");
            $display("");
        end else begin
            $display("");
            $display("*** TESTS FAILED ***");
            $display("");
        end
        
        $display("Simulation finished at %0t", $time);
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #50000000;  // 50ms timeout
        $display("ERROR: Simulation timeout!");
        $display("I2C state: %0d, config_written: %b, read_started: %b", 
                 i2c_state, i2c_config_written, i2c_read_started);
        $finish;
    end
    
    // VCD dump
    initial begin
        $dumpfile("adc_dac_passthrough.vcd");
        $dumpvars(0, tb_adc_dac_passthrough);
    end

endmodule
