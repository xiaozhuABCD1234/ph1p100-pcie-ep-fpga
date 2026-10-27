

module pcie_uprotocol
#(
    parameter CLK_RATE = 50000000   
)
(
    input   wire        clk,
    input   wire        rst_n,
    // uart-rx
    input   wire        rx_en,
    input   wire [7:0]  rx_data,
    
    // uart-tx
    output  reg         tx_en,
    output  reg  [7:0]  tx_data    ,
    input   wire        tx_ready,
    
    // ubus write
    output  reg         ubus_wen   ,
    output  reg  [31:0] ubus_waddr ,
    output  reg  [31:0] ubus_wdata ,

// ubus read
    output  reg         ubus_ren   ,
    output  reg  [31:0] ubus_raddr ,
    input   wire        ubus_bken,
    input   wire [31:0] ubus_rdata
);

localparam HEAD_0 = 8'h41;
localparam HEAD_1 = 8'h42;
localparam HEAD_2 = 8'h43;
localparam HEAD_3 = 8'h44;
localparam HEAD_4 = 8'h45;
localparam HEAD_5 = 8'h46;

reg auto_rst;
reg [31:0] auto_rst_cnt;
reg [7:0] reg0;
reg [7:0] reg1;
reg [7:0] reg2;
reg [7:0] reg3;
reg [7:0] reg4;
reg [7:0] reg5;
reg [7:0] reg6;
reg [7:0] reg7;
reg rd_mode;
reg wt_mode;
reg wt_flag;
reg wt_flag0;
reg wt_flag1;
reg wt_flag2;
reg wt_flag3;
reg wt_flag4;
reg wt_flag5;
reg rd_flag;
reg rd_flag0;
reg rd_flag1;
reg rd_flag2;
reg rd_flag3;
reg rd_flag4;
reg rd_flag5;
reg recv_state;
reg [2:0] recv_cnt;
reg recv_flag;
reg send_start = 0;
reg send_finish;
reg send_flag;
reg tx_ready_flag;
reg [3:0] tx_ready_cnt;
reg [3:0] send_cnt;
reg [31:0] tx_buffer0;
reg [31:0] tx_buffer1;

