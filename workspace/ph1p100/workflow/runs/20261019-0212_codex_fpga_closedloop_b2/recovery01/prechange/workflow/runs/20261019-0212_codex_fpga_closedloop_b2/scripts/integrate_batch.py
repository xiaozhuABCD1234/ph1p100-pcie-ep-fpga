import pathlib,hashlib,json,re,shutil
ROOT=pathlib.Path(__file__).resolve().parents[4]; OUT=pathlib.Path(__file__).resolve().parents[1]
P=ROOT/'upstream/ph1p100-pcie-ep-fpga'; assert P.resolve().is_relative_to(ROOT.resolve())
manifest=ROOT/'workflow/runs/20261017-011744-rk-fpga-align/algo/candidate-manifest.json'
m=json.loads(manifest.read_text()); provenance=[]
for e in m['entries']:
    if e['kind']=='rtl' and not e['path'].endswith('img_algo_top_g2.v'):
        src=ROOT/e['path']; assert hashlib.sha256(src.read_bytes()).hexdigest()==e['sha256']
        dst=P/'rtl/ep_side/img/algo'/src.name
        assert dst.resolve().is_relative_to(P.resolve())
        assert not dst.exists() or dst.read_bytes()==src.read_bytes()
        shutil.copyfile(src,dst); provenance.append({'source':str(src),'destination':str(dst),'sha256':e['sha256']})
(OUT/'algo-integration').mkdir(exist_ok=True)
(OUT/'algo-integration/source-provenance.json').write_text(json.dumps({'manifest':str(manifest),'entries':provenance},indent=2))
top=P/'rtl/ep_side/ph1p_pcie_ep_top.v'; s=top.read_text(encoding='utf-8')
def replace(a,b):
    global s
    assert s.count(a)==1,(a[:80],s.count(a));s=s.replace(a,b)
replace("parameter DBG_CTRL_DEFAULT_EN = 1'b0", "parameter DBG_CTRL_DEFAULT_EN = 1'b0,\n    parameter CLOSEDLOOP_EN = 1'b0")
# Add independent read wires. Static exclusive routing has no run-time owner CDC.
pos=s.index('// ==== 图像通路')
decl='''// B01 debug-only exclusive reader and same-domain publication contract.
wire [3:0] push_arid;wire [28:0] push_araddr;wire [7:0] push_arlen;
wire [2:0] push_arsize;wire [1:0] push_arburst;wire push_arvalid,push_arready,push_rvalid,push_rready;
wire [1:0] cl_release;wire cl_pub_valid;wire [31:0] cl_pub_seq,cl_pub_base,cl_pub_len,cl_pub_session,cl_writer_good,cl_writer_bad;
wire cl_inject_abort;
'''
s=s[:pos]+decl+s[pos:]
assert s.count('cam_r10f_writer #(\n    .W')==2
s=s.replace('cam_r10f_writer #(\n    .W', 'cam_r10f_writer #(\n    .CLOSEDLOOP_EN(CLOSEDLOOP_EN),\n    .W',1)
replace('.cam_frame_abort(w_a_frame_abort),','.cam_frame_abort(w_a_frame_abort | cl_inject_abort),')
replace('    .axi_busy      (w_camw_busy       ),','''    .axi_busy      (w_camw_busy       ),
    .cl_release(cl_release),.cl_pub_valid(cl_pub_valid),.cl_pub_seq(cl_pub_seq),.cl_pub_base(cl_pub_base),
    .cl_pub_len(cl_pub_len),.cl_pub_session(cl_pub_session),.cl_good_count(cl_writer_good),.cl_bad_count(cl_writer_bad),''')
