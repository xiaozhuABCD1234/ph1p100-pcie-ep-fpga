"""Exact RGB565 derivation; parent RTL stays frozen and separately usable."""
def once(s,a,b):
    assert s.count(a)==1,a
    return s.replace(a,b)

def capture(source):
    s=source.decode().replace('bayer332_capture','bayer565_capture')
    s=once(s,'// Diagnostic preview: one RGB332 pixel from the first2x2 cell of each4x4 block.',
           '// RGB565 preview from each first2x2 cell of a4x4 block; retain raw10 statistics.')
    s=once(s,'output reg out_sof,out_valid,out_last,output reg[7:0] out_data',
           'output reg out_sof,out_valid,out_last,output reg[15:0] out_data,\n input frame_end,frame_good,frame_abort,\n output reg[31:0] stat_a,stat_b,stat_c,stat_d,stat_count,stat_sequence,output reg stat_valid')
    s=s.replace('[15:0] top_line','[19:0] top_line').replace('[15:0] pair','[19:0] pair').replace('[15:0] top_q,bottom_q','[19:0] top_q,bottom_q')
    s=once(s,'{in_pixels[19:12],in_pixels[9:2]}','{in_pixels[19:10],in_pixels[9:0]}')
    s=s.replace('reg[7:0] red,blue','reg[9:0] red,blue').replace('reg[8:0] green_sum','reg[10:0] green_sum')
    s=s.replace('top_q[7:0]','top_q[9:0]').replace('top_q[15:8]','top_q[19:10]').replace('bottom_q[7:0]','bottom_q[9:0]').replace('bottom_q[15:8]','bottom_q[19:10]')
    s=once(s,'{red[7:5],green_sum[8:6],blue[7:6]}','{red[9:5],green_sum[10:5],blue[9:5]}')
    pos=s.index(' always @(posedge clk)begin')
    stats=''' // Physical Bayer positions A/B over C/D, before phase mapping or quantization.
 // Publish only a complete preview belonging to a CSI frame with a good FE verdict.
 reg[31:0] sum_a,sum_b,sum_c,sum_d,sample_count;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   sum_a<=0;sum_b<=0;sum_c<=0;sum_d<=0;sample_count<=0;
   stat_a<=0;stat_b<=0;stat_c<=0;stat_d<=0;stat_count<=0;stat_sequence<=0;stat_valid<=0;
  end else begin
   if(frame_rise)begin sum_a<=0;sum_b<=0;sum_c<=0;sum_d<=0;sample_count<=0;end
   else if(pending)begin
    sum_a<=sum_a+top_q[9:0];sum_b<=sum_b+top_q[19:10];
    sum_c<=sum_c+bottom_q[9:0];sum_d<=sum_d+bottom_q[19:10];sample_count<=sample_count+1'b1;
   end
   if(frame_abort)stat_valid<=0;
   else if(frame_end)begin
    stat_valid<=frame_good&&!frame_rise&&(sample_count+(pending?1:0)==SW*SH);
    if(frame_good&&!frame_rise&&(sample_count+(pending?1:0)==SW*SH))begin
     stat_a<=sum_a+(pending?top_q[9:0]:10'd0);stat_b<=sum_b+(pending?top_q[19:10]:10'd0);
     stat_c<=sum_c+(pending?bottom_q[9:0]:10'd0);stat_d<=sum_d+(pending?bottom_q[19:10]:10'd0);
     stat_count<=sample_count+(pending?1:0);stat_sequence<=stat_sequence+1'b1;
    end
   end
  end
 end
'''
    return (s[:pos]+stats+s[pos:]).encode()

def pack(source):
    s=source.decode().replace('gray_frame_pack_guarded','rgb565_frame_pack_guarded').replace('FRAME_BYTES=518400','FRAME_BYTES=1036800')
    s=s.replace('input[7:0] pixel','input[15:0] pixel').replace('reg[4:0] byte_index','reg[3:0] pixel_index')
    s=s.replace('byte_index','pixel_index').replace('pixel_index==31','pixel_index==15')
    s=once(s,'crc_byte(crc,pixel)','crc_byte(crc_byte(crc,pixel[7:0]),pixel[15:8])')
    s=s.replace('byte_count==FRAME_BYTES-1','byte_count==FRAME_BYTES-2')
    s=once(s,'{2\'b00,pixel,pack_data[247:0]}','{2\'b00,pixel,pack_data[239:0]}')
    s=once(s,'pack_data[pixel_index*8+:8]<=pixel','pack_data[pixel_index*16+:16]<=pixel')
    s=once(s,"byte_count<=byte_count+1'b1","byte_count<=byte_count+2'd2")
    return s.encode()

