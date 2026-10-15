///////////////////////////////////////////////////////////////
//  img_regs.v — PCIe EP 用户寄存器块 + 帧数据窗口
//
//  挂在 ph1p_pcie_ep_top 的 fabric-logic UBUS 上
//  （ep_ubus_bridge 把 waddr/raddr[31:24]==8'hFF 的访问送到逻辑侧）。
//
//  寄存器索引空间：字节地址 0x40 ~ 0x7F（= 索引 16~31），
//  避开原设计占用的 0x00~0x1C（ltssm / 链路状态那批）。
//
//  UBUS 时序（与原设计保持一致）：
//    T0 : ubus_ren 拉起
//    T1 : ren_dly=1，地址有效
//    T2 : bken 与 rdata 同拍有效（读延迟 2 拍）
//
//  寄存器表（字节偏移 → 名字）：
//    0x40  MAGIC       R    0x50434946 ("FICP" 小端)，用于探测本模块
//    0x44  CTRL        R/W  bit0 = enable（连续出帧），bit1 = 单帧触发（自清）
//    0x48  STATUS      R    bit0 = ready（出过帧）, bit1 = busy（正在写缓存）
//    0x4C  FRAME_CNT   R    已完成帧数
//    0x50  WIDTH       R    图像宽（像素）
//    0x54  HEIGHT      R    图像高（行）
//    0x58  DATA_LEN    R    每帧字节数
//    0x5C  PTR         R/W  数据窗口读指针（字节偏移，写设置、读回当前值）
//    0x60  DATA        R    返回 PTR 处的 32bit 并自动 PTR += 4（读完整帧用）
//    0x64  VERSION     R    本模块版本
//    0x68  CLK_MHZ     R    用户逻辑时钟频率(MHz)，主机用来算带宽
//    0x6C  SCRATCH     R/W 读写回环，寄存器通路自检
///////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module img_regs #(
    parameter [31:0] MAGIC    = 32'h5043_4946,   // "FICP"
    parameter [31:0] VERSION  = 32'h0001_0000,   // v1.0
    parameter [31:0] PTR_MASK = 32'h0001_2BFC    // 320x240-4，缓冲区回绕掩码
)(
    input  wire        clk,
    input  wire        rst,

    input  wire [8:0]  clk_mhz,

    // UBUS（fabric logic 侧，来自 ep_ubus_bridge）
    input  wire        ubus_wen,
    input  wire [31:0] ubus_waddr,
    input  wire [31:0] ubus_wdata,
    input  wire        ubus_ren,
    input  wire [31:0] ubus_raddr,

    output wire        hit_dly,     // 本次访问落在本模块地址范围（与 bken 同拍）
    output wire        bken,
    output wire [31:0] rdata,

    // 帧缓存读口（接 img_frame_src）
    output wire [31:0] fb_raddr,
    input  wire [31:0] fb_rdata,

    // 控制/状态（接 img_frame_src）
    output wire        ctrl_enable,
    output wire        ctrl_trigger,
    input  wire        st_ready,
    input  wire        st_busy,
    input  wire [31:0] st_frame_cnt,
    input  wire [15:0] st_width,
    input  wire [15:0] st_height,
    input  wire [31:0] st_data_len
);

    // 本模块占字节地址 0x40~0x7F（addr[7:6] == 2'b01）

    reg        ren_dly, wen_dly;
    reg [31:0] raddr_dly, waddr_dly, wdata_dly;
    reg        bken_r;
    reg [31:0] rdata_r;
    reg        hit_dly_r;

    reg        ctrl_en, ctrl_trig, trig_d;
    reg [31:0] scratch;
    reg [31:0] rd_ptr;

    assign hit_dly      = hit_dly_r;
    assign bken         = bken_r;
    assign rdata        = rdata_r;
    assign fb_raddr     = rd_ptr;
    assign ctrl_enable  = ctrl_en;
    assign ctrl_trigger = ctrl_trig & ~trig_d;    // 单拍脉冲

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ren_dly    <= 1'b0;
            wen_dly    <= 1'b0;
            raddr_dly  <= 32'd0;
            waddr_dly  <= 32'd0;
            wdata_dly  <= 32'd0;
            bken_r     <= 1'b0;
            rdata_r    <= 32'd0;
            hit_dly_r  <= 1'b0;
            ctrl_en    <= 1'b0;
            ctrl_trig  <= 1'b0;
            trig_d     <= 1'b0;
            scratch    <= 32'd0;
            rd_ptr     <= 32'd0;
        end else begin
            // ---- 1 拍延迟 ----
            ren_dly   <= ubus_ren;
            wen_dly   <= ubus_wen;
            raddr_dly <= ubus_raddr;
            waddr_dly <= ubus_waddr;
            wdata_dly <= ubus_wdata;
            trig_d    <= ctrl_trig;

            // ---- 读响应：bken 自清，rdata 与 bken 同拍 ----
            bken_r    <= bken_r ? 1'b0 : (ren_dly ? 1'b1 : 1'b0);
            hit_dly_r <= ren_dly & (raddr_dly[7:6] == 2'b01);

            case (raddr_dly[7:0])
                8'h40:   rdata_r <= MAGIC;
                8'h44:   rdata_r <= {30'd0, ctrl_trig, ctrl_en};
                8'h48:   rdata_r <= {30'd0, st_busy, st_ready};
                8'h4C:   rdata_r <= st_frame_cnt;
                8'h50:   rdata_r <= {16'd0, st_width};
                8'h54:   rdata_r <= {16'd0, st_height};
                8'h58:   rdata_r <= st_data_len;
                8'h5C:   rdata_r <= rd_ptr;
                8'h60:   rdata_r <= fb_rdata;
                8'h64:   rdata_r <= VERSION;
                8'h68:   rdata_r <= {23'd0, clk_mhz};
                8'h6C:   rdata_r <= scratch;
                default: rdata_r <= 32'hDEAD_BEEF;
            endcase

            // ---- 写 + 指针维护（rd_ptr 只在此处驱动，避免多驱动）----
            if (wen_dly && waddr_dly[7:6] == 2'b01) begin
                case (waddr_dly[7:0])
                    8'h44: begin
                        ctrl_en   <= wdata_dly[0];
                        ctrl_trig <= wdata_dly[1];
                    end
                    8'h5C:   rd_ptr <= wdata_dly & PTR_MASK;
                    8'h6C:   scratch <= wdata_dly;
                    default: ;
                endcase
            end else if (ren_dly && raddr_dly[7:6] == 2'b01 && raddr_dly[7:0] == 8'h60) begin
                // 读 DATA：返回当前指针的字，然后指针 +4（读到末尾回绕到 0）
                rd_ptr <= (rd_ptr + 32'd4) & PTR_MASK;
            end
        end
    end

endmodule
