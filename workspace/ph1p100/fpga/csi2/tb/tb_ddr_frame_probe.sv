`timescale 1ns/1ps
module tb_ddr_frame_probe #(parameter FRAME_WORDS=8,HIGH_ADDRESS_ALIAS=0);
 reg clk=0;always #5 clk=~clk;
 reg rst_n=0,ddr_ready=0;
 wire [31:0] passed_frames,failed_words,published_frames,protocol_errors;
 wire [26:0] paxi_awaddr,paxi_araddr;wire [255:0] paxi_wdata;
 wire [31:0] paxi_wstrb;wire paxi_awvalid,paxi_wvalid,paxi_wlast,paxi_arvalid,paxi_rready;
 integer cycles=0,delay_left=0,writes=0,reads=0;reg [2:0] touched=0;
 integer write_index=0,local_offset,model_word,high_writes=0,high_reads=0,alias_hits=0;
 wire paxi_awready=ddr_ready&&cycles%3!=0;
 wire paxi_arready=ddr_ready&&cycles%5!=0;
 wire paxi_wready=ddr_ready&&cycles%7!=0;
 reg [255:0] paxi_rdata=0,pending_data=0;reg paxi_rvalid=0,paxi_rlast=1,pending=0,injected=0;
 reg [255:0] memory[0:FRAME_WORDS*3-1];
 ddr_frame_probe #(.FRAME_WORDS(FRAME_WORDS)) dut(.*);
 task fail(input string msg);begin $display("DDR_PROBE_FAIL %s",msg);$finish;end endtask
 always @(posedge clk)begin
   cycles<=cycles+1;
   if(!rst_n||!ddr_ready)begin paxi_rvalid<=0;pending<=0;write_index=0;end
   else begin
     if(paxi_awvalid)begin
       if(!paxi_wvalid||!paxi_awready||!paxi_wready||paxi_wstrb!==0||!paxi_wlast)fail("native write contract");
       if(paxi_awaddr>=FRAME_WORDS*24||paxi_awaddr[2:0]!=0)fail("write range/stride");
       local_offset=(paxi_awaddr>>3)%FRAME_WORDS;
       if(local_offset!=write_index)fail($sformatf("write offset wrapped/truncated expected=%0d actual=%0d",write_index,local_offset));
       if(local_offset>=65536)high_writes=high_writes+1;
       write_index=(write_index==FRAME_WORDS-1)?0:write_index+1;
       memory[paxi_awaddr>>3]<=paxi_wdata;writes<=writes+1;
       touched[paxi_awaddr/(FRAME_WORDS*8)]<=1;
     end
     if(paxi_rvalid&&paxi_rready)paxi_rvalid<=0;
     if(pending)begin
       if(delay_left!=0)delay_left<=delay_left-1;
       else begin paxi_rvalid<=1;paxi_rdata<=pending_data;pending<=0;end
     end
     if(paxi_arvalid&&paxi_arready)begin
       if(pending||paxi_rvalid)fail("read overlap");
       if(paxi_araddr>=FRAME_WORDS*24||paxi_araddr[2:0]!=0)fail("read range/stride");
       local_offset=(paxi_araddr>>3)%FRAME_WORDS;
       model_word=paxi_araddr>>3;
       // Deliberately clear word-offset bit16 only for ordinary payload reads.
       // Preserve the full-address fence so this tests the data checker.
       if(HIGH_ADDRESS_ALIAS&&!dut.u_store.want_fence)begin
         model_word=(model_word/FRAME_WORDS)*FRAME_WORDS+(local_offset&~65536);
         if(model_word!=(paxi_araddr>>3))alias_hits=alias_hits+1;
       end
       if(local_offset>=65536&&!dut.u_store.want_fence)high_reads=high_reads+1;
       pending_data<=memory[model_word];pending<=1;delay_left<=cycles%4+2;reads<=reads+1;
       // Corrupt an ordinary word, not the last-word fence.
       if(!HIGH_ADDRESS_ALIAS&&passed_frames>=2&&!injected&&(paxi_araddr>>3)%FRAME_WORDS==0)begin
         pending_data<=memory[paxi_araddr>>3]^256'd1;injected<=1;
       end
     end
     if(HIGH_ADDRESS_ALIAS&&failed_words!=0)begin
       if(high_reads==0||alias_hits==0||protocol_errors!=0)fail("high alias coverage");
       $display("DDR_PROBE_PASS high_alias frame_words=%0d detected=%0d high_reads=%0d alias_hits=%0d",FRAME_WORDS,failed_words,high_reads,alias_hits);$finish;
     end
     if(passed_frames>=4)begin
       if(failed_words!=1||!injected||protocol_errors!=0||touched!=3'b111)fail("checker/fault/slot coverage");
       if(writes<FRAME_WORDS*5||reads<FRAME_WORDS*5)fail("incomplete frame traversal");
       if(FRAME_WORDS>65536&&(high_writes==0||high_reads<FRAME_WORDS-65536))fail("high offset not traversed");
       $display("DDR_PROBE_PASS frame_words=%0d passed=%0d detected_corrupt_words=%0d writes=%0d reads=%0d slots=%b high_writes=%0d high_reads=%0d",FRAME_WORDS,passed_frames,failed_words,writes,reads,touched,high_writes,high_reads);$finish;
     end
   end
 end
 initial begin repeat(4)@(negedge clk);rst_n=1;repeat(5)@(negedge clk);ddr_ready=1;end
 initial begin #(30000000+FRAME_WORDS*2000);fail("watchdog: probe did not verify complete frames");end
endmodule
