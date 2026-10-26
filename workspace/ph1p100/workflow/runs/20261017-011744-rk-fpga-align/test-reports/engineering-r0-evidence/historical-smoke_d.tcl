# T01.tool-D smoke step D: full flow in a fresh session:
# open_project -> load_project_ips (re-register from ip xml) -> set_property ->
# generate_target. This is the corrected full headless create/set/generate flow.
puts "SMOKE_D_BEGIN"
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    open_project ./td2026_smoke.al
    set lr [catch { load_project_ips } lmsg]
    puts "LOAD2_RC:$lr"
    puts "LOAD2_MSG:$lmsg"
    puts "IPS_BEFORE:[get_ips]"
    set sr [catch { set_property CONFIG.AL_GPIO_WD 8 [get_ips apb_gpio_0] } smsg]
    puts "SETPROP_RC:$sr"
    puts "SETPROP_MSG:$smsg"
    set gr [catch { generate_target [get_ips apb_gpio_0] } gmsg]
    puts "GENTARGET_RC:$gr"
    puts "GENTARGET_MSG:$gmsg"
    puts "IPS_AFTER:[get_ips]"
    close_project
} msg]} {
    puts "SMOKE_D_ERROR: $msg"
    exit 1
}
puts "SMOKE_D_DONE"
exit 0
