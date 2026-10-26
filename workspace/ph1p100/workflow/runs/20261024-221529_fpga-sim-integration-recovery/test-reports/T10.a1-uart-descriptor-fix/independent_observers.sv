`timescale 1ns/1ps
// Physical 8N1 observation is independent of the exporter's debug byte tap.
module serial_probe #(parameter real BIT_NS=40.0)(input rst_n, txd, input [31:0] epoch);
 integer fd, i, serial_count=0; reg [7:0] b; reg [31:0] e;
 reg [2047:0] path;
 initial begin
  if (!$value$plusargs("WIRE=%s",path)) $fatal(1,"INDEPENDENT_WIRE_PATH");
  fd=$fopen(path,"w"); if(!fd) $fatal(1,"INDEPENDENT_WIRE_OPEN");
 end
 always @(negedge txd) if(rst_n) begin
  e=epoch; b=0; #(BIT_NS/2.0);
  if(txd!==0) $fatal(1,"WIRE_START_BIT");
  for(i=0;i<8;i=i+1) begin
   #(BIT_NS); if(txd!==0 && txd!==1) $fatal(1,"WIRE_X"); b[i]=txd;
  end
  #(BIT_NS); if(txd!==1 || !rst_n) $fatal(1,"WIRE_STOP_BIT_OR_RESET");
  $fwrite(fd,"%0d %0d\n",e,b); serial_count=serial_count+1;
 end
 final begin $display("INDEPENDENT_WIRE_COUNT=%0d",serial_count); $fclose(fd); end
endmodule

module tester_descriptor;
 tb_descriptor tb();
 serial_probe #(.BIT_NS(40.0)) wire_observer(tb.rst_n,tb.txd,tb.epoch);
endmodule

module tester_full;
 tb_full_clean #(.W(8),.H(2),.MAX_CYCLES(1500000)) tb();
 serial_probe #(.BIT_NS(21.332)) wire_observer(tb.rst_n,tb.txd,tb.epoch);
endmodule
