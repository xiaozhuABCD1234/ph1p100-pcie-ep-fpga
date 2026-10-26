`timescale 1ps/1ps

// pat_sel = 4'b0000 : PRBS
// pat_sel = 4'b0001 : Counter
// pat_sel = 4'b0010 : 64'h0000_0000_0000_0000
// pat_sel = 4'b0011 : 64'hffff_ffff_ffff_ffff
// pat_sel = 4'b0100 : 64'hff00_ff00_ff00_ff00
// pat_sel = 4'b0101 : 64'h00ff_00ff_00ff_00ff
// pat_sel = 4'b0110 : User Seed

module data_check (
    input                clk     ,
    input                rst_n   ,
    input        [ 3:0]  pat_sel ,
    input        [31:0]  seed0   ,
    input        [31:0]  seed1   ,
    input                data_en ,
    input        [63:0]  data    ,
    output  reg          err     ,

// debug
    input                clear   ,
    output  reg  [31:0]  cnt_rd  ,
    output  reg  [31:0]  cnt_err ,
    output  reg  [63:0]  data_rel,
    output  reg  [63:0]  data_1x_exp,
    output  reg  [63:0]  data_1x_rd ,
    output  reg  [63:0]  data_1x_xor,
    output  reg  [63:0]  data_2x_exp,
    output  reg  [63:0]  data_2x_rd ,
    output  reg  [63:0]  data_2x_xor,
    output  reg  [63:0]  data_3x_exp,
    output  reg  [63:0]  data_3x_rd ,
    output  reg  [63:0]  data_3x_xor,
    output  reg  [63:0]  data_4x_exp,
    output  reg  [63:0]  data_4x_rd ,
    output  reg  [63:0]  data_4x_xor,
    output  reg  [63:0]  data_acc_xor
);


///////////////////////////////////////////////////////////////////////////////////////////////////
//
///////////////////////////////////////////////////////////////////////////////////////////////////
wire  [63:0] data_exp;
reg   [63:0] data_xor;
reg   [63:0] data_xor_r;

reg          data_en_r;
reg   [63:0] data_r   ;
reg   [63:0] data_r1  ;
reg   [63:0] data_r2  ;

reg   [63:0] data_exp_r1;
reg   [63:0] data_exp_r2;

reg          err_1x;
reg          err_2x;
reg          err_3x;
reg          err_4x;
wire  [ 3:0] err_x4;

data_gen u_data_gen (
    .clk      ( clk          ),
    .rst_n    ( rst_n        ),
    .pat_sel  ( pat_sel      ),

    .seed0    ( seed0        ),
    .seed1    ( seed1        ),

    .data_en  ( data_en_r    ),
    .data     ( data_exp     )
);

// read data pipeline
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        data_en_r <=  1'b0;
        data_r    <= 64'h0;
    end else begin
        data_en_r <= data_en;
        data_r    <= data   ;
    end
end

// data xor
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        data_xor <= 64'h0;
    else if (data_en_r == 1'b1)
        data_xor <= data_exp ^ data_r;
    else
        data_xor <= 64'h0;
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        data_xor_r  <= 64'h0;
        data_exp_r1 <= 64'h0;
        data_exp_r2 <= 64'h0;
        data_r1     <= 64'h0;
        data_r2     <= 64'h0;
    end else begin
        data_xor_r  <= data_xor;
        data_exp_r1 <= data_exp;
        data_exp_r2 <= data_exp_r1;
        data_r1     <= data_r;
        data_r2     <= data_r1;
    end
end

// error gen
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        err <= 1'b0;
    else if (|data_xor == 1'b1)
        err <= 1'b1;
    else
        err <= 1'b0;
end

///////////////////////////////////////////////////////////////
// DEBUG
///////////////////////////////////////////////////////////////
reg  [1:0] clr_r ;
wire       clr_pos;

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        clr_r <= 2'b00;
    else
        clr_r <= {clr_r[0], clear};
end

assign clr_pos = (clr_r[0] == 1'b1) & (clr_r[1] == 1'b0);

// read data cnt
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        cnt_rd <= 32'h0;
    else if (clr_pos == 1'b1)
        cnt_rd <= 32'h0;
    else if (data_en_r == 1'b1)
        cnt_rd <= cnt_rd + 1'b1;
    else
        cnt_rd <= cnt_rd;
end

// err cnt
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        cnt_err <= 32'h0;
    else if (clr_pos == 1'b1)
        cnt_err <= 32'h0;
    else if (err == 1'b1)
        cnt_err <= cnt_err + 1'b1;
    else
        cnt_err <= cnt_err;
end

// first four err
assign err_x4 = {err_4x, err_3x, err_2x, err_1x};
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        err_1x <= 1'b0;
        err_2x <= 1'b0;
        err_3x <= 1'b0;
        err_4x <= 1'b0;
    end else if (clr_pos == 1'b1) begin
        err_1x <= 1'b0;
        err_2x <= 1'b0;
        err_3x <= 1'b0;
        err_4x <= 1'b0;
    end else if ((err == 1'b1) && (err_x4 == 4'b0000)) begin
        err_1x <= 1'b1;
    end else if ((err == 1'b1) && (err_x4 == 4'b0001)) begin
        err_2x <= 1'b1;
    end else if ((err == 1'b1) && (err_x4 == 4'b0011)) begin
        err_3x <= 1'b1;
    end else if ((err == 1'b1) && (err_x4 == 4'b0111)) begin
        err_4x <= 1'b1;
    end else begin
        err_1x <= err_1x;
        err_2x <= err_2x;
        err_3x <= err_3x;
        err_4x <= err_4x;
    end
end

// real time : read data
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        data_rel <= 64'h0;
    else if (data_en_r == 1'b1)
        data_rel <= data_r;
    else
        data_rel <= data_rel;
end

// first error logging
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        data_1x_exp <= 64'h0;
        data_1x_rd  <= 64'h0;
        data_1x_xor <= 64'h0;
    end else if (clr_pos == 1'b1) begin
        data_1x_exp <= 64'h0;
        data_1x_rd  <= 64'h0;
        data_1x_xor <= 64'h0;
    end else if ((err == 1'b1) && (err_x4 == 4'b0000)) begin
        data_1x_exp <= data_exp_r2;
        data_1x_rd  <= data_r2    ;
        data_1x_xor <= data_xor_r ;
    end else begin
        data_1x_exp <= data_1x_exp;
        data_1x_rd  <= data_1x_rd ;
        data_1x_xor <= data_1x_xor;
    end
end

// second error logging
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        data_2x_exp <= 64'h0;
        data_2x_rd  <= 64'h0;
        data_2x_xor <= 64'h0;
    end else if (clr_pos == 1'b1) begin
        data_2x_exp <= 64'h0;
        data_2x_rd  <= 64'h0;
        data_2x_xor <= 64'h0;
    end else if ((err == 1'b1) && (err_x4 == 4'b0001)) begin
        data_2x_exp <= data_exp_r2;
        data_2x_rd  <= data_r2    ;
        data_2x_xor <= data_xor_r ;
    end else begin
        data_2x_exp <= data_2x_exp;
        data_2x_rd  <= data_2x_rd ;
        data_2x_xor <= data_2x_xor;
    end
end

// third error logging
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        data_3x_exp <= 64'h0;
        data_3x_rd  <= 64'h0;
        data_3x_xor <= 64'h0;
    end else if (clr_pos == 1'b1) begin
        data_3x_exp <= 64'h0;
        data_3x_rd  <= 64'h0;
        data_3x_xor <= 64'h0;
    end else if ((err == 1'b1) && (err_x4 == 4'b0011)) begin
        data_3x_exp <= data_exp_r2;
        data_3x_rd  <= data_r2    ;
        data_3x_xor <= data_xor_r ;
    end else begin
        data_3x_exp <= data_3x_exp;
        data_3x_rd  <= data_3x_rd ;
        data_3x_xor <= data_3x_xor;
    end
end

// forth error logging
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        data_4x_exp <= 64'h0;
        data_4x_rd  <= 64'h0;
        data_4x_xor <= 64'h0;
    end else if (clr_pos == 1'b1) begin
        data_4x_exp <= 64'h0;
        data_4x_rd  <= 64'h0;
        data_4x_xor <= 64'h0;
    end else if ((err == 1'b1) && (err_x4 == 4'b0111)) begin
        data_4x_exp <= data_exp_r2;
        data_4x_rd  <= data_r2    ;
        data_4x_xor <= data_xor_r ;
    end else begin
        data_4x_exp <= data_4x_exp;
        data_4x_rd  <= data_4x_rd ;
        data_4x_xor <= data_4x_xor;
    end
end

// acc data_xor
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        data_acc_xor <= 64'h0;
    end else if (clr_pos == 1'b1) begin
        data_acc_xor <= 64'h0;
    end else begin
        data_acc_xor <= data_acc_xor | data_xor_r;
    end
end

endmodule

