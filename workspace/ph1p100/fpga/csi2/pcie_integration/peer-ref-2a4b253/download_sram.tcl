set ROOT [file normalize [file dirname [info script]]]
# =============================================================================
#  下载到 SRAM（易失，掉电即失；不碰 flash）
#    -mode jtag = PROGRAM_SRAM（直接配置 FPGA）
#    写 flash 才是 -mode program_spi —— 本脚本故意不用
#  用法：/opt/anlogic/TD_Release_2026.2_NL/bin/bw.sh download_sram.tcl
#  前置：/opt/anlogic/TD_Release_2026.2_NL/bin/hwserver -r -s 5555 -f 12 -v -w 5556 -i 0 已在跑
# =============================================================================

set bit_file $ROOT/ph1p_pcie_ep_top_Runs/best_result/ph1p_pcie_ep_top.bit
set srv 127.0.0.1:5555
set args_s {-r -s 5555 -f 12 -v -w 5556 -i 0}
set ok 0

if {![catch {connect_cable -host_name $srv -usr_args [list $args_s] -open} err]} {
    puts "连接方式1 成功: -usr_args 列表"
    set ok 1
} else {
    puts "连接方式1 失败: $err"
}

if {!$ok} {
    if {![catch {connect_cable -host_name $srv -open} err]} {
        puts "连接方式2 成功: 只给 host_name"
        set ok 1
    } else {
        puts "连接方式2 失败: $err"
    }
}

if {!$ok} {
    if {![catch {connect_cable -allink -open} err]} {
        puts "连接方式3 成功: -allink"
        set ok 1
    } else {
        puts "连接方式3 失败: $err"
    }
}

puts "cable_connected=$ok"

if {$ok} {
    download -bit $bit_file -mode jtag -spd 7 -cable 0
}

exit
