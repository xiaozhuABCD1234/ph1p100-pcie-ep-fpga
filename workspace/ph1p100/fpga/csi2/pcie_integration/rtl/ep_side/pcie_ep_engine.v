//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2024 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : pcie_ep_engine.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2024-07-10 18:13:32
//  Create        : 2023-05-11 11:03:47
//  Description   : 
//                  1. rec iow  Pkg and respond cpl
//                  2. rec ior  Pkg and respond cpld
//                  3. rec memw pkg 
//                  1. rec memr pkg and respond cpld
///////////////////////////////////////////////////////////////

`timescale  1ns/1ps

module pcie_ep_engine #(
    parameter [31:0] IMG_PTRBYTES = 32'h0004_B000,
    parameter [8:0]  IMG_CLK_MHZ = 9'd62        
)(

    // Clock and Reset
    input       wire                tl_clk_user            ,
    input       wire                tl_rst_user            ,

    input       wire    [3:0]       tl_int_msix_trigger    ,

    // Rx interface
    output      wire                tl_rx_wait             ,
    output      wire                tl_rx_masknp           ,
    input       wire    [47:0]      tl_rx_bardec           ,
    input       wire    [255:0]     tl_rx_data             ,
    input       wire                tl_rx_eop              ,
    input       wire    [7:0]       tl_rx_err              ,
    input       wire    [9:0]       tl_rx_mchit            ,
    input       wire                tl_rx_sop              ,
    input       wire    [7:0]       tl_rx_valid            ,

    // TX interface 
    output      reg     [255:0]     tl_tx_data             ,
    output      reg                 tl_tx_eop              ,
    output      wire    [7:0]       tl_tx_err              ,
    output      reg                 tl_tx_sop              ,
    output      wire                tl_tx_stream           ,
    output      reg     [7:0]       tl_tx_valid            ,
    input       wire                tl_tx_wait             ,
    input       wire    [95:0]      tl_tx_credits          ,
    // ==== 本移植新增：BAR0 真窗口 → 图像源接口 ====
    output      wire                img_ctrl_enable        ,
    output      wire                img_ctrl_trigger       ,
    output      wire    [1:0]       img_ctrl_pattern       ,
    input       wire                img_st_ready           ,
    input       wire                img_st_busy            ,
    input       wire    [31:0]      img_st_frame_cnt       ,
    input       wire    [15:0]      img_st_width           ,
    input       wire    [15:0]      img_st_height          ,
    input       wire    [31:0]      img_st_data_len        ,
    output      wire    [31:0]      img_fb_raddr           ,
    input       wire    [31:0]      img_fb_rdata           ,
    output      wire    [31:0]      img_dbg_rd_idx         ,
    input       wire    [255:0]     cam_stat_bus           ,
    output      wire    [6:0]       cam_tap_cfg            ,
    output      wire    [6:0]       cam_tap_b_cfg          ,   // B 路 tap（0xD4，转发给 ep_bar_win）
    output      wire                cam_ab_sel             ,   // CTRL[8] 推帧取 A/B 路
    input       wire [31:0]         cam_diag_b             ,   // B 路相机直通诊断（0xD8）
    input       wire [95:0]         cam_drop_a             ,   // A 路丢帧诊断（0xDC/0xF0/0xF4）
    input       wire [127:0]        ddr_ro_b               ,   // B 路整帧搬运握手字（0xE0~0xEC）
    // ==== 本移植新增：DDR3 整帧搬运（CTRL[5] + 只读握手字）====
    output      wire                img_ctrl_ddr_en        ,
    input       wire    [127:0]     img_ddr_ro             ,
    // fb 读口仲裁（img_frame_src ↔ ep_bar_win，两个都在外层 top 里）
    output      wire                img_host_rd_prio       ,
    input       wire                img_host_grant         ,
    // ==== 本步新增：DDR→主机推帧（ddr_frame_pusher）寄存器面 + 用户侧 TL 发送口 ====
    //   推帧的 TLP 不走下面那个发送状态机，而是从这里插进 TL 发送口：
    //   TL_TX_IDLE 里给 utx_req 最低优先权，进 TL_TX_USER 态后由顶层把 tl_tx_*
    //   换成用户侧那一组（见 ph1p_pcie_ep_top.v 的推帧段）。
    output      wire                img_push_en            , // CTRL[6]
    output      wire                img_push_src           , // CTRL[7] 推帧数据源选择
    output      wire    [31:0]      img_push_dst_lo        , // 0xB0
    output      wire    [31:0]      img_push_dst_hi        , // 0xB4
    output      wire    [31:0]      img_push_db_lo         , // 0xB8
    output      wire    [31:0]      img_push_db_hi         , // 0xBC
    input       wire    [127:0]     img_push_ro            , // {tlp_cnt, status, done, err}
    // ==== T07 新增：RKA1 安全扩展寄存器面（0x100..0x11C）+ CSI 诊断 ====
    //   这些只是把 ep_bar_win 的端口引到顶层的「过路」端口，逻辑都在顶层/安全门里。
    output      wire    [31:0]      tx_cap_bytes           , // 0x100
    output      wire    [31:0]      tx_session_id          , // 0x104
    output      wire                tx_cmd_arm             , // 0x108.bit0 单拍
    output      wire                tx_cmd_ack             , // 0x108.bit1 单拍
    output      wire                tx_cmd_cancel          , // 0x108.bit2 单拍
    output      wire    [31:0]      tx_ack_seq             , // 0x10C
    output      wire    [31:0]      tx_ack_session         , // 0x110
    input       wire    [31:0]      tx_status_in           , // 0x114（安全门给）
    input       wire                tx_block_cfg           , // 1 = busy/held/draining
    output      wire                cfg_reject             , // 活动期写配置被拒（单拍）
    input       wire    [31:0]      csi_diag_a             , // 0x120
    input       wire    [31:0]      csi_diag_a2            , // 0x124
    input       wire    [31:0]      csi_diag_b             , // 0x128
    input       wire    [31:0]      csi_diag_b2            , // 0x12C
    input       wire                utx_req                ,
    input       wire                utx_eop                ,
    input       wire    [7:0]       utx_valid              ,
    output      wire                utx_sel
);

`include "../common/TLP_FMT_TYPE.v"
`include "../common/BDF.v"

// ====================================================================
// Parameter|Wire|Reg
// ====================================================================
// T07 仿真兼容修正（行为不变）：tl_tx_state 与其状态编码原声明在下面 TX Engine
// 段（本段先使用、后声明），TD 能过、ModelSim vlog 报 vlog-2730/2388。声明提前。
reg   [4:0]  tl_tx_state=0;
localparam   TL_TX_IDLE     = 5'b0_0001,
             TL_TX_ACK_IOW  = 5'b0_0010,
             TL_TX_ACK_IOR  = 5'b0_0100,
             TL_TX_ACK_MEMR = 5'b0_1000,
             TL_TX_ACK_MSIX = 5'b1_0000,
             TL_TX_USER     = 5'b10_0000;

// pipeline for input signals
reg     [47:0]       tl_rx_bardec_ff        ;
reg     [255:0]      tl_rx_data_ff          ;
reg                  tl_rx_eop_ff           ;
reg     [7:0]        tl_rx_err_ff           ;
reg     [9:0]        tl_rx_mchit_ff         ;
reg                  tl_rx_sop_ff           ;
reg     [7:0]        tl_rx_valid_ff         ;

reg     [47:0]       tl_rx_bardec_2ff       ;
reg     [255:0]      tl_rx_data_2ff         ;
reg                  tl_rx_eop_2ff          ;
reg     [7:0]        tl_rx_err_2ff          ;
reg     [9:0]        tl_rx_mchit_2ff        ;
reg                  tl_rx_sop_2ff          ;
reg     [7:0]        tl_rx_valid_2ff        ;

reg     [47:0]       tl_rx_bardec_3ff       ;
reg     [255:0]      tl_rx_data_3ff         ;
reg                  tl_rx_eop_3ff          ;
reg     [7:0]        tl_rx_err_3ff          ;
reg     [9:0]        tl_rx_mchit_3ff        ;
reg                  tl_rx_sop_3ff          ;
reg     [7:0]        tl_rx_valid_3ff        ;

reg                  iow_flag               ;
reg                  ior_flag               ;
reg                  memwr_flag             ;
reg                  memrd_flag             ;
// 本步新增推帧后：iow/ior/memrd 三个请求标志改为「发完才清」（不再在 rx_eop 时清）。
// 原因：推帧时 TL 发送口可能被用户侧连占好几拍，主机的 MRd 在这期间到达时，
// 原来那个「两拍就清」的标志会在状态机回到 IDLE 之前就消失，完成包被丢，
// 主机读到全 F。现在它们一直挂着，到下一次 TL_TX_IDLE 就一定被服务。
// （标志仍只有一个，靠主机非投递读的「等完成再发下一笔」语义保证不会叠单。）
reg     [6:0]        memrd_addr             ;

reg     [15:0]       rc_bdf                 ;
reg     [7:0]        np_tag                 ;

reg     [31:0]       iodata_array[5:0]      ;
reg     [31:0]       iodata                 ;
reg     [5:0]        io_addr                ;

integer i;
   
reg     [7:0]        mrdata_cycle_valid     ;
reg     [10:0]       mrdata_cycle           ;

wire    [9:0]        mrdata_cycle_valid_32bit;
wire    [15:0]       mrdata_cycle_valid_tmp ;

reg                  mwdata_wr_en           ;
reg     [255:0]      mwdata_wr_data         ;
reg     [6:0]        mwdata_wr_addr         ;
reg     [6:0]        mrdata_rd_addr         ;
reg     [6:0]        mrdata_rd_addr_dly     ;
wire    [255:0]      mrdata_rd_data         ;
reg     [255:0]      mrdata_rd_data_ff      ;

reg                  mem_first_cycle        ;
reg                  mem_addr_is_64bit      ;
reg     [10:0]       tl_mr_len_ff           ;

`ifdef PH1P_PCIE_MSIX_INT_ENABLE
reg     [3:0]       tl_int_msix_trigger_ff  ;
reg     [63:0]      tl_msix_sgm_addr_ff     ;
reg     [31:0]      tl_msix_sgm_data_ff     ;
reg     [63:0]      tl_msix_sgm_addr_0      ;
reg     [31:0]      tl_msix_sgm_data_0      ;
reg     [63:0]      tl_msix_sgm_addr_1      ;
reg     [31:0]      tl_msix_sgm_data_1      ;
reg     [63:0]      tl_msix_sgm_addr_2      ;
reg     [31:0]      tl_msix_sgm_data_2      ;
reg     [63:0]      tl_msix_sgm_addr_3      ;
reg     [31:0]      tl_msix_sgm_data_3      ;
`else 
wire    [3:0]       tl_int_msix_trigger_ff='d0;
wire    [63:0]      tl_msix_sgm_addr_ff='d0;
wire    [31:0]      tl_msix_sgm_data_ff='d0;
`endif

