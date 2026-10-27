<?xml version="1.0" encoding="UTF-8"?>
<!-- =========================================================================
     brd_board.al.tmpl: T11.BRD.P1 r1 TD project TEMPLATE.
     D:/fpga/repos/ph1p100-pcie-ep-fpga is the only absolute-path placeholder; it is replaced by
     build/gen_al.py with the actual repository root.  No T:, no Y:, no
     D:/fpga/ph1p100.  Generated file: brd_board.al (do not hand-edit).
     ========================================================================= -->
<Project Version="3" Minor="2" Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/build">
    <Project_Created_Time></Project_Created_Time>
    <TD_Version>6.2.3.210850</TD_Version>
    <Name>brd_board</Name>
    <HardWare>
        <Family>PH1</Family>
        <Device>PH1P100SBG484</Device>
        <Speed>-3</Speed>
    </HardWare>
    <Source_Files>
        <Verilog>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/rtl/brd_integrated_top.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="1"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/rtl/brd_board_datapath.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="2"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/rtl/brd_cam_fe.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="3"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/rtl/brd_cdc_mailboxes.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="4"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/rtl/brd_ddr_rd_arb.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="5"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/rtl/brd_a1_core_pll.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="6"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/rtl/brd_export_seq.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="7"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/rtl/a1_raw_crop.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="8"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/rtl/p2_ddr_bridge.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="9"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/ddr/ddr_frame_pusher.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="10"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/img/ep_bar_win.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="11"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/img/img_regs.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="12"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/common/ph1p_pcie_case_param.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="13"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/common/ph1p_pcie_rst_sync.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="14"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/common/uart/bps_setting.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="15"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/common/uart/pcie_uart.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="16"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/common/uart/pcie_uprotocol.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="17"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/common/uart/uart_cdc.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="18"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/common/uart/uart_rx_setting.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="19"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/common/uart/uart_tx_setting.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="20"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/common/ubus2hxt_apb.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="21"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/common/ubus2pcie_apb.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="22"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/pcie_ep_engine.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="23"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/pcie_ep_int_handle.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="24"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/ubus_bridge/ep_ubus_bridge.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="25"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/clk_activity.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="26"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/pulse2toggle.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="27"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/auto_delay_ctl.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="28"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/csi_rx_10bit_unpack.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="29"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/csi_rx_byte_align.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="30"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/csi_rx_clock_det.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="31"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/csi_rx_hdr_ecc.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="32"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/csi_rx_packet_handler.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="33"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/csi_rx_word_align.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="34"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/csi_rx_word_gear_box.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="35"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/mipi_csi2_rx_ph1p.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="36"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/mipi_csi2_rx_ph1p_checked.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="37"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/rx_phy_ph1p.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="38"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/sfifo.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="39"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/wfifo.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="40"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/ui_cfg_imx415.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="41"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/ui_i2c.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="42"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/ep_side/cam/ui_imx415_reg.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="43"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/checked/csi_rx_packet_integrity.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="44"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/rtl/checked/csi_rx_10bit_unpack_checked.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="45"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/mem/capture_async_fifo.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="46"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/integrated_delivery/integrated_delivery_top.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="47"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/integrated_delivery/integrated_input_processing_top.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="48"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/integrated_delivery/bayer_raw10_demosaic4_p4.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="49"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/integrated_delivery/img_algo_parallel_top_p4.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="50"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/integrated_delivery/aplus_pcie_egress_adapter.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="51"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/integrated_delivery/dual_channel_capture_scheduler.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="52"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/integrated_delivery/frame_good_publish_cancel.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="53"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/integrated_delivery/raw10_sample_vector_to_packed.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="54"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/p4/workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/r2-timing-experiment/algo_rowwin3_p4.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="55"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/p4/workflow/runs/20261026-2138_fpga-integrated-delivery/INT.P4/r2-timing-experiment/gray8_gaussian3x3_stream_p4.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="56"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/img/algo_obuf.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="57"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/img/algo_rowwin3.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="58"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/img/algo_rowwin_reader.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="59"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/img/bayer_raw10_demosaic4.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="60"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/img/gray8_gaussian3x3_frame.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="61"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/img/gray8_gaussian3x3_stream.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="62"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/img/gray8_he_cdfmin_frame.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="63"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/img/img_algo_parallel_top.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="64"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/img/img_algo_top_g2.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="65"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/fpga/csi2/src/img/rgb8_gray_stream.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="66"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/r0/changed-src/cam_diag_mailbox.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="67"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/p4/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/a1_frame_top.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="68"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/p4/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/a1_deflate_core.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="69"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/p4/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/a1_ddr_slot_store.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="70"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/p4/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b20-a-timing/r0/changed-src/a1_ddr_arb2.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="71"/>
                </FileInfo>
            </File>
        </Verilog>
        <ADC_FILE>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/constraints/ph1p_pcie_case_ep.adc">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="1"/>
                </FileInfo>
            </File>
        </ADC_FILE>
        <SDC_FILE>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/workflow/runs/20261027-0726_fpga-board-integration/T11.BRD.P1/r1/constraints/brd_board.sdc">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="2"/>
                </FileInfo>
            </File>
        </SDC_FILE>
        <IP_FILE>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/al_ip/pcie_ep_core/pcie_ep_core.xml">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="71"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/al_ip/pcie_pll_ep/pcie_pll_ep.xml">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="72"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/al_ip/ram/ram.xml">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="73"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/brd-p1-r1-20261027/external/pcie_integration/al_ip/ddr3_mc_0/ddr3_mc_0.xml">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="74"/>
                </FileInfo>
            </File>
            <File Path="D:/fpga/repos/ph1p100-pcie-ep-fpga/handoff/fpga-sim-only-20261027/inputs/board-filelist/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.b18-b17-b/r0/td/src/camera/uisrc/03_ip/raw10_clocks/raw10_clocks.xml">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&amp;R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="75"/>
                </FileInfo>
            </File>
        </IP_FILE>
    </Source_Files>
    <FileSets>
        <FileSet Name="design_1" Type="DesignFiles">
        </FileSet>
        <FileSet Name="constraint_1" Type="ConstrainFiles">
        </FileSet>
    </FileSets>
    <TOP_MODULE>
        <LABEL></LABEL>
        <MODULE>brd_integrated_top</MODULE>
        <CREATEINDEX>user</CREATEINDEX>
    </TOP_MODULE>
    <Property>
    </Property>
    <Device_Settings>
    </Device_Settings>
    <Configurations>
    </Configurations>
    <Runs>
        <Run Name="syn_1" Type="Synthesis" ConstraintSet="constraint_1" Description="" Active="true">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
    </Runs>
    <Project_Settings>
    </Project_Settings>
</Project>
