`timescale 1ns/1ps
module tb_cam_algo_adapter;
    parameter BIG=0;
    localparam W=BIG?1920:8,H=BIG?1080:4,X0=8,Y0=2,SKIP=1,NP=W*H/4;
    reg clk=0;always #2.666 clk=~clk;
    reg rst_n=0,vs=0,fr=0,ln=0,pv=0,good=0,ab=0;
    reg [39:0] pix=0;
    reg [2:0] ready=7;
    integer errors=0,frames=0,all3=0,i,j,k,t,base0,base1,base2;
    reg fe_seen=0;
    cam_algo_diagnostics #(.W(W),.H(H),.X0(X0),.Y0(Y0),.SKIP_ROWS(SKIP),.FIFO_AW(BIG?10:4),.PHASE(3)) dut(
        .clk(clk),.rst_n(rst_n),.cam_vsync(vs),.cam_in_frame(fr),.cam_in_line(ln),.cam_pix(pix),.cam_pix_valid(pv),.cam_good(good),.cam_abort(ab),.sink_ready(ready));
    task chk(input c,input [8*96-1:0] msg);begin if(!c)begin errors=errors+1;if(errors<20)$display("ADAPTER_MISMATCH %s @%t",msg,$time);end end endtask
    always @(negedge clk) if(rst_n) begin
        if(dut.ov[0]&&ready[0]) chk(dut.od0==32'h80808080,"gray independent constant oracle");
        if(dut.ov[1]&&ready[1]) chk(dut.od1==32'h80808080,"Gaussian independent constant oracle");
        if(dut.ov[2]&&ready[2]) chk(dut.od2==32'h80808080,"HE constant oracle");
        if(|(dut.oe & dut.ov & ready)) chk(fe_seen,"algorithm EOF before checked source verdict");
        if(dut.ov==7 && ready==7) all3=all3+1;
    end
    task send_frame(input bad,input integer gap);
        integer y,x;
        begin
            @(negedge clk);vs=1;fe_seen=0;
            @(negedge clk);vs=0;fr=1;
            // Real sensor FE follows source rows after the ROI has ended.
            for(y=0;y<Y0+SKIP+H+2;y=y+1) begin
                @(negedge clk);ln=1;
                @(negedge clk);ln=0;
                for(x=0;x<X0+W+8;x=x+4) begin
                    @(negedge clk);pv=1;pix=(x<X0||x>=X0+W||y<Y0+SKIP||y>=Y0+SKIP+H)?40'd0:40'h8020080200;
                end
                @(negedge clk);pv=0;
                repeat(gap) @(negedge clk);
            end
            @(negedge clk);good=!bad;ab=bad;
            @(negedge clk);fr=0;fe_seen=1;
            @(negedge clk);good=0;ab=0;
        end
    endtask
    task wait_done;
        begin t=0;while(dut.busy&&t<100000)begin @(negedge clk);t=t+1;end chk(!dut.busy,"adapter failed to finish/abort");repeat(10)@(negedge clk);end
    endtask
    initial begin
        repeat(10)@(negedge clk);rst_n=1;repeat(20)@(negedge clk);
        send_frame(0,BIG?32:20);wait_done();
        chk(dut.complete0==1&&dut.complete1==1&&dut.complete2==1,"first complete count");
        chk(dut.beats0==NP&&dut.beats1==NP&&dut.beats2==NP,"ROI group count");
        send_frame(0,BIG?32:20);wait_done();
        chk(dut.complete0==2&&dut.complete1==2&&dut.complete2==2,"two-frame service");
        if(!BIG) begin
            send_frame(1,20);wait_done();
            chk(dut.complete0==2&&dut.complete1==2&&dut.complete2==2,"bad FE published partial frame");
            chk(dut.reject0>0&&dut.reject1>0&&dut.reject2>0,"bad frame did not abort three branches");
            send_frame(0,20);wait_done();
            chk(dut.complete0==3&&dut.complete1==3&&dut.complete2==3,"good recovery after bad FE");
            ready=0;send_frame(0,0);send_frame(0,0);
            chk(dut.rejected>0,"busy frame not rejected");
            ready=7;wait_done();
        end
        chk(all3>0,"no hardware parallel output");
        if(errors==0)$display("ALGO_ADAPTER_PASS BIG=%0d groups=%0d all3=%0d complete=%0d/%0d/%0d rejected=%0d overflow=%0d",BIG,NP,all3,dut.complete0,dut.complete1,dut.complete2,dut.rejected,dut.overflow);
        else $display("ALGO_ADAPTER_FAIL errors=%0d",errors);
        $finish;
    end
    initial begin #100000000;$display("ALGO_ADAPTER_FAIL watchdog");$finish;end
endmodule
