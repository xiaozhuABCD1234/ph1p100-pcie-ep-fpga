`timescale 1ns/1ps
module tb_cam_algo_oracle;
    parameter MUTATE=0;
    localparam W=16,H=6,X0=8,Y0=2,SKIP=1,NB=24,FRAMES=3;
    reg clk=0;always #2.666 clk=~clk;
    reg rst_n=0,vs=0,fr=0,ln=0,pv=0,good=0;reg [39:0] pix=0;
    reg [2:0] ready=7;
    reg [39:0] raw[0:71];reg [31:0] gy[0:71],ga[0:71],he[0:71];
    integer count[0:2],cycles=0,errors=0,f,y,x,t,b,idx,localidx;
    reg [2:0] was_stall=0;reg [35:0] saved[0:2];
    reg [31:0] value,expected;reg [3:0] side;
    cam_algo_diagnostics #(.W(W),.H(H),.X0(X0+(MUTATE?4:0)),.Y0(Y0),.SKIP_ROWS(SKIP),.PHASE(3)) dut(
        .clk(clk),.rst_n(rst_n),.cam_vsync(vs),.cam_in_frame(fr),.cam_in_line(ln),.cam_pix(pix),.cam_pix_valid(pv),.cam_good(good),.cam_abort(1'b0),.sink_ready(ready));
    task mismatch(input [8*90-1:0] msg);begin errors=errors+1;if(errors<20)$display("ADAPTER_ORACLE_MISMATCH %s time=%t",msg,$time);end endtask
    // Sample the transfer before the DUT's nonblocking updates, at the actual
    // handshake edge. Ready is driven on the opposite edge.
    always @(posedge clk) if(rst_n)begin
        cycles=cycles+1;
        for(b=0;b<3;b=b+1)begin
            case(b)0:begin value=dut.od0;side={dut.oa[0],dut.oe[0],dut.ol[0],dut.os[0]};end
                1:begin value=dut.od1;side={dut.oa[1],dut.oe[1],dut.ol[1],dut.os[1]};end
                2:begin value=dut.od2;side={dut.oa[2],dut.oe[2],dut.ol[2],dut.os[2]};end endcase
            if(was_stall[b]&&(!dut.ov[b]||{side,value}!==saved[b]))mismatch("output changed while stalled");
            was_stall[b]=dut.ov[b]&&!ready[b];saved[b]={side,value};
            if(dut.ov[b]&&ready[b])begin
                idx=count[b];localidx=idx%NB;
                case(b)0:expected=gy[idx];1:expected=ga[idx];2:expected=he[idx];endcase
                if(value!==expected)mismatch("pixel differs from independent Bayer/gray/Gaussian/previous-frame HE oracle");
                if(side!=={1'b0,(localidx==NB-1),(localidx%4==3),(localidx==0)})mismatch("sideband/ROI ordering");
                count[b]=count[b]+1;
            end
        end
    end
    always @(negedge clk)if(rst_n)begin ready[0]=(cycles%17)>1;ready[1]=(cycles%19)>1;ready[2]=(cycles%23)>1;end
    initial begin
        $readmemh("raw.hex",raw);$readmemh("gray.hex",gy);$readmemh("gauss.hex",ga);$readmemh("he.hex",he);
        count[0]=0;count[1]=0;count[2]=0;
        repeat(10)@(negedge clk);rst_n=1;repeat(20)@(negedge clk);
        for(f=0;f<FRAMES;f=f+1)begin
            @(negedge clk);vs=1;@(negedge clk);vs=0;fr=1;
            for(y=0;y<Y0+SKIP+H+2;y=y+1)begin
                @(negedge clk);ln=1;@(negedge clk);ln=0;
                for(x=0;x<X0+W+8;x=x+4)begin
                    @(negedge clk);pv=1;
                    if(y>=Y0+SKIP&&y<Y0+SKIP+H&&x>=X0&&x<X0+W)pix=raw[f*NB+(y-Y0-SKIP)*4+(x-X0)/4];else pix=40'h123456789a;
                end
                @(negedge clk);pv=0;repeat(20)@(negedge clk);
            end
            @(negedge clk);good=1;@(negedge clk);fr=0;@(negedge clk);good=0;
            t=0;while(dut.busy&&t<20000)begin @(negedge clk);t=t+1;end
            if(t==20000)mismatch("frame did not finish");repeat(1000)@(negedge clk);
        end
        if(count[0]!=72||count[1]!=72||count[2]!=72)mismatch("output group count");
        if(errors==0)$display("ADAPTER_ORACLE_PASS frames=3 beats=%0d/%0d/%0d cycles=%0d",count[0],count[1],count[2],cycles);else $display("ADAPTER_ORACLE_FAIL errors=%0d MUTATE=%0d",errors,MUTATE);
        $finish;
    end
    initial begin #10000000;$display("ADAPTER_ORACLE_FAIL watchdog");$finish;end
endmodule
