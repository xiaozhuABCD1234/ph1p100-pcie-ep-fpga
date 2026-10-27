from pathlib import Path
import shutil,re,json,hashlib
H=Path(__file__).resolve().parent
ROOT=Path(r'D:\fpga\ph1p100')
B10=ROOT/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b10-b9-fix/r0/td/src/camera/uisrc/03_ip/ui_imx415_cfg'
CAM=H/'candidate/rtl/ep_side/cam'
old=ROOT/'workflow/runs/20261024-221529_fpga-sim-integration-recovery/T08.sync-production-sim'
# b10 core is a clock-enable implementation supporting real random reads.
shutil.copyfile(B10/'ui_i2c.v',CAM/'ui_i2c.v')
shutil.copyfile(B10/'ui_imx415_reg.v',CAM/'ui_imx415_reg.v')
cfg=(B10/'ui_cfg_imx415.v').read_text(encoding='utf-8',errors='replace')
mask=cfg[cfg.index('    function [7:0] read_mask;'):cfg.index('    ui_i2c #')]
transport='''// Named sync wrapper: b10 read masks/timeout, safe standby, one real I2C.
module sync_i2c_config #(parameter integer CLK_DIV=624,
 parameter integer TRANSACTION_TIMEOUT_CYCLES=200000)(
 input wire clk,rst_n,input wire [1:0] cam_mode,
 output wire scl,inout wire sda,output reg cfg_done,output reg bus_error,
 output wire [8:0] dbg_idx,output wire dbg_busy,
 input wire req_valid,input wire [15:0] req_addr,input wire [7:0] req_data,
 output wire req_ready,output reg rsp_valid,rsp_ok);
 localparam IDLE=0,LAUNCH=1,WAIT_DONE=2,FAILED=3;
 reg [1:0] state;reg [8:0] index;reg read_phase,initialized,owner_sync;
 reg core_req,error_seen;reg [31:0] write_data,timer;reg [7:0] wr_count,rd_count,expected,mask_q;
 wire [31:0] table_data;wire [7:0] table_size,read_data;wire core_busy,core_error;
 wire [23:0] safe_data=(table_data[23:8]==16'h3000 || table_data[23:8]==16'h3002)
   ? {table_data[23:8],8'h01} : table_data[23:8]==16'h30c1
   ? {16'h30c1,8'h0f} : table_data[23:0];
 ui_imx415reg table_rom(cam_mode,index,table_data,table_size);
MASK
 ui_i2c #(.WMEN_LEN(4),.RMEN_LEN(1),.CLK_DIV(CLK_DIV)) core(
 .I_clk(clk),.I_rstn(rst_n),.O_iic_scl(scl),.IO_iic_sda(sda),
 .I_wr_data(write_data),.I_wr_cnt(wr_count),.O_rd_data(read_data),.I_rd_cnt(rd_count),
 .I_iic_req(core_req),.I_iic_mode(rd_count!=0),.O_iic_busy(core_busy),
 .O_iic_bus_error(core_error),.O_iic_sda_dg());
 assign req_ready=cfg_done && state==IDLE && !core_busy;
 assign dbg_idx=index;assign dbg_busy=core_busy;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   state<=IDLE;index<=0;initialized<=0;read_phase<=0;owner_sync<=0;core_req<=0;
   error_seen<=0;write_data<=0;cfg_done<=0;bus_error<=0;rsp_valid<=0;rsp_ok<=0;
   timer<=0;wr_count<=4;rd_count<=0;expected<=0;mask_q<=0;
  end else begin
   rsp_valid<=0;
   if(core_error) begin error_seen<=1;bus_error<=1;end
   if((state==LAUNCH || state==WAIT_DONE) && timer>=TRANSACTION_TIMEOUT_CYCLES) begin
    core_req<=0;cfg_done<=0;bus_error<=1;state<=FAILED;
    if(owner_sync) begin rsp_valid<=1;rsp_ok<=0;end
   end else begin
    if(state==LAUNCH || state==WAIT_DONE) timer<=timer+1'b1;else timer<=0;
    case(state)
     IDLE: if(!initialized) begin
      if(index=={1'b0,table_size}) begin
       if(!read_phase) begin index<=0;read_phase<=1;end
       else begin initialized<=1;cfg_done<=1;end
      end else if(read_phase && read_mask(safe_data[23:8])==0) index<=index+1'b1;
      else begin
       write_data<={safe_data[7:0],safe_data[15:8],safe_data[23:16],8'h34};
       expected<=safe_data[7:0];mask_q<=read_mask(safe_data[23:8]);
       wr_count<=read_phase?3:4;rd_count<=read_phase?1:0;
       owner_sync<=0;error_seen<=0;core_req<=1;state<=LAUNCH;
      end
     end else if(req_valid && req_ready) begin
      write_data<={req_data,req_addr[7:0],req_addr[15:8],8'h34};wr_count<=4;rd_count<=0;
      owner_sync<=1;error_seen<=0;core_req<=1;state<=LAUNCH;
     end
     LAUNCH: if(core_busy) begin core_req<=0;state<=WAIT_DONE;end
     WAIT_DONE: if(!core_busy) begin
      if(owner_sync) begin rsp_valid<=1;rsp_ok<=!(error_seen||core_error);state<=IDLE;end
      else if(error_seen||core_error || (read_phase && ((read_data&mask_q)!=(expected&mask_q)))) begin
       cfg_done<=0;bus_error<=1;state<=FAILED;
      end else begin index<=index+1'b1;state<=IDLE;end
     end
     FAILED: begin core_req<=0;cfg_done<=0;end
    endcase
   end
  end
 end
endmodule
'''.replace('MASK',mask)
(H/'sync_i2c_config.v').write_text(transport,encoding='ascii')
# All edits are applied from the verified original, making this generator repeatable.
top=(old/'candidate/rtl/ep_side/ph1p_pcie_ep_top.v').read_text(encoding='utf-8',errors='replace')
top=top.replace("parameter CLOSEDLOOP_EN = 1'b0,","parameter CLOSEDLOOP_EN = 1'b0,\n    parameter DUAL_LOCAL_EN=1'b0,\n    parameter integer CONSUMER_MODE=1, LOCAL_TIMEOUT=2097152,")
ports=['input wire [31:0] consumer_epoch','input wire [1:0] consumer_mode','input wire local_abort',
 'output wire [31:0] local_pass_count,local_fail_count,local_fault,local_reject_count',
 'output wire [3:0] local_held','output wire [1:0] local_active_mode',
 'input wire rel_valid','output wire rel_ready','input wire rel_camera_id,rel_slot_id',
 'input wire [31:0] rel_epoch,rel_session,rel_capture_seq','input wire [2:0] rel_status',
 'input wire [3:0] ext_arid','input wire [28:0] ext_araddr','input wire [7:0] ext_arlen',
 'input wire [2:0] ext_arsize','input wire [1:0] ext_arburst','input wire ext_arvalid',
 'output wire ext_arready','output wire [3:0] ext_rid','output wire [255:0] ext_rdata',
 'output wire [1:0] ext_rresp','output wire ext_rlast,ext_rvalid','input wire ext_rready',
 'output wire [31:0] sync_skew,sync_seq_a,sync_seq_b,sync_miss_a,sync_miss_b,sync_relock,sync_timestamp']
