import json, hashlib, pathlib, datetime

root = pathlib.Path(r'D:\fpga\ph1p100')
pkg = root/'workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b7-cam-diag'
r0 = pkg/'r0'

def sha(p):
    return hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest()

def rec(p):
    p = pathlib.Path(p)
    if not p.exists():
        return None
    return dict(path=str(p), bytes=p.stat().st_size, sha256=sha(p))

groups = {
    'changed_rtl': [
        r0/'changed-src/cam_diag_mailbox.v',
        r0/'changed-src/camera_a1_uart_top.v',
        r0/'changed-src/a1_uart_export.v',
        r0/'changed-src/a1_deflate_core.v',
        r0/'td/src/f9p_camera_display_core.v',
        r0/'td/src/p2_a1_board_top.v',
        r0/'td/01_build.tcl',
    ],
    'frozen_inputs': [
        root/'fpga/csi2/src/a1/a1_raw_crop.v',
        root/'fpga/csi2/src/a1/a1_ddr_slot_store.v',
        root/'fpga/csi2/src/a1/a1_ddr_arb2.v',
        root/'fpga/csi2/src/mem/capture_async_fifo.v',
        root/'upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_frame_top.v',
        r0/'td/02_bitgen.tcl',
        r0/'td/03_cwc.tcl',
        r0/'td/a1_eng_top.v',
        r0/'td/a1_small_top.sdc',
        r0/'td/p2_board.sdc',
        r0/'td/board_p2.adc',
    ],
    'sim': [
        r0/'sim/tb_status_pkt_v2.v',
        r0/'sim/tb_cam_dead.v',
        r0/'sim/tb_camera_a1_uart_top.v',
        r0/'sim/a1_ddr_model.v',
        r0/'sim/status_v2_bytes.txt',
        r0/'sim/status_v2_parse.txt',
        r0/'sim/status_dead_bytes.txt',
        r0/'sim/status_dead_parse.txt',
        r0/'sim/vsim_status_v2.log',
        r0/'sim/vsim_deadcam.log',
        r0/'sim/p1-regression-b7.json',
        r0/'sim/run_p1.py',
        r0/'sim/caps/micro8x2.dec',
        r0/'sim/caps/mid64x8.dec',
        r0/'sim/caps/full_grad.dec',
        r0/'sim/caps/micro8x2.stats',
        r0/'sim/caps/mid64x8.stats',
        r0/'sim/caps/full_grad.stats',
    ],
    'candidate': [
        r0/'td/a1_board.bit',
        r0/'td/a1_board.cwc',
        r0/'td/a1_board_inst.bid',
        r0/'td/cw/compiled.bit',
        r0/'td/cw/compiled.cwc',
    ],
    'reports': [
        r0/'td/build_console_r0diag_route1.log',
        r0/'td/build_console_r0diag_route2.log',
        r0/'td/syn_gate_timing.rpt',
        r0/'td/syn_gate_area.rpt',
        r0/'td/routed_timing_summary.rpt',
        r0/'td/routed_check_timing.rpt',
        r0/'td/routed_area.rpt',
        r0/'td/routed_qor.rpt',
        r0/'td/candidate_timing.rpt',
        r0/'td/candidate_abnormal.rpt',
        r0/'td/bitgen_console_r0diag.log',
        r0/'td/cwc_console_r0diag.log',
        r0/'td/route1_routed_timing_summary.rpt',
        r0/'td/route1_routed_qor.rpt',
        r0/'td/route1_phy_pr_timing_flow.rpt',
    ],
    'board': [
        r0/'board/ping_cable.tcl',
        r0/'board/ping_cable_b7.log',
        r0/'board/download_sram_camdiag.tcl',
        r0/'board/download_sram_camdiag.log',
        r0/'board/capture_com8.py',
        r0/'board/parse_status_v2.py',
        r0/'board/captures/com8_60s.bin',
        r0/'board/captures/com8_60s.dec',
        r0/'board/captures/com8_60s.stats',
        r0/'board/captures/status_v2_60s.txt',
    ],
    'docs': [
        r0/'rtl-diff-r0diag.patch',
        pkg/'result-r0diag.md',
        pkg/'lessons-r0diag.md',
    ],
}

