module uart_cdc(

    input  wire        aux_clk,
    input  wire        uart_axu_rst_n,
    input  wire        aux_rx_en,
    input  wire  [7:0] aux_rx_data,
    output reg         aux_tx_en,
    output reg   [7:0] aux_tx_data,
    input  wire        aux_tx_ready,

    input  wire        core_clk,
    input  wire        uart_core_rst_n,
    output reg         core_rx_en,
    output reg   [7:0] core_rx_data,
    input  wire        core_tx_en,
    input  wire  [7:0] core_tx_data,
    output reg         core_tx_ready

);

//-------------------------------------------------------------------------
//registerandsignaldefine
//-------------------------------------------------------------------------
reg aux_rx_en_f;
reg aux_rx_en_ack_1;
reg aux_rx_en_ack_2;
reg[7:0]aux_rx_data_r;
reg core_rx_en_f_1;
reg core_rx_en_f_2;
reg core_rx_en_ack;
reg core_rx_en_ack_r;
reg[7:0]core_rx_data_1;
reg[7:0]core_rx_data_2;


reg core_tx_en_f;
reg core_tx_en_ack_1;
reg core_tx_en_ack_2;
reg[7:0]core_tx_data_r;
reg aux_tx_en_f_1;
reg aux_tx_en_f_2;
reg aux_tx_en_ack;
reg aux_tx_en_ack_r;
reg[7:0]aux_tx_data_1;
reg[7:0]aux_tx_data_2;

reg core_tx_ready_1;
reg core_tx_ready_2;


//------RxPath,Fromaux_clktocore_clk
always@(posedge aux_clk or posedge uart_axu_rst_n)begin
    if(uart_axu_rst_n)
        aux_rx_en_f<=1'b0;
    else if(aux_rx_en)
        aux_rx_en_f<=1'b1;
    else if(aux_rx_en_ack_2)
        aux_rx_en_f<=1'b0;
end

always@(posedge aux_clk or posedge uart_axu_rst_n)begin
    if(uart_axu_rst_n)begin
        aux_rx_en_ack_1<=1'b0;
        aux_rx_en_ack_2<=1'b0;
    end else begin
        aux_rx_en_ack_1<=core_rx_en_ack;
        aux_rx_en_ack_2<=aux_rx_en_ack_1;
    end
end

always@(posedge aux_clk or posedge uart_axu_rst_n)begin
    if(uart_axu_rst_n)
        aux_rx_data_r<=8'd0;
    else if(aux_rx_en_f)
        aux_rx_data_r<=aux_rx_data;
end


always@(posedge core_clk or posedge uart_core_rst_n)begin
    if(uart_core_rst_n)begin
        core_rx_en_f_1<=1'b0;
        core_rx_en_f_2<=1'b0;
        core_rx_data_1<=1'b0;
        core_rx_data_2<=1'b0;
        core_rx_en_ack_r<=1'b0;
    end else begin
        core_rx_en_f_1<=aux_rx_en_f;
        core_rx_en_f_2<=core_rx_en_f_1;
        core_rx_data_1<=aux_rx_data_r;
        core_rx_data_2<=core_rx_data_1;
        core_rx_en_ack_r<=core_rx_en_ack;
    end
end

always@(posedge core_clk or posedge uart_core_rst_n)begin
    if(uart_core_rst_n)
        core_rx_en_ack<=1'b0;
    else if(core_rx_en_f_2)
        core_rx_en_ack<=1'b1;
    else
        core_rx_en_ack<=1'b0;
end

always@(posedge core_clk or posedge uart_core_rst_n)begin
    if(uart_core_rst_n)begin
        core_rx_en<=1'b0;
        core_rx_data<=8'd0;
    end else begin
        core_rx_en<=!core_rx_en_ack&core_rx_en_ack_r;//posedgedetect
        core_rx_data<=core_rx_data_2;
    end
end

//------TxPath,Fromcore_clktoaux_clk
always@(posedge core_clk or posedge uart_core_rst_n)begin
    if(uart_core_rst_n)
        core_tx_en_f<=1'b0;
    else if(core_tx_en)
        core_tx_en_f<=1'b1;
    else if(core_tx_en_ack_2&!core_tx_ready_2)
        core_tx_en_f<=1'b0;
end

always@(posedge core_clk or posedge uart_core_rst_n)begin
    if(uart_core_rst_n)begin
        core_tx_en_ack_1<=1'b0;
        core_tx_en_ack_2<=1'b0;
    end else begin
        core_tx_en_ack_1<=aux_tx_en_ack;
        core_tx_en_ack_2<=core_tx_en_ack_1;
    end
end

always@(posedge core_clk or posedge uart_core_rst_n)begin
    if(uart_core_rst_n)
        core_tx_data_r<=8'd0;
    else if(core_tx_en)
        core_tx_data_r<=core_tx_data;
end

always@(posedge aux_clk or posedge uart_axu_rst_n)begin
    if(uart_axu_rst_n)begin
        aux_tx_en_f_1<=1'b0;
        aux_tx_en_f_2<=1'b0;
        aux_tx_data_1<=1'b0;
        aux_tx_data_2<=1'b0;
        aux_tx_en_ack_r<=1'b0;
    end else begin
        aux_tx_en_f_1<=core_tx_en_f;
        aux_tx_en_f_2<=aux_tx_en_f_1;
        aux_tx_data_1<=core_tx_data_r;
        aux_tx_data_2<=aux_tx_data_1;
        aux_tx_en_ack_r<=aux_tx_en_ack;
    end
end

always@(posedge aux_clk or posedge uart_axu_rst_n)begin
    if(uart_axu_rst_n)
        aux_tx_en_ack<=1'b0;
    else if(aux_tx_en_f_2)
        aux_tx_en_ack<=1'b1;
    else
        aux_tx_en_ack<=1'b0;
end


always@(posedge aux_clk or posedge uart_axu_rst_n)begin
    if(uart_axu_rst_n)begin
        aux_tx_en<=1'b0;
        aux_tx_data<=8'd0;
    end else begin
        aux_tx_en<=aux_tx_en_ack&!aux_tx_en_ack_r;
        aux_tx_data<=aux_tx_data_2;
    end
end

always@(posedge core_clk or posedge uart_core_rst_n)begin
    if(uart_core_rst_n)begin
        core_tx_ready_1<=1'b0;
        core_tx_ready_2<=1'b0;
    end else begin
        core_tx_ready_1<=aux_tx_ready;
        core_tx_ready_2<=core_tx_ready_1;
    end
end

always@(posedge core_clk or posedge uart_core_rst_n)begin
    if(uart_core_rst_n)
        core_tx_ready<=1'b0;
    else if(core_tx_en_f)
        core_tx_ready<=1'b0;
    else
        core_tx_ready<=core_tx_ready_2;
end


endmodule
