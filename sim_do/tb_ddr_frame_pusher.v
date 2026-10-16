///////////////////////////////////////////////////////////////
//  tb_ddr_frame_pusher.v — ddr_frame_pusher 冒烟测试（iverilog）
//
//  跑法（已实跑通过，输出见末尾 "ALL PASS"）：
//    # ★ 必须带 -I：ddr_frame_pusher.v 里 include 的是 ../../common/TLP_FMT_TYPE.v，
//    #   而 iverilog 的 include 是按「当前目录 + -I」找的，不看被包含文件的位置。
//    iverilog -I ../rtl/ep_side/ddr -I ../rtl/common \
//             -o tb_ddr_frame_pusher tb_ddr_frame_pusher.v \
//             ../rtl/ep_side/ddr/ddr_frame_pusher.v
//    ./tb_ddr_frame_pusher          # 期望输出 "ALL PASS"
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
    reg         src_sel = 0;      // 本 TB 只跑 DDR 源；ERAM 源未覆盖（见文件头）
    reg  [31:0] dst_lo, dst_hi, db_lo, db_hi;
    reg  [31:0] ddr_seq, ddr_base, ddr_status;
    reg  [31:0] frame_bytes_r = FRAME_BYTES;
    // ERAM 源端口：src_sel=0 时本模块不发 fb_req，所以这里固定「不给授权、数据 0」即可
    reg  [31:0] fb_frame_cnt = 0;
    reg  [31:0] fb_rd_data  = 0;
    wire        fb_grant;
    wire [31:0] fb_rd_addr;
    wire        fb_req, fb_src_act;
    // ERAM 源（CTRL[7]=1）用的假帧缓存：与 img_frame_src 的 fb[] 同布局
    //（字 i 低字节 = 最左像素；读口 1 拍延迟、一直给授权）
    localparam integer EWORDS = FRAME_BYTES/4;
    reg [31:0] fbm [0:EWORDS-1];
    reg        eram_phase = 0;
    assign fb_grant = fb_req;
    always @(posedge clk_fb) fb_rd_data <= fbm[fb_rd_addr[31:2]];
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
        .src_sel(src_sel), .fb_frame_cnt(fb_frame_cnt),
        .fb_rd_addr(fb_rd_addr), .fb_rd_data(fb_rd_data),
        .fb_req(fb_req), .fb_grant(fb_grant), .src_act(fb_src_act),
        .dst_lo(dst_lo), .dst_hi(dst_hi), .db_lo(db_lo), .db_hi(db_hi),
        .st_done(st_done), .st_status(st_status), .st_err(st_err), .st_tlp_cnt(st_tlp_cnt),
        .frame_bytes(frame_bytes_r),    // 本帧字节数（顶层按源给；本 TB 可切换）
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
                        // ★ 本拍被收走后必须**立刻把下一拍摆出来**（rvalid 保持 1），
                        //   否则从机会一直重复同一拍：DUT 卡在等 rlast，看起来像死锁。
                        burst_beat <= burst_beat + 1;
                        slave_rlast <= (burst_beat + 1 == BB-1);
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
                errs = errs + 1;
                if (errs <= 15) $display("ERROR #%0d @%0t [%s]", errs, $time, msg);   // 名字用 ASCII 才不糊
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
    reg [31:0] dw0, dw4, dw8, dw12, dwle;   // 函数调用结果的位选要先落寄存器（iverilog）
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
                dw0 = be32(0); dw4 = be32(4); dw8 = be32(8); dw12 = be32(12); dwle = le32(16);
                // ---- 逐笔检查 ----
                if (tlp_idx < NTLP) begin
                    chk(beat_idx == 1 + PAY_BEATS, "frame MWr beats != 5");
                    chk(dw0[31:29] == 3'b011, "Fmt != 4DW with data");
                    chk(dw0[28:24] == 5'b0_0000, "Type != MWR");
                    chk(dw0[9:0] == 32, "Length != 32 dw");
                    chk(dw4[31:16] == 16'h0100, "RequesterID != 01:00.0");
                    chk(dw4[15:8] == 8'h00, "Tag != 0");
                    chk(dw4[3:0] == 4'hf, "FirstDWBE != F");
                    chk(dw4[7:4] == 4'hf, "LastDWBE != F (len>1)");
                    exp_addr = DST_ADDR + tlp_idx * TLP_BYTES;
                    chk(be32(8)  == exp_addr[63:32], "addr hi32 (dw2) wrong");
                    chk(be32(12) == {exp_addr[31:2], 2'b00}, "addr lo30 (dw3) wrong");
                    // 载荷必须与「本源」同一段逐字节相同：
                    //   DDR 源（默认）比 ddr[]，ERAM 源（src_sel=1）比 fbm[]
                    for (k = 0; k < TLP_BYTES; k = k + 1) begin
                        if (eram_phase)
                            chk(got_bytes[16+k] ==
                                fbm[(tlp_idx*TLP_BYTES + k) >> 2][8*(k%4) +: 8],
                                "ERAM payload byte mismatch");
                        else begin
                            if (got_bytes[16+k] !== ddr[(DDR_BASE0[12:0] + tlp_idx*TLP_BYTES + k) >> 2][8*(k%4) +: 8]) begin
                                if (errs < 3)
                                    $display("DDRMISMATCH tlp=%0d k=%0d got=%02h exp=%02h (word %0d) beat bytes=%02h %02h %02h %02h",
                                        tlp_idx, k, got_bytes[16+k],
                                        ddr[(DDR_BASE0[12:0] + tlp_idx*TLP_BYTES + k) >> 2][8*(k%4) +: 8],
                                        (DDR_BASE0[12:0] + tlp_idx*TLP_BYTES + k) >> 2,
                                        got_bytes[16], got_bytes[17], got_bytes[18], got_bytes[19]);
                                errs = errs + 1;
                            end
                        end
                    end
                end else begin
                    chk(beat_idx == 1, "doorbell not single-beat TLP");
                    chk(dw0[31:29] == 3'b011, "doorbell Fmt != 4DW");
                    chk(dw0[9:0] == 1, "doorbell Length != 1");
                    chk(dw4[7:4] == 4'h0, "doorbell LastDWBE != 0 (len=1)");
                    chk(dw4[3:0] == 4'hf, "doorbell FirstDWBE != F");
                    chk(be32(8)  == DB_ADDR[63:32], "doorbell addr hi32 wrong");
                    chk(be32(12) == {DB_ADDR[31:2], 2'b00}, "doorbell addr lo30 wrong");
                    chk(le32(16) == db_expect, "doorbell payload != expected seq");
                    db_expect = db_expect + 32'd1;
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
    reg ok;
    reg [31:0] db_expect = 32'd1;   // 下一笔门铃应当写的序号（每收到一笔 +1）

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

        // ==================== 尺寸换算自检（4K vs 640x480）====================
        //  本步把 NTLP/NBURST 从「编译期由 W*H 推」改成「由 frame_bytes 现算」，
        //  4K 的 64800 个 MWr / 2025 个突发会把老的 12bit/8bit 计数器直接撑爆，
        //  所以这里先把换算结果对一遍（不跑整帧，直接看内部推导）：
        frame_bytes_r = 32'd8294400;                       // 3840x2160 灰度
        #1; ok = (dut.ntlp_m1_w == 17'd64799);   chk(ok, "4K: ntlp_m1 != 64799");
        ok = (dut.nburst_m1_w == ((8294400/(BB*32)) - 1)); chk(ok, "4K: nburst_m1 wrong");
        frame_bytes_r = 32'd307200;                        // 640x480 灰度
        #1; ok = (dut.ntlp_m1_w == 17'd2399);    chk(ok, "640x480: ntlp_m1 != 2399");
        ok = (dut.nburst_m1_w == ((307200/(BB*32)) - 1));  chk(ok, "640x480: nburst_m1 wrong");
        frame_bytes_r = FRAME_BYTES;                       // 回到本 TB 的小尺寸
        #1; ok = (dut.ntlp_m1_w == (NTLP - 1));     chk(ok, "TB: ntlp_m1 wrong");
        ok = (dut.nburst_m1_w == (NBURST - 1)); chk(ok, "TB: nburst_m1 wrong");

        $display("PHASE0 start @%0t", $time);
        // ---- 0) 没配地址：不发、错误码 1 ----
        push_en   = 1; dst_lo = 32'd0; dst_hi = 32'd0;
        db_lo     = DB_ADDR[31:0]; db_hi = DB_ADDR[63:32];
        ddr_seq   = 32'd1; ddr_base = DDR_BASE0; ddr_status = 32'b1_0001;
        tlp_idx   = 0;
        repeat (20) @(posedge clk_fb);
        chk(st_err == 8'd1, "zero dst: err != 1");
        chk(st_done == 32'd0, "zero dst: st_done changed");
        chk(tlp_idx == 0, "zero dst: sent TLP");

        $display("PHASE1 start, errs=%0d @%0t", errs, $time);
        // ---- 1) 正常推一帧 ----
        //  ★ 顺序要紧：PHASE0 留下的是「帧号 1、目标是 0」这个待处理组合。
        //    如果先配目标再换帧号，pusher 会在同一拍看到「帧号 1 + 目标已配」，
        //    于是把帧号 1 也推一帧，再接帧号 2 —— 变成两帧（本 TB 原来就是这么
        //    多出 3 笔 TLP 的）。所以先换帧号（此时目标仍是 0 → 只报 E_NO_DST、
        //    不推），等两拍让它消化掉，再配目标。
        ddr_seq  = 32'd2;
        ddr_base = DDR_BASE0;
        repeat (2) @(posedge clk_fb);
        dst_lo = DST_ADDR[31:0]; dst_hi = DST_ADDR[63:32];
        tlp_idx  = 0;
        // 等到整帧 + 门铃都发完
        t = 0;
        while ((tlp_idx <= NTLP) && (t < 200000)) begin
            @(posedge clk_fb); t = t + 1;
        end
        repeat (30) @(posedge clk_fb);     // 等收尾（S_WAIT -> S_IDLE）把状态字写完
        chk(tlp_idx == NTLP+1, "P2: tlp count != NTLP+1");
        chk(st_done == 32'd1, "已推帧数不是 1");
        chk(st_tlp_cnt == NTLP, "0xCC 记的 MWr 数不是 NTLP");
        chk(st_err == 8'd0, "正常推帧后错误码不是 0");
        chk(st_status[1] == 1'b1, "last_ok 没置起");
        chk(st_status[2] == 1'b1, "doorbell_sent 没置起");

        $display("PHASE2 start, errs=%0d @%0t", errs, $time);
        // ---- 2) 门铃地址全 0：数据照推、错误码 4、已推帧数仍 +1 ----
        dst_lo = DST_ADDR[31:0]; dst_hi = DST_ADDR[63:32];
        db_lo = 32'd0; db_hi = 32'd0;
        ddr_seq  = 32'd3; ddr_base = DDR_BASE1;
        tlp_idx  = 0;
        t = 0;
        while ((tlp_idx <= NTLP) && (t < 200000)) begin
            @(posedge clk_fb); t = t + 1;
        end
        repeat (30) @(posedge clk_fb);     // 等收尾（S_WAIT -> S_IDLE）把状态字写完
        chk(tlp_idx == NTLP, "zero db: sent doorbell");
        chk(st_done == 32'd2, "zero db: st_done not +1");
        chk(st_err == 8'd4, "zero db: err != 4");

        $display("PHASE3(ERAM) start, errs=%0d @%0t", errs, $time);
        // ---- 3) 【本步新增】ERAM 源（CTRL[7]）：完全不碰 AXI，直接读片内 fb ----
        eram_phase = 1;
        src_sel    = 1;
        for (i = 0; i < EWORDS; i = i + 1) fbm[i] = 32'h5A5A_0000 + i;   // 与 ddr[] 不同，便于区分
        dst_lo = DST_ADDR[31:0]; dst_hi = DST_ADDR[63:32];
        db_lo  = DB_ADDR[31:0];  db_hi  = DB_ADDR[63:32];
        ddr_status  = 32'd0;              // 故意给 0：ERAM 源不该看 ddr_status
        db_expect   = 32'd3;              // 本帧是第 3 帧（PHASE2 没发门铃，帧号照样 +1）
        fb_frame_cnt = 32'd1;             // 帧计数器一变 = 有一整帧
        tlp_idx = 0;
        t = 0;
        while ((tlp_idx <= NTLP) && (t < 400000)) begin
            @(posedge clk_fb); t = t + 1;
        end
        repeat (30) @(posedge clk_fb);     // 同上：等状态字写完
        chk(tlp_idx == NTLP+1, "ERAM: tlp count != NTLP+1");
        chk(st_done == 32'd3, "ERAM: st_done != 3");
        chk(st_tlp_cnt == NTLP, "ERAM: st_tlp_cnt != NTLP");
        chk(st_err == 8'd0, "ERAM: err != 0");
        chk(st_status[1] == 1'b1, "ERAM: last_ok not set");
        chk(st_status[2] == 1'b1, "ERAM: doorbell_sent not set");
        chk(m_axi_arvalid == 1'b0, "ERAM: arvalid not 0");
        chk(fb_src_act == 1'b1, "ERAM: src_act not set");

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
