//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2024 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : pcie_rc_rx_engine.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2024-07-10 21:00:13
//  Create        : 2023-05-11 16:12:58
//  Description   : 
//   
///////////////////////////////////////////////////////////////

`timescale  1ns/1ps

module  pcie_rc_rx_engine(

    // Clock and Reset
    input       wire                tl_clk_user            ,
    input       wire                tl_rst_user            ,

    // Rx Control signals
    output      reg                 tl_mr_op_over          ,
    input       wire                tl_mr_en               ,
    input       wire    [12:0]      tl_mr_len              ,
    output      wire    [31:0]      tl_mr_data             ,
    input       wire                tl_mr_data_vld         ,
    input       wire                tl_mr_mode             ,
    input       wire                tl_mr_prbs_clear       ,
    
    input       wire                tl_iow_en              ,
    output      reg                 tl_iow_op_over         ,
    input       wire                tl_ior_en              ,
    output      reg                 tl_ior_op_over         ,
    output      reg     [31:0]      tl_ior_data            ,
    
    input       wire                tl_cfg0w_en            ,
    output      reg                 tl_cfg0w_op_over       ,
    input       wire                tl_cfg0r_en            ,
    output      reg                 tl_cfg0r_op_over       ,
    output      reg     [31:0]      tl_cfg0r_data          ,
    
    // MSI&MSI-X
    output      reg                 msi_ctrl_int           ,
    output      reg    [31:0]       msi_ctrl_int_vec       ,
    input       wire   [31:0]       msi_ctrl_clear         ,
    
    // RX interface 
    output      wire                tl_rx_wait             ,
    output      wire                tl_rx_masknp           ,
    input       wire    [47:0]      tl_rx_bardec           ,
    input       wire    [255:0]     tl_rx_data             ,
    input       wire                tl_rx_eop              ,
    input       wire    [7:0]       tl_rx_err              ,
    input       wire    [9:0]       tl_rx_mchit            ,
    input       wire                tl_rx_sop              ,
    input       wire    [7:0]       tl_rx_valid            ,
    // Debug 
    output      wire                o_alm       
);


`include "../common/TLP_FMT_TYPE.v"
`include "../common/BDF.v"

// ====================================================================
// Parameter|Wire|Reg
// ====================================================================

reg     [7:0]        tl_rx_engine_state     ;
reg     [7:0]        tl_rx_engine_state_next;

// pipeline for input signals
reg     [47:0]       tl_rx_bardec_dly       ;
reg     [255:0]      tl_rx_data_dly         ;
reg                  tl_rx_eop_dly          ;
reg     [7:0]        tl_rx_err_dly          ;
reg     [9:0]        tl_rx_mchit_dly        ;
reg                  tl_rx_sop_dly          ;
reg     [7:0]        tl_rx_valid_dly        ;
reg     [47:0]       tl_rx_bardec_dly2      ;
reg     [255:0]      tl_rx_data_dly2        ;
reg                  tl_rx_eop_dly2         ;
reg     [7:0]        tl_rx_err_dly2         ;
reg     [9:0]        tl_rx_mchit_dly2       ;
reg                  tl_rx_sop_dly2         ;
reg     [7:0]        tl_rx_valid_dly2       ;

reg                  tl_mr_en_dly           ;
reg                  tl_mr_data_vld_dly     ;
reg                  tl_mr_mode_dly         ;
reg                  tl_iow_en_dly          ;
reg                  tl_ior_en_dly          ;
reg                  tl_cfg0w_en_dly        ;
reg                  tl_cfg0r_en_dly        ;

// prbs
reg     [7:0]        prbs_enable            ;
reg     [255:0]      prbs_input_data        ;
wire    [7:0]        o_alm_bits             ;
reg                  alm_vld                ;
reg                  prbs_rst               ;

// memwr 
reg                  memwr32_flag           ;
reg                  memwr64_flag           ;
reg                  memwr32_flag_dly       ;
reg                  memwr64_flag_dly       ;

// memrd
reg                  memrd_flag             ;

// cpld
reg                  cpld_flag              ;
reg                  cpld_flag_dly          ;

// io 
reg                  iowr_flag              ;
reg                  iowr_error             ;
reg     [31:0]       iowr_data              ;

// cpl
reg                  cpl_flag               ;

localparam      TL_RX_IDEL      = 8'b0000_0001,
                TL_RX_TYPE_DEF  = 8'b0000_0010,
                TL_RX_MEMWR     = 8'b0000_0100,
                TL_RX_MEMRD     = 8'b0000_1000,
                TL_RX_CFGWR     = 8'b0001_0000,
                TL_RX_CFGRD     = 8'b0010_0000,
                TL_RX_IOWR      = 8'b0100_0000,
                TL_RX_IORD      = 8'b1000_0000;

// ====================================================================
// Main Code
// ====================================================================

assign      tl_rx_wait      = 1'b0;
assign      tl_rx_masknp    = 1'b0;

// pipeline input signals
always@( posedge tl_clk_user or posedge tl_rst_user )
begin 
    if( tl_rst_user ) begin 
        tl_rx_bardec_dly <= 48'd0;
        tl_rx_data_dly   <= 256'd0;
        tl_rx_eop_dly    <= 1'b0;
        tl_rx_err_dly    <= 8'd0;
        tl_rx_mchit_dly  <= 10'd0;
        tl_rx_sop_dly    <= 1'b0;
        tl_rx_valid_dly  <= 8'd0;

        tl_rx_bardec_dly2<= 48'd0;
        tl_rx_data_dly2  <= 256'd0;
        tl_rx_eop_dly2   <= 1'b0;
        tl_rx_err_dly2   <= 8'd0;
        tl_rx_mchit_dly2 <= 10'd0;
        tl_rx_sop_dly2   <= 1'b0;
        tl_rx_valid_dly2 <= 8'd0;
    end else begin 
        tl_rx_bardec_dly <= tl_rx_bardec; 
        tl_rx_data_dly   <= tl_rx_data;   
        tl_rx_eop_dly    <= tl_rx_eop;    
        tl_rx_err_dly    <= tl_rx_err;    
        tl_rx_mchit_dly  <= tl_rx_mchit;  
        tl_rx_sop_dly    <= tl_rx_sop;    
        tl_rx_valid_dly  <= tl_rx_valid;  

        tl_rx_bardec_dly2<= tl_rx_bardec_dly;
        tl_rx_data_dly2  <= tl_rx_data_dly;  
        tl_rx_eop_dly2   <= tl_rx_eop_dly;   
        tl_rx_err_dly2   <= tl_rx_err_dly;   
        tl_rx_mchit_dly2 <= tl_rx_mchit_dly; 
        tl_rx_sop_dly2   <= tl_rx_sop_dly;   
        tl_rx_valid_dly2 <= tl_rx_valid_dly; 
    end
end

always@(posedge tl_clk_user or posedge tl_rst_user)
begin 
    if(tl_rst_user) begin 
        tl_mr_en_dly       <= 1'b0;
        tl_mr_data_vld_dly <= 1'b0;
        tl_mr_mode_dly     <= 1'b0;
        tl_iow_en_dly      <= 1'b0;
        tl_ior_en_dly      <= 1'b0;
        tl_cfg0w_en_dly    <= 1'b0;
        tl_cfg0r_en_dly    <= 1'b0;
    end else begin 
        tl_mr_en_dly       <= tl_mr_en      ;
        tl_mr_data_vld_dly <= tl_mr_data_vld;
        tl_mr_mode_dly     <= tl_mr_mode    ;
        tl_iow_en_dly      <= tl_iow_en     ;
        tl_ior_en_dly      <= tl_ior_en     ;
        tl_cfg0w_en_dly    <= tl_cfg0w_en   ;
        tl_cfg0r_en_dly    <= tl_cfg0r_en   ;
    end
end

// ====================================================================
// TL interface decode
// ====================================================================

// detect which tlp type is received 
always@( posedge tl_clk_user or posedge tl_rst_user )
begin 
    if( tl_rst_user ) begin 
        memwr32_flag <= 1'b0;
        memwr64_flag <= 1'b0;
        memrd_flag   <= 1'b0;
        cpld_flag    <= 1'b0;
        cpl_flag     <= 1'b0;
        iowr_flag    <= 1'b0;
    end else if( tl_rx_eop_dly2 )  begin
        memwr32_flag <= 1'b0;
        memwr64_flag <= 1'b0;
        memrd_flag   <= 1'b0;
        cpld_flag    <= 1'b0;
        cpl_flag     <= 1'b0;
        iowr_flag    <= 1'b0;
    end else begin
        if( tl_rx_sop_dly==1'b1 && tl_rx_data_dly[255:253]==`MWR_FMT_3DW && tl_rx_data_dly[252:248]==`MWR_TYPE )
            memwr32_flag <= 1'b1;
        if( tl_rx_sop_dly==1'b1 && tl_rx_data_dly[255:253]==`MWR_FMT_4DW && tl_rx_data_dly[252:248]==`MWR_TYPE )
            memwr64_flag <= 1'b1;
        if( tl_rx_sop_dly==1'b1 && tl_rx_data_dly[255:253]==`MRD_FMT_4DW && tl_rx_data_dly[252:248]==`MRD_TYPE )
            memrd_flag <= 1'b1;
        if( tl_rx_sop_dly==1'b1 && tl_rx_data_dly[255:253]==`CPLD_FMT    && tl_rx_data_dly[252:248]==`CPLD_TYPE )
            cpld_flag  <= 1'b1;
        if( tl_rx_sop_dly==1'b1 && tl_rx_data_dly[255:253]==`CPL_FMT     && tl_rx_data_dly[252:248]==`CPL_TYPE )
            cpl_flag  <= 1'b1;
        if( tl_rx_sop_dly==1'b1 && tl_rx_data_dly[255:253]==`IOWR_FMT    && tl_rx_data_dly[252:248]==`IOWR_TYPE )
            iowr_flag  <= 1'b1;
    end
end

always@( posedge tl_clk_user )
begin
    memwr32_flag_dly <= memwr32_flag;
    memwr64_flag_dly <= memwr64_flag;
    cpld_flag_dly    <= cpld_flag   ;
end

// ====================================================================
// Cfg0w & Cfg0r
// ====================================================================

// cfg0w
always@(posedge tl_clk_user or posedge tl_rst_user)
begin 
    if(tl_rst_user) begin 
        tl_cfg0w_op_over <= 1'b0;
    end else if(cpl_flag & tl_cfg0w_en_dly ) begin 
        tl_cfg0w_op_over <= 1'b1;
    end else begin 
        tl_cfg0w_op_over <= 1'b0;
    end
end

// cfg0r
always@(posedge tl_clk_user or posedge tl_rst_user)
begin 
    if(tl_rst_user) begin 
        tl_cfg0r_op_over <= 1'b0;
    end else if(cpld_flag & tl_cfg0r_en_dly ) begin 
        tl_cfg0r_op_over <= 1'b1;
    end else begin
        tl_cfg0r_op_over <= 1'b0;
    end
end

always@(posedge tl_clk_user or posedge tl_rst_user)
begin 
    if(tl_rst_user)  
        tl_cfg0r_data <= 32'd0;
    else if( cpld_flag & tl_cfg0r_en_dly & tl_rx_sop_dly2 )
        tl_cfg0r_data <= tl_rx_data_dly2[159:128];
end

// ====================================================================
// IOw & IOr
// ====================================================================

// iow
always@(posedge tl_clk_user or posedge tl_rst_user)
begin 
    if(tl_rst_user) begin 
        tl_iow_op_over <= 1'b0;
    end else if(cpl_flag & tl_iow_en_dly ) begin 
        tl_iow_op_over  <= 1'b1;
    end else begin 
        tl_iow_op_over <= 1'b0;
    end
end

// ior
always@(posedge tl_clk_user or posedge tl_rst_user)
begin 
    if(tl_rst_user) begin 
        tl_ior_op_over <= 1'b0;
    end else if(cpld_flag & tl_ior_en_dly ) begin 
        tl_ior_op_over <= 1'b1;
    end else begin
        tl_ior_op_over <= 1'b0;
    end
end

always@(posedge tl_clk_user or posedge tl_rst_user)
begin 
    if(tl_rst_user)  
        tl_ior_data <= 32'd0;
    else if( cpld_flag & tl_ior_en_dly & tl_rx_sop_dly2 )
        tl_ior_data  <= tl_rx_data_dly2[159:128];
end

// ====================================================================
// memrd 
// ====================================================================

//tl_mr_op_over 
always@(posedge tl_clk_user or posedge tl_rst_user)
begin 
    if(tl_rst_user) begin 
        tl_mr_op_over <= 1'b0;
    end else if(cpld_flag & tl_rx_eop_dly2 & tl_mr_en_dly ) begin 
        tl_mr_op_over <= 1'b1;
    end else begin
        tl_mr_op_over <= 1'b0;
    end
end


// ====================================================================
// prbs mode logic 
// ====================================================================

// prbs_input_data 
always@( posedge tl_clk_user or posedge tl_rst_user ) 
begin
    if( tl_rst_user )
        prbs_input_data <= 256'd0;
    else begin
        prbs_input_data <= {tl_rx_data_dly2[159:0],tl_rx_data_dly[255:160]} ;
    end
end

//prbs_enable
always@( posedge tl_clk_user or posedge tl_rst_user ) 
begin
     if( tl_rst_user )
        prbs_enable <= 8'b0;
     else if( cpld_flag & tl_mr_en_dly )
        prbs_enable <= {tl_rx_valid_dly2[4:0], tl_rx_valid_dly[7:5]};
     else 
        prbs_enable <= 8'b0;          
end
always@(posedge tl_clk_user or posedge tl_rst_user)
begin 
    if(tl_rst_user) begin 
        prbs_rst       <= 1'b1;
    end else begin 
        prbs_rst       <= ~tl_mr_en      ;
    end
end
// prbs data check, use 16 prbs_chk module,every module has 
// independent enable signal, and output data width is 32bits
genvar i;
generate
    for(i=0;i<8;i=i+1)
    begin : prbs_chk
        prbs_chk_pcie
        #(
            .PRBS_PLOY  ( 15'h6000                        ),
            .DAT_W      ( 32                              ),
            .PRBS_WIDTH ( 35                              )
        )u_prbs_chk_pcie
        (
            .clk        ( tl_clk_user                     ),
            .rst        ( prbs_rst                        ),
            .i_en       ( prbs_enable[i]                  ),
            .i_dat      ( prbs_input_data[32*i+31:32*i]   ),
            .o_alm      ( o_alm_bits[i]                   )
        );
    end
endgenerate

always@( posedge tl_clk_user or posedge tl_rst_user ) 
begin
    if( tl_rst_user )
        alm_vld <= 1'b0;
    else if( tl_mr_prbs_clear )       
        alm_vld <= 1'b0;
    else if( (|o_alm_bits) & !tl_mr_mode_dly )
        alm_vld <= 1'b1;
end

assign  o_alm = alm_vld ; 
  
// ====================================================================
// user mode logic 
// ====================================================================
// write path
wire        user_memrd_wren;
reg [6:0]   user_memrd_wraddr;
wire[255:0] user_memrd_wrdata_inv;
reg [255:0] user_memrd_wrdata;

reg  [9:0]   user_memrd_rdaddr;
wire [31:0]  user_memrd_rddata;
reg  [31:0]  user_memrd_rddata_dly;

// user_memrd_wrdata 
assign  user_memrd_wrdata_inv = { tl_rx_data_dly2[159:0], tl_rx_data_dly [255:160] } ;
always@( posedge tl_clk_user or posedge tl_rst_user ) 
begin
    if( tl_rst_user )
        user_memrd_wrdata <= 256'd0;
    else begin
        user_memrd_wrdata <= { user_memrd_wrdata_inv[31 : 0],
                               user_memrd_wrdata_inv[63 :32],
                               user_memrd_wrdata_inv[95 :64],
                               user_memrd_wrdata_inv[127:96],
                               user_memrd_wrdata_inv[128+31 :128+ 0],
                               user_memrd_wrdata_inv[128+63 :128+32],
                               user_memrd_wrdata_inv[128+95 :128+64],
                               user_memrd_wrdata_inv[128+127:128+96]
                             };
    end
end
//user_memrd_wraddr
always@( posedge tl_clk_user or posedge tl_rst_user ) 
begin
     if( tl_rst_user )
        user_memrd_wraddr <= 7'd0;
     else if( tl_mr_en_dly )
        user_memrd_wraddr <= (|prbs_enable) ? user_memrd_wraddr + 1'b1 : user_memrd_wraddr ;
     else 
        user_memrd_wraddr <= 7'd0;
end
assign  user_memrd_wren = (|prbs_enable) ? 1'b1 : 1'b0;

// read path
//user_memrd_rdaddr
always@( posedge tl_clk_user or posedge tl_rst_user ) 
begin
    if( tl_rst_user ) begin
        user_memrd_rdaddr <= 10'd0;
    end else if( tl_mr_mode_dly ) begin
        user_memrd_rdaddr <=  tl_mr_data_vld_dly ? user_memrd_rdaddr + 1'b1 : user_memrd_rdaddr ;
    end else begin
        user_memrd_rdaddr <= 10'd0;
    end
end

//user_memrd_rddata
always@( posedge tl_clk_user or posedge tl_rst_user ) 
begin
    if( tl_rst_user )
        user_memrd_rddata_dly <= 32'd0;
    else 
        user_memrd_rddata_dly <= user_memrd_rddata ;
end

pcie_rx_ram u_pcie_rx_eram(
    .clka           (tl_clk_user        ),
    .cea            (user_memrd_wren    ),
    .dia            (user_memrd_wrdata  ),
    .addra          (user_memrd_wraddr  ),

    .ceb            (1'b1               ),
    .addrb          (user_memrd_rdaddr  ),
    .dob            (user_memrd_rddata  )
);

assign  tl_mr_data = tl_mr_mode_dly ? user_memrd_rddata_dly :  {31'b0, alm_vld};  

// ====================================================================
// MSI Detect logic 
// ====================================================================

`ifdef PH1P_PCIE_MSI_INT_ENABLE
    always@( posedge tl_clk_user or posedge tl_rst_user ) 
    begin
        if( tl_rst_user ) begin
            msi_ctrl_int     <= 1'b0;
            msi_ctrl_int_vec <= 32'b0;
        end else if( msi_ctrl_clear[0]) begin
            msi_ctrl_int     <= 1'b0;
            msi_ctrl_int_vec <= 32'b0;
        end else if( memwr64_flag==1'b1 && tl_rx_data_dly2[191:128]=={`MSI_CTRL_ADDRH,`MSI_CTRL_ADDRL}) begin
            msi_ctrl_int     <= 1'b1;
            msi_ctrl_int_vec <= { tl_rx_data_dly2[119:112],tl_rx_data_dly2[127:120] }-`MSI_CTRL_DATA;
        end 
    end

`elsif PH1P_PCIE_MSIX_INT_ENABLE
    always@( posedge tl_clk_user or posedge tl_rst_user ) 
    begin
        if( tl_rst_user ) begin
            msi_ctrl_int     <= 1'b0;
            msi_ctrl_int_vec <= 32'b0;
        end else if( msi_ctrl_clear[0]) begin
            msi_ctrl_int     <= 1'b0;
            msi_ctrl_int_vec <= 32'b0;
        end else begin
            if( memwr64_flag==1'b1 && tl_rx_data_dly2[191:128]==`MSIX_MSG_ADDR0 ) begin
                msi_ctrl_int     <= 1'b1;
                msi_ctrl_int_vec <= tl_rx_data_dly2[127:96];
            end 
            if( memwr64_flag==1'b1 && tl_rx_data_dly2[191:128]==`MSIX_MSG_ADDR1 ) begin
                msi_ctrl_int     <= 1'b1;
                msi_ctrl_int_vec <= tl_rx_data_dly2[127:96];
            end 
            if( memwr64_flag==1'b1 && tl_rx_data_dly2[191:128]==`MSIX_MSG_ADDR2 ) begin
                msi_ctrl_int     <= 1'b1;
                msi_ctrl_int_vec <= tl_rx_data_dly2[127:96];
            end 
            if( memwr64_flag==1'b1 && tl_rx_data_dly2[191:128]==`MSIX_MSG_ADDR3 ) begin
                msi_ctrl_int     <= 1'b1;
                msi_ctrl_int_vec <= tl_rx_data_dly2[127:96];
            end 
        end
    end

`else
    always@( posedge tl_clk_user or posedge tl_rst_user ) 
    begin
        if( tl_rst_user ) begin
            msi_ctrl_int     <= 1'b0;
            msi_ctrl_int_vec <= 32'b0;
        end else begin
            msi_ctrl_int     <= 1'b1;
            msi_ctrl_int_vec <= 32'hffff_ffff;
        end
    end
`endif



/*synthesis translate_off*/
initial begin 
    forever 
    fork
        wait((|alm_vld) & !tl_mr_mode_dly )
            $display("%0t: logic info : rx side detect prbs data error ",$realtime );
        #100_000;
    join
end

/*synthesis translate_on*/

endmodule
