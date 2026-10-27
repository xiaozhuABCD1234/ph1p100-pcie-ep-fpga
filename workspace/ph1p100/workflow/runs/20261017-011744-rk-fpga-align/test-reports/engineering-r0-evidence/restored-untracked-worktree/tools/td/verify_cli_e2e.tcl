# TD CLI end-to-end scratch verification, stage 1: project creation + synthesis.
# Chain: import_device -> create_project -> add_files -> top_module ->
#        create_run (synthesis) -> launch_runs -> wait_run -> close_project.
# Scratch, non-production design. No bit generation, no download.
# Invocation (cwd must be the scratch project directory; TD requires './'):
#   D:/downlaod/bin/td_commands_prompt.exe ./verify_cli_e2e.tcl
if {[catch {
    import_device ph1_100p.db -package PH1P100SBG484 -speed 3
    create_project td_cli_e2e_counter ./ -family ph1 -device PH1P100SBG484 -speed -3
    add_files ./td_cli_e2e_counter.v
    add_files ./td_cli_e2e_counter.adc
    add_files ./td_cli_e2e_counter.sdc
    top_module td_cli_e2e_counter
    create_run -constrset constraint_1 syn_e2e_1
    puts "TD_CLI_E2E_SYN_RUN_CREATED syn_e2e_1"
    if {[catch {reset_runs syn_e2e_1} rmsg]} {
        puts "TD_CLI_E2E_RESET_RUNS_SKIPPED: $rmsg"
    } else {
        puts "TD_CLI_E2E_RESET_RUNS_OK syn_e2e_1"
    }
    launch_runs syn_e2e_1
    puts "TD_CLI_E2E_LAUNCH_RUNS_RETURNED syn_e2e_1"
    wait_run syn_e2e_1 -quiet
    close_project
    puts "TD_CLI_E2E_SYN_RETURNED"
} msg]} {
    puts stderr "TD_CLI_E2E_SYN_ERROR: $msg"
    exit 1
}
exit 0
