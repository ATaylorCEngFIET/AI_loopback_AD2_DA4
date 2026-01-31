// Simple I2C Slave Model for AD7991 ADC
// Responds to write (config) and read (data) transactions

module i2c_slave_model #(
    parameter SLAVE_ADDR = 7'h14  // 0x28 >> 1
)(
    inout wire sda,
    input wire scl,
    input wire [11:0] adc_value
);

    reg sda_out;
    reg sda_oe;
    assign sda = sda_oe ? sda_out : 1'bz;
    
    reg [7:0] bit_count;
    reg [15:0] data_to_send;
    reg [7:0] received_byte;
    
    integer state;
    localparam IDLE = 0, ADDR = 1, ACK_ADDR = 2, DATA_WR = 3, ACK_DATA = 4;
    localparam DATA_RD = 5, ACK_RD = 6, NACK_RD = 7;
    
    reg start_detected;
    reg stop_detected;
    reg sda_r, sda_rr;
    reg scl_r, scl_rr;
    
    // Detect START and STOP conditions
    always @(posedge scl or negedge scl or posedge sda or negedge sda) begin
        sda_rr <= sda_r;
        sda_r <= sda;
        scl_rr <= scl_r;
        scl_r <= scl;
        
        // START: SDA falling while SCL high
        if (scl && scl_r && !sda && sda_r) begin
            start_detected = 1;
            stop_detected = 0;
        end
        
        // STOP: SDA rising while SCL high  
        if (scl && scl_r && sda && !sda_r) begin
            stop_detected = 1;
            start_detected = 0;
        end
    end
    
    // Main I2C state machine
    always @(posedge scl or posedge start_detected or posedge stop_detected) begin
        if (stop_detected) begin
            state <= IDLE;
            sda_oe <= 0;
            bit_count <= 0;
        end else if (start_detected) begin
            state <= ADDR;
            bit_count <= 7;
            sda_oe <= 0;
            start_detected <= 0;
        end else begin
            case (state)
                ADDR: begin
                    received_byte[bit_count] <= sda;
                    if (bit_count == 0) begin
                        state <= ACK_ADDR;
                    end else begin
                        bit_count <= bit_count - 1;
                    end
                end
                
                DATA_WR: begin
                    received_byte[bit_count] <= sda;
                    if (bit_count == 0) begin
                        state <= ACK_DATA;
                    end else begin
                        bit_count <= bit_count - 1;
                    end
                end
                
                DATA_RD: begin
                    if (bit_count == 0) begin
                        state <= (bit_count == 8) ? ACK_RD : NACK_RD;
                    end else begin
                        bit_count <= bit_count - 1;
                    end
                end
            endcase
        end
    end
    
    // Handle ACKs and data output on falling edge
    always @(negedge scl or posedge stop_detected) begin
        if (stop_detected) begin
            sda_oe <= 0;
        end else begin
            case (state)
                ACK_ADDR: begin
                    // Check if address matches
                    if (received_byte[7:1] == SLAVE_ADDR) begin
                        sda_oe <= 1;
                        sda_out <= 0;  // ACK
                        
                        if (received_byte[0] == 0) begin
                            // Write
                            state <= DATA_WR;
                            bit_count <= 7;
                        end else begin
                            // Read - prepare data
                            data_to_send <= {4'b0000, adc_value};  // Channel 0 + data
                            state <= DATA_RD;
                            bit_count <= 15;
                        end
                    end else begin
                        sda_oe <= 0;  // NACK
                        state <= IDLE;
                    end
                end
                
                ACK_DATA: begin
                    sda_oe <= 1;
                    sda_out <= 0;  // ACK
                    state <= IDLE;  // Wait for restart or stop
                end
                
                DATA_RD: begin
                    sda_oe <= 1;
                    sda_out <= data_to_send[bit_count];
                end
                
                ACK_RD: begin
                    sda_oe <= 0;  // Release for master ACK
                    bit_count <= 7;
                end
                
                NACK_RD: begin
                    sda_oe <= 0;  // Release for master NACK
                    state <= IDLE;
                end
                
                default: begin
                    sda_oe <= 0;
                end
            endcase
        end
    end
    
    initial begin
        state = IDLE;
        sda_oe = 0;
        sda_out = 1;
        bit_count = 0;
        start_detected = 0;
        stop_detected = 0;
        sda_r = 1;
        sda_rr = 1;
        scl_r = 1;
        scl_rr = 1;
    end

endmodule
