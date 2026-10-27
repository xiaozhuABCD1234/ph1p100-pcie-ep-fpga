`timescale 1ns/1ps
module tb_closedloop_raw_algo;
    reg cam=0,ddr=0,fb=0;always #2.666 cam=~cam;always #5 ddr=~ddr;always #8 fb=~fb;
    reg rst=1,rst_n=0,vs=0,fr=0,ln=0,pv=0,good=0,ab=0;
    reg [39:0] pix=40'h8020080200;reg [2:0] sink_ready=0;reg read_stall=1;
    wire [31:0] seq,base,status,len,pseq,pbase,plen,psession,wgood,wbad;
    wire pub;wire [1:0] release_slot;
    wire [28:0] awaddr,araddr;wire [7:0] awlen,arlen;wire awvalid,wvalid,wlast,bready,arvalid,rready;
    wire [255:0] wdata;wire [31:0] wstrb;
    reg bvalid=0;reg [7:0] write_left=0;integer write_index=0,read_index=0,read_left=0,write_addresses=0;
    reg rvalid=0,rlast=0;reg [255:0] rdata=0;reg [255:0] memory[0:255];
    integer errors=0,t,n,y,x,failed_before,seq_before,complete_before;
    cam_r10f_writer #(.W(64),.H(16),.X0(0),.Y0(0),.SKIP_ROWS(0),.BASE0(32'h100000),.BASE1(32'h102000),.CLOSEDLOOP_EN(1)) writer(
        .cam_clk(cam),.cam_rst_n(rst_n),.cam_vsync(vs),.cam_in_frame(fr),.cam_in_line(ln),.cam_pix(pix),.cam_pix_valid(pv),.cam_frame_good(good),.cam_frame_abort(ab),
        .prot_en(1'b0),.rel_tgl0(1'b0),.rel_tgl1(1'b0),.clk_fb(fb),.rst_fb(rst),.session_id(32'h12345678),.wr_frame_seq(seq),.wr_base(base),.wr_status(status),.wr_len(len),
        .dbg_lines_per_frame(),.dbg_max_grp_per_line(),.dbg_anomaly(),.dbg_drop(),.clk_ddr(ddr),.rst_ddr(rst),.ddr_cal_done(1'b1),.arm(1'b1),.axi_busy(),
        .cl_release(release_slot),.cl_pub_valid(pub),.cl_pub_seq(pseq),.cl_pub_base(pbase),.cl_pub_len(plen),.cl_pub_session(psession),.cl_good_count(wgood),.cl_bad_count(wbad),
        .m_axi_awaddr(awaddr),.m_axi_awlen(awlen),.m_axi_awsize(),.m_axi_awburst(),.m_axi_awvalid(awvalid),.m_axi_awready(1'b1),.m_axi_wdata(wdata),.m_axi_wstrb(wstrb),.m_axi_wlast(wlast),.m_axi_wvalid(wvalid),.m_axi_wready(1'b1),.m_axi_bresp(2'd0),.m_axi_bvalid(bvalid),.m_axi_bready(bready));
    ddr_closedloop_readback #(.BASE0(32'h100000),.BASE1(32'h102000),.TIMEOUT_CYCLES(32'd1000000)) reader(
        .clk(ddr),.rst(rst),.pub_valid(pub),.pub_seq(pseq),.pub_base(pbase),.pub_len(plen),.pub_session(psession),.writer_good(wgood),.writer_bad(wbad),.abort(1'b0),.release_slot(release_slot),
        .arid(),.araddr(araddr),.arlen(arlen),.arsize(),.arburst(),.arvalid(arvalid),.arready(1'b1),.rid(4'd0),.rdata(rdata),.rresp(2'd0),.rlast(rlast),.rvalid(rvalid),.rready(rready));
    cam_algo_diagnostics #(.W(64),.H(16),.X0(0),.Y0(0),.SKIP_ROWS(0),.FIFO_AW(4),.PHASE(0)) algo(
        .clk(cam),.rst_n(rst_n),.cam_vsync(vs),.cam_in_frame(fr),.cam_in_line(ln),.cam_pix(pix),.cam_pix_valid(pv),.cam_good(good),.cam_abort(ab),.sink_ready(sink_ready));
    task chk(input c,input [8*100-1:0] msg);begin if(!c)begin errors=errors+1;if(errors<25)$display("RAW_ALGO_MISMATCH %s time=%t",msg,$time);end end endtask
    always @(posedge ddr) begin
        if(rst)begin bvalid<=0;rvalid<=0;write_left<=0;read_left=0;end
        else begin
            if(awvalid)begin
                if(awaddr>=32'h102000)begin write_index=128+(awaddr-32'h102000)/32;chk(!writer.protect1,"overwrite of held slot1");end
                else begin write_index=(awaddr-32'h100000)/32;chk(!writer.protect0,"overwrite of held slot0");end
                write_left<=awlen+1'b1;write_addresses=write_addresses+1;
            end
            if(wvalid)begin
                for(n=0;n<32;n=n+1)if(wstrb[n])memory[write_index][8*n+:8]<=wdata[8*n+:8];
                write_index=write_index+1;write_left<=write_left-1'b1;if(wlast)bvalid<=1;
            end
            if(bvalid&&bready)bvalid<=0;
            if(arvalid)begin read_index=araddr>=32'h102000 ? 128+(araddr-32'h102000)/32 : (araddr-32'h100000)/32;read_left=arlen+1;end
            if(rvalid&&rready)begin rvalid<=0;read_index=read_index+1;read_left=read_left-1;end
            if(!rvalid&&read_left>0&&!read_stall)begin rdata<=memory[read_index];rlast<=read_left==1;rvalid<=1;end
        end
    end
    task frame(input bad);
        integer yy,xx;begin
            @(negedge cam);vs=1;@(negedge cam);vs=0;fr=1;
            // Mirrors the top's delayed one-shot internal abort, while CSI good
            // remains true. No line/data fault is injected into the source.
            if(bad)begin @(negedge cam);ab=1;@(negedge cam);ab=0;end
            for(yy=0;yy<16;yy=yy+1)begin
                @(negedge cam);ln=1;@(negedge cam);ln=0;
                for(xx=0;xx<16;xx=xx+1)begin @(negedge cam);pv=1;@(negedge cam);pv=0;end
                repeat(100)@(negedge cam);
            end
            @(negedge cam);good=1;@(negedge cam);fr=0;@(negedge cam);good=0;
        end
    endtask
    task writer_idle;begin t=0;while(writer.s_state!=0&&t<30000)begin @(negedge ddr);t=t+1;end repeat(50)@(negedge ddr);chk(t<30000,"writer idle timeout");end endtask
    task settle(input integer passes);begin t=0;while((reader.cl_pass_count<passes||algo.busy)&&t<60000)begin @(negedge ddr);t=t+1;end repeat(20)@(negedge cam);chk(reader.cl_pass_count==passes&&reader.cl_fail_count==0,"readback recovery count/CRC");chk(!algo.busy,"algorithm abort/recovery did not finish");end endtask
    function [31:0] crcbyte(input [31:0] c,input [7:0] b);reg [31:0] v;integer k;begin v=c^b;for(k=0;k<8;k=k+1)v=(v>>1)^((v&1)?32'hedb88320:0);crcbyte=v;end endfunction
    reg [31:0] expected;
    initial begin
        expected=32'hffffffff;for(x=0;x<1024;x=x+1)expected=crcbyte(expected,8'h80);expected=~expected;
        repeat(10)@(negedge cam);rst=0;rst_n=1;repeat(40)@(negedge cam);
        frame(0);writer_idle();chk(seq==1&&writer.protect0,"first frame not published/held");
        chk(algo.overflow>0,"algorithm FIFO overflow was not exercised");chk(algo.complete0==0&&algo.complete1==0&&algo.complete2==0,"overflow published a partial algorithm frame");
        frame(0);writer_idle();chk(seq==2&&writer.protect1,"second slot not published/held");
        seq_before=seq;frame(0);writer_idle();chk(seq==seq_before,"held buffer was overwritten/published");chk(writer.protect0&&writer.protect1,"reader hold disappeared under pressure");
        sink_ready=7;read_stall=0;settle(2);chk(!writer.protect0&&!writer.protect1,"read completion did not release both A slots");
        frame(0);writer_idle();settle(3);chk(algo.complete0==1&&algo.complete1==1&&algo.complete2==1,"algorithm recovery after overflow");
        chk(algo.crc0==expected&&algo.crc1==expected&&algo.crc2==expected,"independent output CRC after recovery");
        failed_before=wbad;seq_before=seq;complete_before=algo.complete0;
        frame(1);writer_idle();repeat(1000)@(negedge cam);
        chk(seq==seq_before&&wbad>failed_before,"internal abort RAW rejection");chk(algo.complete0==complete_before,"internal abort algorithm published");
        frame(0);writer_idle();settle(4);chk(seq==seq_before+1,"good RAW recovery after injected abort");chk(algo.complete0==2&&algo.complete1==2&&algo.complete2==2,"algorithm recovery after internal abort");
        chk(reader.cl_recovery_count==2,"post-rejection full-readback recovery counter");
        chk(reader.cl_flags[31],"completed result snapshot valid bit");
        if(errors==0)$display("RAW_ALGO_PASS raw_good=%0d raw_bad=%0d read_pass=%0d algo_complete=%0d/%0d/%0d overflow=%0d rejected=%0d",wgood,wbad,reader.cl_pass_count,algo.complete0,algo.complete1,algo.complete2,algo.overflow,algo.rejected);else $display("RAW_ALGO_FAIL errors=%0d",errors);
        $finish;
    end
    initial begin #20000000;$display("RAW_ALGO_FAIL watchdog");$finish;end
endmodule
