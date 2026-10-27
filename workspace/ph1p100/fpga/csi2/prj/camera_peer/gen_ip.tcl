# =============================================================================
# gen_ip.tcl — 生成两个 MIPI D-PHY RX IP（FEP-VID006-MIPI + 2x IMX415）
#   TD 的 set_property 参数顺序是  <value> <name> <object>   （与 Vivado 相反）
#   用法: td gen_ip.tcl
# =============================================================================
proc sp {v n o} {
    set rc [catch {set_property $v $n $o} e]
    set rv [catch {get_property $n $o} rb]
    puts [format "  %-34s <= %-14s rc=%d  readback=%s" $n $v $rc $rb]
}
proc gp {n o {d {}}} { set rc [catch {get_property $n $o} r]; return $r }

import_device ph1_100p.db -package PH1P100SBG484 -speed 3
open_project fpga_prj.al
load_project_ips
puts "#### IPs: [get_ips]"

foreach name {mipi_dphy_a mipi_dphy_b} {
    set ip [get_ips $name]
    puts "#### configure $name"
    sp RX                CONFIG.GUI_DATA_FLOW            $ip
    sp Normal(Core+Phy)  CONFIG.GUI_MIPI_MODE_SEL        $ip
    sp 4                 CONFIG.GUI_LANE_NUM             $ip
    sp 8                 CONFIG.GUI_LANE_BIT_WIDTH       $ip
    # 物理层：先试 Hard MIPI，不行就退回 LVDS（软 ISERDES）
    sp {Hard MIPI}       CONFIG.GUI_MIPI_PHY_TYPE        $ip
    set phy [gp CONFIG.GUI_MIPI_PHY_TYPE $ip]
    puts "  PHY_TYPE now = $phy"
    puts "  LVDS_IO_TYPE options -> [gp CONFIG.GUI_LVDS_IO_TYPE $ip]"
    puts "  DPHY_LOCATION options -> [gp CONFIG.GUI_DPHY_LOCATION $ip]"
    sp 891               CONFIG.GUI_MIPI_RX_LINE_RATE    $ip
    sp Continuous        CONFIG.GUI_CLK_LANE_MODE        $ip
    puts "#### generate_target $name"
    set rc [catch {generate_target all $ip} e]
    puts "  rc=$rc $e"
    puts "  files: [glob -nocomplain uisrc/03_ip/$name/*]"
}
puts "#### GEN DONE"
exit
