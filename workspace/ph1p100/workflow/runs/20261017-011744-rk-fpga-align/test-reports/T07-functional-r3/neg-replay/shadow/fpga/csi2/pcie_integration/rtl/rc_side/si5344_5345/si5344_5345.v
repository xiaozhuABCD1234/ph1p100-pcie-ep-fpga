`timescale 1ns/1ns

module si5344_si5345(
    input   wire    clk,
//    input   wire    rst_n,

    output  wire  SI5345_FINC   , //step-up the output frequency
    output  wire  SI5345_FDEC   , //step-down the output frequency  
    output  wire  SI5345_OEB    , //This pin disables all outputs when held high.
    output  wire  SI5345_RSTB_N , //Active low input that performs power-on reset (POR) of the device.
    inout   wire  SI5345_SCK_O  , //This pin functions as the serial clock input for I2C
    inout   wire  SI5345_SDA_IO   //This is the bidirectional data pin (SDA) for the I2C mode
    
    
);
parameter   CLK_FRE        = 50_000_000;

localparam  CLK_UNIT      = 1_000_000_000/CLK_FRE;
localparam  NUM           = 2621400/CLK_UNIT; 

assign      SI5345_FINC     = 0;//
assign      SI5345_FDEC     = 0;//
assign      SI5345_OEB      = 0;//
assign 	    SI5345_RSTB_N = 1;
 
//-----------------------------------------------------------       
//初始化复位模块
//----------------------------------------------------------- 
wire        rst_n;
count_rst_n#
(
	.num 		(16'hffff			)//2.6ms
)u1_count_rst_n
(
	.clk_i		(clk				),
	.rst_o		(rst_n				)
);

soft_ps_wrapper#(
    .SYSCLK               ( 50_000_000           ),
    .DEV_SERIES           ( "PH1"                ),
    .CORE_TYPE            ( "MEDIUM"             ),
    .TCM0_SIZE            ( 32*1024              ),
    .TCM0_INITFILE        ( "NCS23345_IIC.bin.mif" ),
    .TCM0_RAMSTYLE        ( "20K"                ),
    .UART1_BAUDRATE       ( 115200               ),
    .MTIME_ENABLE         ( 1'b0                 ),
    .GPIO_PINNUM          ( 32                   ),
    .GPIO_INTENABLE       ( 1'b1                 ),
    .GPIO_INTCFG          ( {45'h0,3'b101,48'h0} )
)u_soft_ps_wrapper(
    .I_clk                ( clk            ),
    .I_rst                ( !rst_n          ),

    .IO_i2c_scl           (SI5345_SCK_O 		 ),
    .IO_i2c_sda           (SI5345_SDA_IO  		 ) 
);

endmodule
 
 
