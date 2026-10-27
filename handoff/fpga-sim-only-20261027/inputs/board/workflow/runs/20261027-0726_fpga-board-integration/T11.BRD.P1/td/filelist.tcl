# =============================================================================
# filelist.tcl -- T11.BRD.P1 single source list (sourced by 00_build.tcl)
#
# Guarded: a *.v.stale, a src/src/** duplicate tree, a peer-ref-2a4b253 copy, an
# r3 derived variant (algo_rowwin3_p4.v / gray8_gaussian3x3_stream_p4.v) or a
# missing file aborts the build BEFORE TD starts synthesising.
# =============================================================================
set R "D:/fpga/ph1p100"

set FL {}

# ---- board integration (this task, writable scope) ----
lappend FL $R/fpga/csi2/src/board_integration/brd_integrated_top.v
lappend FL $R/fpga/csi2/src/board_integration/brd_board_datapath.v
lappend FL $R/fpga/csi2/src/board_integration/brd_cam_fe.v
lappend FL $R/fpga/csi2/src/board_integration/brd_cdc_mailboxes.v
lappend FL $R/fpga/csi2/src/board_integration/brd_ddr_rd_arb.v
lappend FL $R/fpga/csi2/src/board_integration/brd_a1_core_pll.v
lappend FL $R/fpga/csi2/src/board_integration/a1_raw_crop.v
lappend FL $R/fpga/csi2/src/board_integration/p2_ddr_bridge.v
lappend FL $R/fpga/csi2/pcie_integration/rtl/ep_side/ddr/ddr_frame_pusher.v

# ---- shared FIFO primitive (read-only) ----
lappend FL $R/fpga/csi2/src/mem/capture_async_fifo.v

# ---- P4 r2 candidate (READ-ONLY, INT.P4-r2-manifest DFAB7F9D...) ----
lappend FL $R/fpga/csi2/src/integrated_delivery/integrated_delivery_top.v
lappend FL $R/fpga/csi2/src/integrated_delivery/integrated_input_processing_top.v
lappend FL $R/fpga/csi2/src/integrated_delivery/bayer_raw10_demosaic4_p4.v
lappend FL $R/fpga/csi2/src/integrated_delivery/img_algo_parallel_top_p4.v
lappend FL $R/fpga/csi2/src/integrated_delivery/aplus_pcie_egress_adapter.v
lappend FL $R/fpga/csi2/src/integrated_delivery/dual_channel_capture_scheduler.v
lappend FL $R/fpga/csi2/src/integrated_delivery/frame_good_publish_cancel.v
lappend FL $R/fpga/csi2/src/integrated_delivery/raw10_sample_vector_to_packed.v

# ---- algorithm sources (READ-ONLY, r2 manifest img_sources) ----
lappend FL $R/fpga/csi2/src/img/algo_obuf.v
lappend FL $R/fpga/csi2/src/img/algo_rowwin3.v
lappend FL $R/fpga/csi2/src/img/algo_rowwin_reader.v
lappend FL $R/fpga/csi2/src/img/bayer_raw10_demosaic4.v
lappend FL $R/fpga/csi2/src/img/gray8_gaussian3x3_frame.v
lappend FL $R/fpga/csi2/src/img/gray8_gaussian3x3_stream.v
lappend FL $R/fpga/csi2/src/img/gray8_he_cdfmin_frame.v
lappend FL $R/fpga/csi2/src/img/img_algo_parallel_top.v
lappend FL $R/fpga/csi2/src/img/img_algo_top_g2.v
lappend FL $R/fpga/csi2/src/img/rgb8_gray_stream.v

# ---- P4 r2 timing-hook files (READ-ONLY, r2 manifest hashes F3F345ED / 158AAE4D)
# These two files are instantiated by bayer_raw10_demosaic4_p4.v and
# img_algo_parallel_top_p4.v, so the r2 candidate cannot elaborate without them.
# The copies that are still in src/integrated_delivery/ have DIFFERENT hashes
# (863932B3 / B8096430) and are the r3-derived variants -- they are rejected by
# the guard below.  The r2-hash-bound copies are the ones registered in
# INT.P4-r2-manifest.json new_files.
set R2X $R/workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/r2-timing-experiment
lappend FL $R2X/algo_rowwin3_p4.v
lappend FL $R2X/gray8_gaussian3x3_stream_p4.v

# ---- b18 glue (READ-ONLY) ----
set B18 $R/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/r0/changed-src
lappend FL $B18/cam_diag_mailbox.v

