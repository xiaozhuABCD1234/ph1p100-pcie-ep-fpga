module slave_debug_hub (
    slave_clk, slave_control, slave_status, slave_behavior_clr, slave_rst,
	wakeup, jrst, jtck, jtdi, jtms, jscan, jshift, jupdate, slave_tms_o, slave_tdi_o, slave_jtdo
);

    localparam MAX_CTRL_WIDTH = 672;
	localparam MAX_STAT_WIDTH = 24;
	localparam SLAVE_NUM      = 1;
	localparam LUT1_NUM       = 0;

	localparam [2:0]                SLAVE_ID[0:SLAVE_NUM-1]              = '{0};
	localparam [5:0]                SLAVE_SEL_VAL[0:SLAVE_NUM-1]         = '{0};
	localparam integer              SLAVE_CTRL_LEN[0:SLAVE_NUM-1]        = '{672};
	localparam integer              SLAVE_STAT_LEN[0:SLAVE_NUM-1]        = '{24};
	localparam [0:0]                SLAVE_PWR_ON_EXIST[0:SLAVE_NUM-1]    = '{0};
	localparam [MAX_CTRL_WIDTH-1:0] SLAVE_PWR_ON_CTRL_REG[0:SLAVE_NUM-1] = '{0};

    input		[0:SLAVE_NUM-1]							slave_clk;
	output reg 	[0:SLAVE_NUM-1] [MAX_CTRL_WIDTH-1:0]	slave_control;		//slave_i_clk domain
	input	 	[0:SLAVE_NUM-1] [MAX_STAT_WIDTH-1:0]	slave_status;		//slave_i_clk domain
	output      [0:SLAVE_NUM-1]        					slave_behavior_clr; //if slave_0 is vpi,to reset input bus activity; else floating
	output      [0:SLAVE_NUM-1]          				slave_rst;          //jrst syn to slave_0_clk domain
	
//-------------------------------------cfg interface-----------------------------------
    input		  wakeup;	//for cwc_pwr_on_trigger rst
	input         jrst;
    input         jtck;
    input         jtdi;
    input         jtms;
    input [1:0]   jscan;
    input         jshift;
    input         jupdate;
    output        slave_tms_o;
    output        slave_tdi_o;
    output [1:0]  slave_jtdo;

	top_debug_hub #(
		.MAX_CTRL_WIDTH(MAX_CTRL_WIDTH),
		.MAX_STAT_WIDTH(MAX_STAT_WIDTH),
		.SLAVE_NUM(SLAVE_NUM),
		.LUT1_NUM(LUT1_NUM),
		.SLAVE_ID(SLAVE_ID),
		.SLAVE_SEL_VAL(SLAVE_SEL_VAL),
		.SLAVE_CTRL_LEN(SLAVE_CTRL_LEN),
		.SLAVE_STAT_LEN(SLAVE_STAT_LEN),
		.SLAVE_PWR_ON_EXIST(SLAVE_PWR_ON_EXIST),
		.SLAVE_PWR_ON_CTRL_REG(SLAVE_PWR_ON_CTRL_REG)
	) u_debughub (
		.slave_clk(slave_clk),
		.slave_control(slave_control),
		.slave_status(slave_status),
		.slave_behavior_clr(slave_behavior_clr),
		.slave_rst(slave_rst),
		.wakeup(wakeup),
		.jrst(jrst),
		.jtck(jtck),
		.jtdi(jtdi),
		.jtms(jtms),
		.jscan(jscan),
		.jshift(jshift),
		.jupdate(jupdate),
		.slave_tms_o(slave_tms_o),
		.slave_tdi_o(slave_tdi_o),
		.slave_jtdo(slave_jtdo)
	);
endmodule

