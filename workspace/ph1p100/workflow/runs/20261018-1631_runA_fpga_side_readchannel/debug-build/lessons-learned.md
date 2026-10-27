# Lessons — T11.runB-debug-build

1. **Debug wrapper must not change the top-level hierarchy.** Adding `u_top`
   silently invalidated every absolute SDC path (`u_pcie_pll_ep/...`,
   `u_csi_a/...`), so generated clocks and clock groups were not applied and the
   bit closed at -4.293 ns setup. Rule: any debug top must either preserve the
   original hierarchy or ship a matching SDC in the same commit; build logs must
   be scanned for "No clock match"/"Clock group is empty".
2. **`dbg_bank` is a dead concat.** It is defined but never used; only
   `dbg_bank_word*` feed the read mux. Marking `dbg_bank` cannot work. Probe
   marks must target live nets (registered sources) or use a ChipWatcher IP.
3. **No mark_debug = no CWC.** `insert_debugger` logs KIT-2501 and
   `setup_debugger` exits without creating `cw/`. A P2-only build cannot invent
   probes; RTL must carry `(* mark_debug = "true" *)` or a CWC IP.
4. **ADC/SDC readers are line-oriented.** `if {[catch {...}]}` blocks are
   rejected ("not a valid ADC command" / "missing close-brace"). Only single-line
   commands are accepted; use `set_property mark_debug "true" [get_nets ...]`.
5. **Preserve UTF-8 when copying TD tcl.** Converting the copied entry to ASCII
   can swallow the newline after a Chinese comment and silently drop the next
   `add_files` (cam_r10f_writer.v became a black box).
6. **PowerShell 5.1 script encoding matters.** Wrapper .ps1 files containing
   Chinese paths must be UTF-8 with BOM; no-BOM scripts misread the path and exit
   silently.
7. **TD CLI script args need forward slashes.** Backslashes are eaten by Tcl
   (`C:Users...`); pass `C:/...` or a relative filename.
8. **Budget note:** four preflight aborts (<25 s) were spent on recipe/tool
   syntax, not on the frozen design. Only one full 30-min-class build was run
   (prj_frozen, 637 s); the G2 outcome is a design/scope issue, not a build
   timeout.
