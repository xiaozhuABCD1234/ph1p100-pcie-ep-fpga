`timescale 1ns/1ps
module tb_gray_pattern_probe;
  reg clk=0,rst_n=0;
  always #5 clk=~clk;
  reg[23:0] rgb=0;
  reg de=0,hs=0,vs=0;
  wire[23:0] out_rgb;
  wire out_de,out_hs,out_vs,mode;
  gray_pattern_probe #(.H_ACTIVE(16),.V_ACTIVE(8),.FRAMES_PER_MODE(3)) dut(
    .clk(clk),.rst_n(rst_n),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
    .out_rgb(out_rgb),.out_de(out_de),.out_hs(out_hs),.out_vs(out_vs),.pattern_mode(mode));

  // Check the production default480 boundary count without1080p frames.
  reg dvs=0;
  wire default_mode;
  gray_pattern_probe defaults(.clk(clk),.rst_n(rst_n),.in_rgb(24'b0),
    .in_de(1'b0),.in_hs(1'b0),.in_vs(dvs),.out_rgb(),.out_de(),
    .out_hs(),.out_vs(),.pattern_mode(default_mode));

  integer count=0,toggles=0,camera_samples=0,pattern_samples=0,changes=0;
  reg expected_mode=0,vs_prev=0;
  reg[255:0] palette=0;
  reg[23:0] last_input=0;
  reg have_input=0;
  task tick(input[23:0] value,input d,input h,input v);
    reg old_mode;
    begin
      @(negedge clk);rgb=value;de=d;hs=h;vs=v;
      old_mode=expected_mode;
      if(!rst_n)begin count=0;expected_mode=0;end
      else if(v&&!vs_prev&&!d)begin
        count=count+1;
        if(count==3)begin count=0;expected_mode=~expected_mode;toggles=toggles+1;end
      end
      @(posedge clk);#1;
      if(mode!==expected_mode)$fatal(1,"GRAY_PROBE_FAIL boundary count/toggle");
      if(!rst_n)begin
        if({out_rgb,out_de,out_hs,out_vs}!==27'b0)$fatal(1,"GRAY_PROBE_FAIL reset");
      end else begin
        if({out_de,out_hs,out_vs}!=={d,h,v})$fatal(1,"GRAY_PROBE_FAIL control alignment");
        if(!old_mode&&out_rgb!==value)$fatal(1,"GRAY_PROBE_FAIL camera copy/alignment");
        if(old_mode!=expected_mode&&(d||out_de))$fatal(1,"GRAY_PROBE_FAIL visible toggle");
        if(d)begin
          if(have_input&&last_input==value)$fatal(1,"GRAY_PROBE_FAIL dead stimulus");
          changes=changes+1;last_input=value;have_input=1;
          if(old_mode)begin
            pattern_samples=pattern_samples+1;
            if(out_rgb[23:16]!==out_rgb[15:8]||out_rgb[15:8]!==out_rgb[7:0])
              $fatal(1,"GRAY_PROBE_FAIL pattern not gray");
            if(^out_rgb===1'bx)$fatal(1,"GRAY_PROBE_FAIL unknown pattern");
            palette[out_rgb[7:0]]=1;
          end else camera_samples=camera_samples+1;
        end
      end
      vs_prev=rst_n?v:0;
    end
  endtask
  task frame(input integer n);
    integer r,x;
    reg[7:0] a;
    begin
      // Extended VS tests edge counting, not VS-level counting.
      for(r=0;r<3;r=r+1)
        for(x=0;x<17;x=x+1)tick(0,0,x!=0,r==0);
      for(r=0;r<8;r=r+1)begin
        for(x=0;x<16;x=x+1)begin
          a=n*31+r*16+x;
          tick({a,~a,a^8'h69},1,1,0);
        end
        tick(0,0,0,0);
      end
    end
  endtask
  integer n,levels;
  initial begin
    tick(0,0,0,0);tick(0,0,0,0);
    @(negedge clk);rst_n=1;
    for(n=0;n<12;n=n+1)frame(n);
    if(toggles!=4||expected_mode!=0)$fatal(1,"GRAY_PROBE_FAIL two complete mode cycles");
    // Invalid active-video VS must not switch mode or count a boundary.
    tick(24'h123456,1,1,1);tick(24'h234567,1,1,0);
    if(toggles!=4||count!=0)$fatal(1,"GRAY_PROBE_FAIL active VS counted");
    for(n=12;n<15;n=n+1)frame(n);
    if(!mode)$fatal(1,"GRAY_PROBE_FAIL reset precondition");
    @(negedge clk);rst_n=0;
    tick(24'hff0000,1,1,1);tick(0,0,0,0);
    @(negedge clk);rst_n=1;
    frame(16);
    if(mode||count!=1)$fatal(1,"GRAY_PROBE_FAIL reset recovery");
    levels=0;for(n=0;n<256;n=n+1)if(palette[n])levels=levels+1;
    if(levels<8||camera_samples<256||pattern_samples<256||changes!=camera_samples+pattern_samples)
      $fatal(1,"GRAY_PROBE_FAIL pattern variety or stimulus coverage");
    // Reset default instance, then exercise exactly480 edges twice.
    @(negedge clk);rst_n=0;dvs=0;
    repeat(2)@(negedge clk);
    rst_n=1;
    for(n=1;n<=960;n=n+1)begin
      @(negedge clk);dvs=1;
      @(posedge clk);#1;
      if(default_mode!==((n/480)%2))$fatal(1,"GRAY_PROBE_FAIL production480 boundary");
      @(negedge clk);dvs=0;
      @(posedge clk);#1;
    end
    $display("GRAY_PROBE_PASS camera=%0d pattern=%0d levels=%0d toggles=%0d default_edges=960",camera_samples,pattern_samples,levels,toggles);
    $finish;
  end
  initial begin #100000;$fatal(1,"GRAY_PROBE_FAIL timeout");end
endmodule

`ifdef BASELINE_PASS_THROUGH
// Existing output has no pattern selection. Negative control for missing behavior.
module gray_pattern_probe #(parameter H_ACTIVE=1920,V_ACTIVE=1080,FRAMES_PER_MODE=480)(
  input clk,rst_n,input[23:0] in_rgb,input in_de,in_hs,in_vs,
  output reg[23:0] out_rgb,output reg out_de,out_hs,out_vs,output wire pattern_mode);
  assign pattern_mode=0;
  always @(posedge clk)begin
    if(!rst_n)begin out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;end
    else begin out_rgb<=in_rgb;out_de<=in_de;out_hs<=in_hs;out_vs<=in_vs;end
  end
endmodule
`endif