// ====================================================================
// Main Code
// ====================================================================

assign      tl_rx_wait      = 1'b0;
assign      tl_rx_masknp    = 1'b0;

// pipeline input signals
always@(posedge tl_clk_user or posedge tl_rst_user)
begin 
    if(tl_rst_user) begin 
        tl_rx_bardec_ff       <= 'd0;
        tl_rx_data_ff         <= 'd0;
        tl_rx_eop_ff          <= 'd0;
        tl_rx_err_ff          <= 'd0;
        tl_rx_mchit_ff        <= 'd0;
        tl_rx_sop_ff          <= 'd0;
        tl_rx_valid_ff        <= 'd0;
        tl_rx_bardec_2ff      <= 'd0;
        tl_rx_data_2ff        <= 'd0;
        tl_rx_eop_2ff         <= 'd0;
        tl_rx_err_2ff         <= 'd0;
        tl_rx_mchit_2ff       <= 'd0;
        tl_rx_sop_2ff         <= 'd0;
        tl_rx_valid_2ff       <= 'd0;
        tl_rx_bardec_3ff      <= 'd0;
        tl_rx_data_3ff        <= 'd0;
        tl_rx_eop_3ff         <= 'd0;
        tl_rx_err_3ff         <= 'd0;
        tl_rx_mchit_3ff       <= 'd0;
        tl_rx_sop_3ff         <= 'd0;
        tl_rx_valid_3ff       <= 'd0;
    end else begin 
        tl_rx_bardec_ff       <= tl_rx_bardec    ;
        tl_rx_data_ff         <= tl_rx_data      ;
        tl_rx_eop_ff          <= tl_rx_eop       ;
        tl_rx_err_ff          <= tl_rx_err       ;
        tl_rx_mchit_ff        <= tl_rx_mchit     ;
        tl_rx_sop_ff          <= tl_rx_sop       ;
        tl_rx_valid_ff        <= tl_rx_valid     ;
        tl_rx_bardec_2ff      <= tl_rx_bardec_ff ;
        tl_rx_data_2ff        <= tl_rx_data_ff   ;
        tl_rx_eop_2ff         <= tl_rx_eop_ff    ;
        tl_rx_err_2ff         <= tl_rx_err_ff    ;
        tl_rx_mchit_2ff       <= tl_rx_mchit_ff  ;
        tl_rx_sop_2ff         <= tl_rx_sop_ff    ;
        tl_rx_valid_2ff       <= tl_rx_valid_ff  ;
        tl_rx_bardec_3ff      <= tl_rx_bardec_2ff;
        tl_rx_data_3ff        <= tl_rx_data_2ff  ;
        tl_rx_eop_3ff         <= tl_rx_eop_2ff   ;
        tl_rx_err_3ff         <= tl_rx_err_2ff   ;
        tl_rx_mchit_3ff       <= tl_rx_mchit_2ff ;
        tl_rx_sop_3ff         <= tl_rx_sop_2ff   ;
        tl_rx_valid_3ff       <= tl_rx_valid_2ff ;
    end
