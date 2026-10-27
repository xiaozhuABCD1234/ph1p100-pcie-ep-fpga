// =============================================================================
//  top_elab_stubs.v — 仅本 run 仿真用的三个厂商 IP 端口桩（T07.rk-align-backend）
//
//  目的：让 ModelSim 能**真实例化** ph1p_pcie_ep_top 做顶层接线/编译/精化检查
//  （G1：顶层真实接入）。三个 IP（pcie_ep_core / pcie_pll_ep / ddr3_mc_0）是
//  厂商加密交付，ModelSim 无其原语库，本桩只给**端口方向**、不做任何功能。
//  ⇒ 本桩不进入候选 manifest，不参与 TD 综合；TD 综合/STA 用真 IP（al_ip/）。
//  端口方向按 ph1p_pcie_ep_top.v 里的实例连接与信号用途逐个对出。
// =============================================================================
`timescale 1ns/1ps

module pcie_pll_ep (
    input  wire        refclk,
    input  wire        reset,
    output wire        lock,
    output wire        clk0_out
);
assign clk0_out=refclk;assign lock=~reset;
endmodule

module pcie_ep_core #(
    parameter PH1P_HXT_FAST_SIM = 1'b1
)(
    input  wire        ref_pad_clk_p,
    input  wire        ref_pad_clk_n,
    input  wire [1:0]  pcie_rx_p,
    input  wire [1:0]  pcie_rx_n,
    output wire [1:0]  pcie_tx_p,
    output wire [1:0]  pcie_tx_n,
    input  wire        tl_clk_user,
    input  wire        tl_clk_user_ce_n,
    output wire        tl_clk_locked,
    output wire        tl_clk_gate,
    input  wire        tl_power_on_rst,
    input  wire        tl_cfg_pclk,
    input  wire        tl_cfg_prst,
    input  wire        tl_cfg_penable,
    input  wire        tl_cfg_psel,
    input  wire        tl_cfg_pwrite,
    input  wire [31:0] tl_cfg_paddr,
    input  wire [3:0]  tl_cfg_pstrb,
    input  wire [31:0] tl_cfg_pwdata,
    output wire        tl_cfg_pready,
    output wire [31:0] tl_cfg_prdata,
    output wire        tl_cfg_pslverr,
    input  wire        apb4_clk_i,
    input  wire        apb4_preset_i,
    input  wire        apb4_psel_i,
    input  wire        apb4_penable_i,
    input  wire        apb4_pwrite_i,
    input  wire [31:0] apb4_paddr_i,
    input  wire [31:0] apb4_pwdata_i,
    input  wire [3:0]  apb4_pstrb_i,
    input  wire [2:0]  apb4_pprot_i,
    output wire [31:0] apb4_prdata_o,
    output wire        apb4_pready_o,
    output wire        apb4_pslverr_o,
    output wire [7:0]  tl_cfg_tcvc,
    output wire [12:0] tl_cfg_busdev,
    output wire [2:0]  tl_cfg_max_payload_size,
    output wire [2:0]  tl_cfg_max_read_request_size,
    output wire [2:0]  tl_cfg_current_link_speed,
    output wire [3:0]  tl_cfg_negotiated_width,
    output wire        tl_cfg_read_completion_boundary,
    output wire [7:0]  tl_cfg_pfregs_cmd,
    input  wire [7:0]  tl_cfg_pf0_primary_bus,
    input  wire [7:0]  tl_cfg_pf1_primary_bus,
    output wire [1:0]  pl_equ_phase,
    output wire [4:0]  tl_ltssm,
    output wire [4:0]  pl_ltssm,
    output wire        pl_link_up,
    input  wire        tl_ltssm_enable,
    input  wire [1:0]  tl_int_status,
    input  wire [3:0]  tl_int_pincontrol,
    output wire [3:0]  tl_int_pinstate,
    input  wire        tl_rx_wait,
    input  wire        tl_rx_masknp,
    output wire [47:0] tl_rx_bardec,
    output wire [255:0] tl_rx_data,
    output wire        tl_rx_eop,
    output wire [7:0]  tl_rx_err,
    output wire [9:0]  tl_rx_mchit,
    output wire        tl_rx_sop,
    output wire [7:0]  tl_rx_valid,
    input  wire [255:0] tl_tx_data,
    input  wire        tl_tx_eop,
    input  wire [7:0]  tl_tx_err,
    input  wire        tl_tx_sop,
    input  wire        tl_tx_stream,
    input  wire [7:0]  tl_tx_valid,
    output wire        tl_tx_wait,
    output wire [95:0] tl_tx_credits
);
    // 桩：只给常量，防止 X 传播；不做任何功能
    assign tl_clk_locked = 1'b1;
    assign tl_clk_gate   = 1'b0;
    assign pl_link_up    = 1'b1;
    assign tl_cfg_max_payload_size = 3'd0;    // 128B（与 pusher 固定载荷一致）
    assign tl_cfg_max_read_request_size = 3'd0;
    assign tl_cfg_current_link_speed = 3'd1;
    assign tl_cfg_negotiated_width = 4'd1;
    assign tl_rx_data = 256'd0;
    assign tl_rx_valid = 8'd0;
    assign tl_tx_wait = 1'b0;
    assign tl_tx_credits = 96'd0;

assign pcie_tx_p='0;
assign pcie_tx_n='0;
assign tl_cfg_pready='0;
assign tl_cfg_prdata='0;
assign tl_cfg_pslverr='0;
assign apb4_prdata_o='0;
assign apb4_pready_o='0;
assign apb4_pslverr_o='0;
assign tl_cfg_tcvc='0;
assign tl_cfg_busdev='0;
assign tl_cfg_read_completion_boundary='0;
assign tl_cfg_pfregs_cmd='0;
assign pl_equ_phase='0;
assign tl_ltssm=5'h10;
assign pl_ltssm='0;
assign tl_int_pinstate='0;
assign tl_rx_bardec='0;
assign tl_rx_eop='0;
assign tl_rx_err='0;
assign tl_rx_mchit='0;
assign tl_rx_sop='0;
endmodule

module ddr3_mc_0 (
    input  wire        ref_clk,
    input  wire        sys_rst_n,
    output wire        apb_pclk,
    input  wire        apb_prst_n,
    output wire        apb_pready,
    input  wire        apb_psel,
    input  wire        apb_penable,
    input  wire        apb_pwrite,
    input  wire [15:0] apb_paddr,
    input  wire [31:0] apb_pwdata,
    output wire [31:0] apb_prdata,
    output wire        dhi_clk,
    output wire        cfg_clk,
    output wire        cfg_rst_n,
    output wire        ddrphy_rst_n,
    output wire        ddrphy_rdy,
    input  wire        axi_aclk,
    input  wire        axi_aresetn,
    input  wire [3:0]  axi_awid,
    input  wire [28:0] axi_awaddr,
    input  wire [7:0]  axi_awlen,
    input  wire [2:0]  axi_awsize,
    input  wire [1:0]  axi_awburst,
    input  wire        axi_awvalid,
    output wire        axi_awready,
    input  wire [255:0] axi_wdata,
    input  wire [31:0] axi_wstrb,
    input  wire        axi_wlast,
    input  wire        axi_wvalid,
    output wire        axi_wready,
    output wire [3:0]  axi_bid,
    output wire [1:0]  axi_bresp,
    output wire        axi_bvalid,
    input  wire        axi_bready,
    input  wire [3:0]  axi_arid,
    input  wire [28:0] axi_araddr,
    input  wire [7:0]  axi_arlen,
    input  wire [2:0]  axi_arsize,
    input  wire [1:0]  axi_arburst,
    input  wire        axi_arvalid,
    output wire        axi_arready,
    output wire [3:0]  axi_rid,
    output wire [255:0] axi_rdata,
    output wire [1:0]  axi_rresp,
    output wire        axi_rlast,
    output wire        axi_rvalid,
    input  wire        axi_rready,
    input  wire [1:0]  usr_ref_type,
    input  wire        usr_ref_req,
    output wire        usr_ref_ack,
    output wire        ecc_err_sig,
    output wire        ecc_err_mul,
    output wire        ctl_ram_rst_n,
    output wire        ctl_ram_cke,
    output wire        ddr_ck_p,
    output wire        ddr_ck_n,
    output wire        ddr_reset_n,
    output wire        ddr_cke,
    output wire        ddr_odt,
    output wire        ddr_cs_n,
    output wire        ddr_ras_n,
    output wire        ddr_cas_n,
    output wire        ddr_we_n,
    output wire [2:0]  ddr_ba,
    output wire [13:0] ddr_addr,
    inout  wire [3:0]  ddr_dqs_p,
    inout  wire [3:0]  ddr_dqs_n,
    inout  wire [31:0] ddr_dq,
    inout  wire [3:0]  ddr_dm
);
    reg clock_r=0; always #4 clock_r=~clock_r;
    assign dhi_clk=clock_r;assign cfg_clk=ref_clk;
    assign cfg_rst_n=sys_rst_n;assign ddrphy_rst_n=sys_rst_n;assign ddrphy_rdy=sys_rst_n;
    reg [7:0] mem[0:16383];
    reg [28:0] addr_q;reg [8:0] left_q;reg active_q,bvalid_q;
    integer cycle=0,aw_count=0,w_count=0,j;
    assign axi_awready=sys_rst_n && !active_q && !bvalid_q && (cycle%5!=1);
    assign axi_wready=sys_rst_n && active_q && (cycle%7!=2);
    assign axi_bvalid=bvalid_q;assign axi_bresp=0;assign axi_bid=0;
    assign axi_arready=1'b0;assign axi_rvalid=1'b0;assign axi_rdata=0;
    assign axi_rlast=0;assign axi_rresp=0;assign axi_rid=0;
    function integer map_byte(input [28:0] a);
      if(a>=29'h00100000 && a<29'h00101000) map_byte=a-29'h00100000;
      else if(a>=29'h00900000 && a<29'h00901000) map_byte=4096+a-29'h00900000;
      else if(a>=29'h01100000 && a<29'h01101000) map_byte=8192+a-29'h01100000;
      else if(a>=29'h01900000 && a<29'h01901000) map_byte=12288+a-29'h01900000;
      else begin $fatal(1,"DDR address outside four declared byte-address slots %h",a);map_byte=0;end
    endfunction
    initial begin active_q=0;bvalid_q=0;addr_q=0;left_q=0;
      for(j=0;j<16384;j=j+1) mem[j]=0;end
    always @(posedge clock_r or negedge sys_rst_n) begin
      if(!sys_rst_n) begin active_q<=0;bvalid_q<=0;addr_q<=0;left_q<=0;cycle<=0;aw_count<=0;w_count<=0;end
      else begin
        cycle<=cycle+1;
        if(bvalid_q && axi_bready) bvalid_q<=0;
        if(axi_awvalid && axi_awready) begin
          if(axi_awsize!==3'd5 || axi_awburst!==2'b01 || axi_awaddr[4:0]!=0)
            $fatal(1,"DDR AW format");
          active_q<=1;addr_q<=axi_awaddr;left_q<={1'b0,axi_awlen}+1'b1;aw_count<=aw_count+1;
        end
        if(axi_wvalid && axi_wready) begin
          if(axi_wlast !== (left_q==1)) $fatal(1,"DDR WLAST");
          for(j=0;j<32;j=j+1) if(axi_wstrb[j]) mem[map_byte(addr_q+j)]<=axi_wdata[j*8+:8];
          addr_q<=addr_q+32;left_q<=left_q-1'b1;w_count<=w_count+1;
          if(left_q==1) begin active_q<=0;bvalid_q<=1;end
        end
      end
    end
    task dump_frame(input integer camera,input [31:0] seq,base);
      integer f,k;reg [1023:0] name;
      begin $sformat(name,"frame_%0d_%0d.hex",camera,seq);f=$fopen(name,"w");
        if(!f) $fatal(1,"frame dump open");
        for(k=0;k<4096;k=k+1) $fdisplay(f,"%02x",mem[map_byte(base+k)]);
        $fclose(f);
      end
    endtask
endmodule
