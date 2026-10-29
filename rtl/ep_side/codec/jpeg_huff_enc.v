// jpeg_huff_enc.v — JPEG 熵编码（DC 差分 + AC 游程 + 规范哈夫曼）
// WIP: 比特流与参考实现对不上（前 3 字节 b9 fb 4b 正确，第 4 字节起出现多余的 0xFF）。
//      疑似 DRAIN/FLUSH 与 ffd_sent 的时序交互问题。不要接进顶层。

//
// 输入是量化后的之字形系数（8 个/拍，8 拍一块），输出标准 JPEG 熵编码字节流。
// DC 用差分、AC 用 (run<<4)|cat 查规范哈夫曼表（jpeg_huff_tab.v）；
// 幅度按 T.81：正数直接给 cat 位，负数用 v-1 的 cat 位。
//
// 每块 64 个系数，每个 2 拍（查表 + 打包），一块约 140 拍。
module jpeg_huff_enc (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [127:0] s_data,
    input  wire         s_valid,
    output wire         s_ready,
    input  wire         s_sof,
    output reg  [7:0]   m_data,
    output reg          m_valid,
    input  wire         m_ready,
    output reg          m_sof,
    output reg  [31:0]  st_bits,
    output reg  [31:0]  st_blocks
);
    localparam S_IDLE = 3'd0, S_COLL = 3'd1, S_PROC = 3'd2, S_FLUSH = 3'd3,
               S_DRAIN = 3'd4;
    reg [2:0] st;

    reg [15:0] qz [0:63];
    reg [2:0]  wn;
    reg [5:0]  k;
    reg [3:0]  run;
    reg signed [15:0] prev_dc;
    reg [1:0]  ph;                  // 0=算符号 1=查表/打包
    reg [7:0]  sym;
    reg        is_ac;
    wire [15:0] hcode;
    wire [4:0]  hlen;
    reg [15:0] cur;
    reg [3:0]  ccat;
    reg        do_amp;
    reg [3:0]  pend_run;

    // 位打包
    reg [63:0] bitacc;
    reg [6:0]  bitcnt;
    reg        ffd_sent;            // 上一个输出字节是 0xFF，需要补 0x00

    jpeg_huff_tab u_tab (.sym(sym), .is_ac(is_ac), .code(hcode), .len(hlen));

    // S_IDLE 也要 ready：SOF 和第一组系数是同一拍到的
    wire [7:0] obyt = bitacc >> (bitcnt - 7'd8);

    assign s_ready = (st == S_COLL) || (st == S_IDLE);

    function [3:0] cat;
        input signed [15:0] v;
        reg [15:0] m;
        begin
            m = v[15] ? -v : v;
            if (m < 1) cat = 0;
            else if (m < 2) cat = 1;
            else if (m < 4) cat = 2;
            else if (m < 8) cat = 3;
            else if (m < 16) cat = 4;
            else if (m < 32) cat = 5;
            else if (m < 64) cat = 6;
            else if (m < 128) cat = 7;
            else if (m < 256) cat = 8;
            else if (m < 512) cat = 9;
            else if (m < 1024) cat = 10;
            else if (m < 2048) cat = 11;
            else if (m < 4096) cat = 12;
            else if (m < 8192) cat = 13;
            else if (m < 16384) cat = 14;
            else cat = 15;
        end
    endfunction

    // 把一个 (code,len) 压进 bitacc
    // 位累加器右对齐：低 bitcnt 位有效。每处理完一个系数就 DRAIN 到 bitcnt<8，
    // 所以 bitcnt 最大 38 左右，不会溢出 64 位。
    task put;
        input [15:0] c;
        input [4:0]  l;
        begin
            if (l != 0) begin
                bitacc = (bitacc << l) | {48'd0, c[15:0]};
                bitcnt = bitcnt + l;
            end
        end
    endtask

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_IDLE; wn <= 0; k <= 0; run <= 0; prev_dc <= 0; ph <= 0;
            sym <= 0; is_ac <= 0; cur <= 0; ccat <= 0; do_amp <= 0; pend_run <= 0;
            bitacc <= 0; bitcnt <= 0; m_valid <= 0; m_data <= 0; m_sof <= 0; ffd_sent <= 0;
            st_bits <= 0; st_blocks <= 0;
            for (i = 0; i < 64; i = i + 1) qz[i] <= 0;
        end else begin
            // ---- 字节输出（0xFF 后面必须补 0x00）----
            if (m_valid && m_ready) m_valid <= 1'b0;
            // 把 bitacc 里的整字节逐个吐出；0xFF 后面补 0x00（T.81 字节填充）
            if (!m_valid && (st == S_DRAIN || st == S_FLUSH)) begin
                if (ffd_sent) begin
                    m_data   <= 8'h00;
                    m_valid  <= 1'b1;
                    ffd_sent <= 1'b0;
                end else if (bitcnt >= 7'd8) begin
                    m_data   <= obyt;
                    m_valid  <= 1'b1;
                    ffd_sent <= (obyt == 8'hFF);
                    bitcnt   <= bitcnt - 7'd8;
                    st_bits  <= st_bits + 32'd8;
                end
            end

            case (st)
            S_IDLE: if (s_valid && s_sof && s_ready) begin
                qz[0] <= s_data[15:0];
                qz[1] <= s_data[31:16];
                qz[2] <= s_data[47:32];
                qz[3] <= s_data[63:48];
                qz[4] <= s_data[79:64];
                qz[5] <= s_data[95:80];
                qz[6] <= s_data[111:96];
                qz[7] <= s_data[127:112];
                wn <= 3'd1;
                st <= S_COLL;
            end

            S_COLL: if (s_valid && s_ready) begin
                qz[wn*8+0] <= s_data[15:0];
                qz[wn*8+1] <= s_data[31:16];
                qz[wn*8+2] <= s_data[47:32];
                qz[wn*8+3] <= s_data[63:48];
                qz[wn*8+4] <= s_data[79:64];
                qz[wn*8+5] <= s_data[95:80];
                qz[wn*8+6] <= s_data[111:96];
                qz[wn*8+7] <= s_data[127:112];
                if (wn == 3'd7) begin wn <= 0; k <= 0; run <= 0; ph <= 0; st <= S_PROC; end
                else wn <= wn + 3'd1;
            end

            S_PROC: begin
                if (ph == 2'd0) begin
                    // 算符号 + 幅度
                    cur <= qz[k];
                    ccat <= cat(qz[k]);
                    if (k == 6'd0) begin
                        sym <= {4'd0, cat(qz[0] - prev_dc)};
                        is_ac <= 1'b0;
                        ccat <= cat(qz[0] - prev_dc);
                        cur  <= qz[0] - prev_dc;
                        prev_dc <= qz[0];
                    end else begin
                        is_ac <= 1'b1;
                        if (qz[k] == 16'd0) begin
                            if (run == 4'd15) begin
                                sym <= 8'hF0;      // ZRL：16 个零
                                run <= 0;
                            end else begin
                                run <= run + 4'd1;
                                k   <= k + 6'd1;
                                ph  <= 2'd0;
                                if (k == 6'd63) st <= S_FLUSH;
                            end
                        end else begin
                            sym <= {run, cat(qz[k])};
                            ccat <= cat(qz[k]);
                            run <= 0;
                        end
                    end
                    ph <= 2'd1;
                end else begin
                    // 查表结果已经是组合的，这里打包并接幅度
                    put(hcode, hlen);
                    if (ccat != 0) begin
                        put(cur[15] ? (cur - 16'd1) : cur, {1'b0, ccat});
                    end
                    ph <= 2'd0;
                    if (k == 6'd63) st <= S_FLUSH;
                    else begin
                        k  <= k + 6'd1;
                        st <= S_DRAIN;
                    end
                end
            end

            S_DRAIN: if (!m_valid && bitcnt < 7'd8 && !ffd_sent) st <= S_PROC;

            S_FLUSH: begin
                // 未对齐的比特补 1（JPEG 规定），补到字节边界后由输出通路吐出
                // 右对齐：把低 (8-bitcnt) 位补 1 凑满一个字节
                if (bitcnt != 0 && bitcnt < 7'd8) begin
                    bitacc = bitacc | ((64'h1 << (8 - bitcnt)) - 1);
                    bitcnt = 7'd8;
                end
                if (bitcnt < 7'd8 && !m_valid && !ffd_sent) begin
                    st_blocks <= st_blocks + 32'd1;
                    st <= S_IDLE;
                end
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
