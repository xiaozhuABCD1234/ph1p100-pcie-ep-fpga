"""Create the T08 isolated candidate from the immutable planning snapshot. No deletes."""
from pathlib import Path
import difflib, hashlib, json, shutil

HERE = Path(__file__).resolve().parent
RUN = HERE.parent
SRC = RUN / 'inputs' / 'production-raw'
DST = HERE / 'candidate'
assert HERE.name == 'T08.sync-production-sim'
for p in (HERE, RUN, RUN.parent):
    assert not (p.stat().st_file_attributes & 1024), p
m = json.loads((RUN / 'planning-input-manifest.json').read_text(encoding='utf-8'))
for f in m['files']:
    p = Path(f['frozen'])
    if p.is_relative_to(SRC):
        assert hashlib.sha256(p.read_bytes()).hexdigest() == f['sha256'], p
        out = DST / p.relative_to(SRC)
        out.parent.mkdir(parents=True, exist_ok=True)
        assert not out.exists(), out
        shutil.copyfile(p, out)

def edit(name, fn):
    p = DST / name
    before = p.read_text(encoding='utf-8')
    after = fn(before)
    assert after != before, name
    p.write_text(after, encoding='utf-8', newline='\n')
    diff = HERE / 'diffs' / (Path(name).name + '.diff')
    diff.parent.mkdir(exist_ok=True)
    diff.write_text(''.join(difflib.unified_diff(before.splitlines(True), after.splitlines(True),
        fromfile='inputs/production-raw/'+name, tofile='candidate/'+name)), encoding='utf-8')

def cfg(s):
    s = s.replace("parameter\t CLK_DIV  = 16'd999", "parameter SYNC_ENABLE = 1'b0,\nparameter\t CLK_DIV  = 16'd999")
    s = s.replace('output wire             O_dbg_busy\n', '''output wire             O_dbg_busy,
input wire I_sync_req,
input wire [15:0] I_sync_addr,
input wire [7:0] I_sync_data,
output wire O_sync_ready, O_sync_rsp_valid, O_sync_rsp_ok
''')
    start = s.index('localparam CAM_ID')
    s = s[:start] + '''generate if (SYNC_ENABLE) begin : g_sync
 sync_i2c_config #(.CLK_DIV(CLK_DIV)) transport(
 .clk(I_clk),.rst_n(I_rst_n),.cam_mode(I_cam_mode),
 .scl(O_cam_scl),.sda(IO_cam_sda),.cfg_done(O_cfg_done),
 .bus_error(O_bus_error),.dbg_idx(O_dbg_idx),.dbg_busy(O_dbg_busy),
 .req_valid(I_sync_req),.req_addr(I_sync_addr),.req_data(I_sync_data),
 .req_ready(O_sync_ready),.rsp_valid(O_sync_rsp_valid),.rsp_ok(O_sync_rsp_ok));
 always @* O_ae_cfg_done = 1'b1;
end else begin : g_legacy
 assign O_sync_ready=1'b0;
 assign O_sync_rsp_valid=1'b0;
 assign O_sync_rsp_ok=1'b0;
''' + s[start:]
    return s.replace('\nendmodule', '\nend endgenerate\nendmodule')
edit('rtl/ep_side/cam/ui_cfg_imx415.v', cfg)

