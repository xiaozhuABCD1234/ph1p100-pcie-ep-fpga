`timescale 1ns/1ps
// Four-lane / 32-bit, per-packet PHY synchronization profile.
// CRC16 is streamed; pixels are speculative until selected FE confirms a frame.
// No ECC correction or continuous-HS back-to-back packet support is claimed.
//
// ===========================================================================
// T07 round2：本域有界时序重构（187.5 MHz 字节域，判据与契约不变）
// ===========================================================================
//  改动只针对「每拍必须吃满 4 字节、又不可反压」导致的组合深度，**不动对外接口、
//  不动 SDC、不动 187.5 MHz 前提**，行为由差分 TB（对 round1 只读原源的重命名副本）
//  以随机/边界流量逐拍核对。三条具体手法：
//   ① `consumed`（17bit，配 4 组 17bit 比较器）→ `tail`（还需处理到包尾的字节数，
//      含 2 个 CRC 字节）：keep/CRC 字节选择/包尾判定都化成**小范围比较**（tail≤7 时
//      只看低 3 位），比较器深度与扇出大幅下降；
//   ② 4 字节/拍的 CRC 递推由「8 次移位+条件异或 ×4」串行写法改为**扁平 XOR 树**
//      （`include "crc16_upd4.v"`，由 tools/pcie_integration/gen_crc16_flat.py 用同一
//      poly/init 做 GF(2) 线性化生成，脚本自带 2 万+ 随机/边界自检）；
//   ③ CRC 比较 + 错误/坏帧计数移到包尾的后一拍（新状态 END_PEND）：
//      O_packet_done 仍在最后一拍的**同拍**（上游对齐器握手不变），而
//      `crc_bad` 只寄存 1 bit，计数器由寄存位驱动；frame_bad/abort 因此最多滞后
//      1 拍（远早于本帧 FE 的发布裁决，见 change-report §7.4/§8）。
//  另外把两个超时判定从 `>=` 改成对常量的**相等**比较（同样位宽下浅得多）。
//  数据流语义（keep/masked/CRC 覆盖范围/包尾/超时/FS-FE 裁决）与 round1 完全一致；
//  O_payload_* 与像素流仍逐拍对齐（差分 TB 断言），诊断计数最多滞后 1 拍（已记录）。
// ===========================================================================

module csi_rx_packet_integrity #(
 parameter VC_ID=0,IMAGE_DT=6'h2b,IMAGE_WC=0,EXPECTED_LINES=0,CHECK_FRAME_ID=0,
 parameter PACKET_IDLE_CYCLES=32,FRAME_TIMEOUT_CYCLES=16777216
)(
 input I_clock,I_reset_n,I_enable,input[31:0] I_data,input I_data_valid,
 output reg O_packet_done,output O_sync_wait,
 output reg[31:0] O_payload_out,output reg O_payload_valid,output reg[3:0] O_payload_keep,
 output O_vsync_out,output O_in_frame,output reg O_in_line,
 output reg O_frame_end,O_frame_good,O_frame_abort,
 output reg[31:0] O_crc_errors,O_header_errors,O_packet_timeouts,O_frame_timeouts,O_good_frames,O_bad_frames,
 output reg[15:0] O_last_wc,O_last_lines
);
 localparam IDLE=3'd0,HEADER=3'd1,BODY=3'd2,END_PACKET=3'd3;
 reg[2:0] state;reg[15:0] wc,crc,received_crc,frame_id,line_count,frame_wc;
 localparam IDLE_BITS=(PACKET_IDLE_CYCLES<=1)?1:$clog2(PACKET_IDLE_CYCLES);
 localparam AGE_BITS=(FRAME_TIMEOUT_CYCLES<=1)?1:$clog2(FRAME_TIMEOUT_CYCLES);
 // tail = 还需处理到包尾的字节数（= wc + 2 - consumed）：>4 时每拍减 4；<=4 时本拍收口
 reg[16:0] tail;reg[IDLE_BITS-1:0] idle_cycles;reg[AGE_BITS-1:0] frame_age;
 reg selected,check_crc,frame_open,frame_bad,crc_bad_q;
 wire[5:0] dt=I_data[5:0];wire selected_vc=I_data[7:6]==VC_ID;
 wire[7:0] expected_ecc;csi_rx_hdr_ecc u_ecc(.data(I_data[23:0]),.ecc(expected_ecc));
 wire header_ok=I_data_valid&&(I_data[31:24]==expected_ecc)&&((dt<=3)||(dt>=6'h10&&dt<=6'h37));
 wire raw_header=header_ok&&selected_vc&&(dt==IMAGE_DT);
 wire image_ok=raw_header&&(I_data[23:8]!=0)&&(I_data[23:8]%5==0)&&
   ((IMAGE_WC==0)||(I_data[23:8]==IMAGE_WC))&&((frame_wc==0)||(frame_wc==I_data[23:8]));
 wire fe_geometry=(line_count!=0)&&((EXPECTED_LINES==0)||(line_count==EXPECTED_LINES))&&
   ((!CHECK_FRAME_ID)||(frame_id==I_data[23:8]));
 function[31:0] inc(input[31:0] c);inc=(&c)?c:c+1'b1;endfunction

 // ---- ①+②：BODY 每拍的字节级译码（全部小范围比较）与扁平 CRC ----
 // 扁平 4 字节/拍 CRC-16 递推函数（生成文件；含在模块体内以满足 Verilog-2001：
 // 函数不能出现在模块外）——见 tools/pcie_integration/gen_crc16_flat.py 与模块头 ②
`include "crc16_upd4.v"

 wire[7:0] d0=I_data[7:0],d1=I_data[15:8],d2=I_data[23:16],d3=I_data[31:24];
 wire tail_small = (tail[16:3]==13'd0);           // tail <= 7
 wire tail_le4   = tail_small && (tail[2:0]<=3'd4);
 wire[16:0] tail_m4 = tail - 17'd4;               // 仅 tail>=5 时使用（不会回绕）
 // keep[b] = (b < tail-2)，tail<=7 时只依赖低 3 位
 wire[3:0] keep_d = tail_small ? ((tail[2:0]>=3'd6)?4'b1111:
                                  (tail[2:0]==3'd5)?4'b0111:
                                  (tail[2:0]==3'd4)?4'b0011:
                                  (tail[2:0]==3'd3)?4'b0001:4'b0000)
                               : 4'b1111;
 // CRC 两个字节：lo 取字节 (tail-2)、hi 取字节 (tail-1)，都只在 0..3 时有效
 wire[2:0] lo_idx = tail[2:0] - 3'd2;             // 仅 crc_lo_en 时有效（0..3）
 wire[2:0] hi_idx = tail[2:0] - 3'd1;             // 仅 crc_hi_en 时有效（0..3）
 wire crc_lo_en = tail_small && (tail[2:0]>=3'd2) && (tail[2:0]<=3'd5);
 wire crc_hi_en = tail_small && (tail[2:0]>=3'd1) && (tail[2:0]<=3'd4);
 wire[7:0] mux_b   = (lo_idx[1:0]==2'd0)?d0:(lo_idx[1:0]==2'd1)?d1:(lo_idx[1:0]==2'd2)?d2:d3;
 wire[7:0] mux_bm1 = (hi_idx[1:0]==2'd0)?d0:(hi_idx[1:0]==2'd1)?d1:(hi_idx[1:0]==2'd2)?d2:d3;
 // keep 后的载荷字节（= CRC 输入；非 keep 位置补 0，与 round1 的 crc_byte 输入一致）
 wire[7:0] kb0 = keep_d[0]?d0:8'h00, kb1 = keep_d[1]?d1:8'h00,
           kb2 = keep_d[2]?d2:8'h00, kb3 = keep_d[3]?d3:8'h00;
 // ★ 关键：CRC 只按**本拍实际有效的字节数**推进（keep=1 的字节），不是固定 4 字节。
 //   差分 oracle 抓到的第一处分歧就在这里：固定 4 字节会把补零字节也喂进 CRC。
 wire[15:0] crc_u1 = crc16_upd1(crc,kb0);
 wire[15:0] crc_u2 = crc16_upd2(crc,kb0,kb1);
 wire[15:0] crc_u3 = crc16_upd3(crc,kb0,kb1,kb2);
 wire[15:0] crc_u4 = crc16_upd4(crc,kb0,kb1,kb2,kb3);
 wire[15:0] crc_next = crc_u4;  // NEGATIVE CONTROL M1 (r3 independent replay): fixed 4-byte CRC feed
 wire[15:0] received_next = { crc_hi_en?mux_bm1:received_crc[15:8],
                              crc_lo_en?mux_b   :received_crc[7:0] };
 wire[31:0] masked = {keep_d[3]?d3:8'h00, keep_d[2]?d2:8'h00,
                      keep_d[1]?d1:8'h00, keep_d[0]?d0:8'h00};

 assign O_sync_wait=(state==HEADER);
 assign O_vsync_out=I_enable&&(state==HEADER)&&header_ok&&selected_vc&&(dt==0);
 assign O_in_frame=frame_open;
 always @(posedge I_clock or negedge I_reset_n)begin
  if(!I_reset_n)begin
   state<=IDLE;wc<=0;crc<=16'hffff;received_crc<=0;tail<=0;idle_cycles<=0;
   selected<=0;check_crc<=0;frame_open<=0;frame_bad<=0;frame_id<=0;frame_wc<=0;line_count<=0;frame_age<=0;
   crc_bad_q<=0;
   O_packet_done<=0;O_payload_out<=0;O_payload_valid<=0;O_payload_keep<=0;O_in_line<=0;
   O_frame_end<=0;O_frame_good<=0;O_frame_abort<=0;
   O_crc_errors<=0;O_header_errors<=0;O_packet_timeouts<=0;O_frame_timeouts<=0;O_good_frames<=0;O_bad_frames<=0;O_last_wc<=0;O_last_lines<=0;
  end else begin
   O_packet_done<=0;O_payload_out<=0;O_payload_valid<=0;O_payload_keep<=0;O_in_line<=0;
   O_frame_end<=0;O_frame_good<=0;O_frame_abort<=0;
   if(!I_enable)begin
    state<=IDLE;frame_open<=0;selected<=0;crc_bad_q<=0;
    if(frame_open)begin O_frame_abort<=1;if(!frame_bad)O_bad_frames<=inc(O_bad_frames);end
   end else if(frame_open&&(frame_age==FRAME_TIMEOUT_CYCLES-1))begin
    state<=END_PACKET;frame_open<=0;selected<=0;O_packet_done<=1;O_frame_abort<=1;
    O_frame_timeouts<=inc(O_frame_timeouts);if(!frame_bad)O_bad_frames<=inc(O_bad_frames);
   end else begin
    if(frame_open)frame_age<=frame_age+1'b1;
    case(state)
     IDLE:state<=HEADER;
     HEADER:if(I_data_valid)begin
      if(!header_ok)begin
       state<=END_PACKET;O_packet_done<=1;O_header_errors<=inc(O_header_errors);
       if(frame_open)begin frame_bad<=1;O_frame_abort<=1;if(!frame_bad)O_bad_frames<=inc(O_bad_frames);end
      end else if(dt<=3)begin
       state<=END_PACKET;O_packet_done<=1;
       if(selected_vc&&dt==0)begin
        if(frame_open)begin O_frame_abort<=1;if(!frame_bad)O_bad_frames<=inc(O_bad_frames);end
        frame_open<=1;frame_bad<=0;frame_id<=I_data[23:8];frame_wc<=0;line_count<=0;frame_age<=0;
       end else if(selected_vc&&dt==1&&frame_open)begin
        O_frame_end<=1;frame_open<=0;O_last_lines<=line_count;
        if(!frame_bad&&fe_geometry)begin O_frame_good<=1;O_good_frames<=inc(O_good_frames);end
        else begin O_frame_abort<=1;if(!frame_bad)O_bad_frames<=inc(O_bad_frames);end
       end
      end else begin
       state<=BODY;wc<=I_data[23:8];tail<={1'b0,I_data[23:8]}+17'd2;idle_cycles<=0;crc<=16'hffff;received_crc<=0;
       check_crc<=selected_vc;selected<=image_ok&&frame_open&&!frame_bad;O_in_line<=image_ok&&frame_open&&!frame_bad;
       if(raw_header&&frame_open)begin
        O_last_wc<=I_data[23:8];
        if(line_count!=16'hffff)line_count<=line_count+1'b1;
        if(frame_wc==0&&image_ok)frame_wc<=I_data[23:8];
        if(!image_ok||line_count==16'hffff)begin frame_bad<=1;O_frame_abort<=1;if(!frame_bad)O_bad_frames<=inc(O_bad_frames);end
       end
      end
     end
     BODY:begin
      if(I_data_valid)begin
       idle_cycles<=0;crc<=crc_next;received_crc<=received_next;
       if(selected&&keep_d!=0)begin O_payload_out<=masked;O_payload_valid<=1;O_payload_keep<=keep_d;end
       if(tail_le4)begin
        // 本拍收口：O_packet_done 仍在**同拍**（与 round1 一致）；CRC 比较只寄存 1 bit，
        // 计数/坏帧标记放到紧随的 END_PACKET 第一拍做（③：比较+计数器移出每拍同拍链）。
        // 状态序列与 round1 **完全一致**（不新增状态，避免 IDLE/HEADER 相位漂移）。
        state<=END_PACKET;O_packet_done<=1;
        crc_bad_q<=check_crc&&(crc_next!=received_next);
       end else begin
        tail<=tail_m4;
       end
      end else if(idle_cycles==PACKET_IDLE_CYCLES-1)begin
       state<=END_PACKET;O_packet_done<=1;O_packet_timeouts<=inc(O_packet_timeouts);
       if(frame_open)begin frame_bad<=1;O_frame_abort<=1;if(!frame_bad)O_bad_frames<=inc(O_bad_frames);end
      end else idle_cycles<=idle_cycles+1'b1;
     end
     // ③ 包尾第一拍：只做 CRC 坏→计数/坏帧（输入只有 1 bit 寄存位 + 计数器，浅）。
     //    状态退出条件与 round1 相同（!I_data_valid → IDLE），所以序列/相位不变。
     END_PACKET:begin
      if(crc_bad_q)begin
       crc_bad_q<=1'b0;
       O_crc_errors<=inc(O_crc_errors);
       if(frame_open)begin frame_bad<=1;O_frame_abort<=1;if(!frame_bad)O_bad_frames<=inc(O_bad_frames);end
      end
      if(!I_data_valid)state<=IDLE;
     end
     // packet_done clears the upstream aligners, but their registered word
     // output and gearbox still deliver tail beats. Keep sync acquisition
     // disabled until that pipeline is empty; tail bytes are not headers.
     END_PACKET:if(!I_data_valid)state<=IDLE;
     default:state<=IDLE;
    endcase
   end
  end
 end
endmodule