fields={'camera_id':1,'slot_id':1,'epoch':32,'session':32,'capture_seq':32,'base':32,'dma_bytes':32,'raw_bytes':32,'width':16,'height':16,'bayer_phase':2}
for cam in 'ab':
 ports += [f'output wire {cam}_desc_valid',f'input wire {cam}_desc_ready']
 for f,n in fields.items():ports.append(f'output wire '+(f'[{n-1}:0] ' if n>1 else '')+f'{cam}_desc_{f}')
top=top.replace('input wire sync_start, sync_abort,','input wire sync_start, sync_abort,\n    '+',\n    '.join(ports)+',')
top=top.replace('wire cl_inject_abort;','wire cl_inject_abort;\nwire [1:0] b_cl_release;wire b_cl_pub_valid;wire [31:0] b_cl_pub_seq,b_cl_pub_base,b_cl_pub_len,b_cl_pub_session,b_cl_good,b_cl_bad;')
top=top.replace('.CLOSEDLOOP_EN(CLOSEDLOOP_EN),','.CLOSEDLOOP_EN(CLOSEDLOOP_EN || DUAL_LOCAL_EN),',1)
top=top.replace('cam_r10f_writer #(\n    .W','cam_r10f_writer #(\n    .CLOSEDLOOP_EN(DUAL_LOCAL_EN),\n    .W',1)
top=top.replace('.axi_busy      (w_camw_busy_b     ),','.axi_busy      (w_camw_busy_b     ),\n    .cl_release(b_cl_release),.cl_pub_valid(b_cl_pub_valid),.cl_pub_seq(b_cl_pub_seq),.cl_pub_base(b_cl_pub_base),\n    .cl_pub_len(b_cl_pub_len),.cl_pub_session(b_cl_pub_session),.cl_good_count(b_cl_good),.cl_bad_count(b_cl_bad),')
top=top.replace(".push_en       (CLOSEDLOOP_EN ? 1'b0 : img_push_en)",".push_en       ((CLOSEDLOOP_EN || DUAL_LOCAL_EN) ? 1'b0 : img_push_en)")
mapping=['.clk(w_ddr_dhi_clk)','.rst(~w_ddrphy_rst_n)','.epoch(consumer_epoch)','.requested_mode(consumer_mode)','.abort(local_abort)',
 '.a_pub_valid(cl_pub_valid)','.a_pub_seq(cl_pub_seq)','.a_pub_base(cl_pub_base)','.a_pub_len(cl_pub_len)','.a_pub_session(cl_pub_session)',
 '.b_pub_valid(b_cl_pub_valid)','.b_pub_seq(b_cl_pub_seq)','.b_pub_base(b_cl_pub_base)','.b_pub_len(b_cl_pub_len)','.b_pub_session(b_cl_pub_session)',
 '.a_release(cl_release)','.b_release(b_cl_release)','.pass_count(local_pass_count)','.fail_count(local_fail_count)','.fault(local_fault)','.reject_count(local_reject_count)',
 '.held(local_held)','.active_mode(local_active_mode)']
