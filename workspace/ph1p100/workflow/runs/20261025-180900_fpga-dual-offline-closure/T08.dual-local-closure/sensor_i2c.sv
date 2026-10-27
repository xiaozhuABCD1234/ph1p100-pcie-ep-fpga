`timescale 1ns/1ps
// Pin-only sensor register memory. No access to DUT expectations or hierarchy.
module sensor_i2c #(parameter CAMERA=0)(
 input wire rst_n,scl,inout wire sda,input integer nack_at,
 input wire [7:0] read_xor,input wire [15:0] read_xor_addr,
 output integer transactions,output integer reads);
 reg drive_low=0,active=0,reading=0;integer bits=0,bytes=0;
 reg [7:0] shift=0,tx_data=0;reg [15:0] address=0;
 reg [31:0] word_q=0;reg [3:0] ack_q=0;reg [7:0] regs[0:65535];integer fd,z;
 assign sda=drive_low ? 1'b0 : 1'bz;
 initial begin transactions=0;reads=0;
   for(z=0;z<65536;z=z+1) regs[z]=0;
   if(CAMERA==0) fd=$fopen("i2c_a.log","w");else fd=$fopen("i2c_b.log","w");
   if(!fd) $fatal(1,"I2C trace open");end
 always @(negedge rst_n) begin
   active=0;drive_low=0;reading=0;bits=0;bytes=0;transactions=0;reads=0;word_q=0;ack_q=0;
   $fdisplay(fd,"RESET %0t",$time);
 end
 always @(negedge sda) if(rst_n && scl===1'b1 && !drive_low) begin
   if(active && bytes==3) $fdisplay(fd,"ADDR %0t %04x",$time,address);
   active=1;reading=0;bits=0;bytes=0;word_q=0;ack_q=0;shift=0;
 end
 always @(posedge scl) if(rst_n && active) begin
   if(reading) begin
     if(bits<8) bits=bits+1;
     else begin
       if(sda!==1'b1) $fatal(1,"master must NACK final read byte");
       $fdisplay(fd,"READ %0t %04x %02x",$time,address,tx_data);
       reads=reads+1;reading=0;active=0;drive_low=0;
     end
   end else if(bits<8) begin shift={shift[6:0],sda};bits=bits+1;end
   else begin
     if(bytes<4) begin word_q={word_q[23:0],shift};ack_q[bytes]=(sda===1'b0);end
     if(bytes==1) address[15:8]=shift;
     if(bytes==2) address[7:0]=shift;
     if(bytes==3 && sda===1'b0) regs[address]=shift;
     if(bytes==0 && shift==8'h35) begin
       tx_data=regs[address] ^ ((address==read_xor_addr)?read_xor:8'h00);reading=1;
     end
     bytes=bytes+1;bits=0;
   end
 end
 always @(negedge scl) if(active) begin
   if(reading) drive_low=bits<8 ? !tx_data[7-bits] : 0;
   else drive_low=(bits==8) && !(transactions==nack_at && bytes==3);
 end else drive_low=0;
 always @(posedge sda) if(rst_n && scl===1'b1 && active && !drive_low) begin
   if(bytes==4) begin
     $fdisplay(fd,"TX %0t %0d %08x %01x",$time,transactions,word_q,ack_q);transactions=transactions+1;
   end
   active=0;drive_low=0;
 end
endmodule
