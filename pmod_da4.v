// PmodDA4 SPI DAC - AD5628 8-channel 12-bit DAC
// SPI Mode 1 (CPOL=0, CPHA=1), MSB first, 32-bit frames
// Active low SYNC
// 
// Initialization sequence:
// 1. Reset DAC
// 2. Enable internal reference (2.5V)
// 3. Power up all DAC channels

module pmod_da4 (
    input wire clk,
    input wire rst_n,
    output reg sck,
    output reg sdi,
    output reg sync_n,
    input wire [13:0] s_axis_tdata,   // 14-bit input (use upper 12 bits)
    input wire s_axis_tvalid,
    output reg s_axis_tready
);

    // AD5628 Commands (4 bits)
    localparam CMD_WRITE_UPDATE_N = 4'b0011;  // Write to and update DAC register n
    localparam CMD_POWER         = 4'b0100;   // Power down/up
    localparam CMD_RESET         = 4'b0111;   // Reset
    localparam CMD_SETUP_REF     = 4'b1000;   // Setup internal reference
    
    // States
    localparam WAIT        = 3'd0;
    localparam LOAD        = 3'd1;
    localparam SHIFT       = 3'd2;
    localparam DONE        = 3'd3;
    localparam IDLE        = 3'd4;
    
    // Init phases
    localparam INIT_RESET  = 2'd0;
    localparam INIT_REF    = 2'd1;
    localparam INIT_POWER  = 2'd2;
    localparam INIT_DONE   = 2'd3;
    
    reg [2:0] state;
    reg [1:0] init_phase;
    reg [31:0] shift_reg;
    reg [5:0] bit_cnt;
    reg [7:0] clk_div;
    reg [15:0] wait_cnt;
    
    // SPI clock ~1 MHz (50 MHz / 50 = 1 MHz)
    localparam CLK_DIV = 25;
    localparam WAIT_TIME = 16'd2500;  // 50us at 50MHz

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= WAIT;
            init_phase <= INIT_RESET;
            sck <= 0;
            sdi <= 0;
            sync_n <= 1;
            s_axis_tready <= 0;
            shift_reg <= 0;
            bit_cnt <= 0;
            clk_div <= 0;
            wait_cnt <= 0;
        end else begin
            case (state)
                // ====== Wait state (used between commands) ======
                WAIT: begin
                    sync_n <= 1;
                    sck <= 0;
                    s_axis_tready <= 0;
                    wait_cnt <= wait_cnt + 1;
                    
                    if (wait_cnt >= WAIT_TIME) begin
                        wait_cnt <= 0;
                        
                        // Load command based on init_phase
                        // AD5628 format: [31:28]=X, [27:24]=Cmd, [23:20]=Addr, [19:8]=Data, [7:0]=X
                        case (init_phase)
                            INIT_RESET: begin
                                // Reset: Cmd=0111, Addr=1111
                                shift_reg <= {4'h0, CMD_RESET, 4'hF, 12'h000, 8'h00};
                            end
                            INIT_REF: begin
                                // Enable internal reference: Cmd=1000, DB0=1
                                shift_reg <= {4'h0, CMD_SETUP_REF, 4'h0, 12'h000, 8'h01};
                            end
                            INIT_POWER: begin
                                // Power up all channels: Cmd=0100
                                // DB7-DB0 = channel select (FF = all)
                                // DB9-DB8 = power mode (00 = normal)
                                shift_reg <= {4'h0, CMD_POWER, 4'h0, 12'h000, 8'hFF};
                            end
                            default: begin
                                shift_reg <= 32'h00000000;
                            end
                        endcase
                        
                        bit_cnt <= 32;
                        clk_div <= 0;
                        state <= LOAD;
                    end
                end
                
                // ====== Normal operation - wait for data ======
                IDLE: begin
                    sync_n <= 1;
                    sck <= 0;
                    s_axis_tready <= 1;
                    
                    if (s_axis_tvalid && s_axis_tready) begin
                        // Write and update DAC channel A with 12-bit data
                        // AD5628 format: [31:28]=X, [27:24]=Cmd, [23:20]=Addr, [19:8]=Data, [7:0]=X
                        shift_reg <= {4'h0, CMD_WRITE_UPDATE_N, 4'h0, s_axis_tdata[13:2], 8'h00};
                        bit_cnt <= 32;
                        clk_div <= 0;
                        s_axis_tready <= 0;
                        state <= LOAD;
                    end
                end
                
                // ====== Load first bit, assert SYNC ======
                LOAD: begin
                    sync_n <= 0;           // Assert SYNC low
                    sck <= 0;
                    sdi <= shift_reg[31];  // MSB first
                    clk_div <= 0;
                    state <= SHIFT;
                end
                
                // ====== Shift out 32 bits ======
                SHIFT: begin
                    clk_div <= clk_div + 1;
                    
                    if (clk_div == CLK_DIV - 1) begin
                        sck <= 1;  // Rising edge - data sampled by DAC
                    end else if (clk_div == 2*CLK_DIV - 1) begin
                        sck <= 0;  // Falling edge
                        shift_reg <= {shift_reg[30:0], 1'b0};
                        bit_cnt <= bit_cnt - 1;
                        clk_div <= 0;
                        
                        if (bit_cnt == 1) begin
                            state <= DONE;
                        end else begin
                            sdi <= shift_reg[30];  // Next bit
                        end
                    end
                end
                
                // ====== Transfer complete, determine next state ======
                DONE: begin
                    sync_n <= 1;  // Deassert SYNC to latch data
                    sck <= 0;
                    clk_div <= clk_div + 1;
                    
                    if (clk_div >= CLK_DIV) begin
                        clk_div <= 0;
                        wait_cnt <= 0;
                        
                        // Advance init phase or go to IDLE
                        case (init_phase)
                            INIT_RESET: begin
                                init_phase <= INIT_REF;
                                state <= WAIT;
                            end
                            INIT_REF: begin
                                init_phase <= INIT_POWER;
                                state <= WAIT;
                            end
                            INIT_POWER: begin
                                init_phase <= INIT_DONE;
                                state <= IDLE;
                            end
                            INIT_DONE: begin
                                // Normal operation - return to IDLE
                                state <= IDLE;
                            end
                        endcase
                    end
                end
                
                default: state <= WAIT;
            endcase
        end
    end

endmodule