out = {}
missing = []
for g, paths in groups.items():
    lst = []
    for p in paths:
        r = rec(p)
        if r is None:
            missing.append(str(p))
        else:
            lst.append(r)
    out[g] = lst

expected = {
    'a1_deflate_core.v': '6797db053cfc47497540d6345e3a46b7e79cc1d34fa25da5a4c501505fbf35bb',
    'b6_a1_board.bit': 'a2757d40bcfed7ec4e8a3b0e3985e1c14fdc0311307a096ffa1e1f46c2edffa2',
}
core = [x for x in out['changed_rtl'] if x['path'].endswith('a1_deflate_core.v')]
core_ok = bool(core) and core[0]['sha256'] == expected['a1_deflate_core.v']

man = dict(
    task_id='T10.b7-cam-diag',
    candidate_id='b7-cam-diag-r0diag',
    created=datetime.datetime.now().isoformat(timespec='seconds'),
    package=str(pkg),
    status='ready_for_test',
    scope='camera front-end observability only: 16 camera-core status outputs, '
          'one clk_cam counter bank, two stable-hold/toggle mailboxes, '
          '97-byte v2 idle status packet. No image/frame/CRC/DDR/UART-data/SDC/pin change.',
    device='PH1P100SBG484 -3',
    tools=dict(td='TD_Release_2026.2', modelsim='10.5b (Intel FPGA Edition, win32aloem)'),
    packet_v2=dict(total_bytes=97, header=[0xA5, 0x5A], len=0x61, ver=0x02,
                   legacy_fields=['cap_frames', 'raw_pub', 'enc_frames', 'exported',
                                  'raw_drop', 'cmp_drop', 'errors', 'read_words'],
                   cam_fields=['cam_clk_tgl_inc', 'cam_pkt_tgl_inc', 'cam_vs_tgl_inc',
                               'cam_pix_beats', 'cam_line_rises', 'cam_frame_rises',
                               'cam_frame_falls', 'cam_last_frame_cycles',
                               'crop_roi_frames', 'crop_groups', 'crop_short',
                               'crop_geom_err', 'cam_phystat', 'cam_sysstat',
                               'cam_nack_cnt'],
                   xor8_over='bytes[0..95]'),
    mailboxes=dict(cam=dict(W=352, DIV_BITS=12, from_='clk_cam(a_byte_clk)',
                            to='clk_a1', hold_us_min=37),
                   sys=dict(W=64, DIV_BITS=12, from_='sys_clk50m', to='clk_a1',
                            hold_us_min=82)),
    core_sha_unchanged=core_ok,
    core_sha_expected=expected['a1_deflate_core.v'],
    b6_baseline_bit_sha256=expected['b6_a1_board.bit'],
    budgets=dict(dev_minutes=90, dev_tool_calls=50, td_sessions=3, syn=2, route=1,
                 bitgen=1, cwc=1, download=1, flash=0),
    board_authorization='1 SRAM download + 60 s COM8 capture, granted by the user 2026-10-24; no Flash.',
    artifacts=out,
    missing=missing,
)
(pkg/'CANDIDATE-MANIFEST-b7-cam-diag-r0diag.json').write_text(json.dumps(man, indent=2))

lines = ['# T10.b7-cam-diag r0-diag artifact hashes (SHA256)',
         '# generated %s' % man['created'], '']
for g in groups:
    lines.append('[%s]' % g)
    for r in out[g]:
        lines.append('%s  %12d  %s' % (r['sha256'], r['bytes'], r['path']))
    lines.append('')
if missing:
    lines.append('[MISSING]')
    lines += missing
(pkg/'artifact-hashes.txt').write_text('\n'.join(lines) + '\n')
print('core_sha_unchanged', core_ok)
print('missing', len(missing))
for m in missing:
    print('  MISS', m)
