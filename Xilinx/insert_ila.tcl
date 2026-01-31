# Insert ILA for AXI Stream Debug
# Run this after synthesis, before implementation

# Get all debug nets
set debug_nets [get_nets -hierarchical -filter {MARK_DEBUG == true}]

if {[llength $debug_nets] > 0} {
    puts "Found [llength $debug_nets] debug nets:"
    foreach net $debug_nets {
        puts "  $net"
    }
    
    # Create debug core
    create_debug_core u_ila_0 ila
    
    # Set ILA properties
    set_property C_DATA_DEPTH 4096 [get_debug_cores u_ila_0]
    set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
    set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
    set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
    set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
    set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
    set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
    set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_0]
    
    # Connect clock - use the 50MHz clock
    set_property port_width 1 [get_debug_ports u_ila_0/clk]
    connect_debug_port u_ila_0/clk [get_nets clk_50mhz]
    
    # Connect all debug nets to probes
    set probe_idx 0
    foreach net $debug_nets {
        # Skip nets that can't be debugged (like sda_debug on IOBUF)
        if {[string match "*sda_debug*" $net]} {
            puts "Skipping $net (not accessible from fabric)"
            continue
        }
        
        # Get net width
        set width [llength [get_nets $net]]
        if {$width == 0} {
            set width 1
        }
        
        # Create probe port if needed
        if {$probe_idx > 0} {
            create_debug_port u_ila_0 probe
        }
        
        set_property port_width $width [get_debug_ports u_ila_0/probe$probe_idx]
        connect_debug_port u_ila_0/probe$probe_idx [get_nets $net]
        
        puts "Connected probe$probe_idx to $net (width=$width)"
        incr probe_idx
    }
    
    puts "ILA inserted with $probe_idx probes"
} else {
    puts "WARNING: No debug nets found!"
}
