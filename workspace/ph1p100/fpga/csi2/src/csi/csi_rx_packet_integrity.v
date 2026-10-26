`timescale 1ns/1ps
// Four-lane / 32-bit, per-packet PHY synchronization profile.
// CRC16 is streamed; pixels are speculative until selected FE confirms a frame.
// No ECC correction or continuous-HS back-to-back packet support is claimed.
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
 localparam IDLE=0,HEADER=1,BODY=2,END_PACKET=3;
 reg[1:0] state;reg[15:0] wc,crc,received_crc,frame_id,line_count,frame_wc;
 localparam IDLE_BITS=(PACKET_IDLE_CYCLES<=1)?1:$clog2(PACKET_IDLE_CYCLES);
 localparam AGE_BITS=(FRAME_TIMEOUT_CYCLES<=1)?1:$clog2(FRAME_TIMEOUT_CYCLES);
 reg[16:0] consumed;reg[IDLE_BITS-1:0] idle_cycles;reg[AGE_BITS-1:0] frame_age;
 reg selected,check_crc,frame_open,frame_bad;
 wire[5:0] dt=I_data[5:0];wire selected_vc=I_data[7:6]==VC_ID;
 wire[7:0] expected_ecc;csi_rx_hdr_ecc u_ecc(.data(I_data[23:0]),.ecc(expected_ecc));
 wire header_ok=I_data_valid&&(I_data[31:24]==expected_ecc)&&((dt<=3)||(dt>=6'h10&&dt<=6'h37));
 wire raw_header=header_ok&&selected_vc&&(dt==IMAGE_DT);
 wire image_ok=raw_header&&(I_data[23:8]!=0)&&(I_data[23:8]%5==0)&&
   ((IMAGE_WC==0)||(I_data[23:8]==IMAGE_WC))&&((frame_wc==0)||(frame_wc==I_data[23:8]));
 wire fe_geometry=(line_count!=0)&&((EXPECTED_LINES==0)||(line_count==EXPECTED_LINES))&&
   ((!CHECK_FRAME_ID)||(frame_id==I_data[23:8]));
 function[31:0] inc(input[31:0] c);inc=(&c)?c:c+1'b1;endfunction
 function[15:0] crc_byte(input[15:0] c,input[7:0] b);
  reg[15:0] v;integer k;begin v=c^{8'd0,b};for(k=0;k<8;k=k+1)v=(v>>1)^(v[0]?16'h8408:0);crc_byte=v;end
 endfunction
 reg[15:0] crc_next,received_next;reg[3:0] keep;reg[31:0] masked;integer b;
 always @*begin
  crc_next=crc;received_next=received_crc;keep=0;masked=0;
  for(b=0;b<4;b=b+1)begin
   if(consumed+b<{1'b0,wc})begin crc_next=crc_byte(crc_next,I_data[b*8+:8]);keep[b]=1;masked[b*8+:8]=I_data[b*8+:8];end
   else if(consumed+b=={1'b0,wc})received_next[7:0]=I_data[b*8+:8];
   else if(consumed+b=={1'b0,wc}+1)received_next[15:8]=I_data[b*8+:8];
  end
 end
 assign O_sync_wait=(state==HEADER);
 assign O_vsync_out=I_enable&&(state==HEADER)&&header_ok&&selected_vc&&(dt==0);
 assign O_in_frame=frame_open;
 always @(posedge I_clock or negedge I_reset_n)begin
  if(!I_reset_n)begin
   state<=IDLE;wc<=0;crc<=16'hffff;received_crc<=0;consumed<=0;idle_cycles<=0;
   selected<=0;check_crc<=0;frame_open<=0;frame_bad<=0;frame_id<=0;frame_wc<=0;line_count<=0;frame_age<=0;
   O_packet_done<=0;O_payload_out<=0;O_payload_valid<=0;O_payload_keep<=0;O_in_line<=0;
   O_frame_end<=0;O_frame_good<=0;O_frame_abort<=0;
   O_crc_errors<=0;O_header_errors<=0;O_packet_timeouts<=0;O_frame_timeouts<=0;O_good_frames<=0;O_bad_frames<=0;O_last_wc<=0;O_last_lines<=0;
  end else begin
   O_packet_done<=0;O_payload_out<=0;O_payload_valid<=0;O_payload_keep<=0;O_in_line<=0;
   O_frame_end<=0;O_frame_good<=0;O_frame_abort<=0;
   if(!I_enable)begin
    state<=IDLE;frame_open<=0;selected<=0;
    if(frame_open)begin O_frame_abort<=1;if(!frame_bad)O_bad_frames<=inc(O_bad_frames);end
   end else if(frame_open&&frame_age>=FRAME_TIMEOUT_CYCLES-1)begin
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
       state<=BODY;wc<=I_data[23:8];consumed<=0;idle_cycles<=0;crc<=16'hffff;received_crc<=0;
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
       consumed<=consumed+17'd4;idle_cycles<=0;crc<=crc_next;received_crc<=received_next;
       if(selected&&keep!=0)begin O_payload_out<=masked;O_payload_valid<=1;O_payload_keep<=keep;end
       if(consumed+17'd4>={1'b0,wc}+17'd2)begin
        state<=END_PACKET;O_packet_done<=1;
        if(check_crc&&crc_next!=received_next)begin
         O_crc_errors<=inc(O_crc_errors);
         if(frame_open)begin frame_bad<=1;O_frame_abort<=1;if(!frame_bad)O_bad_frames<=inc(O_bad_frames);end
        end
       end
      end else if(idle_cycles>=PACKET_IDLE_CYCLES-1)begin
       state<=END_PACKET;O_packet_done<=1;O_packet_timeouts<=inc(O_packet_timeouts);
       if(frame_open)begin frame_bad<=1;O_frame_abort<=1;if(!frame_bad)O_bad_frames<=inc(O_bad_frames);end
      end else idle_cycles<=idle_cycles+1'b1;
     end
     // packet_done clears the upstream aligners, but their registered word
     // output and gearbox still deliver tail beats. Keep sync acquisition
     // disabled until that pipeline is empty; tail bytes are not headers.
     END_PACKET:if(!I_data_valid)state<=IDLE;
    endcase
   end
  end
 end
endmodule
