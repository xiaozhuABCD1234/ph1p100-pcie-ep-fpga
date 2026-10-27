`timescale 1ns/1ps
module tb_capture_chain #(parameter FRAME_BYTES=256,parameter ADDRESS_FAULT=0);
 localparam WORDS=FRAME_BYTES/32+1;
 reg clk=0,cap_clk=0;always #2.5 clk=~clk;always #4.5 cap_clk=~cap_clk;
 reg rst_n=0,ddr_ready=0,sof=0,pixel_valid=0,pixel_last=0;reg[7:0] pixel=0;
 wire[31:0] passed_frames,failed_frames,published_frames,protocol_errors,capture_drops;
 wire[26:0] paxi_awaddr,paxi_araddr;wire[255:0] paxi_wdata;
 wire[31:0] paxi_wstrb;wire paxi_awvalid,paxi_wvalid,paxi_wlast,paxi_arvalid,paxi_rready;
 integer cycles=0,delay_left=0,writes=0,reads=0,frame=0,j;reg pending=0;
 wire paxi_awready=ddr_ready&&cycles%3!=0,paxi_arready=ddr_ready&&cycles%5!=0,paxi_wready=ddr_ready&&cycles%7!=0;
 reg[255:0] paxi_rdata=0,pending_data=0;reg paxi_rvalid=0,paxi_rlast=1;
 reg[255:0] memory[0:WORDS*3-1];reg[2:0] touched=0;reg injected_data=0,injected_meta=0,injected_length=0;
 integer rd_word,rd_local,aliased_word,checker_reads=0,alias_hits=0,expected_check_offset=0;
 camera_ddr_capture #(.FRAME_BYTES(FRAME_BYTES),.FIFO_BITS(4)) dut(.*);
 task fail(input string msg);begin $display("CAPTURE_CHAIN_FAIL %s",msg);$finish;end endtask
 always @(posedge clk)begin
  cycles<=cycles+1;
  if(!rst_n||!ddr_ready)begin paxi_rvalid<=0;pending<=0;end
  else begin
   if(paxi_awvalid)begin
    if(!paxi_wvalid||!paxi_awready||!paxi_wready||paxi_wstrb!==0||!paxi_wlast)fail("native write");
    if(paxi_awaddr>=WORDS*24||paxi_awaddr[2:0]!=0)fail("address range");
    memory[paxi_awaddr>>3]<=paxi_wdata;writes<=writes+1;touched[paxi_awaddr/(WORDS*8)]<=1;
   end
   if(paxi_rvalid&&paxi_rready)paxi_rvalid<=0;
   if(pending)begin
    if(delay_left!=0)delay_left<=delay_left-1;
    else begin paxi_rvalid<=1;paxi_rdata<=pending_data;pending<=0;end
   end
   if(paxi_arvalid&&paxi_arready)begin
    if(pending||paxi_rvalid)fail("read overlap");
    rd_word=paxi_araddr>>3;rd_local=rd_word%WORDS;aliased_word=rd_word;
    if(ADDRESS_FAULT&&rd_local<WORDS-1)aliased_word=(rd_word/WORDS)*WORDS+(rd_local&~16);
    pending_data<=memory[aliased_word];pending<=1;delay_left<=cycles%7+45;reads<=reads+1;
    if(dut.u_check.state==2&&!dut.u_store.want_fence)begin
     if(rd_local!=expected_check_offset)fail("checker skipped/repeated address");
     expected_check_offset=(rd_local==WORDS-1)?0:rd_local+1;
     checker_reads<=checker_reads+1;
     if(ADDRESS_FAULT&&aliased_word!=rd_word && memory[aliased_word]!==memory[rd_word])alias_hits<=alias_hits+1;
    end
    if(!ADDRESS_FAULT&&passed_frames>=1&&!injected_data&&rd_local==0&&!dut.u_store.want_fence)begin pending_data<=memory[rd_word]^256'd1;injected_data<=1;end
    // Only corrupt a checker footer response, not the store's fence.
    if(!ADDRESS_FAULT&&failed_frames>=1&&!injected_meta&&rd_local==WORDS-1 && dut.u_check.state==2&&!dut.u_store.want_fence)begin
     pending_data<=memory[paxi_araddr>>3]^(256'd1<<32);injected_meta<=1;
    end
    if(!ADDRESS_FAULT&&failed_frames>=2&&!injected_length&&rd_local==WORDS-1 && dut.u_check.state==2&&!dut.u_store.want_fence)begin
     pending_data<=memory[paxi_araddr>>3]^(256'd1<<96);injected_length<=1;
    end
   end
   if(ADDRESS_FAULT)begin
    if(passed_frames!=0)fail("address alias escaped CRC");
    if(failed_frames>=1)begin
     if(alias_hits==0||checker_reads<WORDS||protocol_errors!=0)fail("address fault coverage");
     $display("CAPTURE_CHAIN_PASS alias bytes=%0d good=%0d rejected=%0d hits=%0d checker_reads=%0d",FRAME_BYTES,passed_frames,failed_frames,alias_hits,checker_reads);$finish;
    end
   end
   if(!ADDRESS_FAULT&&passed_frames>=3 && failed_frames>=3 && injected_data && injected_meta && injected_length)begin
    if(failed_frames!=3||protocol_errors!=0||touched!=3'b111)begin $display("counts good=%0d bad=%0d protocol=%0d slots=%b drops=%0d",passed_frames,failed_frames,protocol_errors,touched,capture_drops);fail("CRC/metadata/slot checks");end
    if(reads<WORDS*6)fail("full-frame traversal");
    $display("CAPTURE_CHAIN_PASS bytes=%0d good=%0d rejected=%0d writes=%0d reads=%0d slots=%b",FRAME_BYTES,passed_frames,failed_frames,writes,reads,touched);$finish;
   end
  end
 end
 initial begin
  repeat(6)@(negedge cap_clk);rst_n=1;repeat(8)@(negedge cap_clk);ddr_ready=1;
  forever begin
   frame=frame+1;@(negedge cap_clk);sof=1;@(negedge cap_clk);sof=0;
   for(j=0;j<FRAME_BYTES;j=j+1)begin @(negedge cap_clk);pixel_valid=1;pixel=(frame*13+j+(j>>8)*29+(j>>16)*101)&255;pixel_last=(j==FRAME_BYTES-1);end
   @(negedge cap_clk);pixel_valid=0;pixel_last=0;repeat(12)@(negedge cap_clk);
  end
 end
 initial begin #(FRAME_BYTES*500);$display("WATCHDOG good=%0d bad=%0d published=%0d protocol=%0d injected=%b%b%b reads=%0d drops=%0d",passed_frames,failed_frames,published_frames,protocol_errors,injected_data,injected_meta,injected_length,reads,capture_drops);fail("watchdog");end
 initial begin if(ADDRESS_FAULT&&FRAME_BYTES<=512)fail("alias requires payload beyond word 15");end
endmodule
