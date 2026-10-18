///////////////////////////////////////////////////////////////////////////////
//  tb_ddr_frame_readback_checker.v — ddr_frame_readback_checker 独立 TB
//
//  覆盖（本包 dev-plan §3.4 语义步骤 3）：
//   · 正例：小尺寸 4KiB 帧（P=640）+ 1080p 全帧（P=2,592,000 / 2,592,768）
//   · 负例（fail-closed，≥4）：magic / 长度 / 头 CRC / 载荷 CRC / AXI 响应
//     SLVERR / 读超时 / abort；另含 busy 重入拒绝与参数非法（err=8）
//   · AXI 读内存模型：32 拍突发逐拍返回，rdata 由 32bit 内存模型拼出
//   · 独立参考 CRC：本 TB 逐**位**实现（poly 0xEDB88320 反射、init 全 1、末值取反），
//     不引用 DUT 的 crc32_upd4.v（避免镜像自证）
//
//  判定：vsim.log 出现 "*** ALL PASS ***"；失败打印 FAIL(id) 明细并累计。
//  运行：tools/pcie_integration/run_sim.ps1 -Tb tb_ddr_frame_readback_checker \
//        -OutDir <dir> -TbFiles tb/tb_ddr_frame_readback_checker.v
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_ddr_frame_readback_checker;

    // ---------------- 常量 ----------------
    localparam CLK_HALF   = 5;                    // 10 ns 周期 = 100 MHz
    localparam MEM_WORDS  = 1 << 20;              // 4 MiB 模型（32bit 字）
    localparam [31:0] BASE1 = 32'h0000_2000;      // 小帧基址（32B 对齐）
    localparam [31:0] BASE2 = 32'h0008_0000;      // 1080p 帧基址
    localparam [31:0] SMALL_PAY    = 32'd640;
    localparam [31:0] SMALL_FBYTES = 32'd4096;
    localparam [31:0] BIG_PAY      = 32'd2_592_000;
    localparam [31:0] BIG_FBYTES   = 32'd2_592_768;

    // ---------------- 时钟 / 复位 ----------------
    reg clk;
    reg rst_dut;
    initial clk = 1'b0;
    always #(CLK_HALF) clk = ~clk;

    // ---------------- 控制 / 状态 ----------------
    reg         start;
    reg  [63:0] base;
    reg  [31:0] frame_bytes;
    reg         abort;
    wire        busy, done, magic_ok, hdr_crc_ok, payload_crc_ok, length_ok;
    wire [7:0]  err_code;
    wire [31:0] rd_header_crc32, rd_payload_crc32, words_read;
    wire [31:0] smp0, smp1, smp2, smp3, smp4, smp5;

    // ---------------- AXI4 读通道（DUT 主 / TB 从）----------------
    wire [3:0]   axi_arid;
    wire [28:0]  axi_araddr;
    wire [7:0]   axi_arlen;
    wire [2:0]   axi_arsize;
    wire [1:0]   axi_arburst;
    wire         axi_arvalid;
    reg          axi_arready;
    wire [3:0]   axi_rid;
    wire [255:0] axi_rdata;
    wire [1:0]   axi_rresp;
    wire         axi_rlast;
    reg          axi_rvalid;
    wire         axi_rready;

    assign axi_rid = 4'd0;

    // ---------------- DUT ----------------
    ddr_frame_readback_checker dut (
        .clk_dhi          (clk),
        .rst_dhi          (rst_dut),
        .start            (start),
        .base             (base),
        .frame_bytes      (frame_bytes),
        .abort            (abort),
        .busy             (busy),
        .done             (done),
        .magic_ok         (magic_ok),
        .hdr_crc_ok       (hdr_crc_ok),
        .payload_crc_ok   (payload_crc_ok),
        .length_ok        (length_ok),
        .err_code         (err_code),
        .rd_header_crc32  (rd_header_crc32),
        .rd_payload_crc32 (rd_payload_crc32),
        .words_read       (words_read),
        .smp0(smp0), .smp1(smp1), .smp2(smp2), .smp3(smp3), .smp4(smp4), .smp5(smp5),
        .m_axi_arid       (axi_arid),
        .m_axi_araddr     (axi_araddr),
        .m_axi_arlen      (axi_arlen),
        .m_axi_arsize     (axi_arsize),
        .m_axi_arburst    (axi_arburst),
        .m_axi_arvalid    (axi_arvalid),
        .m_axi_arready    (axi_arready),
        .m_axi_rid        (axi_rid),
        .m_axi_rdata      (axi_rdata),
        .m_axi_rresp      (axi_rresp),
        .m_axi_rlast      (axi_rlast),
        .m_axi_rvalid     (axi_rvalid),
        .m_axi_rready     (axi_rready)
    );

    // ---------------- 内存模型（32bit 字）----------------
    reg [31:0] mem [0:MEM_WORDS-1];

    // ---------------- AXI 从模型 ----------------
    reg  [31:0] s_addr;       // 当前突发内字节地址
    reg  [31:0] s_left;       // 剩余拍数（含待出示拍）
    reg         s_act;        // 突发在飞
    reg         s_stall;      // 1 = 完全不返回数据（超时用例）
    reg         s_inj_en;     // 1 = 注入 SLVERR
    reg  [31:0] s_inj_beat;   // 注入目标拍下标（突发内）
    reg  [31:0] s_beat_idx;

    wire [31:0]  s_wa    = s_addr >> 2;
    wire [255:0] axi_rdata_c = {mem[s_wa+7], mem[s_wa+6], mem[s_wa+5], mem[s_wa+4],
                                mem[s_wa+3], mem[s_wa+2], mem[s_wa+1], mem[s_wa]};
    assign axi_rdata = axi_rdata_c;
    assign axi_rresp = (s_inj_en && (s_beat_idx == s_inj_beat)) ? 2'b10 : 2'b00;
    assign axi_rlast = (s_left == 32'd1);

    always @(posedge clk or posedge rst_dut) begin
        if (rst_dut) begin
            axi_arready <= 1'b1;
            axi_rvalid  <= 1'b0;
            s_act       <= 1'b0;
            s_addr      <= 32'd0;
            s_left      <= 32'd0;
            s_beat_idx  <= 32'd0;
        end else begin
            if (axi_arvalid && axi_arready) begin
                s_addr      <= {3'd0, axi_araddr};
                s_left      <= {24'd0, axi_arlen} + 32'd1;
                s_act       <= 1'b1;
                s_beat_idx  <= 32'd0;
                axi_arready <= 1'b0;
                axi_rvalid  <= ~s_stall;
            end else if (s_act && axi_rvalid && axi_rready) begin
                if (s_left == 32'd1) begin
                    s_act       <= 1'b0;
                    axi_rvalid  <= 1'b0;
                    axi_arready <= 1'b1;
                end else begin
                    s_addr      <= s_addr + 32'd32;
                    s_left      <= s_left - 32'd1;
                    axi_rvalid  <= ~s_stall;
                end
                s_beat_idx <= s_beat_idx + 32'd1;
            end
        end
    end

    // ---------------- 独立参考 CRC（逐位 oracle）----------------
    function [31:0] ref_crc_byte;
        input [31:0] c;
        input [7:0]  b;
        integer i;
        reg [31:0] x;
        begin
            x = c ^ {24'd0, b};
            for (i = 0; i < 8; i = i + 1) begin
                if (x[0]) x = (x >> 1) ^ 32'hEDB8_8320;
                else      x = (x >> 1);
            end
            ref_crc_byte = x;
        end
    endfunction

    function [31:0] ref_crc_word;
        input [31:0] c;
        input [31:0] w;
        begin
            ref_crc_word = ref_crc_byte(ref_crc_byte(ref_crc_byte(ref_crc_byte(c, w[7:0]),
                                   w[15:8]), w[23:16]), w[31:24]);
        end
    endfunction

    // ---------------- 期望值 ----------------
    reg [31:0] x_pay_crc, x_hdr_crc;
    reg [31:0] x_s0, x_s1, x_s2, x_s3, x_s4, x_s5;

    integer errs;
    integer tid;
    integer t;
    integer w_before, w_after;

    `define CHK(cond, nm) if (!(cond)) begin errs = errs + 1; $display("FAIL(%0d): %s", tid, nm); end

    // ---------------- 组帧任务 ----------------
    task build_frame;
        input [31:0] b;      // 基址（32B 对齐）
        input [31:0] pay;    // payload 字节数
        input [31:0] fby;    // frame_bytes
        integer i;
        reg [31:0] c;
        reg [31:0] w;
        begin
            // 清零整帧区
            for (i = 0; i < (fby / 4); i = i + 1)
                mem[(b >> 2) + i] = 32'd0;
            // 载荷 pattern + 参考 CRC
            c = 32'hFFFF_FFFF;
            for (i = 0; i < (pay / 4); i = i + 1) begin
                w = (i * 32'h9E37_79B1) ^ 32'hA5A5_A5A5;
                mem[(b >> 2) + 32 + i] = w;
                c = ref_crc_word(c, w);
            end
            x_pay_crc = ~c;
            // R10F 头（字段口径同 cam_r10f_writer.v）
            mem[(b >> 2) + 0]  = 32'h4630_3152;
            mem[(b >> 2) + 1]  = 32'h0000_0001;
            mem[(b >> 2) + 2]  = {8'h00, 8'h00, 16'h0080};
            mem[(b >> 2) + 3]  = 32'd0;
            mem[(b >> 2) + 4]  = 32'h0000_0001;
            mem[(b >> 2) + 5]  = 32'h0000_0007;
            mem[(b >> 2) + 6]  = 32'd1;
            mem[(b >> 2) + 7]  = {16'd1080, 16'd1920};
            mem[(b >> 2) + 8]  = 32'd2400;
            mem[(b >> 2) + 9]  = {16'd540, 16'd960};
            mem[(b >> 2) +10]  = 32'h000A_0002;
            mem[(b >> 2) +11]  = pay;
            mem[(b >> 2) +12]  = pay;
            mem[(b >> 2) +13]  = 32'd1;
            mem[(b >> 2) +20]  = x_pay_crc;
            mem[(b >> 2) +21]  = x_pay_crc;
            mem[(b >> 2) +22]  = 32'd0;
            // 头 CRC：word22 已清 0 后覆盖 128B
            c = 32'hFFFF_FFFF;
            for (i = 0; i < 32; i = i + 1)
                c = ref_crc_word(c, mem[(b >> 2) + i]);
            x_hdr_crc = ~c;
            mem[(b >> 2) +22]  = x_hdr_crc;
            // 期望抽样字
            x_s0 = mem[(b >> 2) + 0];
            x_s1 = mem[(b >> 2) + 20];
            x_s2 = mem[(b >> 2) + 21];
            x_s3 = mem[(b >> 2) + 22];
            x_s4 = mem[(b >> 2) + 32];
            x_s5 = mem[(b >> 2) + 32 + ((pay - 32'd1) >> 2)];
        end
    endtask

    // ---------------- 发起一次读回并等 done ----------------
    task do_run;
        input [31:0] b;
        input [31:0] fb;
        begin
            @(posedge clk);
            start <= 1'b1; base <= {32'd0, b}; frame_bytes <= fb; abort <= 1'b0;
            repeat (3) @(posedge clk);
            start <= 1'b0;
            t = 0;
            while ((done !== 1'b0) && (t < 200)) begin @(posedge clk); t = t + 1; end
            t = 0;
            while ((done !== 1'b1) && (t < 30000000)) begin @(posedge clk); t = t + 1; end
            if (done !== 1'b1) begin
                errs = errs + 1;
                $display("FATAL(%0d): done timeout", tid);
            end
            @(posedge clk);
        end
    endtask

    // ---------------- 全身检查（正例全 OK）----------------
    task check_all_ok;
        input [31:0] exp_words;
        begin
            `CHK(done === 1'b1,           "done=1")
            `CHK(busy === 1'b0,           "busy=0")
            `CHK(err_code == 8'd0,        "err=0")
            `CHK(magic_ok === 1'b1,       "magic_ok=1")
            `CHK(hdr_crc_ok === 1'b1,     "hdr_crc_ok=1")
            `CHK(payload_crc_ok === 1'b1, "payload_crc_ok=1")
            `CHK(length_ok === 1'b1,      "length_ok=1")
            `CHK(words_read == exp_words, "words_read")
            `CHK(rd_header_crc32 == x_hdr_crc,  "rd_header_crc32")
            `CHK(rd_payload_crc32 == x_pay_crc, "rd_payload_crc32")
            `CHK(smp0 == x_s0, "smp0")
            `CHK(smp1 == x_s1, "smp1")
            `CHK(smp2 == x_s2, "smp2")
            `CHK(smp3 == x_s3, "smp3")
            `CHK(smp4 == x_s4, "smp4")
            `CHK(smp5 == x_s5, "smp5")
        end
    endtask

    // ========================================================================
    //  测试序列
    // ========================================================================
    initial begin
        rst_dut   = 1'b1;
        start     = 1'b0;
        base      = 64'd0;
        frame_bytes = 32'd0;
        abort     = 1'b0;
        s_stall   = 1'b0;
        s_inj_en  = 1'b0;
        s_inj_beat= 32'd0;
        errs      = 0;
        tid       = 0;

        #100; rst_dut = 1'b0; #100;

        // ---------------- T0：参数非法（frame_bytes=0；base 非 32B 对齐）----
        tid = 0;
        start <= 1'b1; base <= 64'd0; frame_bytes <= 32'd0; abort <= 1'b0;
        repeat (3) @(posedge clk);
        start <= 1'b0;
        repeat (3) @(posedge clk);
        `CHK(done === 1'b1,    "T0a done")
        `CHK(busy === 1'b0,    "T0a busy=0")
        `CHK(err_code == 8'd8, "T0a err=8")
        `CHK(magic_ok === 1'b0,"T0a magic=0")
        @(posedge clk);
        start <= 1'b1; base <= {32'd0, BASE1 + 32'd4}; frame_bytes <= SMALL_FBYTES; abort <= 1'b0;
        repeat (3) @(posedge clk);
        start <= 1'b0;
        repeat (3) @(posedge clk);
        `CHK(done === 1'b1,    "T0b done")
        `CHK(err_code == 8'd8, "T0b err=8 (base unaligned)")
        $display("T0 param checks done");

        // ---------------- T1：小尺寸正例 ----------------
        tid = 1;
        build_frame(BASE1, SMALL_PAY, SMALL_FBYTES);
        do_run(BASE1, SMALL_FBYTES);
        check_all_ok(32'd1024);
        $display("T1 crc hdr=%08x pay=%08x words=%0d", rd_header_crc32, rd_payload_crc32, words_read);

        // ---------------- N1：magic 破坏 ----------------
        tid = 2;
        build_frame(BASE1, SMALL_PAY, SMALL_FBYTES);
        mem[(BASE1 >> 2) + 0] = 32'hDEAD_BEEF;
        do_run(BASE1, SMALL_FBYTES);
        `CHK(err_code == 8'd1,  "N1 err=1 (magic)")
        `CHK(magic_ok === 1'b0, "N1 magic_ok=0")
        $display("N1 err=%0d", err_code);

        // ---------------- N2：长度不一致 ----------------
        tid = 3;
        build_frame(BASE1, SMALL_PAY, SMALL_FBYTES);
        mem[(BASE1 >> 2) + 12] = 32'd4736;    // 128+P' 超出 frame_bytes
        do_run(BASE1, SMALL_FBYTES);
        `CHK(err_code == 8'd4,   "N2 err=4 (length)")
        `CHK(length_ok === 1'b0, "N2 length_ok=0")
        $display("N2 err=%0d", err_code);

        // ---------------- N3：头 CRC 破坏（word5）----------------
        tid = 4;
        build_frame(BASE1, SMALL_PAY, SMALL_FBYTES);
        mem[(BASE1 >> 2) + 5] = mem[(BASE1 >> 2) + 5] ^ 32'h0000_0100;
        do_run(BASE1, SMALL_FBYTES);
        `CHK(err_code == 8'd2,        "N3 err=2 (hdr crc)")
        `CHK(hdr_crc_ok === 1'b0,     "N3 hdr_crc_ok=0")
        `CHK(magic_ok === 1'b1,       "N3 magic_ok=1")
        `CHK(length_ok === 1'b1,      "N3 length_ok=1")
        `CHK(payload_crc_ok === 1'b1, "N3 payload_crc_ok=1")
        $display("N3 err=%0d", err_code);

        // ---------------- N4：载荷 CRC 破坏 ----------------
        tid = 5;
        build_frame(BASE1, SMALL_PAY, SMALL_FBYTES);
        mem[(BASE1 >> 2) + 32 + 16] = mem[(BASE1 >> 2) + 32 + 16] ^ 32'hFFFF_0001;
        do_run(BASE1, SMALL_FBYTES);
        `CHK(err_code == 8'd3,        "N4 err=3 (pay crc)")
        `CHK(payload_crc_ok === 1'b0, "N4 payload_crc_ok=0")
        `CHK(hdr_crc_ok === 1'b1,     "N4 hdr_crc_ok=1")
        `CHK(magic_ok === 1'b1,       "N4 magic_ok=1")
        `CHK(length_ok === 1'b1,      "N4 length_ok=1")
        $display("N4 err=%0d", err_code);

        // ---------------- N5：AXI 响应 SLVERR（第 3 拍）----------------
        tid = 6;
        build_frame(BASE1, SMALL_PAY, SMALL_FBYTES);
        s_inj_beat = 32'd2;
        s_inj_en   = 1'b1;
        do_run(BASE1, SMALL_FBYTES);
        s_inj_en   = 1'b0;
        `CHK(err_code == 8'd5, "N5 err=5 (axi)")
        `CHK(magic_ok === 1'b1, "N5 magic_ok=1")
        $display("N5 err=%0d", err_code);

        // ---------------- T7：1080p 全帧 + busy 重入拒绝 ----------------
        tid = 7;
        build_frame(BASE2, BIG_PAY, BIG_FBYTES);
        @(posedge clk);
        start <= 1'b1; base <= {32'd0, BASE2}; frame_bytes <= BIG_FBYTES; abort <= 1'b0;
        repeat (3) @(posedge clk);
        start <= 1'b0;
        t = 0;
        while ((busy !== 1'b1) && (t < 100000)) begin @(posedge clk); t = t + 1; end
        t = 0;
        while ((dut.wcnt < 32'd5000) && (t < 1000000)) begin @(posedge clk); t = t + 1; end
        w_before = dut.wcnt;
        start <= 1'b1;                      // 重入脉冲：busy 期间必须被忽略
        repeat (5) @(posedge clk);
        start <= 1'b0;
        repeat (2000) @(posedge clk);
        w_after = dut.wcnt;
        `CHK(busy === 1'b1, "T7 reentry: still busy")
        if (w_after > w_before) begin
            $display("T7 reentry ignored: wcnt %0d -> %0d", w_before, w_after);
        end else begin
            errs = errs + 1;
            $display("FAIL(7): reentry restarted wcnt %0d -> %0d", w_before, w_after);
        end
        t = 0;
        while ((done !== 1'b1) && (t < 30000000)) begin @(posedge clk); t = t + 1; end
        check_all_ok(32'd648192);
        $display("T7 crc hdr=%08x pay=%08x words=%0d", rd_header_crc32, rd_payload_crc32, words_read);

        // ---------------- T8：读超时（从机不返回数据）----------------
        tid = 8;
        s_stall = 1'b1;
        @(posedge clk);
        start <= 1'b1; base <= {32'd0, BASE1}; frame_bytes <= SMALL_FBYTES; abort <= 1'b0;
        repeat (3) @(posedge clk);
        start <= 1'b0;
        t = 0;
        while ((done !== 1'b0) && (t < 200)) begin @(posedge clk); t = t + 1; end
        t = 0;
        while ((done !== 1'b1) && (t < 5000000)) begin @(posedge clk); t = t + 1; end
        s_stall = 1'b0;
        `CHK(done === 1'b1,    "T8 done (timeout)")
        `CHK(busy === 1'b0,    "T8 busy=0")
        `CHK(err_code == 8'd6, "T8 err=6 (timeout)")
        `CHK(magic_ok === 1'b0,"T8 magic_ok=0")
        $display("T8 err=%0d", err_code);

        // ---------------- T9：abort ----------------
        tid = 9;
        build_frame(BASE1, SMALL_PAY, SMALL_FBYTES);
        s_stall = 1'b1;                     // 停在等 R，便于在途 abort
        @(posedge clk);
        start <= 1'b1; base <= {32'd0, BASE1}; frame_bytes <= SMALL_FBYTES; abort <= 1'b0;
        repeat (3) @(posedge clk);
        start <= 1'b0;
        t = 0;
        while ((busy !== 1'b1) && (t < 100000)) begin @(posedge clk); t = t + 1; end
        repeat (10) @(posedge clk);
        abort <= 1'b1;
        repeat (3) @(posedge clk);
        abort <= 1'b0;
        repeat (5) @(posedge clk);
        s_stall = 1'b0;
        `CHK(done === 1'b1,        "T9 done (abort)")
        `CHK(busy === 1'b0,        "T9 busy=0")
        `CHK(err_code == 8'd7,     "T9 err=7 (abort)")
        `CHK(magic_ok === 1'b0,    "T9 magic_ok=0")
        `CHK(payload_crc_ok === 1'b0, "T9 payload_crc_ok=0")
        $display("T9 err=%0d", err_code);

        // ---------------- 汇总 ----------------
        if (errs == 0) begin
            $display("*** ALL PASS ***");
            $display("Errors: 0");
        end else begin
            $display("*** FAIL *** errors=%0d", errs);
            $display("Errors: %0d", errs);
        end
        $finish;
    end

    // ---------------- 看门狗（绝对上限）----------------
    initial begin
        #400_000_000;
        $display("FAIL: TB watchdog expired");
        $display("*** FAIL *** (watchdog)");
        $finish;
    end

endmodule
