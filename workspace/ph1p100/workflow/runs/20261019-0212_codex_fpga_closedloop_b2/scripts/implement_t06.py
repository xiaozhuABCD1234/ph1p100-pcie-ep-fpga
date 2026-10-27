import hashlib, json, pathlib
ROOT=pathlib.Path(__file__).resolve().parents[4]
OUT=pathlib.Path(__file__).resolve().parents[1]
P=ROOT/'upstream/ph1p100-pcie-ep-fpga'
assert P.resolve().is_relative_to(ROOT.resolve())
for rel,expected in {
'rtl/ep_side/img/ep_bar_win.v':'285fc9f009bd5c2481dbc25ee1c7ddd809a70b328b12dca63c0bd59baf581717',
'rtl/ep_side/pcie_ep_engine.v':'4c9d2e35d181929393b55047e67cfe59d389afe19d06032ac3ec95c9deca9b85',
'rtl/ep_side/ph1p_pcie_ep_top.v':'006932297de30921295538a5a3c448001d254f0d617b7c487bf1a38b23f189a9',
'sim/tb/tb_ep_bar_win_debug.v':'3aa3e11b49ec57652efdc88f34c5d6e8b7a30e640cfcc2549e4b3dadc5a6355e'
}.items():
    path=P/rel
    assert path.resolve().is_relative_to(P.resolve())
    assert hashlib.sha256(path.read_bytes()).hexdigest()==expected, rel
(OUT/'ddr-integration').mkdir(exist_ok=True)
(OUT/'ddr-integration/baseline-verified.json').write_text(json.dumps({'root':str(P),'four_dirty_sha_verified':True},indent=2))

def edit(rel, changes):
    path=P/rel
    assert path.resolve().is_relative_to(P.resolve())
    text=path.read_text(encoding='utf-8')
    for old,new in changes:
        assert text.count(old)==1, (rel, old[:80], text.count(old))
        text=text.replace(old,new)
    path.write_text(text,encoding='utf-8',newline='\n')

edit('rtl/ep_side/ddr/cam_r10f_writer.v',[
('    parameter [20:0]  TMO_LIMIT',"    parameter integer CLOSEDLOOP_EN = 0, // debug-only DHI ownership; default preserves legacy\n    parameter [20:0]  TMO_LIMIT"),
('    // ---------------- AXI4 写通道 ----------------', '''    // All closedloop ports are clk_ddr-domain; no multi-bit control CDC.
    input wire [1:0] cl_release,
    output reg cl_pub_valid,
    output reg [31:0] cl_pub_seq, cl_pub_base, cl_pub_session,
    output wire [31:0] cl_pub_len,
    output reg [31:0] cl_good_count, cl_bad_count,

    // ---------------- AXI4 写通道 ----------------'''),
('    wire rel0_evt = rel0_s2 ^ rel0_s3;','    wire rel0_evt = CLOSEDLOOP_EN ? cl_release[0] : (rel0_s2 ^ rel0_s3);'),
('    wire rel1_evt = rel1_s2 ^ rel1_s3;','    wire rel1_evt = CLOSEDLOOP_EN ? cl_release[1] : (rel1_s2 ^ rel1_s3);'),
('    wire blk_locked = prot_en_s2 & (frame_idx[0] ? protect1 : protect0);','    wire protect_enabled = CLOSEDLOOP_EN || prot_en_s2;\n    wire blk_locked = protect_enabled & (frame_idx[0] ? protect1 : protect0);\n    assign cl_pub_len = DMA_BYTES32;'),
('            protect1      <= 1\'b0;','''            protect1      <= 1'b0;
            cl_pub_valid <= 1'b0;
            cl_pub_seq <= 0; cl_pub_base <= 0; cl_pub_session <= 0;
            cl_good_count <= 0; cl_bad_count <= 0;'''),
('            frame_close <= 1\'b0;','            frame_close <= 1\'b0;\n            cl_pub_valid <= 1\'b0;'),
('                            c_bad    <= c_bad + 16\'d1;','                            c_bad    <= c_bad + 16\'d1;\n                            cl_bad_count <= cl_bad_count + 1\'b1;'),
('                            if (verdict_bad) c_bad <= c_bad + 16\'d1;\n                            if (prot_en_s2 && ~verdict_bad) begin','''                            if (verdict_bad) begin
                                c_bad <= c_bad + 16'd1;
                                cl_bad_count <= cl_bad_count + 1'b1;
                            end else begin
                                cl_good_count <= cl_good_count + 1'b1;
                                if (CLOSEDLOOP_EN) begin
                                    cl_pub_valid <= 1'b1;
                                    cl_pub_seq <= f_seq;
                                    cl_pub_base <= base_r;
                                    cl_pub_session <= f_sess;
                                end
                            end
                            if (protect_enabled && ~verdict_bad) begin''')])

