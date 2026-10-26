+define+DDRPHY_ROM_INIT='"<mis_path>/ddrmc_x32/src/rtl/phy/ddrphy_cfg_rom.txt"'

+incdir+<mis_path>/ddrmc_x32/src/rtl/include
+incdir+<mis_path>/ddrmc_x32/src/rtl/phy/include
+incdir+<mis_path>/ddrmc_x32/src/rtl/timing/ddr3

# MIS TOP
<mis_path>/ddrmc_x32/ddrmc_x32.v
<mis_path>/ddrmc_x32/ph1p_ddrmc_wrapper_ddrmc_x32.v

#DDRMC TOP
<mis_path>/ddrmc_x32/src/rtl/top/ph1p_ddrmc_top.v

# Clock Gen
<mis_path>/ddrmc_x32/src/rtl/clk/ph1p_ddrphy_clk_top.v
<mis_path>/ddrmc_x32/src/rtl/clk/ph1p_ddrphy_pll0.v
<mis_path>/ddrmc_x32/src/rtl/clk/ph1p_ddrphy_pll1.v

# CAL EN
<mis_path>/ddrmc_x32/src/rtl/cal/ph1p_ddrphy_cal_gate.v
<mis_path>/ddrmc_x32/src/rtl/cal/ph1p_ddrphy_cal_gate_wrapper.v
<mis_path>/ddrmc_x32/src/rtl/cal/ph1p_ddrphy_cal_wla.v
<mis_path>/ddrmc_x32/src/rtl/cal/ph1p_ddrphy_cal_wla_wrapper.v
<mis_path>/ddrmc_x32/src/rtl/cal/ph1p_ddrphy_cal_wrlvl.v
<mis_path>/ddrmc_x32/src/rtl/cal/ph1p_ddrphy_cal_wrlvl_wrapper.v
<mis_path>/ddrmc_x32/src/rtl/cal/ph1p_ddrphy_cal_wrapper.v

#DDRPHY
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_wrapper.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_apb_bridge.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_bankref_cfg.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_init.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_mdl_cal.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_mdl_cal_wrapper.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_fast_init.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_fast_init_wrapper.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_dcu.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_dcu_wrapper.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_wphase_ctl.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_rphase_ctl.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_cmd_decode.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_cmd_execution.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_cmd_wrapper.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_dbi_wrapper.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_rdbi.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_wdbi.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_byte_wrapper.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy.v
<mis_path>/ddrmc_x32/src/rtl/phy/ph1p_ddrphy_top.v

#INIT
<mis_path>/ddrmc_x32/src/rtl/init/ph1p_ddrphy_dram_init.v

#MISC
<mis_path>/ddrmc_x32/src/rtl/misc/ph1p_ddrphy_sync_rst_gen.v
<mis_path>/ddrmc_x32/src/rtl/misc/ph1p_ddr_fifo_dram_sync.v



 
#MC
<mis_path>/ddrmc_x32/src/rtl/mc/alc_phy2mc_fifo_ctrl.v
<mis_path>/ddrmc_x32/src/rtl/mc/mc0_alc_mc_top_all.enc.sv