def reader(source):
    s=source.decode().replace('module ddr_display_read','module rgb565_display_read')
    s=once(s,'ROW_WORDS=SW/32,PAYLOAD_WORDS=SW*SH/32','ROW_WORDS=SW/16,PAYLOAD_WORDS=SW*SH/16')
    s=once(s,'rd_data[127:96]==SW*SH','rd_data[127:96]==SW*SH*2')
    s=once(s,"crc<=crc_byte(crc,crc_word[7:0]);crc_word<={8'd0,crc_word[255:8]};byte_index<=byte_index+1'b1;",
           "crc<=crc_byte(crc_byte(crc,crc_word[7:0]),crc_word[15:8]);crc_word<={16'd0,crc_word[255:16]};byte_index<=byte_index+2'd2;")
    s=once(s,'if(byte_index==31)','if(byte_index==30)')
    return s.encode()

def consumer(source):
    s=source.decode().replace('rgb332_display_pixels','rgb565_display_pixels')
    s=once(s,'parameter SW=960,SH=540,FRAMES_PER_MODE=480','parameter SW=960,SH=540')
    s=once(s,' reg[4:0] byte_index;reg[7:0] last_gray;',' reg[3:0] pixel_index;reg[15:0] last_color;')
    start=s.index(' localparam COUNT_BITS=');end=s.index('\n wire[1:0] tag=',start)
    s=s[:start]+''' // Force real color; no automatic grayscale mode changes.
 always @* color_mode=1'b1;
 function[23:0] decode(input[15:0] code);
  begin decode={code[15:11],code[15:13],code[10:5],code[10:9],code[4:0],code[4:2]};end
 endfunction
'''+s[end:]
    s=s.replace('byte_index','pixel_index').replace('last_gray','last_color').replace('pixel_index==31','pixel_index==15')
    s=s.replace('current_word[7:0],color_mode','current_word[15:0]').replace('next_word[7:0],color_mode','next_word[15:0]').replace('last_color,color_mode','last_color')
    s=s.replace('last_color<=current_word[7:0]','last_color<=current_word[15:0]').replace('last_color<=next_word[7:0]','last_color<=next_word[15:0]')
    s=s.replace("{8'd0,current_word[255:8]}","{16'd0,current_word[255:16]}").replace("{8'd0,next_word[255:8]}","{16'd0,next_word[255:16]}")
    s=s.replace('// RGB332 diagnostic; DATA rows and each packed pixel retain the existing2x repetition.','// RGB565 color; DATA rows and each packed pixel retain the existing2x repetition.')
    s=s.replace('shifts by a fixed byte','shifts by one16-bit pixel')
    # A constant output is a net, not a no-sensitivity combinational process.
    s=s.replace('output reg color_mode','output color_mode').replace("always @* color_mode=1'b1;","assign color_mode=1'b1;")
    return s.encode()

def wrapper(source):
    s=source.decode().replace('module camera_ddr_display_guarded','module camera_rgb565_display_guarded')
    s=once(s,'input[7:0] pixel','input[15:0] pixel')
    s=once(s,'gray_frame_pack_guarded #(.FRAME_BYTES(SW*SH))','rgb565_frame_pack_guarded #(.FRAME_BYTES(SW*SH*2))')
    s=once(s,'(.FRAME_WORDS((SW*SH)/32+1))','(.FRAME_WORDS((SW*SH)/16+1))')
    s=once(s,'ddr_display_read #(','rgb565_display_read #(')
    s=once(s,'rgb332_display_pixels #(.SW(SW),.SH(SH),.FRAMES_PER_MODE(480))','rgb565_display_pixels #(.SW(SW),.SH(SH))')
    s=once(s,'.rgb(display_camera_rgb)','.rgb(rgb)')
    s=once(s,' wire[23:0] display_camera_rgb;\n','')
    start=s.index(' // Reference bars bypass')
    s=s[:start]+'endmodule\n'
    return s.encode()
