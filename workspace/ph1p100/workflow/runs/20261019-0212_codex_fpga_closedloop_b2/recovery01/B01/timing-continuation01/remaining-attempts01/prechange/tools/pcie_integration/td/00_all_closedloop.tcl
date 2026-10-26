# =============================================================================
#  00_all_debug.tcl — T11.runB-debug-rtl：**debug 诊断位流**单会话全流程
#  （建工程 → syn → phy → bit），与 00_all.tcl 并列，不改其默认行为。
#
#  与 00_all.tcl 的逐条差异（同见 run debug-rtl/candidate-manifest.json）：
#    1) add_files 增加 debug 顶层包装 rtl/ep_side/debug/ph1p_pcie_ep_top_closedloop.v
#       （仅本入口编译；00_all 文件表保持逐字节不变）；
#    2) top_module = ph1p_pcie_ep_top_closedloop —— 把 DBG_CTRL_DEFAULT_EN=1'b1 覆盖进
#       ph1p_pcie_ep_top -> pcie_ep_engine -> ep_bar_win：复位默认仅
#       bit0 enable / bit5 ddr_en = 1；TX/push/doorbell 域全部保持 0
#       （依据 run debug-spec/enable-state.md §2）；
#    3) 末尾 marker 增加 T11_DBG_ALL_DONE（保留 T07_ALL_DONE，会同判据不变）。
#  其余 add_files / 约束 / IP / syn / phy / save_best_bits 与 00_all.tcl 完全一致。
#
#  用法（与 00_all 相同入口，只换 -Stage；不推送、不下载、不写 Flash）：
#    powershell -ExecutionPolicy Bypass -File tools/pcie_integration/run_td.ps1 `
#        -Stage 00_all_debug -OutDir <out>
#
#  P2 (T11.runB-debug-build) 提示 —— 本文件不自动执行 setup_debugger：
#    · 按 debug-spec/cwc-flow.md §2.1：位流生成后须经 TD setup_debugger 后处理
#      产出 cw/compiled.cwc + cw/compiled.bit，再跑 tools/td/check_chipwatcher_readback.py
#      （0 失败）后，方可进 P3；
#    · CWC 探针目标（elaboration 后回写 probe-map）：
#        ph1p_pcie_ep_top_closedloop/u_top/u_pcie_ep_engine/u_ep_bar_win/dbg_bank[287:0]
#        以及同层 dbg_bank_word0..dbg_bank_word8。
# =============================================================================

set PRJ_ROOT  "REPO_ROOT"

create_project ph1p_pcie_integration ./ -family PH1 -device PH1P100SBG484 -speed 3 -force

