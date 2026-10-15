//`defineNONE_PARI
`define PARI
    `ifdef PARI
        `define ODD
//`defineEVEN
    `endif

module uart_tx_setting
(
    input  wire clk,//25M系统时钟
    input  wire rst_n,//复位
    input  wire[7:0] data,//串口待发送的8位数据
    input  wire x_int,//接收到数据过程标志
    input  wire clk_bps,//bps时钟
    output wire uart_tx,
    output wire bps_start,//bps初始
    output wire tx_ready
);
//-------------------------------------------------------------------------
//变量定义
//-------------------------------------------------------------------------
reg x_int0,x_int1,x_int2;//x_int打拍
wire neg_x_int;//x_int接收完成1-0状态，寻找下降沿
always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    begin
        x_int0<=1'b0;
        x_int1<=1'b0;
        x_int2<=1'b0;
    end
    else
    begin
        x_int0<=x_int;
        x_int1<=x_int0;
        x_int2<=x_int1;
    end
end

assign neg_x_int=~x_int1&x_int2;//接收完成标志
//---------------------------------------------------------
reg[7:0]tx_data;//���������ݵļĴ���
reg bps_start_r;
reg tx_en;//��������ʹ���źţ�����Ч
reg[3:0]num;

`ifdef NONE_PARI
always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    begin
        bps_start_r<=1'b0;
        tx_en<=1'b0;
        tx_data<=8'd0;
    end
    else if(neg_x_int)
    begin//接收完成后
        bps_start_r<=1'b1;//发送模块bps时钟起开始工作，
        tx_data<=data;//将数据发给tx——data待发送
        tx_en<=1'b1;//发送过程中tx——en拉高，
    end
    else if(num==4'd11)
    begin//发送完成，拉低
        bps_start_r<=1'b0;
        tx_en<=1'b0;
    end
end

assign bps_start=bps_start_r;

//---------------------------------------------------------
reg uart_tx_r;
always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    begin
        num<=4'd0;
        uart_tx_r<=1'b1;
    end
    else if(tx_en)
    begin
        if(clk_bps)
        begin
            num<=num+1'b1;
            case(num)
                4'd0:uart_tx_r<=1'b0;//起始位
                4'd1:uart_tx_r<=tx_data[0];//bit0
                4'd2:uart_tx_r<=tx_data[1];//bit1
                4'd3:uart_tx_r<=tx_data[2];//bit2
                4'd4:uart_tx_r<=tx_data[3];//bit3
                4'd5:uart_tx_r<=tx_data[4];//bit4
                4'd6:uart_tx_r<=tx_data[5];//bit5
                4'd7:uart_tx_r<=tx_data[6];//bit6
                4'd8:uart_tx_r<=tx_data[7];//bit7
                4'd9:uart_tx_r<=1'b1;//停止位
                default:uart_tx_r<=1'b1;
            endcase
        end
    else if(num==4'd11)
        num<=4'd0;
    end
end
`endif
`ifdef PARI

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    begin
        bps_start_r<=1'b0;
        tx_en<=1'b0;
        tx_data<=8'd0;
    end
    else if(neg_x_int)
    begin//接收完成后
        bps_start_r<=1'b1;//发送模块bps时钟起开始工作，
        tx_data<=data;//将数据发给tx——data待发送
        tx_en<=1'b1;//发送过程中tx——en拉高，
    end
    else if(num==4'd12)
    begin//发送完成，拉低
        bps_start_r<=1'b0;
        tx_en<=1'b0;
    end
end

assign bps_start=bps_start_r;

//---------------------------------------------------------
reg uart_tx_r;
always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    begin
        num<=4'd0;
        uart_tx_r<=1'b1;
    end
    else if(tx_en)
    begin
        if(clk_bps)
        begin
        num<=num+1'b1;
        case(num)
            4'd0:uart_tx_r<=1'b0;//起始位
            4'd1:uart_tx_r<=tx_data[0];//bit0
            4'd2:uart_tx_r<=tx_data[1];//bit1
            4'd3:uart_tx_r<=tx_data[2];//bit2
            4'd4:uart_tx_r<=tx_data[3];//bit3
            4'd5:uart_tx_r<=tx_data[4];//bit4
            4'd6:uart_tx_r<=tx_data[5];//bit5
            4'd7:uart_tx_r<=tx_data[6];//bit6
            4'd8:uart_tx_r<=tx_data[7];//bit7
            `ifdef ODD
            4'd9:uart_tx_r<=!(^tx_data);//奇
            `endif
            `ifdef EVEN
            4'd9:uart_tx_r=(^tx_data);//偶校验
            `endif
            4'd10:uart_tx_r<=1'b1;//停止位
            default:uart_tx_r<=1'b1;
        endcase
    end
    else if(num==4'd12)
        num<=4'd0;
    end
end

`endif
assign uart_tx=uart_tx_r;
assign tx_ready=!tx_en;

endmodule
