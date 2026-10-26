`timescale 1ns/1ps
module tb_csi_integrity #(parameter LINE_BYTES=20);
 reg clk=0,rst_n=0,en=1,valid=0;reg[31:0] data=0;reg[23:0] hdr=0;
 wire[7:0] ecc;wire[31:0] payload;wire pv,done,waitsync,vs,inf,inl;wire[3:0] keep;
 wire fe,fg,abort_frame;wire[31:0] crc_errors,header_errors,packet_timeouts,frame_timeouts,good_frames,bad_frames;wire[15:0] last_wc,last_lines;
 integer ends=0,goods=0,aborts=0,cases=0,i,j,k,g0,e0,c0;reg check_keep=1,corrupt_payload=0;reg[15:0] known;
 csi_rx_hdr_ecc e(.data(hdr),.ecc(ecc));always #5 clk=~clk;
`ifdef BASELINE
 reg prev=0;assign fe=prev&&!inf;assign fg=fe;assign abort_frame=0;
 assign crc_errors=0;assign header_errors=0;assign packet_timeouts=0;assign frame_timeouts=0;assign good_frames=0;assign bad_frames=0;assign last_wc=0;assign last_lines=0;
 always @(posedge clk)prev<=inf;
 csi_rx_packet_handler_checked d(
`else
 csi_rx_packet_integrity #(.EXPECTED_LINES(2),.CHECK_FRAME_ID(1),.FRAME_TIMEOUT_CYCLES(8192)) d(.O_frame_end(fe),.O_frame_good(fg),.O_frame_abort(abort_frame),.O_crc_errors(crc_errors),.O_header_errors(header_errors),.O_packet_timeouts(packet_timeouts),.O_frame_timeouts(frame_timeouts),.O_good_frames(good_frames),.O_bad_frames(bad_frames),.O_last_wc(last_wc),.O_last_lines(last_lines),
`endif
 .I_clock(clk),.I_reset_n(rst_n),.I_enable(en),.I_data(data),.I_data_valid(valid),.O_packet_done(done),.O_sync_wait(waitsync),.O_payload_out(payload),.O_payload_valid(pv),.O_payload_keep(keep),.O_vsync_out(vs),.O_in_frame(inf),.O_in_line(inl));
 task fail(input string why);begin $display("INTEGRITY_FAIL packet %s goods=%0d crc=%0d",why,goods,crc_errors);$finish;end endtask
 always @(posedge clk)begin #1;if(fe)ends++;if(fg)goods++;if(abort_frame)aborts++;
  if(pv&&check_keep)begin if(!(keep==1||keep==3||keep==7||keep==15))fail("keep");for(integer b=0;b<4;b++)if(!keep[b]&&payload[b*8+:8]!==0)fail("tail mask");end
 end
 // Independent MSB-first 0x1021 reference, with explicit input/output reversal.
 function[7:0] rev8(input[7:0] v);begin for(integer b=0;b<8;b++)rev8[b]=v[7-b];end endfunction
 function[15:0] reverse16(input[15:0] v);begin for(integer b=0;b<16;b++)reverse16[b]=v[15-b];end endfunction
 function[7:0] value(input integer n);value=(n*37+(n>>8)*13+7)&255;endfunction
 function[15:0] checksum(input integer wc);
 reg[15:0] c;reg[7:0] b;begin c=16'hffff;for(integer n=0;n<wc;n++)begin b=rev8(value(n));c=c^{b,8'd0};for(integer z=0;z<8;z++)c=(c<<1)^(c[15]?16'h1021:0);end checksum=reverse16(c);end endfunction
 task beat(input[31:0] v);begin @(negedge clk);data=v;valid=1;end endtask
 task idle(input integer n);begin @(negedge clk);valid=0;repeat(n)@(negedge clk);end endtask
 task shortpkt(input[7:0] di,input[15:0] num,input bit bad_ecc);begin hdr={num,di};#1;beat({ecc^(bad_ecc?8'h01:8'h00),hdr});idle(6);end endtask
 task linepkt(input[7:0] di,input integer wc,input bit bad_crc,input bit gaps);
 reg[15:0] c;reg[31:0] w;integer offset;begin
 hdr={wc[15:0],di};#1;beat({ecc,hdr});c=checksum(wc)^(bad_crc?16'h0001:0);
 for(integer n=0;n<(wc+5)/4;n++)begin
  w=32'hd00dd00d;for(integer b=0;b<4;b++)begin offset=n*4+b;if(offset<wc)w[b*8+:8]=value(offset);else if(offset==wc)w[b*8+:8]=c[7:0];else if(offset==wc+1)w[b*8+:8]=c[15:8];end
  if(corrupt_payload&&n==0)w[0]=~w[0];if(gaps&&n%7==1)idle(1);beat(w);
 end idle(8);
 end endtask
 task good(input integer wc);begin g0=goods;shortpkt(0,7,0);linepkt(8'h2b,wc,0,1);linepkt(8'h2b,wc,0,0);shortpkt(1,7,0);if(goods!=g0+1)fail("complete recovery");cases++;end endtask
 initial begin
  repeat(4)@(negedge clk);rst_n=1;idle(4);
  // First red case: correct payload, corrupted CRC in second image line.
  shortpkt(0,7,0);linepkt(8'h2b,LINE_BYTES,0,0);linepkt(8'h2b,LINE_BYTES,1,0);shortpkt(1,7,0);
  if(goods!=0||crc_errors!=1||aborts==0)fail("bad CRC frame accepted or undetected");cases++;
  good(LINE_BYTES);
  g0=goods;c0=crc_errors;shortpkt(0,7,0);linepkt(8'h2b,LINE_BYTES,0,0);corrupt_payload=1;linepkt(8'h2b,LINE_BYTES,0,0);corrupt_payload=0;shortpkt(1,7,0);if(goods!=g0||crc_errors!=c0+1)fail("payload bit corruption");good(LINE_BYTES);cases++;
  for(k=5;k<=40;k=k+5)good(k); // CRC footer starts at every byte residue.
  g0=goods;c0=crc_errors;shortpkt(0,7,0);linepkt(8'h6b,5,1,0);linepkt(8'h12,3,0,0);linepkt(8'h2b,LINE_BYTES,0,0);linepkt(8'h2b,LINE_BYTES,0,0);shortpkt(8'h41,7,0);if(!inf)fail("foreign FE closed frame");shortpkt(1,7,0);if(goods!=g0+1||crc_errors!=c0)fail("foreign VC/embedded isolation");cases++;
  g0=goods;shortpkt(0,7,0);linepkt(8'h2b,LINE_BYTES,0,0);linepkt(8'h2b,LINE_BYTES,0,0);linepkt(8'h12,1,1,0);shortpkt(1,7,0);if(goods!=g0)fail("late metadata CRC accepted");good(LINE_BYTES);cases++;
  g0=goods;shortpkt(0,7,0);linepkt(8'h2b,LINE_BYTES,0,0);linepkt(8'h2b,LINE_BYTES+5,0,0);shortpkt(1,7,0);if(goods!=g0)fail("inconsistent WC accepted");good(LINE_BYTES);cases++;
  g0=goods;shortpkt(0,7,0);linepkt(8'h2b,6,0,0);linepkt(8'h2b,6,0,0);shortpkt(1,7,0);if(goods!=g0)fail("invalid RAW10 WC accepted");good(LINE_BYTES);cases++;
  g0=goods;shortpkt(0,7,0);linepkt(8'h2b,LINE_BYTES,0,0);shortpkt(1,7,0);if(goods!=g0)fail("short geometry accepted");good(LINE_BYTES);cases++;
  g0=goods;shortpkt(0,7,0);linepkt(8'h2b,LINE_BYTES,0,0);linepkt(8'h2b,LINE_BYTES,0,0);shortpkt(1,8,0);if(goods!=g0)fail("FE ID mismatch");good(LINE_BYTES);cases++;
  g0=goods;shortpkt(0,7,0);linepkt(8'h2b,LINE_BYTES,0,0);shortpkt(1,7,1);idle(40);if(goods!=g0||header_errors==0)fail("ECC failure");good(LINE_BYTES);cases++;
  g0=goods;shortpkt(0,7,0);hdr={16'd20,8'h2b};#1;beat({ecc,hdr});beat(32'h12345678);idle(40);shortpkt(1,7,0);if(goods!=g0||packet_timeouts==0)fail("truncated body accepted");good(LINE_BYTES);cases++;
  g0=goods;shortpkt(0,7,0);linepkt(8'h2b,LINE_BYTES,0,0);linepkt(8'h2b,LINE_BYTES,0,0);idle(8300);if(goods!=g0||inf||frame_timeouts==0)fail("missing FE timeout");good(LINE_BYTES);cases++;
  if(crc_errors!=3||header_errors!=1||packet_timeouts!=1||frame_timeouts!=1)fail("exact cumulative diagnostics");
  $display("INTEGRITY_DIAGNOSTICS crc=%0d header=%0d packet_timeout=%0d frame_timeout=%0d bad_frames=%0d",crc_errors,header_errors,packet_timeouts,frame_timeouts,bad_frames);
  shortpkt(0,7,0);linepkt(8'h2b,LINE_BYTES,0,0);rst_n=0;idle(4);rst_n=1;idle(4);good(LINE_BYTES);
  $display("INTEGRITY_PASS packet cases=%0d goods=%0d crc_errors=%0d header_errors=%0d packet_timeouts=%0d frame_timeouts=%0d",cases,goods,crc_errors,header_errors,packet_timeouts,frame_timeouts);$finish;
 end
 initial begin #10000000;fail("watchdog");end
endmodule