# ---- 顶层与寄存器面 ----
add_files $PRJ_ROOT/rtl/ep_side/img/ep_bar_win.v
add_files $PRJ_ROOT/rtl/ep_side/img/img_regs.v
add_files $PRJ_ROOT/rtl/ep_side/img/img_frame_src.v
# ---- T11 debug 顶层包装（仅本 debug 入口；见文件头差异 1/2）----
add_files $PRJ_ROOT/rtl/ep_side/debug/ph1p_pcie_ep_top_closedloop.v
# ---- common ----
add_files $PRJ_ROOT/rtl/common/ph1p_pcie_case_param.v
add_files $PRJ_ROOT/rtl/common/ph1p_pcie_rst_sync.v
add_files $PRJ_ROOT/rtl/common/uart/bps_setting.v
add_files $PRJ_ROOT/rtl/common/uart/pcie_uart.v
add_files $PRJ_ROOT/rtl/common/uart/pcie_uprotocol.v
add_files $PRJ_ROOT/rtl/common/uart/uart_cdc.v
add_files $PRJ_ROOT/rtl/common/uart/uart_rx_setting.v
add_files $PRJ_ROOT/rtl/common/uart/uart_tx_setting.v
add_files $PRJ_ROOT/rtl/common/ubus2hxt_apb.v
add_files $PRJ_ROOT/rtl/common/ubus2pcie_apb.v
# ---- 引擎/顶层/桥 ----
add_files $PRJ_ROOT/rtl/ep_side/pcie_ep_engine.v
add_files $PRJ_ROOT/rtl/ep_side/pcie_ep_int_handle.v
add_files $PRJ_ROOT/rtl/ep_side/ph1p_pcie_ep_top.v
add_files $PRJ_ROOT/rtl/ep_side/ubus_bridge/ep_ubus_bridge.v
# ---- 相机 / CSI（peer 原样 + 本包 checked）----
add_files $PRJ_ROOT/rtl/ep_side/cam/clk_activity.v
add_files $PRJ_ROOT/rtl/ep_side/cam/pulse2toggle.v
add_files $PRJ_ROOT/rtl/ep_side/cam/auto_delay_ctl.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_10bit_unpack.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_byte_align.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_clock_det.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_hdr_ecc.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_packet_handler.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_word_align.v
add_files $PRJ_ROOT/rtl/ep_side/cam/csi_rx_word_gear_box.v
add_files $PRJ_ROOT/rtl/ep_side/cam/mipi_csi2_rx_ph1p.v
add_files $PRJ_ROOT/rtl/ep_side/cam/rx_phy_ph1p.v
add_files $PRJ_ROOT/rtl/ep_side/cam/sfifo.v
add_files $PRJ_ROOT/rtl/ep_side/cam/wfifo.v
add_files $PRJ_ROOT/rtl/ep_side/cam/ui_cfg_imx415.v
add_files $PRJ_ROOT/rtl/ep_side/cam/ui_i2c.v
add_files $PRJ_ROOT/rtl/ep_side/cam/ui_imx415_reg.v
add_files $PRJ_ROOT/rtl/checked/csi_rx_packet_integrity.v
add_files $PRJ_ROOT/rtl/checked/csi_rx_10bit_unpack_checked.v
add_files $PRJ_ROOT/rtl/ep_side/cam/mipi_csi2_rx_ph1p_checked.v
# ---- DDR 通路 ----
add_files $PRJ_ROOT/rtl/ep_side/ddr/ddr_frame_pusher.v
add_files $PRJ_ROOT/rtl/ep_side/ddr/ddr_wr_arb.v
add_files $PRJ_ROOT/rtl/ep_side/ddr/cam_ddr_writer.v
# T11：正式 RAW10→R10F 写者
add_files $PRJ_ROOT/rtl/ep_side/ddr/cam_r10f_writer.v
add_files $PRJ_ROOT/rtl/ep_side/ddr/closedloop/ddr_closedloop_readback.v
add_files $PRJ_ROOT/rtl/ep_side/img/algo/algo_diagnostic_sink.v
add_files $PRJ_ROOT/rtl/ep_side/img/algo/algo_obuf.v
add_files $PRJ_ROOT/rtl/ep_side/img/algo/algo_rowwin3.v
add_files $PRJ_ROOT/rtl/ep_side/img/algo/algo_rowwin_reader.v
add_files $PRJ_ROOT/rtl/ep_side/img/algo/bayer_raw10_demosaic4.v
add_files $PRJ_ROOT/rtl/ep_side/img/algo/cam_algo_diagnostics.v
add_files $PRJ_ROOT/rtl/ep_side/img/algo/csi_algo_roi_adapter.v
add_files $PRJ_ROOT/rtl/ep_side/img/algo/gray8_gaussian3x3_frame.v
add_files $PRJ_ROOT/rtl/ep_side/img/algo/gray8_gaussian3x3_stream.v
add_files $PRJ_ROOT/rtl/ep_side/img/algo/gray8_he_cdfmin_frame.v
add_files $PRJ_ROOT/rtl/ep_side/img/algo/img_algo_parallel_top.v
add_files $PRJ_ROOT/rtl/ep_side/img/algo/rgb8_gray_stream.v
add_files $PRJ_ROOT/rtl/ep_side/ddr/ddr_frame_readback_checker.v
# ---- 约束 ----
# T11 P1-fix：debug 构建使用 debug SDC 变体（生产 SDC 一字不动；仅 u_top/ 前缀，
#   由 run debug-fix/gen_validate_dbg_sdc.ps1 机械生成并 fail-closed 校验通过）。
#   生产 SDC（ph1p_pcie_case_ep.sdc）不加入本 debug 工程，避免重复时钟定义。
add_files $PRJ_ROOT/constraints/ph1p_pcie_case_ep.adc
add_files $PRJ_ROOT/constraints/ph1p_pcie_case_ep_closedloop.sdc
# ---- 匹配版本 IP ----
add_files $PRJ_ROOT/al_ip/pcie_ep_core/pcie_ep_core.xml
add_files $PRJ_ROOT/al_ip/pcie_pll_ep/pcie_pll_ep.xml
add_files $PRJ_ROOT/al_ip/ram/ram.xml
add_files $PRJ_ROOT/al_ip/ddr3_mc_0/ddr3_mc_0.xml

top_module ph1p_pcie_ep_top_closedloop

# ---- 综合 ----
launch_runs { syn_1 } -jobs 4
wait_run syn_1 -quiet
# 报告命令要求会话里已 import netlist；失败不要中断流程（报告本体在 run 目录里）
if { [catch { report_area   -file syn_area.rpt }  e] } { puts "report_area(syn) skipped: $e" }
if { [catch { report_timing -file syn_timing.rpt } e] } { puts "report_timing(syn) skipped: $e" }

# ---- Native full route, explicit hold repair, then paired bit/CWC ----
# -step and fix_hold are verified in local Release_2026.2 native help.
# DefaultFlow's explicit fix_hold is conditional on arr_filter=on; call it
# here on the completed routed DB without changing clocks/IP/constraints.
launch_runs { phy_1 } -step opt_route -jobs 4
wait_run phy_1 -quiet
set phy_dir [file normalize ./ph1p_pcie_integration_Runs/phy_1]
close_project
cd $phy_dir
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./ph1p_pcie_integration.prj -noanalyze
    import_db ./ph1p_pcie_integration_pr.db
    puts "B01_EXPLICIT_HOLD_FIX_BEGIN"
    fix_hold
    puts "B01_EXPLICIT_HOLD_FIX_END"
    update_timing -mode final
    report_timing_status -file ph1p_pcie_integration_phy.ts
    report_timing_summary -file ph1p_pcie_integration_pr.timing
    report_timing_exception -file ph1p_pcie_integration_exception.timing
    check_timing -verbose -file ph1p_pcie_integration_chk.timing
    report_area -io_info -file ph1p_pcie_integration_phy.area
    report_clock_utilization -file route_clock_utilization.txt
    export_db ph1p_pcie_integration_pr.db
    bitgen -bit ph1p_pcie_integration.bit
    setup_debugger -prj ph1p_pcie_integration
    if {![file exists ./cw/compiled.cwc] || ![file exists ./cw/compiled.bit]} {error "missing native paired CWC artifacts"}
} msg]} {puts stderr "B01_NATIVE_FINISH_ERROR: $msg"; exit 1}

puts "T07_ALL_DONE"
puts "B01_CLOSEDLOOP_ALL_DONE"

exit