for cam in 'ab':
 for f in ['valid','ready']+list(fields):mapping.append(f'.{cam}_desc_{f}({cam}_desc_{f})')
for f in ['valid','ready','camera_id','slot_id','epoch','session','capture_seq','status']:mapping.append(f'.rel_{f}(rel_{f})')
for f in ['arid','araddr','arlen','arsize','arburst','arvalid','arready','rid','rdata','rresp','rlast','rvalid','rready']:
 mapping.extend([f'.{f}(w_ddr_{f})',f'.ext_{f}(ext_{f})'])
branch='''generate if(DUAL_LOCAL_EN) begin:g_dual_local
 assign push_arready=0;assign push_rvalid=0;assign cl_inject_abort=0;
 dual_local_closure #(.W(CAMDDR_W),.H(CAMDDR_H),.PHASE(((CAMDDR_X0&1)?2:0)^(((CAMDDR_SKIP_ROWS+CAMDDR_Y0)&1)?3:0)),
 .DEFAULT_MODE(CONSUMER_MODE),.TIMEOUT_CYCLES(LOCAL_TIMEOUT)) u_local(
'''+',\n'.join(mapping)+');\nend else if(CLOSEDLOOP_EN) begin:g_closedloop\n assign b_cl_release=0;\n'
top=top.replace('generate if(CLOSEDLOOP_EN) begin:g_closedloop',branch)
top=top.replace('end else begin:g_original_reader','end else begin:g_original_reader\n    assign b_cl_release=0;')
# Values remain in the 50 MHz observation domain; external consumers must sample this domain.
top=top.replace('.skew(),.pair_seq_a(),.pair_seq_b(),.miss_a(),.miss_b(),.overrun_a(),.overrun_b(),',
 '.skew(sync_skew),.pair_seq_a(sync_seq_a),.pair_seq_b(sync_seq_b),.miss_a(sync_miss_a),.miss_b(sync_miss_b),.overrun_a(),.overrun_b(),')
