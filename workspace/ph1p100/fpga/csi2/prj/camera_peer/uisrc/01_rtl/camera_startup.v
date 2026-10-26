`timescale 1ns/1ps
// Sony E19505D2X p85: XCLR release -> INCK >=1 us, communication >=20 us.
// Lock loss asserts reset immediately; release is synchronized to each domain.
module camera_startup #(
    parameter POWER_WAIT_CYCLES=8388608,
    parameter MCLK_WAIT_CYCLES=100,
    parameter CFG_WAIT_CYCLES=2000
)(input wire I_clk,input wire I_pll_locked,input wire I_mclk,
  output wire O_xclr_n,output wire O_mclk,output wire O_cfg_rst_n);
    reg [1:0] lock_sync=0;
    always @(posedge I_clk or negedge I_pll_locked)
        if(!I_pll_locked) lock_sync<=0;else lock_sync<={lock_sync[0],1'b1};
    reg [23:0] count=0;
    always @(posedge I_clk or negedge I_pll_locked)
        if(!I_pll_locked) count<=0;
        else if(!lock_sync[1]) count<=0;
        else if(count<POWER_WAIT_CYCLES+CFG_WAIT_CYCLES) count<=count+1'b1;
    assign O_xclr_n=I_pll_locked && lock_sync[1] && count>=POWER_WAIT_CYCLES;
    assign O_cfg_rst_n=I_pll_locked && lock_sync[1] && count>=POWER_WAIT_CYCLES+CFG_WAIT_CYCLES;
    reg enable_request=0;
    always @(posedge I_clk or negedge I_pll_locked)
        if(!I_pll_locked) enable_request<=0;
        else if(lock_sync[1] && count>=POWER_WAIT_CYCLES+MCLK_WAIT_CYCLES) enable_request<=1;
    // Update the output-only clock gate on falling edges, never during its high pulse.
    reg gate_meta=0,gate_ready=0;
    always @(negedge I_mclk or negedge I_pll_locked)
        if(!I_pll_locked) begin gate_meta<=0;gate_ready<=0;end
        else begin gate_meta<=enable_request;gate_ready<=gate_meta;end
    assign O_mclk=I_mclk && gate_ready;
endmodule
