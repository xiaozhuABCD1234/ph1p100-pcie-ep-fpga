from pathlib import Path
import re
H=Path(__file__).resolve().parent
p=H/'candidate/rtl/ep_side/ph1p_pcie_ep_top.v'
s=p.read_text(encoding='utf-8')
s=s.replace('sync_a_rsp,sync_b_rsp,sync_a_ok,sync_b_ok,sync_ready;', 'sync_a_rsp,sync_b_rsp,sync_a_ok,sync_b_ok,sync_ready,sync_ready_ctrl;')
s=s.replace('.abort_req(sync_abort),', '.abort_req(sync_abort || (sync_ready_ctrl && !sync_locked)),')
s=s.replace('.ready(sync_ready),', '.ready(sync_ready_ctrl),')
s=s.replace('    assign sync_req_ready=', '    assign sync_ready=SYNC_ENABLE ? (sync_ready_ctrl && sync_locked) : 1\'b1;\n    assign sync_req_ready=')
s=s.replace('assign sync_ready=1;', 'assign sync_ready_ctrl=1;')
p.write_text(s,encoding='utf-8',newline='\n')
s=(H/'candidate/sim/tb/top_elab_stubs.v').read_text(encoding='utf-8')
s=s[:s.index('    assign dhi_clk')]+'''    reg clock_r=0; always #4 clock_r=~clock_r;
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
'''
s=s.replace('output wire        clk0_out\n);\nendmodule', 'output wire        clk0_out\n);\nassign clk0_out=refclk;assign lock=~reset;\nendmodule')
# Fill only otherwise-undriven vendor PCIe outputs. Target camera logic is unchanged.
start=s.index('module pcie_ep_core');end=s.index('endmodule',start)
piece=s[start:end]
outputs=re.findall(r'output\s+wire\s*(?:\[[^\]]+\]\s*)?(\w+)',piece)
for name in outputs:
    if not re.search(r'assign\s+'+name+r'\s*=',piece):
        value="5'h10" if name=='tl_ltssm' else "'0"
        piece+='\nassign '+name+'='+value+';'
s=s[:start]+piece+'\n'+s[end:]
(H/'vendor_env.sv').write_text(s,encoding='utf-8',newline='\n')
print('ENV_CREATED explicit_pll_pcie_ddr_models=true')
