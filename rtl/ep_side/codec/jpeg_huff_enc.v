// jpeg_huff_enc.v — JPEG 熵编码（DC 差分 + AC 游程 + 规范哈夫曼）
//
// 输入量化后的之字形系数（8 个/拍，8 拍一块），输出标准 JPEG 熵编码字节流。
// DC 用差分、AC 用 (run<<4)|cat 查规范哈夫曼表；幅度按 T.81（负数用 v-1）。
//
// 实现要点：
//  * 位累加器 bitacc 右对齐、48 位（一个系数最多 31 比特，加残留 < 40 位，不会溢出）。
//  * 每个系数分两个状态各做一次 put，全部用非阻塞赋值 —— 同一拍多次写同一寄存器
//    会让结果不可预测（这是上一版比特流错位的根因）。
//  * 每处理完一个系数进 S_DRAIN，把整字节吐干净再继续。
module jpeg_huff_enc (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] s_data,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire         s_sof,
    input  wire         s_eof,          // 帧末：只有这里才补位到字节边界
    output reg  [7:0]   m_data,
    output reg          m_valid,
    input  wire         m_ready,
    output reg  [31:0]  st_bits,
    output reg  [31:0]  st_blocks,
    output reg          m_done      // 帧末块（带 eof）处理完时给一拍脉冲
);
    localparam S_IDLE  = 3'd0,   // 等 SOF
               S_COLL  = 3'd1,   // 收 8 拍系数
               S_HC    = 3'd2,   // 定符号（DC 差分 / AC 游程）
               S_AMP   = 3'd3,   // put 哈夫曼码
               S_AMP2  = 3'd6,   // put 幅度
               S_NEXT  = 3'd7,   // 下一个系数
               S_DRAIN = 3'd4,   // 吐整字节
               S_FLUSH = 3'd5;   // 收尾补位
    reg [2:0] st;

    reg [15:0] qz [0:63];
    reg [2:0]  wn;
    reg [5:0]  k;
    reg [5:0]  run;      // 游程长度，够表示一整块的零个数
    reg signed [15:0] prev_dc;

    reg [7:0]  sym;
    reg        is_ac;
    wire [15:0] hcode;
    wire [4:0]  hlen;
    reg [15:0] cur;            // 当前系数的幅度值（DC 时是差值）
    reg [3:0]  ccat;           // 当前系数的类别

    reg [47:0] bitacc;         // 右对齐，低 bitcnt 位有效
    reg [5:0]  bitcnt;
    reg        ffd_sent;       // 上一字节是 0xFF，下一拍必须补 0x00
    reg        eof_lat;        // 本块是否帧末块（eof 跟着系数来，要锁存到收尾）

    jpeg_huff_tab u_tab (.sym(sym), .is_ac(is_ac), .code(hcode), .len(hlen));

    assign s_ready = (st == S_COLL) || (st == S_IDLE);

    // 幅度编码：正数原样，负数用 v-1（T.81 F.1.2.1.2）
    wire [15:0] amp_v = cur[15] ? (cur - 16'd1) : cur;

    function [3:0] cat;
        input signed [15:0] v;
        reg [15:0] m;
        begin
            m = v[15] ? -v : v;
            if      (m < 1)     cat = 0;
            else if (m < 2)     cat = 1;
            else if (m < 4)     cat = 2;
            else if (m < 8)     cat = 3;
            else if (m < 16)    cat = 4;
            else if (m < 32)    cat = 5;
            else if (m < 64)    cat = 6;
            else if (m < 128)   cat = 7;
            else if (m < 256)   cat = 8;
            else if (m < 512)   cat = 9;
            else if (m < 1024)  cat = 10;
            else if (m < 2048)  cat = 11;
            else if (m < 4096)  cat = 12;
            else if (m < 8192)  cat = 13;
            else if (m < 16384) cat = 14;
            else                cat = 15;
        end
    endfunction

    // 从 bitacc 取最高字节
    // 幅度掩码：只保留低 ccat 位
    wire [47:0] amp_mask = (48'd1 << ccat) - 48'd1;

    wire [7:0] obyt = bitacc >> (bitcnt - 6'd8);

    // 收拾一个系数的符号：DC = 差分，AC = (run<<4)|cat
    wire signed [15:0] dc_diff = qz[0] - prev_dc;
    wire [3:0]         ac_cat  = cat(qz[k]);
    wire [15:0]        ac_amp  = qz[k][15] ? (qz[k] - 16'd1) : qz[k];

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; wn <= 0; k <= 0; run <= 0; prev_dc <= 0;
            sym <= 0; is_ac <= 0; cur <= 0; ccat <= 0;
            bitacc <= 0; bitcnt <= 0; ffd_sent <= 0; eof_lat <= 0; m_done <= 1'b0;
            m_valid <= 0; m_data <= 0;
            st_bits <= 0; st_blocks <= 0;
            for (i = 0; i < 64; i = i + 1) qz[i] <= 0;
        end else begin
            if (m_valid && m_ready) m_valid <= 1'b0;
            m_done <= 1'b0;

            // ---------------- 字节输出（只在这两个状态）----------------
            if (!m_valid && (st == S_DRAIN || st == S_FLUSH)) begin
                if (ffd_sent) begin
                    m_data   <= 8'h00;
                    m_valid  <= 1'b1;
                    ffd_sent <= 1'b0;
                end else if (bitcnt >= 6'd8) begin
                    m_data   <= obyt;
                    m_valid  <= 1'b1;
                    ffd_sent <= (obyt == 8'hFF);
                    // 不移 bitacc：低 bitcnt 位始终有效，靠 bitcnt 递减即可
                    bitcnt   <= bitcnt - 6'd8;
                    st_bits  <= st_bits + 32'd8;
                end
            end

            case (st)
            // ---------------- 收系数 ----------------
            S_IDLE: if (s_valid && s_sof && s_ready) begin
                // 每帧第一块的 DC 预测必须从 0 起（T.81）。原来只在复位清，
                // 连续帧时第一块 DC 会带上一帧的尾值，整帧被一个常数抬亮
                // （板上实测 +102，图像结构正确但整体发白）。
                prev_dc <= 16'sd0;
                qz[0] <= s_data[15:0];   qz[1] <= s_data[31:16];
                qz[2] <= s_data[47:32];  qz[3] <= s_data[63:48];
                qz[4] <= s_data[79:64];  qz[5] <= s_data[95:80];
                qz[6] <= s_data[111:96]; qz[7] <= s_data[127:112];
                wn <= 3'd1;
                st <= S_COLL;
            end

            S_COLL: if (s_valid && s_ready) begin
                qz[wn*8+0] <= s_data[15:0];   qz[wn*8+1] <= s_data[31:16];
                qz[wn*8+2] <= s_data[47:32];  qz[wn*8+3] <= s_data[63:48];
                qz[wn*8+4] <= s_data[79:64];  qz[wn*8+5] <= s_data[95:80];
                qz[wn*8+6] <= s_data[111:96]; qz[wn*8+7] <= s_data[127:112];
                if (wn == 3'd7) begin
                    eof_lat <= s_eof;
                    wn <= 0; k <= 0; run <= 0; st <= S_HC;
                end
                else wn <= wn + 3'd1;
            end

            // ---------------- 定符号（DC 差分 / AC 游程）----------------
            // AC 的游程**只在遇到非零系数时**才展开成 ZRL（T.81 的做法）：
            // 块尾剩下的零一律用 EOB 表示，不在尾部发 ZRL。
            S_HC: begin
                if (k == 6'd0) begin
                    sym    <= {4'd0, cat(dc_diff)};
                    is_ac  <= 1'b0;
                    cur    <= dc_diff;
                    ccat   <= cat(dc_diff);
                    prev_dc<= qz[0];
                    st     <= S_AMP;
                end else if (qz[k] == 16'd0) begin
                    run <= run + 6'd1;
                    if (k == 6'd63) begin
                        sym   <= 8'h00;      // EOB：后面全是零
                        is_ac <= 1'b1;
                        ccat  <= 4'd0;
                        st    <= S_AMP;
                    end else k <= k + 6'd1;
                end else if (run >= 6'd16) begin
                    // 积压的零超过 15 个：先发一个 ZRL（16 个零），k 不动
                    sym   <= 8'hF0;
                    is_ac <= 1'b1;
                    ccat  <= 4'd0;
                    run   <= run - 6'd16;
                    st    <= S_AMP;
                end else begin
                    sym   <= {run[3:0], ac_cat};
                    is_ac <= 1'b1;
                    cur   <= qz[k];
                    ccat  <= ac_cat;
                    run   <= 6'd0;
                    st    <= S_AMP;
                end
            end

            // ---------------- 打包哈夫曼码 + 幅度 ----------------
            S_AMP: begin
                // 一次 put 哈夫曼码
                bitacc <= (bitacc << hlen) | {32'd0, hcode};
                bitcnt <= bitcnt + {1'b0, hlen};
                st     <= (ccat == 4'd0) ? S_NEXT : S_AMP2;
            end

            S_AMP2: begin
                // 幅度只有低 ccat 位有效，必须掩码 —— amp_v 是 16 位符号扩展值，
                // 直接 OR 会把 bit15..ccat 的 1 也塞进去（这就是比特流错位的根因）。
                bitacc <= (bitacc << ccat) | (amp_v & amp_mask);
                bitcnt <= bitcnt + {2'b0, ccat};
                st     <= S_NEXT;
            end

            // ---------------- 下一个系数 / 收尾 ----------------
            S_NEXT: begin
                if (sym == 8'hF0) begin
                    // ZRL：k 不动，drain 完接着处理同一个系数
                    st <= S_DRAIN;
                end else if (k == 6'd63) st <= S_FLUSH;
                else begin
                    k  <= k + 6'd1;
                    st <= S_DRAIN;
                end
            end

            S_DRAIN: if (!m_valid && bitcnt < 6'd8 && !ffd_sent) st <= S_HC;

            // ---------------- 收尾：补 1 到字节边界 ----------------
            S_FLUSH: begin
                if (!eof_lat) begin
                    // 帧内块之间**不补位**：JPEG 熵编码比特流是连续的，只在帧末补 1
                    st_blocks <= st_blocks + 32'd1;
                    wn <= 3'd0;
                    st <= S_COLL;
                end else begin
                    // 帧末：把低 (8-bitcnt) 位补 1 凑满字节，再把残留字节吐完
                    if (bitcnt != 0 && bitcnt < 6'd8) begin
                        // 补位语义要和 T.81 一致：把有效数据左移到字节高位，
                        // 低位补 1。直接在高位 OR 1 会把数据挤到低端，输出就反了。
                        bitacc <= (bitacc << (8 - bitcnt)) | ((48'd1 << (8 - bitcnt)) - 48'd1);
                        bitcnt <= 6'd8;
                    end
                    if (bitcnt < 6'd8 && !m_valid && !ffd_sent) begin
                        st_blocks <= st_blocks + 32'd1;
                        wn <= 3'd0;
                        m_done <= 1'b1;      // 整帧码流结束
                        st <= S_IDLE;
                    end
                end
            end

            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
