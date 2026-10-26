`timescale 1ns/1ps
// Four-lane/32-bit gearbox packet profile. CRC bytes are drained but NOT
// checked here. ECC is detected only (no correction). Bad-frame propagation
// and continuous-HS back-to-back packets require a separate contract.
module csi_rx_packet_handler_checked #(
 parameter MIPI_LAN=4,VC_ID=0,IMAGE_DT=6'h2b,IMAGE_WC=0
)(
 input I_clock,I_reset_n,I_enable,input[31:0] I_data,input I_data_valid,
 output O_packet_done,O_sync_wait,
 output reg[31:0] O_payload_out,output reg O_payload_valid,
 output reg[3:0] O_payload_keep,
 output O_vsync_out,O_in_frame,O_in_line
);
 localparam IDLE=0,HEADER=1,BODY=2,END_PACKET=3;
 reg[1:0] state,next_state;
 reg[15:0] wc;
 reg[16:0] consumed;
 reg selected,frame_open,line_start,packet_done;
 reg[5:0] idle_cycles;
 wire[5:0] dt=I_data[5:0];
 wire selected_vc=(I_data[7:6]==VC_ID);
 wire[7:0] expected_ecc;
 csi_rx_hdr_ecc u_ecc(.data(I_data[23:0]),.ecc(expected_ecc));
 // Recognize foreign VC packets too, so their entire body is skipped.
 wire header_ok=I_data_valid&&(I_data[31:24]==expected_ecc)&&
  ((dt<=6'h03)||(dt>=6'h10&&dt<=6'h37));
 wire image_header=header_ok&&selected_vc&&(dt==IMAGE_DT)&&
  (I_data[23:8]!=0)&&((IMAGE_WC==0)||(I_data[23:8]==IMAGE_WC));
 wire[16:0] remaining={1'b0,wc}-consumed;
 wire payload_beat=(state==BODY)&&I_data_valid&&selected&&(consumed<{1'b0,wc});
 wire[3:0] keep=(remaining>=4)?4'b1111:(remaining==3)?4'b0111:(remaining==2)?4'b0011:4'b0001;
 wire[31:0] mask={{8{keep[3]}},{8{keep[2]}},{8{keep[1]}},{8{keep[0]}}};
 always @* begin
  next_state=state;
  case(state)
   IDLE:next_state=HEADER;
   HEADER:if(header_ok)next_state=(dt>6'h0f)?BODY:END_PACKET;
   BODY:if((I_data_valid&&consumed+17'd4>={1'b0,wc}+17'd2)||idle_cycles==31)next_state=END_PACKET;
   END_PACKET:next_state=IDLE;
   default:next_state=IDLE;
  endcase
 end
 always @(posedge I_clock or negedge I_reset_n)begin
  if(!I_reset_n)begin
   state<=IDLE;wc<=0;consumed<=0;selected<=0;frame_open<=0;
   line_start<=0;packet_done<=0;idle_cycles<=0;
   O_payload_out<=0;O_payload_valid<=0;O_payload_keep<=0;
  end else begin
   line_start<=0;packet_done<=0;O_payload_valid<=0;O_payload_keep<=0;O_payload_out<=0;
   if(I_enable)begin
    state<=next_state;packet_done<=(next_state==END_PACKET);
    if(state==HEADER)begin
     consumed<=0;idle_cycles<=0;
     if(header_ok)begin
      wc<=I_data[23:8];selected<=image_header;line_start<=image_header;
      if(selected_vc&&dt==0)frame_open<=1;
      if(selected_vc&&dt==1)frame_open<=0;
     end
    end else if(state==BODY)begin
     if(I_data_valid)begin consumed<=consumed+17'd4;idle_cycles<=0;end
     else if(idle_cycles<31)idle_cycles<=idle_cycles+1'b1;
     if(payload_beat)begin O_payload_valid<=1;O_payload_keep<=keep;O_payload_out<=I_data&mask;end
    end
   end
  end
 end
 assign O_vsync_out=I_enable&&(state==HEADER)&&header_ok&&selected_vc&&(dt==0);
 assign O_in_frame=frame_open;
 assign O_in_line=line_start;
 assign O_packet_done=packet_done;
 assign O_sync_wait=(state==HEADER);
endmodule
