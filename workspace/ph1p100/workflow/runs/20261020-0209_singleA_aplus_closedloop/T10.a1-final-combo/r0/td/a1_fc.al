<?xml version="1.0" encoding="UTF-8"?>
<!-- Last modified by TangDynasty Release_2026.2 -->
<Project Version="3" Minor="2" Path="C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道/workflow/runs/20261020-0209_singleA_aplus_closedloop/T10.a1-final-combo/r0/td">
    <Project_Created_Time></Project_Created_Time>
    <TD_Version>6.2.3.210850</TD_Version>
    <Name>a1_fc</Name>
    <HardWare>
        <Family>PH1</Family>
        <Device>PH1P100SBG484</Device>
        <Speed>-3</Speed>
    </HardWare>
    <Source_Files>
        <Verilog>
            <File Path="Y:/upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_frame_top.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="1"/>
                </FileInfo>
            </File>
            <File Path="Y:/upstream/ph1p100-pcie-ep-fpga/rtl/ep_side/codec/a1_deflate_core.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="2"/>
                </FileInfo>
            </File>
            <File Path="./a1_eng_top.v">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="design_1"/>
                    <Attr Name="CompileOrder" Val="3"/>
                </FileInfo>
            </File>
        </Verilog>
        <SDC_FILE>
            <File Path="./a1_small_top.sdc">
                <FileInfo>
                    <Attr Name="UsedInSyn" Val="true"/>
                    <Attr Name="UsedInP&R" Val="true"/>
                    <Attr Name="BelongTo" Val="constraint_1"/>
                    <Attr Name="CompileOrder" Val="1"/>
                </FileInfo>
            </File>
        </SDC_FILE>
    </Source_Files>
    <FileSets>
        <FileSet Name="design_1" Type="DesignFiles">
        </FileSet>
        <FileSet Name="constraint_1" Type="ConstrainFiles">
        </FileSet>
    </FileSets>
    <TOP_MODULE>
        <LABEL></LABEL>
        <MODULE>a1_eng_top</MODULE>
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
                <RtlProperty>
                    <retiming>on</retiming>
                </RtlProperty>
            </Strategy>
            <UserParams>
            </UserParams>
        </Run>
        <Run Name="phy_1" Type="PhysicalDesign" ConstraintSet="constraint_1" Description="" SynRun="syn_1" Active="true">
            <Strategy Name="Default_PhysicalDesign_Strategy">
                <RouteProperty>
                    <post_route_opt>ultra</post_route_opt>
                </RouteProperty>
            </Strategy>
            <UserParams>
                <param>set_param route postrt_opt_loc 20</param>
                <param>set_param route postrt_opt_extra_round 4</param>
            </UserParams>
        </Run>
    </Runs>
    <Project_Settings>
    </Project_Settings>
</Project>
