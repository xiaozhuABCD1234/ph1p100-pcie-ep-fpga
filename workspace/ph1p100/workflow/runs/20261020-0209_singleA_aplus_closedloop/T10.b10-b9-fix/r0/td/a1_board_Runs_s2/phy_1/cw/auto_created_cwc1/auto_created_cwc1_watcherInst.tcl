source "D:/anlogic/TD_Release_2026.2/cw/atpl/templa.tcl"
set fd [open "D:/anlogic/TD_Release_2026.2/cw/atpl/cwc.atpl" r]
set tmpl [read $fd]
close $fd
set parser [::tmpl_parser::tmpl_parser $tmpl]

set ComponentName        {auto_created_cwc1}
set bus_num              {10}
set cwc_ctrl_len         {672}
set cwc_bus_ctrl_len     {616}
set bus_din_num          {288}
set ram_len              {288}
set input_pipe_num       {0}
set output_pipe_num      {0}
set depth                {1024}
set capture_ctrl_exist   {0}
set trig_in_exist        {0}
set trig_out_exist       {0}
set trig_bit_exist       {0}
set bus_width            {32,16,16,32,32,32,32,32,32,32}
set bus_din_pos          {0,32,48,64,96,128,160,192,224,256}
set bus_ctrl_pos         {0,68,104,140,208,276,344,412,480,548}
set fp [open "cw/auto_created_cwc1/auto_created_cwc1_watcherInst.sv" w+]
puts $fp [eval $parser]
close $fp
