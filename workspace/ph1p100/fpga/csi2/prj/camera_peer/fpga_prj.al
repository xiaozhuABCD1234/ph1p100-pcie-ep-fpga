<?xml version="1.0" encoding="UTF-8"?>
<Project Version="3" Minor="2" Path="D:/TD/work/csi2/prj/camera_peer/.">
    <Project_Created_Time></Project_Created_Time>
    <TD_Encoding>UTF-8</TD_Encoding>
    <TD_Version>6.2.200067</TD_Version>
    <UCode>01100110</UCode>
    <Name>fpga_prj</Name>
    <HardWare>
        <Family>PH1</Family>
        <Device>PH1P100SBG484</Device>
        <Speed>-3</Speed>
    </HardWare>
    <Source_Files>
        <Verilog>
            <File Path="uisrc/03_ip/mipi_phy_ph1p/rx_phy_ph1p.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="2"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/mipi_csi_2/csi_rx_hdr_ecc.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="3"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/mipi_csi_2/csi_rx_byte_align.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="4"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/mipi_csi_2/csi_rx_clock_det.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="5"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/mipi_csi_2/auto_delay_ctl.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="7"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/mipi_csi_2/csi_rx_word_align.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="6"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/mipi_csi_2/csi_rx_word_gear_box.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="8"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/mipi_csi_2/csi_rx_packet_handler.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="9"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/mipi_csi_2/csi_rx_10bit_unpack.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="10"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/mipi_csi_2/sfifo.v">
                <FileInfo>
                    <Attr Name="AutoExcluded" Val="true"/>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="11"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/mipi_csi_2/wfifo.v">
                <FileInfo>
                    <Attr Name="AutoExcluded" Val="true"/>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="12"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/mipi_csi_2/mipi_csi2_rx_ph1p.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="13"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/ui_imx415_cfg/ui_i2c.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="15"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/ui_imx415_cfg/ui_imx415_reg.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="14"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/ui_imx415_cfg/ui_cfg_imx415.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="16"/>
                </FileInfo>
            </File>
            <File Path="uisrc/01_rtl/uart_tx.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="17"/>
                </FileInfo>
            </File>
            <File Path="uisrc/01_rtl/pulse2toggle.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="19"/>
                </FileInfo>
            </File>
            <File Path="uisrc/01_rtl/clk_activity.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="21"/>
                </FileInfo>
            </File>
            <File Path="uisrc/01_rtl/dbg_uart.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="18"/>
                </FileInfo>
            </File>
            <File Path="uisrc/01_rtl/f9p_imx415x2_top.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="20"/>
                </FileInfo>
            </File>
            <File Path="uisrc/01_rtl/cam_preview.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="22"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/vtc/uivtc.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="23"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/tpg/uitpg.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="24"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/alip/ui_HDMI_TX/ui_HDMI_TX.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="25"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/alip/ui_HDMI_TX/hdmi_phy_warpper.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="26"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/alip/ui_HDMI_TX/lane_lvds_10_1.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="27"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/alip/ui_HDMI_TX/hdmi_tx_controller_wrapper.enc.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="28"/>
                </FileInfo>
            </File>
            <File Path="uisrc/01_rtl/raw10_display60_clocks.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="30"/>
                </FileInfo>
            </File>
            <File Path="uisrc/01_rtl/camera_startup.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="31"/>
                </FileInfo>
            </File>
        </Verilog>
        <ADC_FILE>
            <File Path="uisrc/04_pin/fep_vid006_imx415.adc">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="constraint_1"/>
                    <Attr Name="CompileOrder" Val="1"/>
                </FileInfo>
            </File>
        </ADC_FILE>
        <SDC_FILE>
            <File Path="uisrc/04_pin/timing.sdc">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="constraint_1"/>
                    <Attr Name="CompileOrder" Val="2"/>
                </FileInfo>
            </File>
        </SDC_FILE>
        <IP_FILE>
            <File Path="uisrc/03_ip/ui_pll/ui_pll.xml">
                <FileInfo>
                    <Attr Name="AutoExcluded" Val="true"/>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="1"/>
                </FileInfo>
            </File>
            <File Path="uisrc/03_ip/raw10_clocks/raw10_clocks.xml">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="29"/>
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
        <LABEL>f9p_imx415x2_top</LABEL>
        <MODULE>f9p_imx415x2_top</MODULE>
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
                <BitgenProperty::GeneralOption>
                    <compress>on</compress>
                </BitgenProperty::GeneralOption>
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_fix_1" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_fix_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_fix_1">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_fix_2" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_fix_2" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_fix_2">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_fix_3" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_fix_3" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_fix_3">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_pad_1" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_pad_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_pad_1">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_seq_20261010_203628" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_seq_20261010_203628" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_seq_20261010_203628">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_stable_20261010_231329" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_stable_20261010_231329" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_stable_20261010_231329">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_stable_20261010_231430" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_stable_20261010_231430" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_stable_20261010_231430">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_stable_20261010_232220" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_stable_20261010_232220" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_stable_20261010_232220">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_stable_20261010_232444" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_stable_20261010_232444" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_stable_20261010_232444">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_stable_20261010_233724" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_stable_20261010_233724" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_stable_20261010_233724">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_stable_20261010_234257" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_stable_20261010_234257" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_stable_20261010_234257">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_display60_20261011_174124" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_display60_20261011_174124" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_display60_20261011_174124">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="syn_display60_20261011_174231" Type="Synthesis" ConstraintSet="constraint_1" Description="">
            <Strategy Name="Default_Synthesis_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_display60_20261011_174231" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_display60_20261011_174231">
            <Strategy Name="Default_PhysicalDesign_Strategy">
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
    </Runs>
    <Project_Settings>
    </Project_Settings>
</Project>