end

//--------------------------------------------
// Tl interface decode
//--------------------------------------------

always@(posedge tl_clk_user or posedge tl_rst_user)
begin
    if(tl_rst_user) begin 
        iow_flag   <= 1'b0;
        ior_flag   <= 1'b0;
        memwr_flag <= 1'b0;
        memrd_flag <= 1'b0;
        io_addr    <= 6'd0;
        memrd_addr <= 7'd0;
    end else begin
        // 本步新增：iow/ior/memrd 三个请求标志「服务过才清」（原因见声明处注释）。
        // 清的条件与发送状态机自己的验收条件逐字一致；放在置位前面，
        // 同一拍既收完上一笔又来了新请求时，优先照顾新请求。
        if( (tl_tx_state == TL_TX_ACK_IOW)  & tl_tx_eop & tl_tx_sop      & (!tl_tx_wait) )
            iow_flag   <= 1'b0;
        if( (tl_tx_state == TL_TX_ACK_IOR)  & tl_tx_eop & tl_tx_sop      & (!tl_tx_wait) )
            ior_flag   <= 1'b0;
        if( (tl_tx_state == TL_TX_ACK_MEMR) & tl_tx_eop & tl_tx_valid[7] & (!tl_tx_wait) )
            memrd_flag <= 1'b0;

        if(tl_rx_sop_ff) begin 
            if( (tl_rx_data_ff[255:253] == `MWR_FMT_3DW  || tl_rx_data_ff[255:253] == `MWR_FMT_4DW  ) & tl_rx_data_ff[252:248] == `MWR_TYPE )
                memwr_flag <= 1'b1;
        end else if(tl_rx_eop_2ff) begin 
            memwr_flag <= 1'b0;
        end
        if( tl_rx_sop_ff ) begin 
            if( tl_rx_data_ff[255:253] == `IOWR_FMT  & tl_rx_data_ff[252:248] == `IOWR_TYPE  ) begin 
                iow_flag   <= 1'b1;
                io_addr    <= tl_rx_data_ff[167:162]; // dw align
            end
            if( tl_rx_data_ff[255:253] == `IORD_FMT  & tl_rx_data_ff[252:248] == `IORD_TYPE  ) begin 
                ior_flag   <= 1'b1;
                io_addr    <= tl_rx_data_ff[167:162]; // dw align
            end
            if( (tl_rx_data_ff[255:253] == `MRD_FMT_3DW || tl_rx_data_ff[255:253] == `MRD_FMT_4DW ) & tl_rx_data_ff[252:248] == `MRD_TYPE  ) begin 
                memrd_flag <= 1'b1;
                memrd_addr <= tl_rx_data_ff[168:162];
            end
        end
    end 
