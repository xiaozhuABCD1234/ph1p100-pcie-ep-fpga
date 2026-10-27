`timescale 1ns/1ps
// A contiguous low-byte keep is supplied by the checked packet handler.
// Buffer at most four bytes; each five-byte RAW10 group emits four pixels.
module csi_rx_10bit_unpack_checked(
 input I_clock,I_reset_n,I_enable,I_line_in,
 input[31:0] I_data_in,input[3:0] I_keep,input I_din_valid,
 output reg[39:0] O_data_out,output reg O_dout_valid
);
 reg[31:0] pending;
 reg[2:0] count;
 reg[39:0] group_data;reg group_valid;
 wire[2:0] incoming=(I_keep==4'b1111)?4:(I_keep==4'b0111)?3:
                       (I_keep==4'b0011)?2:(I_keep==4'b0001)?1:0;
 wire[3:0] total={1'b0,count}+{1'b0,incoming};
 wire[63:0] joined={32'd0,pending}|({32'd0,I_data_in}<<{count,3'b000});
 always @(posedge I_clock or negedge I_reset_n)begin
  if(!I_reset_n)begin pending<=0;count<=0;group_data<=0;group_valid<=0;O_data_out<=0;O_dout_valid<=0;end
  else begin
   group_valid<=0;O_dout_valid<=0;O_data_out<=0;
   if(I_enable)begin
    if(I_line_in)begin pending<=0;count<=0;end
    else begin
     if(I_din_valid&&incoming!=0)begin
      if(total>=5)begin
       group_data<=joined[39:0];group_valid<=1;pending<=joined[63:40];count<=total-5;
      end else begin pending<=joined[31:0];count<=total;end
     end
     if(group_valid)begin
      O_dout_valid<=1;
      O_data_out<={group_data[31:24],group_data[39:38],group_data[23:16],group_data[37:36],
                   group_data[15:8],group_data[35:34],group_data[7:0],group_data[33:32]};
     end
    end
   end
  end
 end
endmodule
