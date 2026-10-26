`timescale 1ns/1ps
module tb_closedloop_control;
    reg clk=0;always #5 clk=~clk;
    reg rst=1,pub=0,abort=0;
    reg [31:0] seq=0,base=32'h100000,len=4096,session=1;
    wire [1:0] release_slot;
    wire [28:0] araddr;wire [7:0] arlen;wire arvalid,rready;
    reg arready=1,rvalid=0,rlast=0;reg [255:0] rdata=0;
    reg [3:0] rid=0;reg [1:0] rresp=0;
    reg stall_r=0;integer mode=0;
    reg [255:0] memory[0:127];
    integer rdidx=0,rdleft=0,ars=0,rs=0,releases=0,errors=0,t,i,j,cases=0;
    reg [1:0] held=0;
    reg held_ar=0;reg [28:0] saved_addr;reg [7:0] saved_len;
    ddr_closedloop_readback #(.BASE0(32'h100000),.BASE1(32'h102000),.TIMEOUT_CYCLES(32'd32)) dut(
        .clk(clk),.rst(rst),.pub_valid(pub),.pub_seq(seq),.pub_base(base),.pub_len(len),.pub_session(session),
        .writer_good(32'd3),.writer_bad(32'd1),.abort(abort),.release_slot(release_slot),
        .arid(),.araddr(araddr),.arlen(arlen),.arsize(),.arburst(),.arvalid(arvalid),.arready(arready),
        .rid(rid),.rdata(rdata),.rresp(rresp),.rlast(rlast),.rvalid(rvalid),.rready(rready));
    task chk(input c,input [8*100-1:0] msg);begin if(!c)begin errors=errors+1;if(errors<25)$display("CONTROL_MISMATCH %s time=%t state=%0d pending=%b outstanding=%0d",msg,$time,dut.state,dut.pending,dut.outstanding);end end endtask
    function [31:0] crcbyte(input [31:0] c,input [7:0] b);reg [31:0] v;integer k;begin v=c^b;for(k=0;k<8;k=k+1)v=(v>>1)^((v&1)?32'hedb88320:0);crcbyte=v;end endfunction
    reg [31:0] pc,hc;
    initial begin
        for(i=0;i<128;i=i+1)memory[i]=0;
        memory[0][31:0]=32'h46303152;
        memory[0][63:32]=1;memory[0][95:64]=128;
        memory[1][159:128]=40;
        pc=32'hffffffff;
        for(i=0;i<40;i=i+1)begin memory[(128+i)/32][8*((128+i)%32)+:8]=i;pc=crcbyte(pc,i[7:0]);end
        memory[2][159:128]=~pc;memory[2][191:160]=~pc;
        hc=32'hffffffff;for(i=0;i<128;i=i+1)hc=crcbyte(hc,memory[i/32][8*(i%32)+:8]);
        memory[2][223:192]=~hc;
    end
    always @(posedge clk) begin
        if(rst)begin rvalid<=0;rdleft=0;held_ar<=0;held<=0;end
        else begin
            if(held_ar)begin chk(arvalid,"ARVALID withdrawn before handshake");chk(araddr==saved_addr&&arlen==saved_len,"stalled AR payload changed");end
            held_ar<=arvalid&&!arready;if(arvalid&&!arready)begin saved_addr<=araddr;saved_len<=arlen;end
            if(arvalid&&arready)begin
                chk(rdleft==0,"overlapping burst after previous response");
                chk((araddr%4096)+(arlen+1)*32<=4096,"4KiB boundary");
                rdidx=(araddr-(araddr >= 32'h102000 ? 32'h102000 : 32'h100000))/32;rdleft=arlen+1;ars=ars+1;
            end
            if(rvalid&&rready)begin rvalid<=0;rdidx=rdidx+1;rdleft=rdleft-1;rs=rs+1;end
            if(!rvalid&&rdleft>0&&!stall_r)begin
                rdata<=memory[rdidx];rvalid<=1;rid<=mode==4?4'd3:0;rresp<=mode==5?2'd2:0;
                rlast<=mode==6?(rdleft==2):mode==7?1'b0:(rdleft==1);
                if(mode==1&&rdidx==0)rdata[0]<=~memory[0][0];
                if(mode==2&&rdidx==0)rdata[160]<=~memory[0][160];
                if(mode==3&&rdidx==4)rdata[32]<=~memory[4][32];
                if(mode==8&&rdidx==1)rdata[159:128]<=0;
            end
            if(pub)held[base == 32'h102000 ? 1 : 0]<=1;
            if(release_slot!=0)begin
                chk(rdleft==0&&!arvalid,"release before old responses drained");
                chk((release_slot&held)==release_slot,"release unowned slot");
                held<=held&~release_slot;releases=releases+1;
            end
        end
    end
    task publish(input integer slot,input integer n);begin
        @(negedge clk);base=slot?32'h102000:32'h100000;seq=n;pub=1;
        @(negedge clk);pub=0;
    end endtask
    task finish_result(input integer expected,input integer prior);begin
        t=0;while(releases==prior&&t<20000)begin @(negedge clk);t=t+1;end
        chk(releases>prior,"completion/release timeout");
        if(dut.cl_flags[15:8]!=expected)$display("CONTROL_ERROR_DETAIL case=%0d mode=%0d expected=%0d actual=%0d",cases,mode,expected,dut.cl_flags[15:8]);
        chk(dut.cl_flags[15:8]==expected,"wrong completion error");
        if(expected==0)begin chk(dut.cl_flags[3:0]==15&&dut.cl_words==1024,"good frame CRC/length/word count");chk(dut.cl_payload_crc==~pc&&dut.cl_header_crc==~hc,"independent CRC mismatch");end
        cases=cases+1;
    end endtask
    task run_case(input integer m,input integer expected);integer before;begin mode=m;before=releases;publish(0,cases+1);finish_result(expected,before);mode=0;repeat(4)@(negedge clk);end endtask
    task reset_bus;begin @(negedge clk);rst=1;pub=0;abort=0;arready=1;stall_r=0;mode=0;repeat(4)@(negedge clk);rst=0;repeat(4)@(negedge clk);end endtask
    integer before,pass_before;
    initial begin
        reset_bus();run_case(0,0);run_case(1,1);run_case(2,2);run_case(3,3);run_case(4,5);run_case(5,5);run_case(6,5);run_case(7,5);run_case(8,4);run_case(0,0);
        before=releases;pass_before=dut.cl_pass_count;publish(0,100);publish(1,101);
        t=0;while(releases<before+2&&t<30000)begin @(negedge clk);t=t+1;end
        chk(releases==before+2&&dut.cl_pass_count==pass_before+2,"two owned slots queued incorrectly");chk(dut.cl_seq==101,"queued metadata identity");cases=cases+1;
        // Abort while AR is stalled: request must remain stable, then drain.
        before=releases;arready=0;publish(0,200);wait(arvalid);repeat(3)@(negedge clk);abort=1;@(negedge clk);abort=0;
        repeat(6)@(negedge clk);chk(arvalid&&held!=0&&releases==before,"abort released/cancelled stalled AR");arready=1;finish_result(7,before);run_case(0,0);
        // Accepted burst pauses until checker timeout, then old responses drain.
        before=releases;stall_r=1;publish(0,300);wait(dut.c_busy);wait(dut.c_done);stall_r=0;finish_result(6,before);run_case(0,0);
        // Abort after responses began, then new session only after old drain.
        before=releases;publish(0,400);wait(dut.c_busy);wait(dut.u_checker.wcnt>8);@(negedge clk);abort=1;@(negedge clk);abort=0;finish_result(7,before);session=2;run_case(0,0);chk(dut.cl_session==2,"old session leaked");
        // No response: bounded fail-closed lock retains ownership until bus reset.
        before=releases;stall_r=1;publish(0,500);repeat(180)@(negedge clk);chk(dut.state==4&&held!=0&&releases==before,"missing response did not retain slot/lock");cases=cases+1;
        reset_bus();session=3;run_case(0,0);chk(dut.cl_session==3,"reset isolation");
        // Bus reset during an active transfer flushes the model and DUT together.
        publish(0,600);wait(dut.outstanding!=0);reset_bus();session=4;run_case(0,0);chk(dut.cl_session==4,"reset active transaction isolation");
        if(errors==0)$display("CONTROL_PASS cases=%0d ar=%0d response_beats=%0d releases=%0d",cases,ars,rs,releases);else $display("CONTROL_FAIL errors=%0d",errors);
        $finish;
    end
    initial begin #10000000;$display("CONTROL_FAIL watchdog");$finish;end
endmodule