top=top.replace('.relock_count(),.ignored_starts(),.timestamp());','.relock_count(sync_relock),.ignored_starts(),.timestamp(sync_timestamp));')
top=top.replace('end else begin : g_no_sync','end else begin : g_no_sync\n      assign sync_skew=0;assign sync_seq_a=0;assign sync_seq_b=0;assign sync_miss_a=0;assign sync_miss_b=0;assign sync_relock=0;assign sync_timestamp=0;')
(H/'candidate/rtl/ep_side/ph1p_pcie_ep_top.v').write_text(top,encoding='utf-8')
# Reader is retained; augment its checks with exact identity/geometry and zero DMA tail.
checker=(old/'candidate/rtl/ep_side/ddr/ddr_frame_readback_checker.v').read_text(encoding='utf-8')
checker=checker.replace('input  wire         abort,','input wire expected_check,expected_camera,\n    input wire [31:0] expected_session,expected_seq,expected_raw,\n    input wire [15:0] expected_width,expected_height,\n    input wire [1:0] expected_phase,\n    input  wire         abort,')
checker=checker.replace('reg          abort_r;','reg          abort_r;\n    reg identity_bad,tail_bad;')
checker=checker.replace('!length_ok     ? E_LENGTH', '(identity_bad || tail_bad || !length_ok) ? E_LENGTH')
checker=checker.replace('abort_r <= 1\'b0;',"abort_r <= 1'b0;identity_bad<=0;tail_bad<=0;")
needle='''            if (st == ST_PROC) begin'''
extra='''            if (st == ST_PROC && expected_check===1'b1) begin
                if((wcnt==2 && pword[23:16]!={7'd0,expected_camera}) ||
                   (wcnt==5 && pword!=expected_seq) || (wcnt==4 && pword!=expected_session) || (wcnt==6 && pword!=1) ||
                   (wcnt==7 && pword!={expected_height,expected_width}) ||
                   (wcnt==8 && pword!=expected_width*5/4) ||
                   (wcnt==10 && pword!=((32'd10<<16)|{30'd0,expected_phase})) ||
                   ((wcnt==11 || wcnt==12) && pword!=expected_raw)) identity_bad<=1;
                if(off_now>=128+expected_raw && pword!=0) tail_bad<=1;
            end
'''
checker=checker.replace(needle,extra+needle)
checker=checker.replace("abort_r     <= 1'b0;", "abort_r     <= 1'b0;identity_bad<=0;tail_bad<=0;")
# legacy closed-loop uses explicitly disabled extended expectations
cl=H/'candidate/rtl/ep_side/ddr/closedloop/ddr_closedloop_readback.v'
cltext=(old/'candidate/rtl/ep_side/ddr/closedloop/ddr_closedloop_readback.v').read_text(encoding='utf-8').replace('.base({32\'d0,current_base})',".expected_check(1'b0),.expected_camera(1'b0),.expected_session(32'd0),.expected_seq(32'd0),.expected_raw(32'd0),.expected_width(16'd0),.expected_height(16'd0),.expected_phase(2'd0),.base({32'd0,current_base})")
cl.write_text(cltext,encoding='utf-8')
(H/'candidate/rtl/ep_side/ddr/ddr_frame_readback_checker.v').write_text(checker,encoding='utf-8')
print('CANDIDATE_GENERATED')
