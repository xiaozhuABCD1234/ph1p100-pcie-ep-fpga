///////////////////////////////////////////////////////////////////////////////
//  ddr_frame_readback_checker.v — 板内 DDR 读回校验核心（本包离线引入，不接顶层）
//
//  用途：对 cam_r10f_writer 写进 DDR3 的 R10F v1 帧做板内自证读回校验：
//  用 AXI4 读主把 [base, base+frame_bytes) 读回，按 R10F 规则核对
//    magic、header_crc32、payload_crc32、长度；
//  抽样字（≥6）仅作证据，不参与判定。全程单时钟 dhi_clk（100 MHz）。
//
//  ===========================================================================
//  一、冻结口径（本包 dev-notes.md 记录；与 fpga-design-guide §3 一致）
//  ===========================================================================
//   · 帧布局：头 [base, base+128)、packed 载荷 [base+128, base+128+P)、
//     其余为 4KiB 对齐尾填充；P = payload_bytes（头 0x30 = word12）。
//     magic = "R10F" = 0x4630_3152（头 word0，小端）。
//   · 头字段：raw_crc32=word20(0x50)、payload_crc32=word21(0x54)、
//     header_crc32=word22(0x58)。
//   · header_crc32 重算：word22 置 0 后覆盖完整 128B；payload_crc32 覆盖
//     packed 载荷；尾填充不进任何 CRC。CRC32 poly 0xEDB88320（反射）、
//     init 全 1、末值取反（与 crc32_upd4.v / gen_crc32_flat.py 一致）。
//   · 长度判定（等价 writer 的 DMA_BYTES = ceil((128+P)/4096)*4096）：
//     P != 0 且 frame_bytes[11:0]==0 且 frame_bytes >= 128+P 且
//     frame_bytes-(128+P) < TAIL_MAX(=4096)。
//   · 抽样（证据，不判定；P==0 时载荷抽样=0）：
//     smp0=head[0]；smp1=head[20]；smp2=head[21]；smp3=head[22]；
//     smp4=载荷首字（word32）；smp5=含载荷末字节的 32bit 字。
//   · 读超时：TIMEOUT_CYCLES=2^21=2,097,152 拍（@100MHz ≈21 ms）为**单次等待**
//     （等 AR 或等 R）无进展的上限；命中即粘滞（tmo_r），收尾时按粘滞位判码。
//     最坏理论读时长：1080p 81,024 拍 × 每拍 8 周期字处理 = 648,192 拍
//     ⇒ 阈值 ≥2× 最坏值（实际 3.24×）。
//   · busy 重入拒绝：start 仅在本模块 IDLE 时被采样，busy 期间忽略（不重启、
//     不清进度）。abort 仅 busy 期间有效：中止读回并收尾（fail-closed）。
//   · err_code：0 无错；1 magic；2 header_crc；3 payload_crc；4 长度；
//     5 AXI 响应非 OKAY（或 rlast 与拍数不符）；6 读超时；7 abort；
//     8 参数非法（frame_bytes=0 / >MAX_FRAME_BYTES / base 越出 29bit 窗口 /
//     base 非 32B 对齐）。done 时优先级：abort>timeout>AXI>magic>长度>
//     header_crc>payload_crc。逐项 ok 位只在对应检查真正执行过才置位；
//     中止/超时/参数非法时保持 0（不补假 PASS）。
//   · 读法：AXI4 读主 256bit/INCR（arsize=5，arlen≤127=4KiB 突发），与
//     ddr_frame_pusher.v 的 AXI 风格一致；每拍 8 个 32bit 字**串行**处理
//     （8 周期/拍，扁平 crc32_upd4 每周期一级，STA 友好；读数带宽
//     ~400 MB/s @100MHz，够用）。words_read=已处理 32bit 字数
//     （=8×拍数；32B 对齐帧时 = frame_bytes/4）。
//   · 本模块不集成进生产顶层、不参与构建（集成=后续主题：AXI 读仲裁 +
//     状态寄存器；本包只交付 RTL+TB 与回归证据）。
//
//  ===========================================================================
//  二、验证入口
//  ===========================================================================
//   · sim/tb/tb_ddr_frame_readback_checker.v（正例：小尺寸 + 1080p 全帧；
//     负例 ≥4：magic/长度/头CRC/载荷CRC/AXI 响应/读超时/abort + busy 重入）。
//   · 运行：tools/pcie_integration/run_sim.ps1 -Tb tb_ddr_frame_readback_checker
//     -OutDir <dir> -TbFiles tb/tb_ddr_frame_readback_checker.v（判定看 vsim.log
//     的 ALL PASS / FAIL）。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module ddr_frame_readback_checker #(
    parameter integer BURST_BEATS    = 128,            // 每突发最大拍数（4KiB @32B/拍）
    parameter [31:0]  TIMEOUT_CYCLES = 32'h0020_0000,  // 2^21：单次等待无进展上限
    parameter [31:0]  MAGIC          = 32'h4630_3152,  // "R10F"
    parameter [31:0]  MAX_FRAME_BYTES= 32'h0100_0000,  // 16 MiB（覆盖 4K + 余量）
    parameter [31:0]  TAIL_MAX       = 32'd4096         // 尾填充上限（4KiB 对齐规则）
)(
    input  wire         clk_dhi,        // 单时钟域（100 MHz）
    input  wire         rst_dhi,        // 异步复位，高有效

    // ---------------- 控制 ----------------
    input  wire         start,          // IDLE 时采样（建议单拍脉冲）；busy 期间忽略
    input  wire [63:0]  base,           // DDR 字节基址（用 [28:0]；须 32B 对齐）
    input  wire [31:0]  frame_bytes,    // 发布长度（1080p=2,592,768）
    input  wire         abort,          // busy 期间有效：中止本次读回

    // ---------------- 状态 / 结果 ----------------
    output reg          busy,
    output reg          done,           // 完成粘滞（下次 start 清）
    output reg          magic_ok,
    output reg          hdr_crc_ok,
    output reg          payload_crc_ok,
    output reg          length_ok,
    output reg  [7:0]   err_code,
    output reg  [31:0]  rd_header_crc32,    // 重算的头 CRC（末值）
    output reg  [31:0]  rd_payload_crc32,   // 重算的载荷 CRC（末值）
    output reg  [31:0]  words_read,         // 已处理 32bit 字数
    output reg  [31:0]  smp0, smp1, smp2, smp3, smp4, smp5,

    // ---------------- AXI4 读通道 ----------------
    output wire [3:0]   m_axi_arid,
    output reg  [28:0]  m_axi_araddr,
    output reg  [7:0]   m_axi_arlen,
    output wire [2:0]   m_axi_arsize,
    output wire [1:0]   m_axi_arburst,
    output reg          m_axi_arvalid,
    input  wire         m_axi_arready,
    input  wire [3:0]   m_axi_rid,
    input  wire [255:0] m_axi_rdata,
    input  wire [1:0]   m_axi_rresp,
    input  wire         m_axi_rlast,
    input  wire         m_axi_rvalid,
    output wire         m_axi_rready
);

    // ========================================================================
    //  常量 / 错误码 / 状态
    // ========================================================================
    localparam [2:0]  AXI_SIZE  = 3'd5;      // 2**5 = 32 字节/拍
    localparam [1:0]  AXI_BURST = 2'b01;     // INCR

    localparam [7:0]  E_NONE    = 8'd0,
                      E_MAGIC   = 8'd1,
                      E_HDR_CRC = 8'd2,
                      E_PAY_CRC = 8'd3,
                      E_LENGTH  = 8'd4,
                      E_AXI     = 8'd5,
                      E_TIMEOUT = 8'd6,
                      E_ABORT   = 8'd7,
                      E_PARAM   = 8'd8;

    localparam [2:0]  ST_IDLE = 3'd0,
                      ST_AR   = 3'd1,
                      ST_R    = 3'd2,
                      ST_PROC = 3'd3,
                      ST_FIN  = 3'd4;

    // ---- CRC 递推函数（生成文件；与 cam_r10f_writer.v 同一包含方式）----
    `include "crc32_upd4.v"

    // ========================================================================
    //  寄存器
    // ========================================================================
    reg  [2:0]   st;
    reg  [31:0]  fbytes_q;       // 本次读回长度（锁存）
    reg  [31:0]  beats_left;     // 剩余 32B 拍
    reg  [31:0]  burst_beats_q;  // 本突发拍数（≤BURST_BEATS）
    reg  [31:0]  rbeat_cnt;      // 本突发已收拍
    reg          rlast_done;     // 当前拍为突发末拍，处理完做突发收尾
    reg  [28:0]  addr_q;         // 当前突发字节地址
    reg  [2:0]   lane;           // 拍内 32bit 字序号 0..7
    reg  [255:0] rd_beat;        // 已收的 32B 拍
    reg  [31:0]  wcnt;           // 已处理 32bit 字的流序号
    reg  [31:0]  hdr_crc_q, pay_crc_q;
    reg  [31:0]  pbytes_q;       // 头 word12 payload_bytes
    reg  [31:0]  hdr_field_q;    // 头 word22 读出值
    reg  [31:0]  pay_field_q;    // 头 word21 读出值
    reg  [31:0]  tmo_cnt;
    reg          tmo_r;          // 超时粘滞（收尾判码用；下次 start 清）
    reg          axi_err_r;

    // ========================================================================
    //  组合量
    // ========================================================================
    wire [31:0]  beats_total = (frame_bytes + 32'd31) >> 5;
    wire [31:0]  burst_first = (beats_total >= BURST_BEATS) ? BURST_BEATS : beats_total;

    wire         bad_param   = (frame_bytes == 32'd0) ||
                               (frame_bytes > MAX_FRAME_BYTES) ||
                               (base[63:29] != 35'd0) ||
                               (base[4:0]   != 5'd0);

    wire [31:0]  beats_left_nxt = beats_left - burst_beats_q;
    wire [31:0]  burst_nxt      = (beats_left_nxt >= BURST_BEATS) ? BURST_BEATS : beats_left_nxt;
    wire [28:0]  addr_nxt       = addr_q + (burst_beats_q << 5);

    wire         abort_now = busy && abort;

    wire         quad_done = (st == ST_PROC) && (lane == 3'd7) && rlast_done &&
                             (beats_left == burst_beats_q);

    wire         tmo_hit = (tmo_cnt == TIMEOUT_CYCLES);

    wire         go_fin  = (st != ST_FIN) && (abort_now | tmo_hit | tmo_r | quad_done);

    wire [7:0]   e_final = abort_now      ? E_ABORT   :
                           tmo_r          ? E_TIMEOUT :
                           axi_err_r      ? E_AXI     :
                           !magic_ok      ? E_MAGIC   :
                           !length_ok     ? E_LENGTH  :
                           !hdr_crc_ok    ? E_HDR_CRC :
                           !payload_crc_ok? E_PAY_CRC : E_NONE;

    // ---- 流内字处理（ST_PROC 每周期一字）----
    wire [31:0]  pword    = rd_beat[(lane * 32) +: 32];
    wire [31:0]  off_now  = wcnt << 2;
    wire [31:0]  pay_end  = 32'd128 + pbytes_q;
    wire         in_hdr   = (wcnt < 32'd32);
    wire         in_pay   = (pbytes_q != 32'd0) && (off_now >= 32'd128) && (off_now < pay_end);
    wire         pay_part = in_pay && ((off_now + 32'd4) > pay_end);
    wire [1:0]   pay_k    = pay_end[1:0];
    wire         pay_last_word = in_pay && ((off_now + 32'd4) >= pay_end);

    wire [31:0]  hdr_word_eff = (wcnt == 32'd22) ? 32'd0 : pword;
    wire [31:0]  crc_hdr_upd  = crc32_upd4(hdr_crc_q,
                                           hdr_word_eff[7:0],  hdr_word_eff[15:8],
                                           hdr_word_eff[23:16], hdr_word_eff[31:24]);
    wire [31:0]  crc_pay_u1 = crc32_upd1(pay_crc_q, pword[7:0]);
    wire [31:0]  crc_pay_u2 = crc32_upd2(pay_crc_q, pword[7:0], pword[15:8]);
    wire [31:0]  crc_pay_u3 = crc32_upd3(pay_crc_q, pword[7:0], pword[15:8], pword[23:16]);
    wire [31:0]  crc_pay_u4 = crc32_upd4(pay_crc_q, pword[7:0], pword[15:8],
                                         pword[23:16], pword[31:24]);
    wire [31:0]  crc_pay_upd = pay_part ? ((pay_k == 2'd1) ? crc_pay_u1 :
                                           (pay_k == 2'd2) ? crc_pay_u2 : crc_pay_u3)
                                        : crc_pay_u4;

    wire [31:0]  smp5_idx = 32'd32 + ((pbytes_q - 32'd1) >> 2);

    // ========================================================================
    //  主时序
    // ========================================================================
    always @(posedge clk_dhi or posedge rst_dhi) begin
        if (rst_dhi) begin
            st         <= ST_IDLE;
            busy       <= 1'b0;
            done       <= 1'b0;
            magic_ok   <= 1'b0;
            hdr_crc_ok <= 1'b0;
            payload_crc_ok <= 1'b0;
            length_ok  <= 1'b0;
            err_code   <= E_NONE;
            rd_header_crc32  <= 32'd0;
            rd_payload_crc32 <= 32'd0;
            words_read <= 32'd0;
            smp0 <= 32'd0; smp1 <= 32'd0; smp2 <= 32'd0;
            smp3 <= 32'd0; smp4 <= 32'd0; smp5 <= 32'd0;
            fbytes_q     <= 32'd0;
            beats_left   <= 32'd0;
            burst_beats_q<= 32'd0;
            rbeat_cnt    <= 32'd0;
            rlast_done   <= 1'b0;
            addr_q       <= 29'd0;
            lane         <= 3'd0;
            rd_beat      <= 256'd0;
            wcnt         <= 32'd0;
            hdr_crc_q    <= 32'hFFFF_FFFF;
            pay_crc_q    <= 32'hFFFF_FFFF;
            pbytes_q     <= 32'd0;
            hdr_field_q  <= 32'd0;
            pay_field_q  <= 32'd0;
            tmo_cnt      <= 32'd0;
            tmo_r        <= 1'b0;
            axi_err_r    <= 1'b0;
            m_axi_araddr <= 29'd0;
            m_axi_arlen  <= 8'd0;
            m_axi_arvalid<= 1'b0;
        end else begin

            // ---------------- (A) ST_PROC 字处理（每周期一字）----------------
            if (st == ST_PROC) begin
                if (in_hdr) begin
                    hdr_crc_q <= crc_hdr_upd;
                    if (wcnt == 32'd0)  begin magic_ok <= (pword == MAGIC); smp0 <= pword; end
                    if (wcnt == 32'd12) pbytes_q <= pword;
                    if (wcnt == 32'd20) smp1 <= pword;
                    if (wcnt == 32'd21) begin pay_field_q <= pword; smp2 <= pword; end
                    if (wcnt == 32'd22) begin hdr_field_q <= pword; smp3 <= pword; end
                    if (wcnt == 32'd31) begin
                        rd_header_crc32 <= ~crc_hdr_upd;
                        hdr_crc_ok      <= (hdr_field_q == ~crc_hdr_upd);
                        length_ok       <= (pbytes_q != 32'd0) &&
                                           (fbytes_q[11:0] == 12'd0) &&
                                           (fbytes_q >= (32'd128 + pbytes_q)) &&
                                           ((fbytes_q - (32'd128 + pbytes_q)) < TAIL_MAX);
                    end
                end
                if (in_pay) begin
                    pay_crc_q <= crc_pay_upd;
                    if (pay_last_word) begin
                        rd_payload_crc32 <= ~crc_pay_upd;
                        payload_crc_ok   <= (pay_field_q == ~crc_pay_upd);
                    end
                end
                if ((pbytes_q != 32'd0) && (wcnt == 32'd32)) smp4 <= pword;
                if ((pbytes_q != 32'd0) && (wcnt == smp5_idx)) smp5 <= pword;
                wcnt <= wcnt + 32'd1;
            end

            // ---------------- 等待计时（单次无进展上限；命中粘滞）----------------
            if (((st == ST_AR) && m_axi_arvalid && !m_axi_arready) ||
                ((st == ST_R)  && !m_axi_rvalid)) begin
                tmo_cnt <= tmo_cnt + 32'd1;
                if (tmo_hit) tmo_r <= 1'b1;
            end else begin
                tmo_cnt <= 32'd0;
            end

            // ---------------- (B) 收尾 / 状态机 ----------------
            if (go_fin) begin
                st            <= ST_FIN;
                m_axi_arvalid <= 1'b0;      // 撤销未完成的 AR / 停止收拍
            end else begin
                case (st)
                    ST_IDLE: begin
                        if (start) begin
                            if (bad_param) begin
                                busy       <= 1'b0;
                                done       <= 1'b1;
                                err_code   <= E_PARAM;
                                magic_ok   <= 1'b0;
                                hdr_crc_ok <= 1'b0;
                                payload_crc_ok <= 1'b0;
                                length_ok  <= 1'b0;
                                rd_header_crc32  <= 32'd0;
                                rd_payload_crc32 <= 32'd0;
                                words_read <= 32'd0;
                                smp0 <= 32'd0; smp1 <= 32'd0; smp2 <= 32'd0;
                                smp3 <= 32'd0; smp4 <= 32'd0; smp5 <= 32'd0;
                                st <= ST_IDLE;
                            end else begin
                                busy        <= 1'b1;
                                done        <= 1'b0;
                                err_code    <= E_NONE;
                                fbytes_q    <= frame_bytes;
                                beats_left  <= beats_total;
                                burst_beats_q <= burst_first;
                                addr_q      <= base[28:0];
                                m_axi_araddr<= base[28:0];
                                m_axi_arlen <= burst_first[7:0] - 8'd1;
                                m_axi_arvalid <= 1'b1;
                                rbeat_cnt   <= 32'd0;
                                rlast_done  <= 1'b0;
                                lane        <= 3'd0;
                                wcnt        <= 32'd0;
                                tmo_cnt     <= 32'd0;
                                tmo_r       <= 1'b0;
                                axi_err_r   <= 1'b0;
                                hdr_crc_q   <= 32'hFFFF_FFFF;
                                pay_crc_q   <= 32'hFFFF_FFFF;
                                pbytes_q    <= 32'd0;
                                hdr_field_q <= 32'd0;
                                pay_field_q <= 32'd0;
                                magic_ok    <= 1'b0;
                                hdr_crc_ok  <= 1'b0;
                                payload_crc_ok <= 1'b0;
                                length_ok   <= 1'b0;
                                rd_header_crc32  <= 32'd0;
                                rd_payload_crc32 <= 32'd0;
                                words_read  <= 32'd0;
                                smp0 <= 32'd0; smp1 <= 32'd0; smp2 <= 32'd0;
                                smp3 <= 32'd0; smp4 <= 32'd0; smp5 <= 32'd0;
                                st <= ST_AR;
                            end
                        end
                    end

                    ST_AR: begin
                        if (m_axi_arready) begin
                            m_axi_arvalid <= 1'b0;
                            rbeat_cnt     <= 32'd0;
                            st            <= ST_R;
                        end
                    end

                    ST_R: begin
                        if (m_axi_rvalid) begin
                            rd_beat     <= m_axi_rdata;
                            lane        <= 3'd0;
                            rlast_done  <= m_axi_rlast | ((rbeat_cnt + 32'd1) == burst_beats_q);
                            if (m_axi_rlast !== ((rbeat_cnt + 32'd1) == burst_beats_q))
                                axi_err_r <= 1'b1;
                            if (m_axi_rresp != 2'b00) axi_err_r <= 1'b1;
                            rbeat_cnt   <= rbeat_cnt + 32'd1;
                            tmo_cnt     <= 32'd0;
                            st          <= ST_PROC;
                        end
                    end

                    ST_PROC: begin
                        if (lane == 3'd7) begin
                            if (rlast_done) begin
                                rbeat_cnt  <= 32'd0;
                                rlast_done <= 1'b0;
                                if (beats_left == burst_beats_q) begin
                                    st <= ST_FIN;
                                end else begin
                                    beats_left    <= beats_left_nxt;
                                    burst_beats_q <= burst_nxt;
                                    addr_q        <= addr_nxt;
                                    m_axi_araddr  <= addr_nxt;
                                    m_axi_arlen   <= burst_nxt[7:0] - 8'd1;
                                    m_axi_arvalid <= 1'b1;
                                    st            <= ST_AR;
                                end
                            end else begin
                                st <= ST_R;
                            end
                        end else begin
                            lane <= lane + 3'd1;
                        end
                    end

                    ST_FIN: begin
                        busy       <= 1'b0;
                        done       <= 1'b1;
                        err_code   <= e_final;
                        tmo_r      <= 1'b0;
                        words_read <= wcnt;
                        tmo_cnt    <= 32'd0;
                        m_axi_arvalid <= 1'b0;
                        st         <= ST_IDLE;
                    end

                    default: st <= ST_IDLE;
                endcase
            end
        end
    end

    // ========================================================================
    //  AXI 输出常量
    // ========================================================================
    assign m_axi_arid    = 4'd0;
    assign m_axi_arsize  = AXI_SIZE;
    assign m_axi_arburst = AXI_BURST;
    assign m_axi_rready  = (st == ST_R);

endmodule
