import pathlib
p=pathlib.Path(r'D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery\T10.a1-abort-cdc-fix')
s=(p/'tb_recovery.sv').read_text()
s=s.replace('MAX_CYCLES=1500000);','MAX_CYCLES=1500000, parameter real CAM_HALF=7.0, A1_HALF=2.6665, A1_PHASE=1.7);')
s=s.replace('always #2.6665 clk_cam=~clk_cam;','always #(CAM_HALF) clk_cam=~clk_cam;\n reg a1_enable=1;\n initial begin #100000000; $fatal(1,"ABSOLUTE_WATCHDOG"); end')
s=s.replace('initial begin #1.7; forever #2.6665 clk_a1=~clk_a1; end','initial begin #(A1_PHASE); forever #(A1_HALF) if(a1_enable) clk_a1=~clk_a1; end')
s=s.replace('integer y,g,j,rej0;', 'integer y,g,j,rej0;')
s=s.replace('     pv=!(bad && y==ROI_Y && g==CG-1);', '''`ifdef CORRECTED
     if(bad==3 && y==ROI_Y && g==ROI_X/4) begin
      pv=0; a1_enable=1;
      j=0;
      while(!(dut.cam_abort_pending && dut.cam_room) && j<200) begin @(negedge clk_cam);j=j+1;end
      if(j==200) $fatal(1,"SOF_ABORT_ALIGNMENT_MISS");
     end
`endif
     pv=!((bad==1 && y==ROI_Y && g==CG-1)||(bad==2 && y==0 && g==CG-1));''')
# Add independent stream queue monitor, stable holding check and priority assertions.
mark=' task drive_frame;'
monitor=''' integer abort_writes=0,abort_reads=0,raw_aborts=0,abort_stalls=0,last_abort_hits=0,sof_abort_hits=0,source_losses=0;
 reg held_stall=0; reg [42:0] held_prev;
 reg [42:0] token_queue[0:16383]; integer token_w=0,token_r=0;
 always @(negedge rst_n) begin token_w=0;token_r=0;held_stall=0;end
 always @(posedge clk_cam) if(rst_n) begin
  if(held_stall && (!dut.u_cam_fifo.w_valid || dut.u_cam_fifo.w_data!==held_prev)) $fatal(1,"FIFO_STALL_TOKEN_CHANGED");
  held_stall=dut.u_cam_fifo.w_valid&&!dut.u_cam_fifo.w_ready;
  held_prev=dut.u_cam_fifo.w_data;
  if(dut.u_cam_fifo.w_valid&&dut.u_cam_fifo.w_ready) begin
   token_queue[token_w]=dut.u_cam_fifo.w_data;token_w=token_w+1;
   if(dut.u_cam_fifo.w_data[42]) begin
    if(dut.u_cam_fifo.w_data[41:0]!==42'd0) $fatal(1,"ABORT_PIXEL_SIDEBAND");
    abort_writes=abort_writes+1;
    $fwrite(ft,"ABORT_WRITE cycles=%0d count=%0d crop_sof=%0d\\n",cycles,abort_writes,dut.crop_sof);
    if(dut.crop_valid&&dut.crop_sof) sof_abort_hits=sof_abort_hits+1;
   end
  end
  if(dut.u_cam_fifo.w_valid&&!dut.u_cam_fifo.w_ready&&dut.u_cam_fifo.w_data[42]) abort_stalls=abort_stalls+1;
`ifdef CORRECTED
  if(dut.crop_valid && !dut.cam_drop && !dut.cam_abort_pending && !dut.cam_abort_held && !dut.cam_room) source_losses=source_losses+1;
`endif
 end
 always @(posedge clk_a1) if(rst_n) begin
  if(dut.fifo_valid&&dut.fifo_ready) begin
   if(token_r>=token_w || dut.fifo_dout!==token_queue[token_r]) $fatal(1,"CDC_ORDER_MISMATCH");
   token_r=token_r+1;
   if(dut.e_abort) begin
    abort_reads=abort_reads+1;
    if(dut.skid_valid&&dut.skid_last) last_abort_hits=last_abort_hits+1;
`ifdef CORRECTED
    if(dut.raw_store_valid||dut.skid_take||dut.raw_begin) $fatal(1,"ABORT_STORE_PRIORITY");
`endif
   end
  end
  if(dut.raw_abort) begin
   raw_aborts=raw_aborts+1;
   if(dut.u_raw_store.wr_valid) $fatal(1,"ABORT_WRITE_CONCURRENT");
  end
 end
'''
s=s.replace(mark,monitor+mark)
s=s.replace('integer i,t,start_exp;', 'integer i,t,start_exp,abort_base;')
needle='  end\n  // At most four GOOD recovery inputs.'
extra='''  end
`ifdef CORRECTED
  else if(case_id==5 || case_id==6 || case_id==7) begin
   geom_before=geom;rawdrop_before=rawdrop;cmpdrop_before=cmpdrop;err_before=err;
   @(negedge clk_a1);a1_enable=0;
   drive_frame(100,0);drive_frame(101,1);
   if(!dut.u_cam_fifo.full || !dut.cam_abort_pending || !dut.cam_hold_valid) $fatal(1,"FULL_PENDING_ABORT_MISS");
   state_log("full_pending_abort");inject_hit=1;
   if(case_id==6) begin
    rst_n=0;a1_enable=1;epoch=1;
    repeat(24) @(negedge clk_a1);
    if(dut.cam_hold_valid||dut.cam_abort_pending||dut.raw_active||dut.skid_valid||err||rawdrop||rawpub) $fatal(1,"PENDING_RESET_CLEAR");
    post_reset_zero=1;rst_n=1;repeat(50) @(negedge clk_a1);
   end else begin
    if(case_id==7) drive_frame(2000,3);
    else a1_enable=1;
    repeat(10000) @(negedge clk_a1);snapshot_fault;
    if(abort_writes!=1||abort_reads!=1||dut.u_raw_store.wr_active||dut.skid_valid) $fatal(1,"ORDERED_ABORT_RELEASE_FAIL");
    if(case_id==7 && sof_abort_hits!=1) $fatal(1,"SOF_ABORT_SIMULTANEOUS_MISS");
   end
  end else if(case_id==8) begin
   geom_before=geom;rawdrop_before=rawdrop;cmpdrop_before=cmpdrop;err_before=err;
   stall_write=1;drive_frame(100,0);
   t=0;while(!(dut.skid_valid&&dut.skid_last&&dut.u_raw_store.wr_active)&&t<2000) begin @(negedge clk_a1);t=t+1;end
   if(t==2000) $fatal(1,"LAST_SKID_NOT_STALLED");
   drive_frame(101,2);repeat(200) @(negedge clk_a1);
   if(last_abort_hits!=1||rawpub!=0||rawdrop!=1||dut.u_raw_store.wr_active||dut.skid_valid) $fatal(1,"LAST_SKID_ABORT_NOT_RELEASED");
   inject_hit=1;stall_write=0;snapshot_fault;
  end
`endif
  // At most four GOOD recovery inputs.'''
