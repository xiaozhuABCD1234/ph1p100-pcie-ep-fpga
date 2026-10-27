`timescale 1ns/1ps
module independent_observer;
 integer f, row=0, group_index=0, writes=0, reads=0, transitions=0;
 reg prev_frame=0,prev_line=0;
 reg [1:0] p0=0,p1=0,p2=0,p3=0;
 reg [2047:0] path;
 initial begin
  if(!$value$plusargs("OBS=%s",path)) $fatal(1,"OBSERVER_PATH_MISSING");
  f=$fopen(path,"w"); if(!f) $fatal(1,"OBSERVER_OPEN_FAIL");
 end
 always @(posedge tb_recovery.clk_cam) begin
  if(!tb_recovery.rst_n) begin row=0;group_index=0;prev_frame=0;prev_line=0;end
  else begin
   if(tb_recovery.inf && !prev_frame) begin row=0;group_index=0;end
   if(tb_recovery.il && !prev_line) group_index=0;
   if(tb_recovery.inf && tb_recovery.il) begin
    if(tb_recovery.pv) $fwrite(f,"SOURCE_PIXEL seed=%0d row=%0d group=%0d bits=%010h\n",tb_recovery.active_seed,row,group_index,tb_recovery.pix);
    group_index=group_index+1;
   end
   if(!tb_recovery.il && prev_line) row=row+1;
   prev_frame=tb_recovery.inf;prev_line=tb_recovery.il;
  end
 end
 always @(posedge tb_recovery.clk_a1) begin
  if(tb_recovery.rst_n) begin
   if(tb_recovery.awvalid && tb_recovery.awready && tb_recovery.wvalid && tb_recovery.wready) begin
    if(tb_recovery.awaddr < 131072) begin
     if(tb_recovery.dut.u_raw_store.slot_st[tb_recovery.dut.u_raw_store.wr_slot] !== 2'd1) $fatal(1,"INDEPENDENT_WRITE_WITHOUT_RAW_OWNER");
     if(tb_recovery.awaddr != tb_recovery.dut.u_raw_store.BASE_WORD + tb_recovery.dut.u_raw_store.wr_slot*tb_recovery.dut.u_raw_store.SLOT_WORDS+tb_recovery.dut.u_raw_store.waddr) $fatal(1,"INDEPENDENT_RAW_WRITE_ADDRESS");
    end else begin
     if(tb_recovery.dut.u_cmp_store.slot_st[tb_recovery.dut.u_cmp_store.wr_slot] !== 2'd1) $fatal(1,"INDEPENDENT_WRITE_WITHOUT_CMP_OWNER");
     if(tb_recovery.awaddr != tb_recovery.dut.u_cmp_store.BASE_WORD + tb_recovery.dut.u_cmp_store.wr_slot*tb_recovery.dut.u_cmp_store.SLOT_WORDS+tb_recovery.dut.u_cmp_store.waddr) $fatal(1,"INDEPENDENT_CMP_WRITE_ADDRESS");
    end
    writes=writes+1;
    $fwrite(f,"WRITE cycles=%0d epoch=%0d address=%0d data=%064h\n",tb_recovery.cycles,tb_recovery.epoch,tb_recovery.awaddr,tb_recovery.wdata);
   end
   if(tb_recovery.arvalid && tb_recovery.arready) begin
    if(tb_recovery.araddr<131072) begin
     if(tb_recovery.dut.u_raw_store.slot_st[tb_recovery.dut.u_raw_store.rd_sel] !== 2'd3) $fatal(1,"INDEPENDENT_READ_WITHOUT_RAW_OWNER");
    end else begin
     if(tb_recovery.dut.u_cmp_store.slot_st[tb_recovery.dut.u_cmp_store.rd_sel] !== 2'd3) $fatal(1,"INDEPENDENT_READ_WITHOUT_CMP_OWNER");
    end
    reads=reads+1;
    $fwrite(f,"READ cycles=%0d epoch=%0d address=%0d\n",tb_recovery.cycles,tb_recovery.epoch,tb_recovery.araddr);
   end
  end
 end
 always @(negedge tb_recovery.clk_a1) begin
  if({p0,p1,p2,p3} !== {tb_recovery.dut.u_raw_store.slot_st[0],tb_recovery.dut.u_raw_store.slot_st[1],tb_recovery.dut.u_cmp_store.slot_st[0],tb_recovery.dut.u_cmp_store.slot_st[1]}) begin
   transitions=transitions+1;
   $fwrite(f,"SLOTS cycles=%0d reset=%0d r0=%0d r1=%0d c0=%0d c1=%0d writes=%0d reads=%0d\n",tb_recovery.cycles,!tb_recovery.rst_n,tb_recovery.dut.u_raw_store.slot_st[0],tb_recovery.dut.u_raw_store.slot_st[1],tb_recovery.dut.u_cmp_store.slot_st[0],tb_recovery.dut.u_cmp_store.slot_st[1],writes,reads);
   p0=tb_recovery.dut.u_raw_store.slot_st[0];p1=tb_recovery.dut.u_raw_store.slot_st[1];p2=tb_recovery.dut.u_cmp_store.slot_st[0];p3=tb_recovery.dut.u_cmp_store.slot_st[1];
  end
 end
endmodule
