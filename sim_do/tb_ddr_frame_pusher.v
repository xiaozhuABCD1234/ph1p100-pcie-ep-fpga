///////////////////////////////////////////////////////////////
//  tb_ddr_frame_pusher.v — ddr_frame_pusher 冒烟测试（iverilog）
//
//  ★ 本机没有仿真器：本测试台「只写不跑」，结论里必须标注“未运行”。
//    在有 iverilog 的机器上跑：
//      iverilog -o tb_ddr_frame_pusher tb_ddr_frame_pusher.v \
//               ../../rtl/ep_side/ddr/ddr_frame_pusher.v
//      ./tb_ddr_frame_pusher          # 期望输出 "ALL PASS"
//
//  测什么：
//   1) 结构：整帧正好 NTLP 笔 MWr，每笔 5 拍（第 0 拍 valid=F0 只有 4 个 dw 头、
//      第 1..4 拍 valid=FF），sop 只在第 0 拍、eop 只在第 4 拍；之后正好一笔
//      单拍门铃（valid=F8、length=1、Last DW BE=0）；
//   2) 头字段：Fmt=4DW、Type=MWR、Length=32、RequesterID=EP_PF0_BDF、Tag=0、
//      First DW BE=F；地址 dw2/dw3 = {高 32 位, 低 30 位+00}，每笔 +128，
//      并跨过 32 位边界（低 32 位在帧中间回绕进高位）——这是本步最容易拼错的地方；
//   3) 字节序（最关键）：把 TL 口上收到的字节流按「每拍最高字节位的字节先出线」拼成
//      TLP 字节流后，载荷必须与假 DDR 里同一段数据**逐字节相同**（即主机内存里拿到的
//      就是 DDR3 里的那一帧，一个字节都不错位、不翻转）；
//   4) 反压：从机随机把 tl_tx_wait 拉高、并随机把「引擎让口子」推迟若干拍，
//      推帧必须原样保持那一拍（不许丢拍、不许重复计数）、不许提前超时；
//   5) 门铃：推完一帧后单独一笔 MWr 写到主机给的门铃地址，载荷 = 本帧序号（1 起），
//      主机按小端读出来的值就等于它（即线上的字节是 bswap 过的）；
//   6) 出错路径：目标地址配 0 时整帧不发、错误码 = 1；
//      门铃地址配 0 时数据照推、错误码 = 4、已推帧数仍 +1。
//
//  参数取小值以便跑得快：W=64,H=32 → 2048B/帧、16 笔 MWr、64 拍、4 个突发。
///////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_ddr_frame_pusher;

    localparam integer W           = 64;
    localparam integer H           = 32;
    localparam integer FRAME_BYTES = W * H;           // 2048
    localparam integer BEAT_BYTES  = 32;
    localparam integer TLP_BYTES   = 128;
    localparam integer NTLP        = FRAME_BYTES / TLP_BYTES;  // 16
    localparam integer PAY_BEATS   = 4;
    localparam integer NBEATS      = FRAME_BYTES / BEAT_BYTES; // 64
    localparam integer BB          = 16;              // BURST_BEATS
    localparam integer NBURST      = NBEATS / BB;     // 4
    localparam integer FIFO_AW     = 4;               // 深度 16 拍，故意做浅一点

    localparam [31:0] DDR_BASE0 = 32'h0010_0000;
    localparam [31:0] DDR_BASE1 = 32'h0018_0000;

    // 目标地址故意让低 32 位在帧中间回绕：0x0000_0001_FFFF_FF00 + 128*k
    localparam [63:0] DST_ADDR = 64'h0000_0001_FFFF_FF00;
    localparam [63:0] DB_ADDR  = 64'h0000_0002_0000_0008;

    localparam [15:0] WAIT_LIMIT = 16'h0FFF;          // 测试里放大到 4095 拍

    // ---------------- 时钟 / 复位 ----------------
    reg clk_fb  = 0;      // 62.5MHz（tl_clk_user）
    reg clk_ddr = 0;      // 100MHz（usr_clk）
    reg rst_fb  = 1;
    reg rst_ddr = 1;
    always #8  clk_fb  = ~clk_fb;
    always #5  clk_ddr = ~clk_ddr;

    // ---------------- DUT ----------------
    reg         push_en;
    reg  [31:0] dst_lo, dst_hi, db_lo, db_hi;
    reg  [31:0] ddr_seq, ddr_base, ddr_status;
    wire        utx_req, utx_sel, utx_sop, utx_eop;
    wire [255:0] utx_data;
    wire [7:0]  utx_valid;
    wire [31:0] st_done, st_status, st_tlp_cnt;
    wire [7:0]  st_err;
    wire [3:0]  m_axi_arid, m_axi_rid;
    wire [28:0] m_axi_araddr;
    wire [7:0]  m_axi_arlen;
    wire [2:0]  m_axi_arsize;
    wire [1:0]  m_axi_arburst;
    wire        m_axi_arvalid, m_axi_arready, m_axi_rlast, m_axi_rvalid, m_axi_rready;
    wire [255:0] m_axi_rdata;
    wire [1:0]  m_axi_rresp;

    ddr_frame_pusher #(
        .W(W), .H(H), .PAY_DW(32), .FIFO_AW(FIFO_AW),
        .BURST_BEATS(BB), .WAIT_LIMIT(WAIT_LIMIT)
    ) dut (
        .clk_fb(clk_fb), .rst_fb(rst_fb),
        .push_en(push_en),
        .dst_lo(dst_lo), .dst_hi(dst_hi), .db_lo(db_lo), .db_hi(db_hi),
        .st_done(st_done), .st_status(st_status), .st_err(st_err), .st_tlp_cnt(st_tlp_cnt),
        .ddr_seq(ddr_seq), .ddr_base(ddr_base), .ddr_status(ddr_status),
        .utx_sel(utx_sel), .tl_tx_wait(tl_tx_wait),
        .utx_req(utx_req), .utx_data(utx_data), .utx_sop(utx_sop),
        .utx_eop(utx_eop), .utx_valid(utx_valid),
        .clk_ddr(clk_ddr), .rst_ddr(rst_ddr),
        .m_axi_arid(m_axi_arid), .m_axi_araddr(m_axi_araddr), .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize), .m_axi_arburst(m_axi_arburst),
        .m_axi_arvalid(m_axi_arvalid), .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid), .m_axi_rdata(m_axi_rdata), .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast), .m_axi_rvalid(m_axi_rvalid), .m_axi_rready(m_axi_rready)
    );

    // ========================================================================
    //  假 DDR3：两个 2KB 块，字 i 的内容 = 32'hA5A5_0000 + 块号*1000 + i
    // ========================================================================
    reg [31:0] ddr [0:(2*FRAME_BYTES/4)-1];
    integer i;

    function [31:0] ddr_word;
        input [28:0] byte_addr;
        integer idx;
        begin
            idx = byte_addr[12:2];            // 块内字偏移（每块 2KB）
            ddr_word = ddr[idx];
        end
    endfunction

    // ========================================================================
    //  假 AXI4 从机：每突发 BB 拍、随机拉高 rvalid 间隔、随机 rready 反压
    // ========================================================================
    reg        slave_arready = 1;
    reg        slave_rvalid  = 0;
    reg        slave_rlast   = 0;
    reg [255:0] slave_rdata  = 0;
    integer    burst_beat;
    reg [28:0] burst_addr;
    reg        slave_busy = 0;
    integer    gap;
    reg [31:0] seed = 32'h1234_5678;
    integer    rr;

    task automatic rand_step;        // 一个便宜的伪随机步进
        begin
            seed = {seed[30:0], seed[31] ^ seed[21] ^ seed[1]};
        end
    endtask

    assign m_axi_rdata = slave_rdata;
    assign m_axi_rlast = slave_rlast;
    assign m_axi_rvalid = slave_rvalid;
    assign m_axi_rid = 4'd0;
    assign m_axi_rresp = 2'b00;
    assign m_axi_arready = !slave_busy;

    always @(posedge clk_ddr) begin
        if (rst_ddr) begin
            slave_busy <= 0; slave_rvalid <= 0; slave_rlast <= 0;
            burst_beat <= 0; gap <= 0;
        end else begin
            rand_step;
            rr = seed[3:0];
            // 每 8 拍停 1 拍发数据（反压），rvalid 也要受 m_axi_rready 管
            if (!slave_busy && m_axi_arvalid && m_axi_arready) begin
                slave_busy <= 1;
                burst_addr <= m_axi_araddr;
                burst_beat <= 0;
                gap        <= 0;
            end else if (slave_busy) begin
                if (slave_rvalid && m_axi_rready) begin
                    if (slave_rlast) begin
                        slave_busy <= 0; slave_rvalid <= 0; slave_rlast <= 0;
                    end else begin
                        burst_beat <= burst_beat + 1;
                        slave_rdata <= {ddr_word(burst_addr + (burst_beat+1)*BEAT_BYTES + 28),
                                        ddr_word(burst_addr + (burst_beat+1)*BEAT_BYTES + 24),
                                        ddr_word(burst_addr + (burst_beat+1)*BEAT_BYTES + 20),
                                        ddr_word(burst_addr + (burst_beat+1)*BEAT_BYTES + 16),
                                        ddr_word(burst_addr + (burst_beat+1)*BEAT_BYTES + 12),
                                        ddr_word(burst_addr + (burst_beat+1)*BEAT_BYTES +  8),
                                        ddr_word(burst_addr + (burst_beat+1)*BEAT_BYTES +  4),
                                        ddr_word(burst_addr + (burst_beat+1)*BEAT_BYTES +  0)};
                    end
                end else if (!slave_rvalid) begin
                    if (gap == 0) begin
                        slave_rvalid <= 1;
                        slave_rlast  <= (burst_beat == BB-1);
                        slave_rdata  <= {ddr_word(burst_addr + 28),
                                         ddr_word(burst_addr + 24),
                                         ddr_word(burst_addr + 20),
                                         ddr_word(burst_addr + 16),
                                         ddr_word(burst_addr + 12),
                                         ddr_word(burst_addr +  8),
                                         ddr_word(burst_addr +  4),
                                         ddr_word(burst_addr +  0)};
                        gap <= (rr == 0) ? 3 : 1;
                    end else begin
                        gap <= gap - 1;
                    end
                end
            end
        end
    end

    // ========================================================================
    //  假引擎侧 TL 口：口子按 utx_req 给，但要等 eop 收走才收回；
    //  随机插 CPL 忙（把给口子推迟几拍），验证推帧那一拍保持不动
    // ========================================================================
    reg        tl_tx_wait;
    reg        cpl_busy;
    reg        utx_sel_r;
    integer    wait_cnt;

    always @(posedge clk_fb) begin
        if (rst_fb) begin
            utx_sel_r <= 0; cpl_busy <= 0; tl_tx_wait <= 0; wait_cnt <= 0;
        end else begin
            rand_step;
            cpl_busy   <= (seed[7:0] == 8'h5A) && !utx_sel_r;      // 偶发：引擎在发完成包
            tl_tx_wait <= (seed[11:8] == 4'h3);                     // 偶发：链路不收
            if (!utx_sel_r) begin
                if (utx_req && !cpl_busy) utx_sel_r <= 1;
            end else if (utx_eop && (|utx_valid) && !tl_tx_wait) begin
                utx_sel_r <= 0;
            end
        end
    end
    assign utx_sel = utx_sel_r;
    wire ack = utx_sel_r && !tl_tx_wait && (|utx_valid);

    // ========================================================================
    //  TLP 收集与检查
    // ========================================================================
    integer    tlp_idx;           // 第几笔（0..NTLP-1 是帧数据，NTLP 是门铃）
    integer    beat_idx;
    reg [7:0]  got_bytes [0:255]; // 本笔 TLP 收到的字节流
    integer    nb;
    integer    errs;
    integer    pass_tlps;

    // 按「最高字节位的字节先出线」把一拍摊成字节流
    task automatic push_beat;
        input [255:0] d;
        input [7:0]   v;
        integer       n, b;
        begin
            for (n = 7; n >= 0; n = n - 1) begin
                if (v[n]) begin
                    got_bytes[nb+0] = d[32*n + 31 -: 8];
                    got_bytes[nb+1] = d[32*n + 23 -: 8];
                    got_bytes[nb+2] = d[32*n + 15 -: 8];
                    got_bytes[nb+3] = d[32*n +  7 -: 8];
                    nb = nb + 4;
                end
            end
        end
    endtask

    task automatic chk;
        input       cond;
        input [8*64-1:0] msg;
        begin
            if (!cond) begin
                $display("ERROR: %0s", msg);
                errs = errs + 1;
            end
        end
    endtask

    // 字节 → 总线上的 dword（线上先出的字节是高位字节）
    function [31:0] be32;
        input integer o;
        begin
            be32 = {got_bytes[o], got_bytes[o+1], got_bytes[o+2], got_bytes[o+3]};
        end
    endfunction

    // 字节 → 主机小端读到的 dword（先出的字节是低位字节）
    function [31:0] le32;
        input integer o;
        begin
            le32 = {got_bytes[o+3], got_bytes[o+2], got_bytes[o+1], got_bytes[o]};
        end
    endfunction

    integer  k, o;
    reg [63:0] exp_addr, exp_addr2;
    reg [31:0] exp_word;

    always @(posedge clk_fb) begin
        if (!rst_fb && ack) begin
            if (utx_sop) begin
                nb = 0;
                beat_idx = 0;
            end
            push_beat(utx_data, utx_valid);
            beat_idx = beat_idx + 1;

            if (utx_eop) begin
                // ---- 逐笔检查 ----
                if (tlp_idx < NTLP) begin
                    chk(beat_idx == 1 + PAY_BEATS, "帧 MWr 拍数不是 5");
                    chk(be32(0)[31:29] == 3'b011, "Fmt 不是 4DW 带数据");
                    chk(be32(0)[28:24] == 5'b0_0000, "Type 不是 MWR");
                    chk(be32(0)[9:0] == 32, "Length 不是 32 个 dw");
                    chk(be32(4)[31:16] == 16'h0100, "Requester ID 不是 01:00.0");
                    chk(be32(4)[15:8] == 8'h00, "Tag 不是 0");
                    chk(be32(4)[3:0] == 4'hf, "First DW BE 不是 F");
                    chk(be32(4)[7:4] == 4'hf, "Last DW BE 不是 F（长度>1）");
                    exp_addr = DST_ADDR + tlp_idx * TLP_BYTES;
                    chk(be32(8)  == exp_addr[63:32], "地址高 32 位（dw2）不对");
                    chk(be32(12) == {exp_addr[31:2], 2'b00}, "地址低 30 位（dw3）不对");
                    // 载荷必须与假 DDR 里同一段逐字节相同
                    for (k = 0; k < TLP_BYTES; k = k + 1) begin
                        chk(got_bytes[16+k] ==
                            ddr[(DDR_BASE0[12:0] + tlp_idx*TLP_BYTES + k) >> 2]
                               [8*(k%4) +: 8],
                            "载荷字节与 DDR 不一致");
                    end
                end else begin
                    chk(beat_idx == 1, "门铃不是单拍 TLP");
                    chk(be32(0)[31:29] == 3'b011, "门铃 Fmt 不是 4DW");
                    chk(be32(0)[9:0] == 1, "门铃 Length 不是 1");
                    chk(be32(4)[7:4] == 4'h0, "门铃 Last DW BE 不是 0（长度=1）");
                    chk(be32(4)[3:0] == 4'hf, "门铃 First DW BE 不是 F");
                    chk(be32(8)  == DB_ADDR[63:32], "门铃地址高 32 位不对");
                    chk(be32(12) == {DB_ADDR[31:2], 2'b00}, "门铃地址低 30 位不对");
                    chk(le32(16) == 32'd1, "门铃载荷不是本帧序号 1（字节序错？）");
                end
                if (errs == 0) pass_tlps = pass_tlps + 1;
                tlp_idx = tlp_idx + 1;
            end
        end
    end

    // ========================================================================
    //  主流程
    // ========================================================================
    integer t;

    initial begin
        errs = 0; pass_tlps = 0; tlp_idx = 0; nb = 0;
        power_on;
        // ---- 假 DDR 填数 ----
        for (i = 0; i < FRAME_BYTES/4; i = i + 1) ddr[i]               = 32'hA5A5_0000 + i;
        for (i = 0; i < FRAME_BYTES/4; i = i + 1) ddr[FRAME_BYTES/4+i] = 32'h5A5A_0000 + i;

        if ($test$plusargs("dump")) begin
            $dumpfile("tb_ddr_frame_pusher.vcd");
            $dumpvars(0, tb_ddr_frame_pusher);
        end

        // ---- 0) 没配地址：不发、错误码 1 ----
        push_en   = 1; dst_lo = 32'd0; dst_hi = 32'd0;
        db_lo     = DB_ADDR[31:0]; db_hi = DB_ADDR[63:32];
        ddr_seq   = 32'd1; ddr_base = DDR_BASE0; ddr_status = 32'b1_0001;
        tlp_idx   = 0;
        repeat (20) @(posedge clk_fb);
        chk(st_err == 8'd1, "目标地址配 0 时错误码不是 1");
        chk(st_done == 32'd0, "目标地址配 0 时已推帧数不该动");
        chk(tlp_idx == 0, "目标地址配 0 时不该发 TLP");

        // ---- 1) 正常推一帧 ----
        dst_lo = DST_ADDR[31:0]; dst_hi = DST_ADDR[63:32];
        ddr_seq  = 32'd2;
        ddr_base = DDR_BASE0;
        tlp_idx  = 0;
        // 等到整帧 + 门铃都发完
        t = 0;
        while ((tlp_idx <= NTLP) && (t < 200000)) begin
            @(posedge clk_fb); t = t + 1;
        end
        chk(tlp_idx == NTLP+1, "帧 TLP 数 + 门铃数 不等于 NTLP+1");
        chk(st_done == 32'd1, "已推帧数不是 1");
        chk(st_tlp_cnt == NTLP, "0xCC 记的 MWr 数不是 NTLP");
        chk(st_err == 8'd0, "正常推帧后错误码不是 0");
        chk(st_status[1] == 1'b1, "last_ok 没置起");
        chk(st_status[2] == 1'b1, "doorbell_sent 没置起");

        // ---- 2) 门铃地址全 0：数据照推、错误码 4、已推帧数仍 +1 ----
        dst_lo = DST_ADDR[31:0]; dst_hi = DST_ADDR[63:32];
        db_lo = 32'd0; db_hi = 32'd0;
        ddr_seq  = 32'd3; ddr_base = DDR_BASE1;
        tlp_idx  = 0;
        t = 0;
        while ((tlp_idx <= NTLP) && (t < 200000)) begin
            @(posedge clk_fb); t = t + 1;
        end
        chk(tlp_idx == NTLP, "门铃地址为 0 时不该发门铃");
        chk(st_done == 32'd2, "门铃地址为 0 时已推帧数该 +1");
        chk(st_err == 8'd4, "门铃地址为 0 时错误码不是 4");

        if (errs == 0) $display("ALL PASS (%0d TLPs checked)", pass_tlps);
        else           $display("FAIL: %0d error(s)", errs);
        $finish;
    end

    task power_on;
        begin
            push_en = 0; dst_lo = 0; dst_hi = 0; db_lo = 0; db_hi = 0;
            ddr_seq = 0; ddr_base = DDR_BASE0; ddr_status = 32'd0;
            rst_fb  = 1; rst_ddr = 1;
            #100;
            rst_fb  = 0;
            rst_ddr = 0;
            #100;
        end
    endtask

endmodule