def top(s):
    s = s.replace("parameter CLOSEDLOOP_EN = 1'b0", '''parameter CLOSEDLOOP_EN = 1'b0,
    parameter SYNC_ENABLE = 1'b0,
    parameter integer SYNC_WAIT_CYCLES=1200000, SYNC_FRAME_TIMEOUT=5000000,
    parameter integer SYNC_PAIR_WINDOW=50000, SYNC_I2C_TIMEOUT=5000000,
    parameter integer CAM_I2C_DIV=624, CAM_POWER_CYCLES=8388607,
    parameter integer CAM_CSI_RELEASE_CYCLES=1000,
    parameter integer CAMDDR_W=1920, CAMDDR_H=1080,
    parameter [15:0] CAMDDR_X0=960, CAMDDR_Y0=540, CAMDDR_SKIP_ROWS=37''')
    s = s.replace('    // serdes high speed pin\n', '''    input wire sync_start, sync_abort,
`ifdef MIPI_PHY_SIM_STUB
    input wire sim_clk_a, sim_clk_b,
    input wire sim_valid_a, sim_valid_b, sim_done_a, sim_done_b,
    input wire [31:0] sim_data_a, sim_data_b,
`endif
    // serdes high speed pin
''', 1)
    import re
    s = re.sub(r'^    localparam (?:integer|\[15:0\])\s+CAMDDR_(?:W|H|X0|Y0|SKIP_ROWS)\s*=.*\n', '', s, flags=re.M)
    s = s.replace('if (w_sel_chg) begin', "if ((SYNC_ENABLE && !pcie_power_on_rst) || w_sel_chg) begin")
    s = s.replace("r_pwr_cnt2 != 23'h7FFFFF", 'r_pwr_cnt2 != CAM_POWER_CYCLES')
    s = s.replace("(r_pwr_cnt2 > 23'd1000)", '(r_pwr_cnt2 > CAM_CSI_RELEASE_CYCLES)')
    for c in 'ab':
        # Explicit existing package-level simulation boundary; real checked receiver remains.
        anchor = f') u_csi_{c} (\n        .I_ref_clk          (tl_clk_user),'
        repl = f''') u_csi_{c} (
`ifdef MIPI_PHY_SIM_STUB
        .I_ref_clk(sim_clk_{c}),.I_sim_word_valid(sim_valid_{c}),
        .I_sim_word_data(sim_data_{c}),.I_sim_packet_done(sim_done_{c}),
`else
        .I_ref_clk(tl_clk_user),
`endif'''
        assert anchor in s
        s = s.replace(anchor, repl)
    s = s.replace("ui_cfg_imx415 #(.CLK_DIV(16'd624))", 'ui_cfg_imx415 #(.SYNC_ENABLE(SYNC_ENABLE),.CLK_DIV(CAM_I2C_DIV))')
    for c in 'ab':
        anchor = f' u_cfg_{c} (\n'
        s = s.replace(anchor, anchor+f'''        .I_sync_req(sync_req_valid && sync_req_ready && (sync_camera==1'b{int(c=='b')})),
        .I_sync_addr(sync_addr),.I_sync_data(sync_data),
        .O_sync_ready(sync_{c}_ready),.O_sync_rsp_valid(sync_{c}_rsp),.O_sync_rsp_ok(sync_{c}_ok),
''')
    anchor = '    ui_cfg_imx415 #('
    at = s.index(anchor)
    integration = '''    wire sync_req_valid,sync_req_ready,sync_camera,sync_a_ready,sync_b_ready;
    wire sync_a_rsp,sync_b_rsp,sync_a_ok,sync_b_ok,sync_ready;
    wire [15:0] sync_addr; wire [7:0] sync_data; wire [3:0] sync_error;
    wire sync_stopped,sync_busy,sync_pair,sync_locked;
    wire [31:0] sync_warmup,sync_pairs;
    assign sync_req_ready=sync_camera ? sync_b_ready : sync_a_ready;
    generate if(SYNC_ENABLE) begin : g_sync_ctrl
      sync_offline_top #(.WAIT_CYCLES(SYNC_WAIT_CYCLES),.WARMUP_FRAMES(8),
        .I2C_TIMEOUT(SYNC_I2C_TIMEOUT),.FRAME_TIMEOUT(SYNC_FRAME_TIMEOUT),
        .PAIR_WINDOW(SYNC_PAIR_WINDOW)) u_sync(
        .clk_ctrl(tl_clk_user),.clk_a(w_a_byte_clk),.clk_b(w_b_byte_clk),
        .rst_n(pcie_power_on_rst && r_rst_n_slow),.start(sync_start),.abort_req(sync_abort),
        .prereq_ok(w_a_cfg_done && w_b_cfg_done && w_ddrphy_rdy),
        .sof_a(w_a_vsync),.sof_b(w_b_vsync),.req_valid(sync_req_valid),
        .req_ready(sync_req_ready),.camera_id(sync_camera),.reg_addr(sync_addr),.reg_data(sync_data),
        .rsp_valid(sync_a_rsp || sync_b_rsp),
        .rsp_ok((sync_a_rsp && sync_a_ok)||(sync_b_rsp && sync_b_ok)),
        .ready(sync_ready),.busy(sync_busy),.stopped_confirmed(sync_stopped),.error_code(sync_error),
        .pair_valid(sync_pair),.locked(sync_locked),.warmup_count(sync_warmup),.pair_count(sync_pairs),
        .skew(),.pair_seq_a(),.pair_seq_b(),.miss_a(),.miss_b(),.overrun_a(),.overrun_b(),
        .relock_count(),.ignored_starts(),.timestamp());
    end else begin : g_no_sync
      assign sync_req_valid=0;assign sync_camera=0;assign sync_addr=0;assign sync_data=0;
      assign sync_ready=1;assign sync_busy=0;assign sync_stopped=0;assign sync_error=0;
      assign sync_pair=0;assign sync_locked=0;assign sync_warmup=0;assign sync_pairs=0;
    end endgenerate
    wire gate_a_vsync,gate_b_vsync,gate_a_frame,gate_b_frame;
    wire gate_a_line,gate_b_line,gate_a_pixel_valid,gate_b_pixel_valid;
    wire gate_a_good,gate_b_good,gate_a_abort,gate_b_abort;
    sync_frame_gate #(.ENABLE(SYNC_ENABLE)) ga(
      w_a_byte_clk,w_a_rst_out,sync_ready,w_a_vsync,w_a_in_frame,w_a_in_line,w_a_pixel_valid,
      w_a_frame_good,w_a_frame_abort,gate_a_vsync,gate_a_frame,gate_a_line,gate_a_pixel_valid,gate_a_good,gate_a_abort);
    sync_frame_gate #(.ENABLE(SYNC_ENABLE)) gb(
      w_b_byte_clk,w_b_rst_out,sync_ready,w_b_vsync,w_b_in_frame,w_b_in_line,w_b_pixel_valid,
      w_b_frame_good,w_b_frame_abort,gate_b_vsync,gate_b_frame,gate_b_line,gate_b_pixel_valid,gate_b_good,gate_b_abort);
'''
    s = s[:at]+integration+s[at:]
    for c in 'ab':
        for port,raw,gated in [('cam_vsync','vsync','vsync'),('cam_in_frame','in_frame','frame'),
                ('cam_in_line','in_line','line'),('cam_pix_valid','pixel_valid','pixel_valid'),
                ('cam_frame_good','frame_good','good')]:
            s = re.sub(r'(\.'+port+r'\s*\()w_'+c+'_'+raw+r'(\s*\))',r'\g<1>gate_'+c+'_'+gated+r'\2',s)
        s = s.replace('cam_frame_abort(w_'+c+'_frame_abort', 'cam_frame_abort(gate_'+c+'_abort')
    return s
edit('rtl/ep_side/ph1p_pcie_ep_top.v', top)
print('OVERLAY_CREATED immutable_input_hashes_checked=true')
