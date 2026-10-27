`timescale 1ns/1ps
module tb_frame_good_publish_cancel;
  reg clk=0,rst_n=0;
  reg sof,last_roi_sample,suffix_done,crc_ok,fe_ok,abort_in,resof;
  wire frame_good,frame_abort,commit,cancel,published,busy;
  frame_good_publish_cancel dut(.clk(clk),.rst_n(rst_n),.sof(sof),.last_roi_sample(last_roi_sample),.suffix_done(suffix_done),.crc_ok(crc_ok),.fe_ok(fe_ok),.abort_in(abort_in),.resof(resof),.frame_good(frame_good),.frame_abort(frame_abort),.commit(commit),.cancel(cancel),.published(published),.busy(busy));
  always #5 clk=~clk;
  integer errors=0;
  // no task helper
  initial begin
    rst_n=0; sof=0;last_roi_sample=0;suffix_done=0;crc_ok=0;fe_ok=0;abort_in=0;resof=0;
    #20; rst_n=1;
    // Scenario A: good frame publishes after suffix with crc+fe
    #10; sof=1; #10; sof=0;
    #10; last_roi_sample=1; #10; last_roi_sample=0;
    #10; crc_ok=1; fe_ok=1; #10; crc_ok=0; fe_ok=0;
    #10; suffix_done=1; #10; suffix_done=0;
    if(!(frame_good && commit && published)) begin $display("SCN A FAIL good/commit/published"); errors=errors+1; end
    // Scenario B: abort same cycle as suffix wins over commit
    #20; sof=1; #10; sof=0;
    #10; last_roi_sample=1; #10; last_roi_sample=0;
    #10; crc_ok=1; fe_ok=1; #10; crc_ok=0; fe_ok=0;
    // inject abort with suffix same cycle
    abort_in=1; suffix_done=1; #10; abort_in=0; suffix_done=0;
    if(frame_good || commit || published) begin $display("SCN B FAIL commit despite abort"); errors=errors+1; end
    if(!(frame_abort && cancel)) begin $display("SCN B FAIL missing abort/cancel"); errors=errors+1; end
    // Scenario C: missing crc => abort
    #20; sof=1; #10; sof=0;
    #10; last_roi_sample=1; #10; last_roi_sample=0;
    #10; fe_ok=1; #10; fe_ok=0;
    #10; suffix_done=1; #10; suffix_done=0;
    if(!(frame_abort && cancel) || frame_good) begin $display("SCN C FAIL expected abort"); errors=errors+1; end
    if(errors==0) $display("TB_FRAME_GOOD_PUBLISH_CANCEL PASS");
    else $display("TB_FRAME_GOOD_PUBLISH_CANCEL FAIL errors=%0d", errors);
    $finish;
  end
endmodule