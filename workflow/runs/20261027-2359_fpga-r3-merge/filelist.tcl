# =============================================================================
# filelist.tcl -- T11.BRD.P1 r3 SINGLE source list (repo-relative)
#
# Usage (teammate environment, from the repository root):
#   cd <repo>
#   td_commands_prompt.exe -f handoff/brd-p1-r3-20261027/build/01_synth.tcl
# or source this file from any TD session whose cwd is the repo root.
#
# Every path is relative to the repository root ($R = [pwd]).  No T:/Y:,
# no D:/fpga/ph1p100, no old absolute path.
#
# r3 vs r2 (78 sources, same count):
#   * board RTL now comes from this package (r3/rtl): the only behavioural
#     deltas are the ACK slice in brd_cdc_mailboxes.v and a_seq/b_seq=1 in
#     brd_board_datapath.v; ddr_frame_pusher.v differs by a comment only
#     (the data-beat mapping was re-verified, not changed);
#   * the A+ core comes from this package's rtl/a1_core_fix01 (byte-identical
#     to the b20 originals and to r1/r2);
#   * the EP base still comes from the frozen r1 external mirror so the
#     pusher/engine includes resolve; every mirrored file is a byte copy of
#     the r0 snapshot.
#
# Guarded before TD sees a single file:
#   *.v.stale, */src/src/*, *peer-ref-2a4b253*, the two r3-era derived copies,
#   a missing file, or a module name defined twice -> error, no synthesis.
# =============================================================================
if {[info exists BRD_REPO_ROOT]} { set R $BRD_REPO_ROOT } else { set R [pwd] }
if {![file exists "$R/handoff/brd-p1-r3-20261027/filelist.tcl"]} {
    error "filelist: set BRD_REPO_ROOT or run from the repository root (pwd=$R)"
}

set FL {}

# ---- r3 board integration (this task) ----
set BRD $R/handoff/brd-p1-r3-20261027
lappend FL $BRD/rtl/brd_integrated_top.v
lappend FL $BRD/rtl/brd_board_datapath.v
lappend FL $BRD/rtl/brd_cam_fe.v
lappend FL $BRD/rtl/brd_cdc_mailboxes.v
lappend FL $BRD/rtl/brd_ddr_rd_arb.v
lappend FL $BRD/rtl/brd_a1_core_pll.v
lappend FL $BRD/rtl/brd_export_seq.v
lappend FL $BRD/rtl/a1_raw_crop.v
lappend FL $BRD/rtl/p2_ddr_bridge.v

# ---- EP base mirror (byte copies of the r0 snapshot + two include files) ----
set EP $R/handoff/brd-p1-r3-20261027/external/pcie_integration
lappend FL $BRD/rtl/ref/ep_side/ddr/ddr_frame_pusher.v
lappend FL $EP/rtl/ep_side/img/ep_bar_win.v
lappend FL $EP/rtl/ep_side/img/img_regs.v
lappend FL $EP/rtl/common/ph1p_pcie_case_param.v
lappend FL $EP/rtl/common/ph1p_pcie_rst_sync.v
lappend FL $EP/rtl/common/uart/bps_setting.v
lappend FL $EP/rtl/common/uart/pcie_uart.v
lappend FL $EP/rtl/common/uart/pcie_uprotocol.v
lappend FL $EP/rtl/common/uart/uart_cdc.v
lappend FL $EP/rtl/common/uart/uart_rx_setting.v
lappend FL $EP/rtl/common/uart/uart_tx_setting.v
lappend FL $EP/rtl/common/ubus2hxt_apb.v
lappend FL $EP/rtl/common/ubus2pcie_apb.v
lappend FL $EP/rtl/ep_side/pcie_ep_engine.v
lappend FL $EP/rtl/ep_side/pcie_ep_int_handle.v
lappend FL $EP/rtl/ep_side/ubus_bridge/ep_ubus_bridge.v
lappend FL $EP/rtl/ep_side/cam/clk_activity.v
lappend FL $EP/rtl/ep_side/cam/pulse2toggle.v
lappend FL $EP/rtl/ep_side/cam/auto_delay_ctl.v
lappend FL $EP/rtl/ep_side/cam/csi_rx_10bit_unpack.v
lappend FL $EP/rtl/ep_side/cam/csi_rx_byte_align.v
lappend FL $EP/rtl/ep_side/cam/csi_rx_clock_det.v
lappend FL $EP/rtl/ep_side/cam/csi_rx_hdr_ecc.v
lappend FL $EP/rtl/ep_side/cam/csi_rx_packet_handler.v
lappend FL $EP/rtl/ep_side/cam/csi_rx_word_align.v
lappend FL $EP/rtl/ep_side/cam/csi_rx_word_gear_box.v
lappend FL $EP/rtl/ep_side/cam/mipi_csi2_rx_ph1p.v
lappend FL $EP/rtl/ep_side/cam/mipi_csi2_rx_ph1p_checked.v
lappend FL $EP/rtl/ep_side/cam/rx_phy_ph1p.v
lappend FL $EP/rtl/ep_side/cam/sfifo.v
lappend FL $EP/rtl/ep_side/cam/wfifo.v
lappend FL $EP/rtl/ep_side/cam/ui_cfg_imx415.v
lappend FL $EP/rtl/ep_side/cam/ui_i2c.v
lappend FL $EP/rtl/ep_side/cam/ui_imx415_reg.v
lappend FL $EP/rtl/checked/csi_rx_packet_integrity.v
lappend FL $EP/rtl/checked/csi_rx_10bit_unpack_checked.v