assert needle in s;s=s.replace(needle,extra)
s=s.replace('  $fclose(fd);$fclose(ft);$fclose(fs);', '''  $fwrite(ft,"CONTROL abort_writes=%0d abort_reads=%0d raw_aborts=%0d abort_stalls=%0d last_abort_hits=%0d sof_abort_hits=%0d source_losses=%0d token_w=%0d token_r=%0d\\n",abort_writes,abort_reads,raw_aborts,abort_stalls,last_abort_hits,sof_abort_hits,source_losses,token_w,token_r);
  if(case_id==3 && (abort_writes!=1||abort_reads!=1||raw_aborts!=1||rawdrop<1)) $fatal(1,"ABORT_ONLY_LOST_OR_SLOT_NOT_RELEASED");
  if(case_id==4 && (abort_writes<1||abort_reads!=abort_writes)) $fatal(1,"OVERFLOW_ABORT_NOT_DELIVERED");
  $fclose(fd);$fclose(ft);$fclose(fs);''')
(p/'tb_recovery.sv').write_text(s,encoding='utf-8',newline='\n')
s=(p/'check_recovery.py').read_text().replace("HERE.parents[1] / 'inputs/a1-r5'", "HERE.parent / 'inputs/a1-r5'")
s=s.replace('epoch=1 if case_id in (1,2) else 0','epoch=1 if case_id in (1,2,6) else 0')
s=s.replace('if case_id==4:\n        for line', 'if case_id in (4,5,7):\n        for line')
# Directed stress cases permit only the wholly received prefix, not collided seed2000.
s=s.replace("if 100<=v['seed']<108 and v['rejected_delta']==0: legal_prefix.append(v['seed'])", "if 100<=v['seed']<108 and v['bad']==0 and v['rejected_delta']==0: legal_prefix.append(v['seed'])")
(p/'check_recovery.py').write_text(s,encoding='utf-8',newline='\n')
print('TB and checker prepared')
