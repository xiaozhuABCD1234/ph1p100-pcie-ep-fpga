
module ubus_model_fast (

    input   wire            clk     ,
    input   wire            rst_n   ,

    output  reg             tx_en   ,
    output  reg   [7:0]     tx_data ,

    input   wire            rx_en   ,
    input   wire  [7:0]     rx_data ,
    output  reg             rx_ready=0
);

// ====================================================================
// Parameter/wire/reg
// ====================================================================

    localparam  HEAD_0 = "A",
                HEAD_1 = "B",
                HEAD_2 = "C",
                HEAD_3 = "D",
                HEAD_4 = "E",
                HEAD_5 = "F";

// ===========================================================================
// Start of BFM
// ===========================================================================



// tx a byte
task tx_byte;
    input  [7:0]   data;

    begin
    @(posedge clk);
    tx_en = 1;
    tx_data = data;
    @(posedge clk);
    tx_en = 0;
    @(posedge clk);
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
    rx_ready = 1'b1;
    while(~rx_en) @(posedge clk);
    data = rx_data;
    rx_ready = 1'b0;
    @(posedge clk);
    @(posedge clk);
    rx_ready = 1'b1;
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



endmodule