# ---- b20 A+ core (READ-ONLY, r2 manifest readonly_a1_inputs) ----
set B20 $R/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src
lappend FL $B20/a1_frame_top.v
lappend FL $B20/a1_deflate_core.v
lappend FL $B20/a1_ddr_slot_store.v
lappend FL $B20/a1_ddr_arb2.v

# ---- PCIe EP board base (READ-ONLY reference project) ----
set P $R/fpga/csi2/pcie_integration
lappend FL $P/rtl/ep_side/img/ep_bar_win.v
lappend FL $P/rtl/ep_side/img/img_regs.v
lappend FL $P/rtl/common/ph1p_pcie_case_param.v
lappend FL $P/rtl/common/ph1p_pcie_rst_sync.v
lappend FL $P/rtl/common/uart/bps_setting.v
lappend FL $P/rtl/common/uart/pcie_uart.v
lappend FL $P/rtl/common/uart/pcie_uprotocol.v
lappend FL $P/rtl/common/uart/uart_cdc.v
lappend FL $P/rtl/common/uart/uart_rx_setting.v
lappend FL $P/rtl/common/uart/uart_tx_setting.v
lappend FL $P/rtl/common/ubus2hxt_apb.v
lappend FL $P/rtl/common/ubus2pcie_apb.v
lappend FL $P/rtl/ep_side/pcie_ep_engine.v
lappend FL $P/rtl/ep_side/pcie_ep_int_handle.v
lappend FL $P/rtl/ep_side/ubus_bridge/ep_ubus_bridge.v
lappend FL $P/rtl/ep_side/cam/clk_activity.v
lappend FL $P/rtl/ep_side/cam/pulse2toggle.v
lappend FL $P/rtl/ep_side/cam/auto_delay_ctl.v
lappend FL $P/rtl/ep_side/cam/csi_rx_10bit_unpack.v
lappend FL $P/rtl/ep_side/cam/csi_rx_byte_align.v
lappend FL $P/rtl/ep_side/cam/csi_rx_clock_det.v
lappend FL $P/rtl/ep_side/cam/csi_rx_hdr_ecc.v
lappend FL $P/rtl/ep_side/cam/csi_rx_packet_handler.v
lappend FL $P/rtl/ep_side/cam/csi_rx_word_align.v
lappend FL $P/rtl/ep_side/cam/csi_rx_word_gear_box.v
lappend FL $P/rtl/ep_side/cam/mipi_csi2_rx_ph1p.v
lappend FL $P/rtl/ep_side/cam/mipi_csi2_rx_ph1p_checked.v
lappend FL $P/rtl/ep_side/cam/rx_phy_ph1p.v
lappend FL $P/rtl/ep_side/cam/sfifo.v
lappend FL $P/rtl/ep_side/cam/wfifo.v
lappend FL $P/rtl/ep_side/cam/ui_cfg_imx415.v
lappend FL $P/rtl/ep_side/cam/ui_i2c.v
lappend FL $P/rtl/ep_side/cam/ui_imx415_reg.v
lappend FL $P/rtl/checked/csi_rx_packet_integrity.v
lappend FL $P/rtl/checked/csi_rx_10bit_unpack_checked.v

# ---- matched IP ----
lappend FL $P/al_ip/pcie_ep_core/pcie_ep_core.xml
lappend FL $P/al_ip/pcie_pll_ep/pcie_pll_ep.xml
lappend FL $P/al_ip/ram/ram.xml
lappend FL $P/al_ip/ddr3_mc_0/ddr3_mc_0.xml
lappend FL $R/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/r0/td/src/camera/uisrc/03_ip/raw10_clocks/raw10_clocks.xml

# ---- constraints (this run) ----
lappend FL $R/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/td/ph1p_pcie_case_ep.adc
lappend FL $R/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/td/brd_board.sdc

# =============================================================================
# guards
# =============================================================================
foreach f $FL {
    if {[string match -nocase "*.v.stale" $f]}      { error "filelist guard: stale source $f" }
    if {[string match "*/src/src/*" $f]}           { error "filelist guard: duplicate src tree $f" }
    if {[string match "*peer-ref-2a4b253*" $f]}    { error "filelist guard: peer reference copy $f" }
    if {[string match "*/integrated_delivery/algo_rowwin3_p4.v" $f]}    { error "filelist guard: r3-era candidate copy $f" }
    if {[string match "*/integrated_delivery/gray8_gaussian3x3_stream_p4.v" $f]} { error "filelist guard: r3-era candidate copy $f" }
    if {![file exists $f]}                         { error "filelist guard: missing source $f" }
}

puts "BRD_FILELIST_COUNT=[llength $FL]"
foreach f $FL { puts "BRD_FILE $f" }

foreach f $FL { add_files $f }
