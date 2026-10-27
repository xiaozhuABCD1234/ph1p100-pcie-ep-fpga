import pathlib
ROOT=pathlib.Path(__file__).resolve().parents[4];P=ROOT/'upstream/ph1p100-pcie-ep-fpga'
f=P/'sim/tb/tb_cam_r10f_writer.v';s=f.read_text(encoding='utf-8')
s=s.replace('module tb_cam_r10f_writer;','module tb_closedloop_writer_checker;')
end=s.index(') u_wr3 (');beg=s.rfind('cam_r10f_writer #(',0,end)
s=s[:beg]+s[beg:end].replace('cam_r10f_writer #(','cam_r10f_writer #(\n        .CLOSEDLOOP_EN(1),',1)+s[end:]
s=s.replace('.wr_frame_seq(c_seq), .wr_base(c_base), .wr_status(c_status), .wr_len(c_len),', '''.wr_frame_seq(c_seq), .wr_base(c_base), .wr_status(c_status), .wr_len(c_len),
        .cl_release(rb_release),.cl_pub_valid(rb_pub),.cl_pub_seq(rb_seq),.cl_pub_base(rb_base),.cl_pub_len(rb_len),.cl_pub_session(rb_session),.cl_good_count(rb_good),.cl_bad_count(rb_bad),''')
extra='''
    wire [1:0] rb_release;wire rb_pub;
    wire [31:0] rb_seq,rb_base,rb_len,rb_session,rb_good,rb_bad;
    wire [28:0] rb_araddr;wire [7:0] rb_arlen;wire rb_arvalid,rb_rready;
    reg rb_rvalid=0;reg [255:0] rb_rdata=0;reg rb_rlast=0;
    reg [255:0] full_ddr[0:81023];
    integer wb=0,wa=0,ww,rdaddr=0,rdleft=0,ar_count=0,rr_count=0;
    always @(posedge clk_ddr) begin
        if(c_awvalid&&c_awready) begin wa=(c_awaddr-BASE0_3)/32;wb=0;end
        if(c_wvalid&&c_wready) begin
            for(ww=0;ww<32;ww=ww+1) if(c_wstrb[ww]) full_ddr[wa+wb][8*ww+:8]<=c_wdata[8*ww+:8];
            wb=wb+1;
        end
        if(wr_rst) begin rb_rvalid<=0;rdleft=0;end
        else begin
            if(rb_arvalid) begin
                chk(rdleft==0,"CL overlapping read bursts");
                chk((rb_araddr%4096)+(rb_arlen+1)*32<=4096,"CL read crosses 4KiB");
                rdaddr=(rb_araddr-BASE0_3)/32;rdleft=rb_arlen+1;ar_count=ar_count+1;
            end
            if(rb_rvalid&&rb_rready) begin rb_rvalid<=0;rdaddr=rdaddr+1;rdleft=rdleft-1;rr_count=rr_count+1;end
            if(!rb_rvalid&&rdleft>0) begin rb_rdata<=full_ddr[rdaddr];rb_rlast<=(rdleft==1);rb_rvalid<=1;end
            if(rb.state==2 || rb.state==3) chk(u_wr3.protect0,"CL slot overwritten/released during read");
        end
    end
    ddr_closedloop_readback rb(.clk(clk_ddr),.rst(wr_rst),.pub_valid(rb_pub),.pub_seq(rb_seq),.pub_base(rb_base),.pub_len(rb_len),.pub_session(rb_session),.writer_good(rb_good),.writer_bad(rb_bad),.abort(1'b0),.release_slot(rb_release),.arid(),.araddr(rb_araddr),.arlen(rb_arlen),.arsize(),.arburst(),.arvalid(rb_arvalid),.arready(1'b1),.rid(4'd0),.rdata(rb_rdata),.rresp(2'd0),.rlast(rb_rlast),.rvalid(rb_rvalid),.rready(rb_rready));
'''
s=s.replace('    reg hdrpass_q3',extra+'\n    reg hdrpass_q3',1) if '    reg hdrpass_q3' in s else s.replace('    reg        hdrpass_q3',extra+'\n    reg        hdrpass_q3',1)
assert extra in s
s=s.replace('        // ---- 汇总 ----', '''        t1=0;
        while(rb.cl_pass_count==0 && rb.cl_fail_count==0 && t1<4000000) begin @(posedge clk_ddr);t1=t1+1;end
        repeat(10) @(posedge clk_ddr);
        chk(rb.cl_pass_count==1 && rb.cl_fail_count==0,"CL complete writer->DDR->checker CRC failed");
        chk(rb.cl_words==648192,"CL words !=648192");
        chk(rb.cl_header_crc==EXP_HDRCRC3 && rb.cl_payload_crc==EXP_PAYCRC3,"CL oracle CRC mismatch");
        chk(rb.cl_flags==15 && rb.cl_fault==0,"CL flag/error/fault mismatch");
        chk(rr_count==81024 && ar_count==633,"CL real DDR read count mismatch");
        chk(!u_wr3.protect0,"CL slot not released after drained completion");
        $display("CLOSEDLOOP_1080P words=%0d header=%08h payload=%08h flags=%08h pass=%0d fail=%0d",rb.cl_words,rb.cl_header_crc,rb.cl_payload_crc,rb.cl_flags,rb.cl_pass_count,rb.cl_fail_count);
        // ---- 汇总 ----''')
(P/'sim/tb/tb_closedloop_writer_checker.v').write_text(s,encoding='utf-8',newline='\n')
print('Integrated 1080p real writer/memory/checker TB created; baseline small-frame regressions retained')
