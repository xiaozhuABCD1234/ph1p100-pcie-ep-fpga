
.PHONY: run_vcs run_verdi run_gui clean 


#***************************************#
# parameter input
#***************************************#
SRC_LIST    =   ../tb/pcie_subsystem_ae_sim.f
SIMV_NAME   =   simv
VPD_NAME    =   $(SIMV_NAME).vpd
TOP         =   pcie_subsystem_tb
INC_DIR     =   +incdir+../Rtl/common         \
                +incdir+../tb                 \
                +incdir+../Rtl/rc_side        \
                +incdir+../Rtl/ep_side         
ALL_DEFINE  =   +define+BINMODE+SIM_FSDB+FAST_SIM+PH1P_HXT_FAST_SIM	  \
#***************************************#
#verdi dump wave compile option
#***************************************#
VERDI_PATH    =    -P     $(VERDI_HOME)/share/PLI/VCS/linux64/novas.tab \
                          $(VERDI_HOME)/share/PLI/VCS/linux64/pli.a     


#***************************************#
# do not modify below
#			+vcs+stop+300us                 \
#			+vcs+finish+300us               \
#***************************************#



RUN_VCS        =    vcs                            	\
                	-full64 +v2k -sverilog         	\
                	+vc                       	\
                	-debug_all               	\
                	-notice                        	\
                	-Mupdate                    	\
                	+notimingcheck                 	\
                	-kdb -lca                       \
                   	+nospecify                    	\
                	+LDFLAGS                    	\
                	-timescale=1ns/1ps            	\
                	-f $(SRC_LIST)                	\
                	-o $(SIMV_NAME)                	\
                	-top $(TOP)                    	\
                	$(INC_DIR)                    	\
                	$(ALL_DEFINE)                
	

# when used dev, auto recode vpd file
ADD_GUI      =    +define+SIM_VPD  -R -gui  +autoflush +vpdfile+$(VPD_NAME) -l run_gui.log &
ADD_VERDI    =    +define+SIM_FSDB -R +fsdb +autoflush -l run_verdi.log 

all:     run_vcs    run_verdi 

run_vcs:
	$(RUN_VCS) $(VERDI_PATH) $(ADD_VERDI)

#run_verdi:
#    ./$(SIMV_NAME) -verdi -sswr ./signal.rc \
#    +vcs+initmem+0                            \
#    run 1000us    

run_verdi:
	verdi -ssf $(TOP).fsdb -sswr ./signal.rc \
    -nologo    -l verdi.log &

run_gui:
	$(RUN_VCS) $(ADD_GUI)

clean:
	rm -rf ./verdiLog rm -rf ./csrc rm -rf ./DVEfiles rm -rf *.vpd rm -rf *.key rm -rf novas.* rm -rf *.log rm -rf $(SIMV_NAME)* rm -rf *.fsdb

