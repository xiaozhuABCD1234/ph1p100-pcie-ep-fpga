//`defineNONE_PARI
`define PARI
    `ifdef PARI
        `define ODD
//`defineEVEN
    `endif
module uart_rx_setting
(
    input  wire clk,//25M系统时钟
    input  wire rst_n,//复位
    input  wire uart_rx,//串口接收到的bit数据

    input  wire clk_bps,//bps时钟
    output wire[7:0] rx_data,//串口接收到的bit数据转换为8位数据
    output wire rx_en,//接收数据过程标志
    output wire bps_start//bps初始
);
//-------------------------------------------------------------------------
//变量定义
//-------------------------------------------------------------------------
reg uart_rx0,uart_rx1,uart_rx2,uart_rx3;//bit数据缓存打拍查找起始位
reg bps_start_r;//bps开始缓存
reg[3:0]num;//8位计数
reg rx_int;
reg[7:0]rx_data_r;//rx_data缓存

reg[8:0]rx_temp_data;//8位串并转换中间寄存

reg crc_r;
reg finish;
wire rx_data_crc;
reg err_flag;
wire neg_uart_rx;//起始位标志
//---------------------------/*检测串口数据下降沿*/-------------------------
always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    begin
        uart_rx0<=1'b0;
        uart_rx1<=1'b0;
        uart_rx2<=1'b0;
        uart_rx3<=1'b0;
    end
    else
    begin
        uart_rx0<=uart_rx;
        uart_rx1<=uart_rx0;
        uart_rx2<=uart_rx1;
        uart_rx3<=uart_rx2;
    end
end

assign neg_uart_rx=uart_rx3&uart_rx2&~uart_rx1&~uart_rx0;//synthesiskeep//找到起始位
//---------------------------/*生成转换标志信号*/-------------------------
`ifdef PARI
always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    begin
        bps_start_r<=1'b0;
        rx_int<=1'b0;
    end
    else if(neg_uart_rx)
    begin//检测到起始位后
        bps_start_r<=1'b1;//数据bps数据clk生成状态start信号拉高，同时在转换过程持续拉高
        rx_int<=1'b1;//接收过程
    end
    else if(num==4'd11)
    begin//接收完8位数据后，在第九拍
        bps_start_r<=1'b0;//bpsclk停止工作
        rx_int<=1'b0;//接收完成
    end
    else
    begin
        bps_start_r<=bps_start_r;
        rx_int<=rx_int;
    end
end
assign bps_start=bps_start_r;

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    begin
        rx_temp_data<=9'd0;
        num<=4'd0;
        rx_data_r<=8'd0;
        crc_r<=1'd0;
    end
    else if(rx_int)//接收信号过程
    begin
        if(clk_bps)//以clk_bps为时钟，num变化，即实现按照波特率的解析
        begin
            num<=num+1'b1;//先加1，在case语句内部，num直接从1开始执行
            case(num)
                4'd1:rx_temp_data[0]<=uart_rx3;//0bit
                4'd2:rx_temp_data[1]<=uart_rx3;//1bit
                4'd3:rx_temp_data[2]<=uart_rx3;//2bit
                4'd4:rx_temp_data[3]<=uart_rx3;//3bit
                4'd5:rx_temp_data[4]<=uart_rx3;//4bit
                4'd6:rx_temp_data[5]<=uart_rx3;//5bit
                4'd7:rx_temp_data[6]<=uart_rx3;//6bit
                4'd8:rx_temp_data[7]<=uart_rx3;//7bit
                4'd9:rx_temp_data[8]<=uart_rx3;
                default:;
             endcase
        end
        else if(num==4'd11)
        begin
            num<=4'd0;//STOP，num初始化，等待下一次数据接收
            rx_data_r<=rx_temp_data[7:0];//缓存rx_data
            crc_r<=rx_temp_data[8];
            finish<=1'b1;
        end
    end
    else begin
        rx_data_r<=rx_data_r;
        crc_r<=crc_r;
        finish<=1'b0;
    end
end
`ifdef ODD
assign rx_data_crc=!(^rx_data_r);//奇
`endif
`ifdef EVEN
assign rx_data_crc=(^rx_data_r);//偶校验
`endif
always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    begin
        err_flag<=1'b0;
    end
    else
    begin
        if(finish)
        begin
            if(rx_data_crc==crc_r)
                err_flag<=1'b0;
            else
                err_flag<=1'b1;
        end 
        else
            err_flag<=err_flag;
    end
end
assign rx_data=err_flag?(8'd0):(rx_data_r);
assign rx_en=finish;
`endif
`ifdef NONE_PARI
always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    begin
        bps_start_r<=1'b0;
        rx_int<=1'b0;
    end
    else if(neg_uart_rx)
    begin//检测到起始位后
        bps_start_r<=1'b1;//数据bps数据clk生成状态start信号拉高，同时在转换过程持续拉高
        rx_int<=1'b1;//接收过程
    end
    else if(num==4'd10)
    begin//接收完8位数据后，在第九拍
        bps_start_r<=1'b0;//bpsclk停止工作
        rx_int<=1'b0;//接收完成
    end
    else
    begin
        bps_start_r<=bps_start_r;
        rx_int<=rx_int;
    end
end
assign bps_start=bps_start_r;

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    begin
        rx_temp_data<=9'd0;
        num<=4'd0;
        rx_data_r<=8'd0;
    end
    else if(rx_int)//接收信号过程
    begin
        if(clk_bps)//以clk_bps为时钟，num变化，即实现按照波特率的解析
        begin
            num<=num+1'b1;//先加1，在case语句内部，num直接从1开始执行
            case(num)
                 4'd1:rx_temp_data[0]<=uart_rx3;//0bit
                 4'd2:rx_temp_data[1]<=uart_rx3;//1bit
                 4'd3:rx_temp_data[2]<=uart_rx3;//2bit
                 4'd4:rx_temp_data[3]<=uart_rx3;//3bit
                 4'd5:rx_temp_data[4]<=uart_rx3;//4bit
                 4'd6:rx_temp_data[5]<=uart_rx3;//5bit
                 4'd7:rx_temp_data[6]<=uart_rx3;//6bit
                 4'd8:rx_temp_data[7]<=uart_rx3;//7bit
                 default:;
            endcase
        end
        else if(num==4'd10)
        begin
            num<=4'd0;//STOP，num初始化，等待下一次数据接收
            rx_data_r<=rx_temp_data;//缓存rx_data
            finish<=1'b1;
        end
    end
    else begin
        finish<=1'b0;
        rx_data_r<=rx_data_r;
    end
end

assign rx_data=rx_data_r;
assign rx_en=finish;

`endif


endmodule