always@(posedge clk or posedge rst_n )
begin
    if(rst_n )
        auto_rst_cnt <= 0;
    else if(rx_en | tx_en)
        auto_rst_cnt <= 0;
    else if(auto_rst_cnt == CLK_RATE - 1)
        auto_rst_cnt <= 0;
    else
        auto_rst_cnt <= auto_rst_cnt + 1;
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        auto_rst<=1;
    else
        auto_rst <= (auto_rst_cnt == CLK_RATE - 1);
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n) begin
        reg0 <= 8'd0;
        reg1 <= 8'd0;
        reg2 <= 8'd0;
        reg3 <= 8'd0;
        reg4 <= 8'd0;
        reg5 <= 8'd0;
        reg6 <= 8'd0;
        reg7 <= 8'd0;
    end else if(rx_en)
    begin
        reg0 <= rx_data;
        reg1 <= reg0;
        reg2 <= reg1;
        reg3 <= reg2;
        reg4 <= reg3;
        reg5 <= reg4;
        reg6 <= reg5;
        reg7 <= reg6;
    end
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n) begin
        wt_flag0 <= 1'b0;
        wt_flag1 <= 1'b0;
        wt_flag2 <= 1'b0;
        wt_flag3 <= 1'b0;
        wt_flag4 <= 1'b0;
        wt_flag5 <= 1'b0;
    end
    else if(!recv_state)
    begin
        wt_flag0 <= (reg5 == HEAD_0);
        wt_flag1 <= (reg4 == HEAD_1);
        wt_flag2 <= (reg3 == HEAD_2);
        wt_flag3 <= (reg2 == HEAD_3);
        wt_flag4 <= (reg1 == HEAD_4);
        wt_flag5 <= (reg0 == HEAD_5);
    end
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    wt_flag <= 1'b0; 
    else
    wt_flag <= &{rx_en,wt_flag0,wt_flag1,wt_flag2,wt_flag3,wt_flag4,wt_flag5};
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    begin
        rd_flag0 <= 1'b0;
        rd_flag1 <= 1'b0;
        rd_flag2 <= 1'b0;
        rd_flag3 <= 1'b0;
        rd_flag4 <= 1'b0;
        rd_flag5 <= 1'b0;
    end
    else if(!recv_state)
    begin
        rd_flag0 <= (reg5 == HEAD_5);
        rd_flag1 <= (reg4 == HEAD_4);
        rd_flag2 <= (reg3 == HEAD_3);
        rd_flag3 <= (reg2 == HEAD_2);
        rd_flag4 <= (reg1 == HEAD_1);
        rd_flag5 <= (reg0 == HEAD_0);
    end
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
    rd_flag <= 1'b0;
    else
    rd_flag <= &{rx_en,rd_flag0,rd_flag1,rd_flag2,rd_flag3,rd_flag4,rd_flag5};
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        rd_mode <= 0;
    else if(recv_flag)
        rd_mode <= 0;
    else if(rd_flag)
        rd_mode <= 1;
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        wt_mode <= 0;
    else if(recv_flag)
        wt_mode <= 0;
    else if(wt_flag)
        wt_mode <= 1;
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        recv_state <= 0;
    else if(auto_rst)
        recv_state <= 0;
    else if(wt_flag || rd_flag)
        recv_state <= 1;
    else if(recv_flag)
        recv_state <= 0;
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        recv_cnt <= 0;
    else if(auto_rst)
        recv_cnt <= 0;
    else if(!recv_state)
        recv_cnt <= 0;
    else if(rx_en)
        recv_cnt <= recv_cnt + 1;
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        recv_flag <= 1'b0;
    else
        recv_flag <= rx_en && (recv_cnt == 6);
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n) begin
        ubus_ren <= 1'b0;
        ubus_wen <= 1'b0;
    end else begin 
        ubus_ren <= recv_flag && rd_mode;
        ubus_wen <= recv_flag && wt_mode;
    end
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        ubus_raddr <= 32'd0;
    else if(recv_flag && rd_mode)
        ubus_raddr <= {reg7,reg6,reg5,reg4};
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n) begin
        ubus_waddr <= 32'd0;
        ubus_wdata <= 32'd0;
    end else if(recv_flag && wt_mode)
    begin
        ubus_waddr <= {reg7,reg6,reg5,reg4};
        ubus_wdata <= {reg3,reg2,reg1,reg0};
    end
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        tx_buffer0 <= 32'd0;
    else if(ubus_ren)
        tx_buffer0 <= ubus_raddr;
    else ;
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        tx_buffer1 <= 32'd0;
    else if(ubus_bken)
        tx_buffer1 <= ubus_rdata;
    else ;
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        send_start <= 0;
    else if(auto_rst)
        send_start <= 0;
    else if(ubus_bken)
        send_start <= 1;
    else if(send_finish)
        send_start <= 0;
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        send_finish <= 1;
    else if(auto_rst)
        send_finish <= 1;
    else if(ubus_ren)
        send_finish <= 0;
    else if(tx_en && send_cnt == 14)
        send_finish <= 1;
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        tx_ready_cnt <= 0;
    else if(tx_ready)
        tx_ready_cnt <= tx_ready_cnt + 1;
    else
        tx_ready_cnt <= 0;
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        tx_ready_flag <= 1'b0;
    else 
        tx_ready_flag <= &tx_ready_cnt;
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        send_cnt <= 0;
    else if(auto_rst)
        send_cnt <= 0;
    else if(send_finish)
        send_cnt <= 0;
    else if(send_start && tx_ready_flag)
        send_cnt <= send_cnt + 1;
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n) begin
        send_flag <= 1'b0;
        tx_en     <= 1'b0;
    end else begin
        send_flag <= (send_start && tx_ready_flag);
        tx_en <= send_flag;
    end
end

always@(posedge clk or posedge rst_n)
begin
    if(rst_n)
        tx_data  <= 8'd0;
    else case(send_cnt)
        1:  tx_data <= HEAD_0;
        2:  tx_data <= HEAD_1;
        3:  tx_data <= HEAD_2;
        4:  tx_data <= HEAD_3;
        5:  tx_data <= HEAD_4;
        6:  tx_data <= HEAD_5;
        
        7:  tx_data <= tx_buffer0[31:24]   ;
        8:  tx_data <= tx_buffer0[23:16]   ;
        9:  tx_data <= tx_buffer0[15:8]    ;
        10: tx_data <= tx_buffer0[7:0]     ;
        11: tx_data <= tx_buffer1[31:24]   ;
        12: tx_data <= tx_buffer1[23:16]   ;
        13: tx_data <= tx_buffer1[15:8]    ;
        14: tx_data <= tx_buffer1[7:0]     ; 
    endcase
end

endmodule
