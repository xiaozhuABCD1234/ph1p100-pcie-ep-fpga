source "D:/anlogic/TD_Release_2026.2/cw/atpl/templa.tcl"
set fd [open "D:/anlogic/TD_Release_2026.2/cw/atpl/debughub.atpl" r]
set tmpl [read $fd]
close $fd
set parser [::tmpl_parser::tmpl_parser $tmpl]

set model_name           {slave_debug_hub}
set max_ctrl_width       {672}
set max_stat_width       {24}
set slave_num            {1}
set lut1_num             {0}
set slave_id             {0}
set slave_sel_val        {0}
set slave_ctrl_len       {672}
set slave_stat_len       {24}
set slave_pwr_on_exist   {0}
set slave_pwr_on_ctrl_reg {0}
set fp [open "cw/debug_hub/debug_hub_wrapper.sv" w+]
puts $fp [eval $parser]
close $fp
