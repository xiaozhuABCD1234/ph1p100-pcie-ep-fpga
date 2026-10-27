
module ubus_model
#(
	parameter BAUDRATE = 115200,
	parameter CLK_RATE = 50000000
)
(
    clk, 
	rst_n,
	// UART
	txd,
	rxd
   );

    input           clk;
	input			rst_n;
	output          txd;
	input           rxd;
// ====================================================================
// Parameter/wire/reg
// ====================================================================
	reg         tx_en ;
	reg   [7:0] tx_data ;
	wire        tx_ready ;
	wire        rx_en ;
	wire  [7:0] rx_data ;

	localparam	HEAD_0 = "A",
				HEAD_1 = "B",
				HEAD_2 = "C",
				HEAD_3 = "D",
				HEAD_4 = "E",
				HEAD_5 = "F";

// ===========================================================================
// Start of BFM
// ===========================================================================

// UBUS Intialization
initial
	begin
    tx_en = 0;
	tx_data = 0;
	end

// tx a byte
task tx_byte;
	input  [7:0]   data;
	
	begin
	wait (tx_ready);
	@(posedge clk);
	tx_en = 1;
	tx_data = data;
	@(posedge clk);
	tx_en = 0;
	@(posedge clk);
	while(~tx_ready) 
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	end
endtask

// write
task ubus_wr;
	input  [31:0]   address;
	input  [31:0]   data;
	
	begin
	tx_byte(HEAD_0);
	tx_byte(HEAD_1);
	tx_byte(HEAD_2);
	tx_byte(HEAD_3);
	tx_byte(HEAD_4);
	tx_byte(HEAD_5);
	tx_byte(address[31:24]);
	tx_byte(address[23:16]);
	tx_byte(address[15: 8]);
	tx_byte(address[ 7: 0]);
	tx_byte(data[31:24]);
	tx_byte(data[23:16]);
	tx_byte(data[15: 8]);
	tx_byte(data[ 7: 0]);
	end
endtask

// rx a byte
task rx_byte;
	output  [7:0]   data;
	
	begin
	@(posedge clk);
	while(~rx_en) @(posedge clk);
	data = rx_data;
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	@(posedge clk);
	end
endtask

// read
task ubus_rd;
	input  [31:0]   address;
	output [31:0]   data;
	
	begin
	// tx
	tx_byte(HEAD_5);
	tx_byte(HEAD_4);
	tx_byte(HEAD_3);
	tx_byte(HEAD_2);
	tx_byte(HEAD_1);
	tx_byte(HEAD_0);
	tx_byte(address[31:24]);
	tx_byte(address[23:16]);
	tx_byte(address[15: 8]);
	tx_byte(address[ 7: 0]);
	tx_byte(0);
	tx_byte(0);
	tx_byte(0);
	tx_byte(0);
	// rx
	rx_byte(data[ 7: 0]);
	rx_byte(data[ 7: 0]);
	rx_byte(data[ 7: 0]);
	rx_byte(data[ 7: 0]);
	rx_byte(data[ 7: 0]);
	rx_byte(data[ 7: 0]);
	rx_byte(data[ 7: 0]);
	rx_byte(data[ 7: 0]);
	rx_byte(data[ 7: 0]);
	rx_byte(data[ 7: 0]);
    
	rx_byte(data[31:24]);
	rx_byte(data[23:16]);
	rx_byte(data[15: 8]);
	rx_byte(data[ 7: 0]);
	end
endtask

// --------------------------------------------------------------------
// UART INST
// --------------------------------------------------------------------

bps_setting
#(
    	.BPS_SET      	(	BAUDRATE			),    		//
		.CLK_PERIO		(	CLK_RATE			)
)
bps_rx(
		.clk			(	clk					),			//
		.rst_n			(	rst_n				),			//
		.clk_bps		(	clk_bps_rx			),			//
        .bps_start		(	bps_start_rx		)
);

bps_setting
#(
    	.BPS_SET      	(	BAUDRATE			),    		//
		.CLK_PERIO		(	CLK_RATE			)
)
bps_tx(
		.clk			(	clk					),			//
		.rst_n			(	rst_n				),			//
		.clk_bps		(	clk_bps_tx			),			//
        .bps_start		(	bps_start_tx		)
);	


uart_rx_setting uart_rx_setting_u
( 
		.clk			(	clk					),			//
		.rst_n			(	rst_n				),			//
		.uart_rx		(	rxd					),			//

		.rx_data		(	rx_data				),			//
		.rx_en			(	rx_en				),			//
		.clk_bps		(	clk_bps_rx			),			//
		.bps_start		(	bps_start_rx		)			//
);  



uart_tx_setting uart_tx_setting_u
(
		.clk			(	clk					),			//
		.rst_n			(	rst_n				),			//
		.data			(	tx_data				),			//
		.x_int			(	tx_en				),			//
		.clk_bps		(	clk_bps_tx			),			//
	    .uart_tx		(	txd					),
		.bps_start		(	bps_start_tx		),			//
        .tx_ready  		(	tx_ready     		)	
 );


endmodule
