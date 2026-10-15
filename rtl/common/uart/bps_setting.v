module bps_setting
#(
    parameter BPS_SET      =  115200 ,//波特率
    parameter CLK_PERIO    =  20 
)
(
    input  wire clk,//25MHz系统时钟
    input  wire rst_n,//复位信号
    input  wire bps_start,//bps时钟开启信号
    output wire clk_bps//输出的clk_bps
);
`define BPS_PARA (1000000000 /CLK_PERIO/BPS_SET)//  25M/9600;
`define BPS_PARA_2 (`BPS_PARA/2)//BPS_PARA/2;


reg [12:0] cnt;//bpsclk生成计数
reg clk_bps_r;//bpsclk缓存

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        cnt <= 13'd0;
    else if(cnt == (`BPS_PARA)||(!bps_start) )
        cnt <= 13'd0;//初始化
    else
        cnt <= cnt + 1'b1;//计数
end        
//|| !bps_start
always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        clk_bps_r <= 1'b0;
    else if(cnt ==(`BPS_PARA_2))
        clk_bps_r <= 1'b1;//clk_bps_r 中间数据时钟
    else
        clk_bps_r <= 1'b0;
end 
assign clk_bps = clk_bps_r;
endmodule
