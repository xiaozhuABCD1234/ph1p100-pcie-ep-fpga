`timescale 1ns/1ps
module tb_packet_audit;
reg clk=0; always #5 clk=~clk;
reg rst=0,en=1,valid=0;
reg [31:0] data=0;
reg [23:0] hdr=0;
wire [7:0] ecc;
wire [31:0] payload;
wire pv,done,waitsync,vs,inf,inl;
integer seen=0;
csi_rx_hdr_ecc e(.data(hdr),.ecc(ecc));
csi_rx_packet_handler #(.MIPI_LAN(4)) d(.I_clock(clk),.I_reset_n(rst),.I_enable(en),.I_data(data),.I_data_valid(valid),.O_packet_done(done),.O_sync_wait(waitsync),.O_payload_out(payload),.O_payload_valid(pv),.O_vsync_out(vs),.O_in_frame(inf),.O_in_line(inl));
always @(posedge clk) begin #1; if(pv) begin seen=seen+1; $display("PAYLOAD word=%0d value=%08h",seen,payload); end end
task reset_dut; begin @(negedge clk); rst=0; valid=0; repeat(3) @(negedge clk); rst=1; repeat(3) @(negedge clk); seen=0; end endtask
task send(input [31:0] v); begin @(negedge clk); data=v; valid=1; end endtask
initial begin
// WC20 is a complete RAW10 packing length: four groups of five bytes.
reset_dut(); hdr={16'd20,8'h2b}; #1;
send({ecc,hdr}); send(32'h44332211); send(32'h88776655);
send(32'hccbbaa99); send(32'h00ffeedd); send(32'h04030201);
send(32'h0000beef); @(negedge clk); valid=0; repeat(5) @(negedge clk);
$display("AUDIT_RAW10_WC20 words=%0d expected=5",seen);
if(seen!=6) $fatal(1,"Audit reproduction changed: inspect RTL and waveform");
reset_dut(); hdr={16'd4,8'h12}; #1;
send({ecc,hdr}); send(32'haabbccdd); send(32'h0000beef); @(negedge clk); valid=0; repeat(5) @(negedge clk);
$display("AUDIT_EMBEDDED_DT12 words=%0d expected_image_payload=0",seen);
if(seen!=2) $fatal(1,"Audit reproduction changed: inspect RTL and waveform");
$finish;
end
endmodule