end

always@(posedge tl_clk_user or posedge tl_rst_user)
begin
    if(tl_rst_user) begin 
        rc_bdf     <= 16'd0;
        np_tag     <= 8'd0;
    end else if( tl_rx_sop_ff ) begin
        rc_bdf     <= tl_rx_data_ff[223:208];
        np_tag     <= tl_rx_data_ff[207:200];
    end
end

//--------------------------------------------
// IOw & IOr
//--------------------------------------------
always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin 
        for(i=0;i<=5;i=i+1)begin : ep_io_array_rest
          iodata_array[i] <= 32'd0;
        end
    end else if(iow_flag & tl_rx_sop_2ff ) begin 
        for(i=0;i<=5;i=i+1)begin : ep_io_array_vaule
          if(io_addr==i)
            iodata_array[i] <= tl_rx_data_2ff[159:128];
        end
    end
end

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin 
        iodata <= 32'd0;
    end else begin 
        iodata <= iodata_array[io_addr];
    end
end

//--------------------------------------------
// MEMw & MEMr
//--------------------------------------------
// cache data in data array

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin 
        mwdata_wr_en <= 1'b0;
    end else if( memwr_flag ) begin 
        mwdata_wr_en <= tl_rx_eop_2ff ? tl_rx_sop_2ff : tl_rx_valid_2ff[7];
    end else begin 
        mwdata_wr_en <= 1'b0;    
    end 
end

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin 
        mwdata_wr_addr    <= 7'h0;
    end else if( memwr_flag  ) begin 
        if( mwdata_wr_en  ) begin 
            mwdata_wr_addr    <= mwdata_wr_addr + 1'b1;
        end
    end else begin 
        mwdata_wr_addr    <= 7'h0;
    end
end

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        mwdata_wr_data <= 256'd0;
    end else if( memwr_flag ) begin 
        if(mem_addr_is_64bit) begin 
              mwdata_wr_data <= {tl_rx_data_2ff[127:0],tl_rx_data_ff[255:128]} ;
        end else  begin 
              mwdata_wr_data <= {tl_rx_data_2ff[159:0],tl_rx_data_ff[255:160]} ;
        end
    end
end


// ==== 本移植：厂商那块 4KB 玩具 RAM 换成真正的 BAR0 窗口 ====
//   （原 RAM 写地址按包内位置自增、读地址当 32B 字索引、>4KB 全回卷）
wire [6:0] memrd_addr_lo;

