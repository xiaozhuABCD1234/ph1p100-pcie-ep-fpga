`timescale 1ns/1ps
// Pin-only open-drain slave/decoder. Does not read any DUT table or hierarchy.
module sensor_i2c #(parameter CAMERA=0)(
 input wire rst_n,scl,inout wire sda,input integer nack_at,
 output integer transactions);
 reg drive_low=0,active=0;integer bits=0,bytes=0;
 reg [7:0] shift=0;reg [31:0] word_q=0;reg [3:0] ack_q=0;
 integer fd;
 assign sda=drive_low ? 1'b0 : 1'bz;
 initial begin transactions=0;
   if(CAMERA==0) fd=$fopen("i2c_a.log","w");else fd=$fopen("i2c_b.log","w");
   if(!fd) $fatal(1,"I2C trace open");end
 always @(negedge rst_n) begin
   active=0;drive_low=0;bits=0;bytes=0;transactions=0;word_q=0;ack_q=0;
   $fdisplay(fd,"RESET %0t",$time);
 end
 always @(negedge sda) if(rst_n && scl===1'b1 && !drive_low) begin
   active=1;bits=0;bytes=0;word_q=0;ack_q=0;shift=0;
 end
 always @(posedge scl) if(rst_n && active) begin
   if(bits<8) begin shift={shift[6:0],sda};bits=bits+1;end
   else begin
     if(bytes<4) begin word_q={word_q[23:0],shift};ack_q[bytes]=(sda===1'b0);end
     bytes=bytes+1;bits=0;
   end
 end
 always @(negedge scl) if(active) begin
   drive_low=(bits==8) && !(transactions==nack_at && bytes==3);
 end else drive_low=0;
 always @(posedge sda) if(rst_n && scl===1'b1 && active && !drive_low) begin
   // STOP has an SCL high setup phase, which can contain one unfinished bit.
   if(bytes!=4 || bits>1) $fatal(1,"I2C malformed transaction camera=%0d bytes=%0d bits=%0d",CAMERA,bytes,bits);
   $fdisplay(fd,"TX %0t %0d %08x %01x",$time,transactions,word_q,ack_q);
   transactions=transactions+1;active=0;drive_low=0;
 end
endmodule
