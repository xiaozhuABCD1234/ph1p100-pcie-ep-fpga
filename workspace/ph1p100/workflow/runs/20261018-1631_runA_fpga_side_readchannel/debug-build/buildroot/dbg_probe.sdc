# T11.runB-debug-build: mark the frozen 288-bit debug bank for ChipWatcher.
# Debug-only SYN attribute; no functional logic change. TD infers the trigger clock.
if {[catch {
  set t11_nets [get_nets -quiet {*/u_ep_bar_win/dbg_bank}]
  if {[llength $t11_nets] > 0} {
    set_property mark_debug "true" $t11_nets
    puts "T11_DBG_MARK_OK: [llength $t11_nets] net(s) dbg_bank marked"
  } else {
    puts "T11_DBG_MARK_MISS: dbg_bank not found"
  }
} t11_err]} { puts "T11_DBG_MARK_ERROR: $t11_err" }