edit('rtl/ep_side/ddr/ddr_frame_readback_checker.v',[
('    reg          axi_err_r;', '    reg          axi_err_r;\n    reg          abort_r;'),
('    wire [31:0]  burst_first = (beats_total >= BURST_BEATS) ? BURST_BEATS : beats_total;', '''    wire [31:0] first_page_beats = (32'd4096 - {20'd0,base[11:0]}) >> 5;
    wire [31:0] first_limit = first_page_beats < BURST_BEATS ? first_page_beats : BURST_BEATS;
    wire [31:0] burst_first = beats_total < first_limit ? beats_total : first_limit;'''),
('                               (base[4:0]   != 5\'d0);', '''                               (base[4:0]   != 5'd0) || (frame_bytes[4:0] != 0) ||
                               (base >= 64'h10000000) ||
                               ({1'b0,base}+{33'd0,frame_bytes} > 65'h010000000);'''),
('    wire [31:0]  burst_nxt      = (beats_left_nxt >= BURST_BEATS) ? BURST_BEATS : beats_left_nxt;\n    wire [28:0]  addr_nxt       = addr_q + (burst_beats_q << 5);', '''    wire [28:0] addr_nxt = addr_q + (burst_beats_q << 5);
    wire [31:0] next_page_beats = (32'd4096 - {20'd0,addr_nxt[11:0]}) >> 5;
    wire [31:0] next_limit = next_page_beats < BURST_BEATS ? next_page_beats : BURST_BEATS;
    wire [31:0] burst_nxt = beats_left_nxt < next_limit ? beats_left_nxt : next_limit;'''),
('wire [7:0]   e_final = abort_now', 'wire [7:0]   e_final = (abort_now | abort_r)'),
('            // ---------------- (A) ST_PROC', '            if (abort_now) abort_r <= 1\'b1;\n            // ---------------- (A) ST_PROC'),
('                                axi_err_r   <= 1\'b0;', '                                axi_err_r   <= 1\'b0;\n                                abort_r     <= 1\'b0;'),
('rlast_done  <= m_axi_rlast | ((rbeat_cnt + 32\'d1) == burst_beats_q);','rlast_done  <= ((rbeat_cnt + 32\'d1) == burst_beats_q);'),
('if (m_axi_rresp != 2\'b00) axi_err_r <= 1\'b1;', 'if ((m_axi_rresp != 2\'b00) || (m_axi_rid != 4\'d0)) axi_err_r <= 1\'b1;'),
('(fbytes_q >= (32\'d128 + pbytes_q)) &&','(fbytes_q >= 32\'d128) && (pbytes_q <= fbytes_q - 32\'d128) &&')])
# abort_r must be reset in the sole reset block.
path=P/'rtl/ep_side/ddr/ddr_frame_readback_checker.v'
s=path.read_text(encoding='utf-8')
needle="            axi_err_r    <= 1'b0;"
if needle not in s:
    import re
    match=re.search(r"^\s+axi_err_r\s+<= 1'b0;",s,re.M)
    assert match
    needle=match.group()
s=s.replace(needle,needle+"\n            abort_r <= 1'b0;",1)
path.write_text(s,encoding='utf-8',newline='\n')
print('T06 writer ownership and checker guards applied')