# ---- shared FIFO (r0 snapshot, read-only) ----
set BF $R/handoff/fpga-sim-only-20261027/inputs/board-filelist
lappend FL $BF/fpga/csi2/src/mem/capture_async_fifo.v

# ---- P4 r2 candidate (read-only, INT.P4-r2-manifest DFAB7F9D...) ----
set P4 $BF/fpga/csi2/src/integrated_delivery
lappend FL $P4/integrated_delivery_top.v
lappend FL $P4/integrated_input_processing_top.v
lappend FL $P4/bayer_raw10_demosaic4_p4.v
lappend FL $P4/img_algo_parallel_top_p4.v
lappend FL $P4/aplus_pcie_egress_adapter.v
lappend FL $P4/dual_channel_capture_scheduler.v
lappend FL $P4/frame_good_publish_cancel.v
lappend FL $P4/raw10_sample_vector_to_packed.v

# ---- P4 r2 timing-hook files (r2 manifest hashes F3F345ED / 158AAE4D) ----
set R2X $R/handoff/fpga-sim-only-20261027/inputs/p4/workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/r2-timing-experiment
lappend FL $R2X/algo_rowwin3_p4.v
lappend FL $R2X/gray8_gaussian3x3_stream_p4.v

# ---- img algorithm sources (read-only) ----
set IMG $BF/fpga/csi2/src/img
lappend FL $IMG/algo_obuf.v
lappend FL $IMG/algo_rowwin3.v
lappend FL $IMG/algo_rowwin_reader.v
lappend FL $IMG/bayer_raw10_demosaic4.v
lappend FL $IMG/gray8_gaussian3x3_frame.v
lappend FL $IMG/gray8_gaussian3x3_stream.v
lappend FL $IMG/gray8_he_cdfmin_frame.v
lappend FL $IMG/img_algo_parallel_top.v
lappend FL $IMG/img_algo_top_g2.v
lappend FL $IMG/rgb8_gray_stream.v

# ---- b18 glue (read-only) ----
lappend FL $BF/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/r0/changed-src/cam_diag_mailbox.v

# ---- A+ core (this package; byte-identical to the b20 originals) ----
set B20 $BRD/rtl/a1_core_fix01
lappend FL $B20/a1_frame_top.v
lappend FL $B20/a1_deflate_core.v
lappend FL $B20/a1_ddr_slot_store.v
lappend FL $B20/a1_ddr_arb2.v

# ---- matched IP (XML) ----
lappend FL $EP/al_ip/pcie_ep_core/pcie_ep_core.xml
lappend FL $EP/al_ip/pcie_pll_ep/pcie_pll_ep.xml
lappend FL $EP/al_ip/ram/ram.xml
lappend FL $EP/al_ip/ddr3_mc_0/ddr3_mc_0.xml
lappend FL $BF/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/r0/td/src/camera/uisrc/03_ip/raw10_clocks/raw10_clocks.xml

# ---- constraints (this package) ----
lappend FL $BRD/constraints/ph1p_pcie_case_ep.adc
lappend FL $BRD/constraints/brd_board.sdc

# =============================================================================
# guards
# =============================================================================
foreach f $FL {
    if {[string match -nocase "*.v.stale" $f]}      { error "filelist guard: stale source $f" }
    if {[string match "*/src/src/*" $f]}           { error "filelist guard: duplicate src tree $f" }
    if {[string match "*peer-ref-2a4b253*" $f]}    { error "filelist guard: peer reference copy $f" }
    if {[string match "*/integrated_delivery/algo_rowwin3_p4.v" $f]}    { error "filelist guard: r3-era candidate copy $f" }
    if {[string match "*/integrated_delivery/gray8_gaussian3x3_stream_p4.v" $f]} { error "filelist guard: r3-era candidate copy $f" }
    if {[string match "*.bit" $f] || [string match "*.cwc" $f]} { error "filelist guard: bitstream/CWC must never be a source $f" }
    if {![file exists $f]}                         { error "filelist guard: missing source $f" }
}

# duplicate module / r3-hash / bitstream checks: run build/check_filelist.py
# (repo root) BEFORE TD; it recomputes SHA256 and aborts on any violation.

puts "BRD_FILELIST_COUNT=[llength $FL]"
foreach f $FL { puts "BRD_FILE $f" }

foreach f $FL { add_files $f }

