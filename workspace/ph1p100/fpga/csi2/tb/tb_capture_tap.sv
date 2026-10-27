`timescale 1ns/1ps
module tb_capture_tap;
  parameter READ_ONLY=0;
  reg bc=0,pclk=0,brst=0,prst=0,valid=0,line_pulse=0,frame=0,de=0,vs=0;
  reg [39:0] data=0;
  wire [23:0] rgb;
  wire ode,alive,gs,gv,gl;wire[7:0] gd;integer taps=0,lasts=0,starts=0;
  integer x,y,f,c,r,want,checks=0,seen=0;
  reg qde0=0,qde1=0;
  reg [7:0] qval0=0,qval1=0;
  cam_preview_capture #(.SW(4),.SH(4),.H_ACT(8),.V_ACT(8),.DEC_LINE(4),.DEC_CYC(1)) dut(
    .I_bc_clk(bc),.I_bc_rst_n(brst),.I_pix_data(data),.I_pix_valid(valid),
    .I_line(line_pulse),.I_frame(frame),.I_pclk(pclk),.I_pclk_rst_n(prst),
    .I_de(de),.I_vs(vs),.O_rgb(rgb),.O_de(ode),.O_cam_alive(alive),.O_gray_sof(gs),.O_gray_valid(gv),.O_gray_last(gl),.O_gray_data(gd));
  always @(posedge bc)if(brst)begin
    if(gs)starts=starts+1;
    if(gv)begin
      if(gd!==dut.r_wr_data||dut.r_we==0)$fatal(1,"CAPTURE_TAP_FAIL tap differs from registered RAM write");
      taps=taps+1;if(gl)lasts=lasts+1;
    end
  end
  always #3 bc=~bc;
  always #5 pclk=~pclk;

  task btick(input bit ln,input bit fr,input bit pv,input integer val);
    begin
      @(negedge bc); line_pulse=ln;frame=fr;valid=pv;
      data={20'b0,10'(val*4),10'(val*4)};
      @(posedge bc);#1;
    end
  endtask
  task line_data(input integer row,input integer base);
    begin
      btick(1,1,0,0);btick(0,1,0,0);
      for(c=0;c<4;c=c+1) btick(0,1,1,base+row*5+c);
      btick(0,1,0,0);btick(0,1,0,0);
    end
  endtask
  task check_memory(input integer base);
    integer col;
    begin
      for(col=0;col<4;col=col+1) begin
        if(dut.r_fb0[col] !== 8'(base+2+col) ||
           dut.r_fb1[col] !== 8'(base+22+col) ||
           dut.r_fb2[col] !== 8'(base+42+col) ||
           dut.r_fb3[col] !== 8'(base+62+col))
          $fatal(1,"CAPTURE_TAP_FAIL capture col=%0d banks=%h/%h/%h/%h base=%0d",
                 col,dut.r_fb0[col],dut.r_fb1[col],dut.r_fb2[col],dut.r_fb3[col],base);
        checks=checks+4;
      end
    end
  endtask
  task display_beat(input bit vd,input bit sv,input integer value);
    begin
      @(negedge pclk); de=vd;vs=sv;
      qde1=qde0;qde0=vd;qval1=qval0;qval0=value;
      @(posedge pclk);#1;
      if(ode!==qde1) $fatal(1,"CAPTURE_TAP_FAIL display DE got=%b want=%b",ode,qde1);
      if(qde1) begin
        if(rgb!=={qval1,qval1,qval1})
          $fatal(1,"CAPTURE_TAP_FAIL display pixel=%0d got=%h want=%h",seen,rgb,qval1);
        seen=seen+1;
      end
      checks=checks+1;
    end
  endtask

  initial begin
    btick(0,0,0,0); brst=1;
    if(!READ_ONLY) begin
      btick(0,1,0,0);
      for(r=0;r<16;r=r+1) line_data(r,64);
      check_memory(64);
      btick(0,0,0,0);btick(0,0,0,0);
      // Abort after three lines; new frame must reset decimation phase.
      btick(0,1,0,0);
      for(r=0;r<3;r=r+1) line_data(r,10);
      btick(0,0,0,0);btick(0,0,0,0);btick(0,1,0,0);
      for(r=0;r<16;r=r+1) line_data(r,96);
      check_memory(96);
    end else begin
      // Isolated read-path test only: known static RAM, no capture claim.
      for(c=0;c<4;c=c+1) begin
        dut.r_fb0[c]=98+c;dut.r_fb1[c]=118+c;
        dut.r_fb2[c]=138+c;dut.r_fb3[c]=158+c;
      end
    end
    display_beat(0,0,0);prst=1;
    display_beat(0,1,0);display_beat(0,0,0);
    for(f=0;f<2;f=f+1) begin
      display_beat(0,1,0);display_beat(0,0,0);
      for(y=0;y<8;y=y+1) begin
        for(x=0;x<8;x=x+1) display_beat(1,0,98+(y/2)*20+x/2);
        display_beat(0,0,0);display_beat(0,0,0);display_beat(0,0,0);
      end
    end
    display_beat(0,0,0);display_beat(0,0,0);
    if(seen!=128) $fatal(1,"CAPTURE_TAP_FAIL display count=%0d",seen);
    if(taps!=36||lasts!=2||starts!=3)$fatal(1,"CAPTURE_TAP_FAIL count taps=%0d lasts=%0d starts=%0d",taps,lasts,starts);
    $display("CAPTURE_TAP_PASS read_only=%0d checks=%0d display_pixels=%0d",READ_ONLY,checks,seen);
    $finish;
  end
  initial begin #100000; $fatal(1,"CAPTURE_TAP_FAIL watchdog"); end
endmodule