replace('.push_en       (img_push_en       ),',".push_en       (CLOSEDLOOP_EN ? 1'b0 : img_push_en),")
# Replace only the pusher's read master connection block, not DDR IP.
start=s.index(') u_ddr_frame_pusher ('); before=s[:start]; block=s[start:]
for old,new in [('w_ddr_arid','push_arid'),('w_ddr_araddr','push_araddr'),('w_ddr_arlen','push_arlen'),('w_ddr_arsize','push_arsize'),('w_ddr_arburst','push_arburst'),('w_ddr_arvalid','push_arvalid'),('w_ddr_arready','push_arready'),('w_ddr_rvalid','push_rvalid'),('w_ddr_rready','push_rready')]: block=block.replace(old,new)
s=before+block
extra='''
generate if(CLOSEDLOOP_EN) begin:g_closedloop
    assign push_arready=1'b0;assign push_rvalid=1'b0;
    ddr_closedloop_readback u_readback(
        .clk(w_ddr_dhi_clk),.rst(~w_ddrphy_rst_n),
        .pub_valid(cl_pub_valid),.pub_seq(cl_pub_seq),.pub_base(cl_pub_base),.pub_len(cl_pub_len),.pub_session(cl_pub_session),
        .writer_good(cl_writer_good),.writer_bad(cl_writer_bad),.abort(1'b0),.release_slot(cl_release),
        .arid(w_ddr_arid),.araddr(w_ddr_araddr),.arlen(w_ddr_arlen),.arsize(w_ddr_arsize),.arburst(w_ddr_arburst),
        .arvalid(w_ddr_arvalid),.arready(w_ddr_arready),.rid(w_ddr_rid),.rdata(w_ddr_rdata),.rresp(w_ddr_rresp),
        .rlast(w_ddr_rlast),.rvalid(w_ddr_rvalid),.rready(w_ddr_rready));
    cam_algo_diagnostics #(.W(CAMDDR_W),.H(CAMDDR_H),.X0(CAMDDR_X0),.Y0(CAMDDR_Y0),.SKIP_ROWS(CAMDDR_SKIP_ROWS),.PHASE(2'd3)) u_algo(
        .clk(w_a_byte_clk),.rst_n(w_a_rst_out),.cam_vsync(w_a_vsync),.cam_in_frame(w_a_in_frame),.cam_in_line(w_a_in_line),
        .cam_pix(w_a_pixel),.cam_pix_valid(w_a_pixel_valid),.cam_good(w_a_frame_good),.cam_abort(w_a_frame_abort|cl_inject_abort),.sink_ready(3'b111));
    // One deliberate internal abort on the third real source frame. No sensor,
    // I2C, link or external wire changes. It must reject RAW publication once.
    reg vs_d, injected,inject_pulse;
    (* MARK_DEBUG="true" *) reg [31:0] source_good,source_bad,source_crc,source_header,source_geometry,source_injected;
    reg [2:0] fe_delay;
    assign cl_inject_abort=inject_pulse;
    always @(posedge w_a_byte_clk or negedge w_a_rst_out) begin
        if(!w_a_rst_out) begin vs_d<=0;injected<=0;inject_pulse<=0;source_good<=0;source_bad<=0;source_crc<=0;source_header<=0;source_geometry<=0;source_injected<=0;fe_delay<=0;end
        else begin
            vs_d<=w_a_vsync;fe_delay<={fe_delay[1:0],w_a_frame_end};
            inject_pulse<=0;
            if(w_a_vsync&&!vs_d&&!injected&&(w_a_good_frm>=2)) begin injected<=1;inject_pulse<=1;source_injected<=source_injected+1'b1;end
            if(fe_delay[2]) begin source_good<=w_a_good_frm;source_bad<=w_a_bad_frm;source_crc<=w_a_crc_err;source_header<=w_a_hdr_err;source_geometry<={w_a_last_lines,w_a_last_wc};end
        end
    end
end else begin:g_original_reader
    assign cl_release=0;assign cl_inject_abort=0;
    assign w_ddr_arid=push_arid;assign w_ddr_araddr=push_araddr;assign w_ddr_arlen=push_arlen;
    assign w_ddr_arsize=push_arsize;assign w_ddr_arburst=push_arburst;assign w_ddr_arvalid=push_arvalid;
    assign push_arready=w_ddr_arready;assign push_rvalid=w_ddr_rvalid;assign w_ddr_rready=push_rready;
end endgenerate
'''
replace('\nendmodule','\n'+extra+'\nendmodule')
top.write_text(s,encoding='utf-8',newline='\n')
# New wrapper preserves the old u_top hierarchy and all pin names.
dbg=(P/'rtl/ep_side/debug/ph1p_pcie_ep_top_dbg.v').read_text(encoding='utf-8')
dbg=dbg.replace('module ph1p_pcie_ep_top_dbg (','module ph1p_pcie_ep_top_closedloop (').replace(".DBG_CTRL_DEFAULT_EN (1'b1)",".DBG_CTRL_DEFAULT_EN (1'b1),\n        .CLOSEDLOOP_EN (1'b1)")
(P/'rtl/ep_side/debug/ph1p_pcie_ep_top_closedloop.v').write_text(dbg,encoding='utf-8',newline='\n')
files=['rtl/ep_side/ddr/closedloop/ddr_closedloop_readback.v']+[str(x.relative_to(P)).replace('\\','/') for x in sorted((P/'rtl/ep_side/img/algo').glob('*.v'))]+['rtl/ep_side/debug/ph1p_pcie_ep_top_closedloop.v']
fl=P/'sim/compile_checked.f'; fl.write_text(fl.read_text(encoding='utf-8')+'\n# B01 closedloop production integration\n'+'\n'.join('../'+x for x in files)+'\n',encoding='utf-8',newline='\n')
tcl=(P/'tools/pcie_integration/td/00_all_debug.tcl').read_text(encoding='utf-8')
tcl=tcl.replace('ph1p_pcie_ep_top_dbg','ph1p_pcie_ep_top_closedloop').replace('ph1p_pcie_case_ep_dbg.sdc','ph1p_pcie_case_ep_closedloop.sdc')
tcl=tcl.replace('# ---- 约束 ----','\n'.join('add_files $PRJ_ROOT/'+x for x in files if '/debug/' not in x)+'\nadd_files $PRJ_ROOT/rtl/ep_side/ddr/ddr_frame_readback_checker.v\n# ---- 约束 ----')
tcl=tcl.replace('puts "T11_DBG_ALL_DONE"','puts "B01_CLOSEDLOOP_ALL_DONE"')
(P/'tools/pcie_integration/td/00_all_closedloop.tcl').write_text(tcl,encoding='utf-8',newline='\n')
shutil.copyfile(P/'constraints/ph1p_pcie_case_ep_dbg.sdc',P/'constraints/ph1p_pcie_case_ep_closedloop.sdc')
# Bounded runner copy: no old-run outputs, production copies as actual DUT.
runner=(ROOT/'tools/algo/run_g1.py').read_text(encoding='utf-8')
runner=runner.replace('ROOT = Path(__file__).resolve().parents[2]','ROOT = Path(__file__).resolve().parents[4]')
runner=runner.replace('IMG = ROOT / "fpga" / "csi2" / "src" / "img"','IMG = ROOT / "upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/img/algo"')
runner=runner.replace('OUTROOT = RUN / "algo" / "g1" / "msim"','OUTROOT = Path(__file__).resolve().parents[1] / "algo-integration/g1"')
runner=runner.replace('((a_px[0] == px_p[0]) && we_r)','((a_px[0] == px_p[0])  && we1)').replace('((a_px[1] == px_p[1]) && we_r)','((a_px[1] == px_p[1])  && we1)').replace('((a_px[2] == px_p[2]) && we_r)','((a_px[2] == px_p[2])  && we1)').replace('((a_px[3] == px_p[3]) && we_r)','((a_px[3] == px_p[3])  && we1)')
runner=runner.replace('timeout=timeout or spec["timeout"]','timeout=min(timeout or spec["timeout"], 300)')
(OUT/'scripts/run_algo_g1.py').write_text(runner,encoding='utf-8',newline='\n')
print('B01 actual production wiring, provenance, stage, bounded runner created')
