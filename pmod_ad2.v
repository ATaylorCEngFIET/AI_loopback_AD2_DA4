// PmodAD2 I2C ADC - HARD-CODED BIT-BANG with STOP after config
// Config write (0x52, 0x10) -> STOP -> delay -> START -> Read (0x53) -> 2 bytes

module pmod_ad2 (
    input wire clk,
    input wire rst_n,
    output wire scl,
    input wire sda_i,         // SDA input (directly from pin)
    output wire sda_o,        // SDA output value
    output wire sda_oe,       // SDA output enable (active high = drive low)
    output reg [11:0] m_axis_tdata,
    output reg m_axis_tvalid,
    input wire m_axis_tready,
    output wire configured_out,
    output wire [3:0] state_out,
    output wire sda_debug,
    output wire sda_oe_debug,
    output wire [7:0] shift_debug
);

    // States (6 bits for 50+ states)
    reg [5:0] state;
    
    localparam IDLE       = 6'd0;
    localparam START1     = 6'd1;
    // Write address 0x52
    localparam WA_BIT7    = 6'd2;
    localparam WA_BIT6    = 6'd3;
    localparam WA_BIT5    = 6'd4;
    localparam WA_BIT4    = 6'd5;
    localparam WA_BIT3    = 6'd6;
    localparam WA_BIT2    = 6'd7;
    localparam WA_BIT1    = 6'd8;
    localparam WA_BIT0    = 6'd9;
    localparam WA_ACK     = 6'd10;
    // Config 0x10
    localparam CF_BIT7    = 6'd11;
    localparam CF_BIT6    = 6'd12;
    localparam CF_BIT5    = 6'd13;
    localparam CF_BIT4    = 6'd14;
    localparam CF_BIT3    = 6'd15;
    localparam CF_BIT2    = 6'd16;
    localparam CF_BIT1    = 6'd17;
    localparam CF_BIT0    = 6'd18;
    localparam CF_ACK     = 6'd19;
    // STOP after config
    localparam STOP_CFG   = 6'd20;
    localparam DELAY      = 6'd21;
    // START2 for read
    localparam START2     = 6'd22;
    // Read address 0x53
    localparam RA_BIT7    = 6'd23;
    localparam RA_BIT6    = 6'd24;
    localparam RA_BIT5    = 6'd25;
    localparam RA_BIT4    = 6'd26;
    localparam RA_BIT3    = 6'd27;
    localparam RA_BIT2    = 6'd28;
    localparam RA_BIT1    = 6'd29;
    localparam RA_BIT0    = 6'd30;
    localparam RA_ACK     = 6'd31;
    // Read byte 1
    localparam RD1_BIT7   = 6'd32;
    localparam RD1_BIT6   = 6'd33;
    localparam RD1_BIT5   = 6'd34;
    localparam RD1_BIT4   = 6'd35;
    localparam RD1_BIT3   = 6'd36;
    localparam RD1_BIT2   = 6'd37;
    localparam RD1_BIT1   = 6'd38;
    localparam RD1_BIT0   = 6'd39;
    localparam RD1_ACK    = 6'd40;
    // Read byte 2
    localparam RD2_BIT7   = 6'd41;
    localparam RD2_BIT6   = 6'd42;
    localparam RD2_BIT5   = 6'd43;
    localparam RD2_BIT4   = 6'd44;
    localparam RD2_BIT3   = 6'd45;
    localparam RD2_BIT2   = 6'd46;
    localparam RD2_BIT1   = 6'd47;
    localparam RD2_BIT0   = 6'd48;
    localparam RD2_NACK   = 6'd49;
    localparam STOP1      = 6'd50;
    localparam WAIT_NEXT  = 6'd51;

    // Clock divider - 100kHz I2C
    // 50MHz / (4 phases * 125) = 100 kHz
    parameter CLK_DIV = 125;
    reg [7:0] clk_cnt;
    reg [1:0] phase;
    wire phase_tick;
    
    // phase_tick is combinational - true on last clock of each phase
    assign phase_tick = (clk_cnt == CLK_DIV - 1);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            clk_cnt <= 0;
            phase <= 0;
        end else begin
            if (clk_cnt == CLK_DIV - 1) begin
                clk_cnt <= 0;
                phase <= phase + 1;
            end else begin
                clk_cnt <= clk_cnt + 1;
            end
        end
    end

    // SCL output
    reg scl_reg;
    assign scl = scl_reg;
    
    // SDA open-drain emulation via separate signals
    reg sda_out;
    assign sda_o = 1'b0;                    // Always drive low when enabled
    assign sda_oe = (sda_out == 1'b0);      // Enable output when driving low
    
    // Read shift register
    reg [15:0] read_shift;
    
    // Config done flag
    reg configured;
    assign configured_out = configured;
    
    // Delay counter
    reg [15:0] delay_cnt;
    
    // Debug outputs
    assign state_out = state[3:0];
    assign sda_debug = sda_i;
    assign sda_oe_debug = sda_oe;
    assign shift_debug = read_shift[15:8];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            scl_reg <= 1;
            sda_out <= 1;
            m_axis_tdata <= 0;
            m_axis_tvalid <= 0;
            read_shift <= 0;
            configured <= 0;
            delay_cnt <= 0;
        end else begin
            m_axis_tvalid <= 0;
            
            case (state)
                IDLE: begin
                    scl_reg <= 1;
                    sda_out <= 1;
                    if (phase_tick && phase == 3)
                        state <= START1;
                end
                
                // START: SDA goes low while SCL high
                START1: begin
                    case (phase)
                        0: begin scl_reg <= 1; sda_out <= 1; end
                        1: begin scl_reg <= 1; sda_out <= 1; end
                        2: begin scl_reg <= 1; sda_out <= 0; end  // START
                        3: begin scl_reg <= 0; sda_out <= 0; 
                           if (phase_tick) begin
                               if (configured)
                                   state <= RA_BIT7;  // Skip config, go to read
                               else
                                   state <= WA_BIT7;
                           end
                        end
                    endcase
                end
                
                // ========== Write Address 0x50 = 01010000 (AD7991 at 0x28) ==========
                WA_BIT7: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=1; if(phase_tick)state<=WA_BIT6; end endcase end
                WA_BIT6: begin sda_out <= 1'b1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=WA_BIT5; end endcase end
                WA_BIT5: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=1; if(phase_tick)state<=WA_BIT4; end endcase end
                WA_BIT4: begin sda_out <= 1'b1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=WA_BIT3; end endcase end
                WA_BIT3: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=WA_BIT2; end endcase end
                WA_BIT2: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=WA_BIT1; end endcase end
                WA_BIT1: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=WA_BIT0; end endcase end
                WA_BIT0: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=1; if(phase_tick)state<=WA_ACK; end endcase end
                WA_ACK:  begin sda_out <= 1'b1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=CF_BIT7; end endcase end
                
                // ========== Config 0x10 = 00010000 ==========
                CF_BIT7: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=CF_BIT6; end endcase end
                CF_BIT6: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=CF_BIT5; end endcase end
                CF_BIT5: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=1; if(phase_tick)state<=CF_BIT4; end endcase end
                CF_BIT4: begin sda_out <= 1'b1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=CF_BIT3; end endcase end
                CF_BIT3: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=CF_BIT2; end endcase end
                CF_BIT2: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=CF_BIT1; end endcase end
                CF_BIT1: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=CF_BIT0; end endcase end
                CF_BIT0: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=1; if(phase_tick)state<=CF_ACK; end endcase end
                CF_ACK:  begin sda_out <= 1'b1; configured<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=STOP_CFG; end endcase end
                
                // ========== STOP after config: SDA goes high while SCL high ==========
                STOP_CFG: begin
                    case (phase)
                        0: begin scl_reg <= 0; sda_out <= 0; end
                        1: begin scl_reg <= 1; sda_out <= 0; end
                        2: begin scl_reg <= 1; sda_out <= 1; end  // STOP
                        3: begin scl_reg <= 1; sda_out <= 1; 
                           if (phase_tick) begin
                               delay_cnt <= 0;
                               state <= DELAY;
                           end
                        end
                    endcase
                end
                
                // ========== Delay between config and read ==========
                DELAY: begin
                    scl_reg <= 1;
                    sda_out <= 1;
                    delay_cnt <= delay_cnt + 1;
                    if (delay_cnt >= 16'd5000) begin  // ~100us at 50MHz
                        state <= START2;
                    end
                end
                
                // ========== START2 for read ==========
                START2: begin
                    case (phase)
                        0: begin scl_reg <= 1; sda_out <= 1; end
                        1: begin scl_reg <= 1; sda_out <= 1; end
                        2: begin scl_reg <= 1; sda_out <= 0; end  // START
                        3: begin scl_reg <= 0; sda_out <= 0; if (phase_tick) state <= RA_BIT7; end
                    endcase
                end
                
                // ========== Read Address 0x51 = 01010001 (AD7991 at 0x28) ==========
                RA_BIT7: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=1; if(phase_tick)state<=RA_BIT6; end endcase end
                RA_BIT6: begin sda_out <= 1'b1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=RA_BIT5; end endcase end
                RA_BIT5: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=1; if(phase_tick)state<=RA_BIT4; end endcase end
                RA_BIT4: begin sda_out <= 1'b1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=RA_BIT3; end endcase end
                RA_BIT3: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=RA_BIT2; end endcase end
                RA_BIT2: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=RA_BIT1; end endcase end
                RA_BIT1: begin sda_out <= 1'b0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=1; if(phase_tick)state<=RA_BIT0; end endcase end
                RA_BIT0: begin sda_out <= 1'b1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=1; if(phase_tick)state<=RA_ACK; end endcase end
                RA_ACK:  begin sda_out <= 1'b1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=1; if(phase_tick)state<=RD1_BIT7; end endcase end
                
                // ========== Read Byte 1 (master releases SDA, samples slave) ==========
                RD1_BIT7: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[15]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD1_BIT6; end endcase end
                RD1_BIT6: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[14]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD1_BIT5; end endcase end
                RD1_BIT5: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[13]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD1_BIT4; end endcase end
                RD1_BIT4: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[12]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD1_BIT3; end endcase end
                RD1_BIT3: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[11]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD1_BIT2; end endcase end
                RD1_BIT2: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[10]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD1_BIT1; end endcase end
                RD1_BIT1: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[9]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD1_BIT0; end endcase end
                RD1_BIT0: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[8]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD1_ACK; end endcase end
                RD1_ACK: begin sda_out<=0; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=1; if(phase_tick)state<=RD2_BIT7; end endcase end
                
                // ========== Read Byte 2 ==========
                RD2_BIT7: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[7]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD2_BIT6; end endcase end
                RD2_BIT6: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[6]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD2_BIT5; end endcase end
                RD2_BIT5: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[5]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD2_BIT4; end endcase end
                RD2_BIT4: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[4]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD2_BIT3; end endcase end
                RD2_BIT3: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[3]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD2_BIT2; end endcase end
                RD2_BIT2: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[2]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD2_BIT1; end endcase end
                RD2_BIT1: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[1]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD2_BIT0; end endcase end
                RD2_BIT0: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:begin scl_reg<=1; read_shift[0]<=sda_i; end 3:begin scl_reg<=0; if(phase_tick)state<=RD2_NACK; end endcase end
                RD2_NACK: begin sda_out<=1; case(phase) 0:scl_reg<=0; 1:scl_reg<=1; 2:scl_reg<=1; 3:begin scl_reg<=0; sda_out<=0; if(phase_tick)state<=STOP1; end endcase end
                
                // ========== STOP: SDA goes high while SCL high ==========
                STOP1: begin
                    case (phase)
                        0: begin scl_reg <= 0; sda_out <= 0; end
                        1: begin scl_reg <= 1; sda_out <= 0; end
                        2: begin scl_reg <= 1; sda_out <= 1; end  // STOP
                        3: begin scl_reg <= 1; sda_out <= 1; 
                           if (phase_tick) begin
                               m_axis_tdata <= read_shift[11:0];
                               m_axis_tvalid <= 1;
                               state <= WAIT_NEXT;
                           end
                        end
                    endcase
                end
                
                // ========== Wait before next read ==========
                WAIT_NEXT: begin
                    scl_reg <= 1;
                    sda_out <= 1;
                    if (phase_tick && phase == 0)
                        state <= START1;  // Next transaction (config already done)
                end
                
                default: state <= IDLE;
            endcase
        end
    end

endmodule
