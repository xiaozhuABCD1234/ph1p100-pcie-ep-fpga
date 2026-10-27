quit -sim

if [file exists work] { 
    file delete -force work 
    } 

if {![file exists work]} { 
    vlib work 
    }

vlog -sv +define+PH1P_HXT_FAST_SIM +define+FAST_SIM +define+SIM_FSDB +incdir+../../Rtl/common/ +incdir+../tb/ +incdir+../../Rtl/common/ -f ../tb/pcie_subsystem_ae_sim.f

# -----------------------------------------------------
# Start evaluation test 
# -----------------------------------------------------
vsim -pli novas_fli.so -t 1fs -suppress 3015 -suppress 2685 -suppress 2912 -suppress 2718  -suppress 8604 -suppress 8630 -suppress 2241 -suppress 2250 -suppress 2958 -suppress 2182 -suppress 2697 -suppress 2122 -suppress 1692 +nospecify -vopt -voptargs="+noacc" -nowlfopt -l log.txt pcie_subsystem_tb

# -----------------------------------------------------
# View the simulation results 
# -----------------------------------------------------
# View the simulation results 
view structure 
view signals 
view wave
run -all