ep_bar_win #(
    .MAGIC    (32'h5043_4946   ),
    .VERSION  (32'h0002_0000   ),
    .PTR_BYTES(IMG_PTRBYTES    ),
    .CLK_MHZ  (IMG_CLK_MHZ     )
) u_ep_bar_win (
    .clk            (tl_clk_user            ),
    .rst            (tl_rst_user            ),
    .rx_sop_ff      (tl_rx_sop_ff           ),
    .rx_data_ff     (tl_rx_data_ff          ),
    .mrdata_rd_data (mrdata_rd_data         ),
    .memrd_addr_lo  (memrd_addr_lo          ),
    .ctrl_enable    (img_ctrl_enable        ),
    .ctrl_trigger   (img_ctrl_trigger       ),
    .ctrl_pattern   (img_ctrl_pattern       ),
    .st_ready       (img_st_ready           ),
    .st_busy        (img_st_busy            ),
    .st_frame_cnt   (img_st_frame_cnt       ),
    .st_width       (img_st_width           ),
    .st_height      (img_st_height          ),
    .st_data_len    (img_st_data_len        ),
    .fb_raddr       (img_fb_raddr           ),
    .fb_rdata       (img_fb_rdata           ),
    .dbg_rd_idx     (img_dbg_rd_idx         ),
    .cam_stat       (cam_stat_bus           ),
    .cam_tap_cfg    (cam_tap_cfg            ),
    .cam_tap_b_cfg  (cam_tap_b_cfg          ),
    .cam_ab_sel     (cam_ab_sel             ),
    .cam_diag_b     (cam_diag_b             ),
    .cam_drop_a     (cam_drop_a             ),
    .ddr_ro_b       (ddr_ro_b               ),
    .ctrl_ddr_en    (img_ctrl_ddr_en        ),
    .ddr_ro         (img_ddr_ro             ),
    .host_rd_prio   (img_host_rd_prio       ),
    .host_grant     (img_host_grant         ),
    // 推帧寄存器面（0xB0~0xCC）与用户侧 TL 发送口
    .push_ro        (img_push_ro            ),
    .ctrl_push_en   (img_push_en            ),
    .ctrl_push_src  (img_push_src           ),
    .push_dst_lo    (img_push_dst_lo        ),
    .push_dst_hi    (img_push_dst_hi        ),
    .push_db_lo     (img_push_db_lo         ),
    .push_db_hi     (img_push_db_hi         ),
    // T07：RKA1 安全扩展寄存器面 + CSI 诊断（过路，逻辑在顶层/安全门）
    .tx_cap_bytes   (tx_cap_bytes           ),
    .tx_session_id  (tx_session_id          ),
    .tx_cmd_arm     (tx_cmd_arm             ),
    .tx_cmd_ack     (tx_cmd_ack             ),
    .tx_cmd_cancel  (tx_cmd_cancel          ),
    .tx_ack_seq     (tx_ack_seq             ),
    .tx_ack_session (tx_ack_session         ),
    .tx_status_in   (tx_status_in           ),
    .tx_block_cfg   (tx_block_cfg           ),
    .cfg_reject     (cfg_reject             ),
    .csi_diag_a     (csi_diag_a             ),
    .csi_diag_a2    (csi_diag_a2            ),
    .csi_diag_b     (csi_diag_b             ),
    .csi_diag_b2    (csi_diag_b2            )
);

// ====================================================================
// TX Engine
// T07 仿真兼容修正（行为不变）：tl_tx_state / TL_TX_* 的声明已提前到文件
// Parameter|Wire|Reg 段（本段下面第一次使用之前），这里不再重复声明。
// ====================================================================

// 顶层据此把 tl_tx_* 换成用户侧那一组
assign  utx_sel = (tl_tx_state == TL_TX_USER);


assign  tl_tx_err    = 8'b0;
assign  tl_tx_stream = 1'b0;

always@(posedge tl_clk_user) begin
    if(tl_rst_user) begin
        tl_tx_state <= TL_TX_IDLE;
        tl_tx_data  <= 'd0;
        tl_tx_eop   <= 'd0;
        tl_tx_sop   <= 'd0;
        tl_tx_valid <= 'd0;
    end else begin 
       case( tl_tx_state ) 
            TL_TX_IDLE: begin 
                if(iow_flag)
                    tl_tx_state <= TL_TX_ACK_IOW;
                else if(ior_flag)
                    tl_tx_state <= TL_TX_ACK_IOR;
                else if(memrd_flag)
                    tl_tx_state <= TL_TX_ACK_MEMR;
                else if(|tl_int_msix_trigger_ff)
                    tl_tx_state <= TL_TX_ACK_MSIX;
                else if(utx_req)                      // 用户侧推帧：最低优先权
                    tl_tx_state <= TL_TX_USER;
                else 
                    tl_tx_state <= tl_tx_state; 
            end

            TL_TX_ACK_IOW:begin  // ack cpl
                if( tl_tx_eop & tl_tx_sop & !tl_tx_wait) begin 
                    tl_tx_eop       <= 1'b0;
                    tl_tx_sop       <= 1'b0;
                    tl_tx_valid     <= 8'h0;
                    tl_tx_state     <= TL_TX_IDLE;
                end else begin
                    tl_tx_eop       <= 1'b1;
                    tl_tx_sop       <= 1'b1;
                    tl_tx_valid     <= 8'hE0;
                end
                
                tl_tx_data <= {`CPL_FMT                              ,
                               `CPL_TYPE                             ,
                               1'b0                                 , // R
                               3'b0                                 , // tc
                               1'b0                                 , // R
                               1'b0                                 , // attr[2]
                               1'b0                                 , // R
                               1'b0                                 , // th
                               1'b0                                 , // td
                               1'b0                                 , // ep 
                               2'b0                                 , // attr
                               2'b0                                 , // AT
                               10'b1                                , // length(dw)
                               `EP_PF0_BDF                           , // completer id
                               3'b000                               , // status
                               1'b0                                 , // bcm
                               12'h0                                , // byte count
                               rc_bdf[15:0]                         , // requester id
                               np_tag[7:0]                          , // np_tag
                               1'b0                                 , // R
                               1'b0                                 , // tile to 1'b0
                               io_addr[5:0]                         , // Lower Address
                               160'd0
                              };
            end

            TL_TX_ACK_IOR:begin  // ack cpld with only one dw
                if( tl_tx_eop & tl_tx_sop & !tl_tx_wait) begin 
                    tl_tx_eop       <= 1'b0;
                    tl_tx_sop       <= 1'b0;
                    tl_tx_valid     <= 8'h0;
                    tl_tx_state     <= TL_TX_IDLE;
                end else begin
                    tl_tx_eop       <= 1'b1;
                    tl_tx_sop       <= 1'b1;
                    tl_tx_valid     <= 8'hF0;
                end
                
                tl_tx_data <= {`CPLD_FMT                            ,
                               `CPLD_TYPE                           ,
                               1'b0                                 , // R
                               3'b0                                 , // tc
                               1'b0                                 , // R
                               1'b0                                 , // attr[2]
                               1'b0                                 , // R
                               1'b0                                 , // th
                               1'b0                                 , // td
                               1'b0                                 , // ep 
                               2'b0                                 , // attr
                               2'b0                                 , // AT
                               10'b1                                , // length(dw)
                               `EP_PF0_BDF                          , // completer id
                               3'b000                               , // status
                               1'b0                                 , // bcm
                               12'h4                                , // byte count
                               rc_bdf[15:0]                         , // requester id
                               np_tag[7:0]                          , // np_tag
                               1'b0                                 , // R
                               1'b0                                 , // tile to 1'b0
                               io_addr[5:0]                         , // Lower Address
                               iodata[31:0]                         , // Read Data 
                               128'd0
                              };   
            end

            TL_TX_ACK_MEMR:begin 
                if( mem_first_cycle ) // first cycle
                    tl_tx_sop <= 1'b1;
                else 
                    tl_tx_sop <= 1'b0;
                                  
                if(tl_tx_eop & (!tl_tx_wait))
                    tl_tx_eop <= 1'b0;
                else if( mem_first_cycle & mrdata_cycle == 10'd0 )
                    tl_tx_eop <= 1'b1;
                else if(tl_tx_valid[7] & (!tl_tx_wait) & (mrdata_cycle == 10'd0) )
                    tl_tx_eop <= 1'b1;

                if(mem_first_cycle | tl_tx_valid[7] & (!tl_tx_wait) )
                    tl_tx_valid <= mrdata_cycle_valid;

                if(mem_first_cycle) 
                    tl_tx_data <= {`CPLD_FMT                            ,
                                   `CPLD_TYPE                           ,
                                   1'b0                                 , // R
                                   3'b0                                 , // tc
                                   1'b0                                 , // R
                                   1'b0                                 , // attr[2]
                                   1'b0                                 , // R
                                   1'b0                                 , // th
                                   1'b0                                 , // td
                                   1'b0                                 , // ep 
                                   2'b0                                 , // attr
                                   2'b0                                 , // AT
                                   tl_mr_len_ff[9:0]                    , // length(dw)
                                   `EP_PF0_BDF                          , // completer id
                                   3'b000                               , // status
                                   1'b0                                 , // bcm
                                   {tl_mr_len_ff[9:0],2'b0}             , // byte count
                                   rc_bdf[15:0]                         , // requester id
                                   np_tag[7:0]                          , // np_tag
                                   1'b0                                 , // R
                                   memrd_addr_lo[6:0]                      , // Lower Address
                                   mrdata_rd_data[255:96]
                                   };  
                else if(tl_tx_valid[7] & (!tl_tx_wait) ) 
                     tl_tx_data <=  { mrdata_rd_data_ff[95:0], mrdata_rd_data[255:96] };

                if( tl_tx_eop & tl_tx_valid[7] & (!tl_tx_wait)  )
                    tl_tx_state     <= TL_TX_IDLE;
            end

            TL_TX_ACK_MSIX:begin

                if( tl_tx_eop & tl_tx_sop & !tl_tx_wait) begin 
                    tl_tx_eop       <= 1'b0;
                    tl_tx_sop       <= 1'b0;
                    tl_tx_valid     <= 8'h0;
                    tl_tx_state     <= TL_TX_IDLE;
                end else begin
                    tl_tx_eop       <= 1'b1;
                    tl_tx_sop       <= 1'b1;
                    tl_tx_valid     <= 8'hF8;
                end

                tl_tx_data <= {`MWR_FMT_4DW                         ,
                               `MWR_TYPE                            ,
                               1'b0                                 , // R
                               3'b0                                 , // tc
                               1'b0                                 , // R
                               1'b0                                 , // attr[2]
                               1'b0                                 , // R
                               1'b0                                 , // th
                               1'b0                                 , // td
                               1'b0                                 , // ep 
                               2'b0                                 , // attr
                               2'b0                                 , // AT
                               10'd1                                , // length(dw)
                               `EP_PF0_BDF                           , // requester id
                               8'd0                                 , // np_tag
                               4'h0                                 , // last be 
                               4'hf                                 , // first be
                               tl_msix_sgm_addr_ff[63:2]            , // address
                               2'b0                                 , // ph
                               tl_msix_sgm_data_ff[31:0]            ,
                               96'd0
                              };
            end
            TL_TX_USER:begin
                // 本步新增：TL 发送口的输出由顶层换成用户侧那一组（utx_data/sop/eop/
                // valid），这里只把本状态机自己的寄存器清零、并在用户侧发出 eop 且
                // 被链路收走（!tl_tx_wait）后回到 IDLE，把口子还给 CPL/CPLD。
                tl_tx_data  <= 'd0;
                tl_tx_eop   <= 1'b0;
                tl_tx_sop   <= 1'b0;
                tl_tx_valid <= 8'h0;
                if( utx_eop & (|utx_valid) & (!tl_tx_wait) )
                    tl_tx_state <= TL_TX_IDLE;
            end
       endcase
    end

end

always@(posedge tl_clk_user or posedge tl_rst_user) 
begin 
    if(tl_rst_user)
        mem_first_cycle <= 1'b1;
    else if(tl_tx_state == TL_TX_IDLE  )
        mem_first_cycle <= 1'b1;
    else 
        mem_first_cycle <= 1'b0;
end

always@(posedge tl_clk_user or posedge tl_rst_user) 
begin 
    if(tl_rst_user)
        mem_addr_is_64bit <= 1'b0;
    else if( tl_rx_sop_ff  )
        if( ( tl_rx_data_ff[255:253] == `MRD_FMT_4DW ) | ( tl_rx_data_ff[255:253] ==`MWR_FMT_4DW  )  )
            mem_addr_is_64bit <= 1'b1;
        else 
            mem_addr_is_64bit <= 1'b0;
   else 
        mem_addr_is_64bit <= mem_addr_is_64bit;
end

always@(posedge tl_clk_user or posedge tl_rst_user) 
begin 
    if(tl_rst_user)
        tl_mr_len_ff <= 11'b0;
    else if( tl_rx_sop_ff  )
        if( (tl_rx_data_ff[255:253] == `MRD_FMT_3DW || tl_rx_data_ff[255:253] == `MRD_FMT_4DW )  & tl_rx_data_ff[252:248] == `MRD_TYPE )
            tl_mr_len_ff  <= (|tl_rx_data_ff[233:224]) ? {1'b0,tl_rx_data_ff[233:224]}  : 11'd1024 ; // max is 1024*4 = 4096 bytes
   else 
        tl_mr_len_ff   <= tl_mr_len_ff;
end

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin 
        mrdata_rd_data_ff <= 256'd0;  
    end else if(tl_tx_state == TL_TX_ACK_MEMR) begin 
        if(tl_tx_valid[7] & (!tl_tx_wait) | mem_first_cycle)begin
        mrdata_rd_data_ff <= mrdata_rd_data; 
        end
    end
end

always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        mrdata_rd_addr_dly <= 7'd0;
    end else begin 
        mrdata_rd_addr_dly <= mrdata_rd_addr;
    end
end 

always@( * ) begin
    if(tl_tx_state == TL_TX_ACK_MEMR) begin 
        if(tl_tx_valid[7] & (!tl_tx_wait) | mem_first_cycle)begin
           mrdata_rd_addr = mrdata_rd_addr_dly + 1'b1 ;
        end else begin
           mrdata_rd_addr = mrdata_rd_addr_dly;
        end 
    end else begin 
        mrdata_rd_addr    = 7'b0;
    end
end

assign  mrdata_cycle_valid_32bit = 10'h3_e0  >> (tl_mr_len_ff[3:0] );
assign  mrdata_cycle_valid_tmp   = 16'hff_00 >> (mrdata_cycle[3:0] );

always@(posedge tl_clk_user or posedge tl_rst_user) begin
     if(tl_rst_user) begin
        mrdata_cycle <= 10'd0;
     end else begin 
        case(tl_tx_state)
            TL_TX_IDLE : begin 
                mrdata_cycle        <= tl_mr_len_ff[10:0] > 5 ? tl_mr_len_ff[10:0] - 5 : 11'd0;
                mrdata_cycle_valid  <= tl_mr_len_ff[10:0] > 5 ? 8'hff                : {3'h7,mrdata_cycle_valid_32bit[4:0] };
            end
            TL_TX_ACK_MEMR :begin 
                if( tl_tx_valid[7] & (!tl_tx_wait) | mem_first_cycle ) begin 
                    mrdata_cycle        <= mrdata_cycle > 8 ? mrdata_cycle - 8 : 10'd0;
                    mrdata_cycle_valid  <= mrdata_cycle > 8 ? 8'hff : mrdata_cycle_valid_tmp[7:0];
                end
            end
        default:;
        endcase
     end
end

// ====================================================================
// MSIx Rec
// default 64bit bar4 is msix bar
// ====================================================================
`ifdef PH1P_PCIE_MSIX_INT_ENABLE
always@(posedge tl_clk_user or posedge tl_rst_user) begin
    if(tl_rst_user) begin
        tl_msix_sgm_addr_0 <= 64'd0;
        tl_msix_sgm_addr_1 <= 64'd0;
        tl_msix_sgm_addr_2 <= 64'd0;
        tl_msix_sgm_addr_3 <= 64'd0;
        tl_msix_sgm_data_0 <= 32'd0;
        tl_msix_sgm_data_1 <= 32'd0;
        tl_msix_sgm_data_2 <= 32'd0;
        tl_msix_sgm_data_3 <= 32'd0;
    end else if( memwr_flag ) begin 
        // msg0
        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[143:128] == ( `MSIX_TABLE_OFFSET << 3 )         ) begin 
            tl_msix_sgm_addr_0[31:0] <= tl_rx_data_2ff[127:96];
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[143:128] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h4 ) begin 
            tl_msix_sgm_addr_0[63:32] <= tl_rx_data_2ff[127:96];
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[143:128] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h8 ) begin 
            tl_msix_sgm_data_0[31:0]  <= tl_rx_data_2ff[127:96];
        end
        
        // msg1
        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[143:128] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h10 ) begin 
            tl_msix_sgm_addr_1[31:0] <= tl_rx_data_2ff[127:96];
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[143:128] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h14 ) begin 
            tl_msix_sgm_addr_1[63:32] <= tl_rx_data_2ff[127:96];
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[143:128] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h18 ) begin 
            tl_msix_sgm_data_1[31:0]  <= tl_rx_data_2ff[127:96];
        end
        
        // msg2
        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[143:128] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h20 ) begin 
            tl_msix_sgm_addr_2[31:0] <= tl_rx_data_2ff[127:96];
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[143:128] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h24 ) begin 
            tl_msix_sgm_addr_2[63:32] <= tl_rx_data_2ff[127:96];
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[143:128] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h28 ) begin 
            tl_msix_sgm_data_2[31:0]  <= tl_rx_data_2ff[127:96];
        end

        // msg3
        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[143:128] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h30 ) begin 
            tl_msix_sgm_addr_3[31:0] <= tl_rx_data_2ff[127:96];
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[143:128] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h34 ) begin 
            tl_msix_sgm_addr_3[63:32] <= tl_rx_data_2ff[127:96];
        end

        if(tl_rx_sop_2ff & tl_rx_bardec_2ff[4] & tl_rx_data_2ff[143:128] == ( `MSIX_TABLE_OFFSET << 3 ) + 16'h38 ) begin 
            tl_msix_sgm_data_3[31:0]  <= tl_rx_data_2ff[127:96];
        end
    end
end

always@(posedge tl_clk_user ) begin 
    tl_int_msix_trigger_ff  <= tl_int_msix_trigger;
    case(tl_int_msix_trigger_ff)
    4'b0001: begin 
        tl_msix_sgm_addr_ff <= tl_msix_sgm_addr_0;
        tl_msix_sgm_data_ff <= tl_msix_sgm_data_0;
    end
    4'b0010: begin 
        tl_msix_sgm_addr_ff <= tl_msix_sgm_addr_1;
        tl_msix_sgm_data_ff <= tl_msix_sgm_data_1;
    end
    4'b0100: begin 
        tl_msix_sgm_addr_ff <= tl_msix_sgm_addr_2;
        tl_msix_sgm_data_ff <= tl_msix_sgm_data_2;
    end
    4'b1000: begin 
        tl_msix_sgm_addr_ff <= tl_msix_sgm_addr_3;
        tl_msix_sgm_data_ff <= tl_msix_sgm_data_3;
    end
    default: ;
    endcase
end
`endif

endmodule
