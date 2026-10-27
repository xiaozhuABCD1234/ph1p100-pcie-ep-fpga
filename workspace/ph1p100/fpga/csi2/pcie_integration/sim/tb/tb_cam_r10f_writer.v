///////////////////////////////////////////////////////////////////////////////
//  tb_cam_r10f_writer.v — T11.rk-align-raw G1：RAW10→R10F 写者（真实 RTL）
//
//  被测：fpga/csi2/pcie_integration/rtl/ep_side/ddr/cam_r10f_writer.v
//  三个实例覆盖不同几何/容量：
//    u_wr  ：8×4（= 冻结验收向量 r10f-small-synthetic.dma 的几何）—— 全字节比对
//            + 头/载荷/尾零 + 三 CRC + 发布/所有权/坏帧/超时/复位
//    u_wr2 ：64×8 + FIFO_AW=6（64 条）—— AXI 停摆时 FIFO 溢出拒整帧
//    u_wr3 ：1920×1080（正式几何，X0=960/Y0=540/SKIP=37）—— 长度边界：
//            81,024 拍 / 633 个主突发 + 1 笔头 CRC 重写 / 640B 尾零 /
//            头字段 + 头 CRC（Python 独立模型常数）+ 载荷 CRC + 抽拍逐字节
//
//  独立模型：TB 自带像素公式/打包/CRC32（不复用 DUT 任何 helper）。
//  行级节流：TB 按“每行 240 前置组 + 480 窗口组 + 行间空档（1800 拍）”驱动，
//  保证 FIFO（1024 条）不因“无空档连发”溢出（真实相机同样有行间空档）。
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_cam_r10f_writer;

    // ---------------- 时钟 / 复位 ----------------
    reg clk_cam = 0, clk_fb = 0, clk_ddr = 0;
    always #3  clk_cam = ~clk_cam;    // 166MHz 量级，仅驱动关系；不测速率
    always #8  clk_fb  = ~clk_fb;
    always #5  clk_ddr = ~clk_ddr;

    reg rst_cam_n = 0;
    reg wr_rst    = 1;                // 同时当 rst_fb / rst_ddr

    integer errors = 0;
    integer t1 = 0;
    task chk(input cond, input [8*96-1:0] msg);
        begin
            if (!cond) begin
                errors = errors + 1;
                if (errors <= 40) $display("  ERROR #%0d @%0t : %s", errors, $time, msg);
            end
        end
    endtask

    // ---------------- 独立 CRC32（逐位，不复用 DUT） ----------------
    function [31:0] crc32_b;
        input [31:0] c;
        input [7:0]  b;
        reg [31:0] v;
        integer k;
        reg fb;
        begin
            v = c ^ {24'd0, b};
            for (k = 0; k < 8; k = k + 1) begin
                fb = v[0];
                v = v >> 1;
                if (fb) v = v ^ 32'hEDB88320;
            end
            crc32_b = v;
        end
    endfunction
    localparam [31:0] CRC_INIT = 32'hFFFF_FFFF;

    // ========================================================================
    //  DUT1：8×4（冻结向量几何）
    // ========================================================================
    localparam integer W1 = 8, H1 = 4, GPQ1 = 2;
    localparam integer PAY1 = 40, DMA1 = 4096, BEATS1 = 128;
    localparam [31:0] BASE0_1 = 32'h0010_0000, BASE1_1 = 32'h0090_0000;
    localparam [31:0] SES1 = 32'h2026_1017;

    // 冻结验收向量（r10f-small-synthetic.dma）的像素模式：每组重复 [0,1,1022,1023]
    function [9:0] pix1;
        input integer x, y;
        begin
            case (x % 4)
                0: pix1 = 10'd0;
                1: pix1 = 10'd1;
                2: pix1 = 10'd1022;
                default: pix1 = 10'd1023;
            endcase
        end
    endfunction

    function [7:0] exp1_byte;
        input integer b;
        integer i, r;
        reg [9:0] p0, p1, p2, p3;
        begin
            i = b / 5; r = b % 5;
            p0 = pix1((4*i+0) % W1,  (4*i+0) / W1);
            p1 = pix1((4*i+1) % W1,  (4*i+1) / W1);
            p2 = pix1((4*i+2) % W1,  (4*i+2) / W1);
            p3 = pix1((4*i+3) % W1,  (4*i+3) / W1);
            case (r)
                0: exp1_byte = p0[9:2];
                1: exp1_byte = p1[9:2];
                2: exp1_byte = p2[9:2];
                3: exp1_byte = p3[9:2];
                default: exp1_byte = {p3[1:0], p2[1:0], p1[1:0], p0[1:0]};
            endcase
        end
    endfunction

    reg [31:0] hdr1_exp [0:31];
    initial begin
        hdr1_exp[0]=32'h46303152; hdr1_exp[1]=32'h00000001; hdr1_exp[2]=32'h00000080; hdr1_exp[3]=32'h00000000;
        hdr1_exp[4]=32'h20261017; hdr1_exp[5]=32'h00000001; hdr1_exp[6]=32'h00000001; hdr1_exp[7]=32'h00040008;
        hdr1_exp[8]=32'h0000000A; hdr1_exp[9]=32'h00000000; hdr1_exp[10]=32'h000A0003; hdr1_exp[11]=32'h00000028;
        hdr1_exp[12]=32'h00000028; hdr1_exp[13]=32'h00000001; hdr1_exp[14]=32'h00000000; hdr1_exp[15]=32'h00000000;
        hdr1_exp[16]=32'h00000000; hdr1_exp[17]=32'h00000000; hdr1_exp[18]=32'h00000000; hdr1_exp[19]=32'h00000000;
        hdr1_exp[20]=32'h97E69DE2; hdr1_exp[21]=32'h97E69DE2; hdr1_exp[22]=32'h6E5C61EE; hdr1_exp[23]=32'h00000000;
        hdr1_exp[24]=32'h00000000; hdr1_exp[25]=32'h00000000; hdr1_exp[26]=32'h00000000; hdr1_exp[27]=32'h00000000;
        hdr1_exp[28]=32'h00000000; hdr1_exp[29]=32'h00000000; hdr1_exp[30]=32'h00000000; hdr1_exp[31]=32'h00000000;
    end

    reg         a_vsync=0, a_in_frame=0, a_in_line=0, a_valid=0, a_good=0, a_abort=0;
    reg  [39:0] a_pix=0;
    reg         a_prot=0, a_rel0=0, a_rel1=0;
    wire [31:0] a_seq, a_base, a_status, a_len;
    wire [15:0] a_lines, a_grp; wire a_anom; wire [95:0] a_drop;
    wire        a_awvalid, a_awready, a_wvalid, a_wready, a_bvalid, a_bready, a_wlast;
    wire [28:0] a_awaddr; wire [7:0] a_awlen; wire [2:0] a_awsize; wire [1:0] a_awburst;
    wire [255:0] a_wdata; wire [31:0] a_wstrb; wire [1:0] a_bresp;
    integer     a_beats = 0;

    cam_r10f_writer #(
        .W(W1), .H(H1), .X0(16'd0), .Y0(16'd0), .SKIP_ROWS(16'd0),
        .BASE0(BASE0_1), .BASE1(BASE1_1), .FIFO_AW(10), .BURST_BEATS(128),
        .CAMERA_ID(8'd0), .SRC_BAYER_PHASE(2'd3), .MODE_ID(32'd1), .TMO_LIMIT(21'd4095)
    ) u_wr (
        .cam_clk(clk_cam), .cam_rst_n(rst_cam_n),
        .cam_vsync(a_vsync), .cam_in_frame(a_in_frame), .cam_in_line(a_in_line),
        .cam_pix(a_pix), .cam_pix_valid(a_valid),
        .cam_frame_good(a_good), .cam_frame_abort(a_abort),
        .prot_en(a_prot), .rel_tgl0(a_rel0), .rel_tgl1(a_rel1),
        .clk_fb(clk_fb), .rst_fb(wr_rst), .session_id(SES1),
        .wr_frame_seq(a_seq), .wr_base(a_base), .wr_status(a_status), .wr_len(a_len),
        .dbg_lines_per_frame(a_lines), .dbg_max_grp_per_line(a_grp),
        .dbg_anomaly(a_anom), .dbg_drop(a_drop),
        .clk_ddr(clk_ddr), .rst_ddr(wr_rst), .ddr_cal_done(1'b1), .arm(1'b1),
        .axi_busy(),
        .m_axi_awaddr(a_awaddr), .m_axi_awlen(a_awlen), .m_axi_awsize(a_awsize),
        .m_axi_awburst(a_awburst), .m_axi_awvalid(a_awvalid), .m_axi_awready(a_awready),
        .m_axi_wdata(a_wdata), .m_axi_wstrb(a_wstrb), .m_axi_wlast(a_wlast),
        .m_axi_wvalid(a_wvalid), .m_axi_wready(a_wready),
        .m_axi_bresp(a_bresp), .m_axi_bvalid(a_bvalid), .m_axi_bready(a_bready)
    );

    reg [255:0] mem1 [0:127];
    reg [28:0]  a_awaddr_q = 0;  reg [7:0] a_awlen_q = 0;
    integer     a_beat_q = 0, a_bursts = 0, a_4k_err = 0;
    reg         a_bpend = 0;
    reg [7:0]   a_bcnt = 0;
    integer     a_bib = 0;
    integer     i1;
    assign a_awready = wr_rst ? 1'b0 : 1'b1;
    assign a_wready  = wr_rst ? 1'b0 : 1'b1;
    assign a_bresp   = 2'b00;
    assign a_bvalid  = a_bpend && (a_bcnt == 8'd0);
    assign a_bready  = 1'b1;

    function [7:0] mem1_byte;
        input integer b;
        begin
            mem1_byte = mem1[b/32][(b%32)*8 +: 8];
        end
    endfunction

    function [7:0] hdr1_byte;
        input integer b;
        begin
            hdr1_byte = hdr1_exp[b/4][(b%4)*8 +: 8];
        end
    endfunction

    always @(posedge clk_ddr) begin
        if (a_awvalid && a_awready) begin
            a_awaddr_q <= a_awaddr;
            a_awlen_q  <= a_awlen;
            a_bursts    = a_bursts + 1;
            a_bib       = 0;
            if (((a_awaddr & 29'd4095) + (a_awlen + 29'd1)*29'd32) > 29'd4096) a_4k_err = a_4k_err + 1;
            a_bcnt     <= a_awlen + 8'd1;
            a_bpend    <= 1'b1;
            a_beat_q    = 0;
        end
        if (a_wvalid && a_wready) begin
            a_beats = a_beats + 1;
            for (i1 = 0; i1 < 32; i1 = i1 + 1)
                if (a_wstrb[i1]) begin
                    if (a_awaddr_q >= BASE1_1[28:0])
                        mem1[((a_awaddr_q - BASE1_1[28:0])>>5) + a_bib[6:0]][i1*8 +: 8] <= a_wdata[i1*8 +: 8];
                    else
                        mem1[((a_awaddr_q - BASE0_1[28:0])>>5) + a_bib[6:0]][i1*8 +: 8] <= a_wdata[i1*8 +: 8];
                end
            a_beat_q = a_beat_q + 1;
            a_bib    = a_bib + 1;
            if (a_bcnt != 8'd0) a_bcnt <= a_bcnt - 8'd1;
        end
        if (a_bvalid && a_bready) a_bpend <= 1'b0;
    end

    // ========================================================================
    //  DUT2：64×8 + FIFO_AW=6（溢出）
    // ========================================================================
    localparam integer W2 = 64, H2 = 8, GPQ2 = 16;
    reg  b_vsync=0, b_in_frame=0, b_in_line=0, b_valid=0, b_good=0;
    reg  [39:0] b_pix=0;
    wire [31:0] b_seq, b_base, b_status, b_len;
    wire [15:0] b_lines, b_grp; wire b_anom;
    wire b_awvalid, b_awready, b_wvalid, b_wready, b_bvalid, b_bready, b_wlast;
    wire [28:0] b_awaddr; wire [7:0] b_awlen; wire [2:0] b_awsize; wire [1:0] b_awburst;
    wire [255:0] b_wdata; wire [31:0] b_wstrb; wire [1:0] b_bresp;
    reg  b_slave_stall = 0;
    integer b_beats = 0;
    assign b_awready = ~b_slave_stall & ~wr_rst;
    assign b_wready  = ~b_slave_stall & ~wr_rst;
    assign b_bresp   = 2'b00;
    assign b_bvalid  = 1'b1;
    assign b_bready  = 1'b1;
    always @(posedge clk_ddr) if (b_wvalid && b_wready) b_beats = b_beats + 1;

    cam_r10f_writer #(
        .W(W2), .H(H2), .X0(16'd0), .Y0(16'd0), .SKIP_ROWS(16'd0),
        .BASE0(32'h0010_0000), .BASE1(32'h0090_0000), .FIFO_AW(6), .BURST_BEATS(128),
        .CAMERA_ID(8'd0), .SRC_BAYER_PHASE(2'd0), .MODE_ID(32'd1), .TMO_LIMIT(21'd8191)
    ) u_wr2 (
        .cam_clk(clk_cam), .cam_rst_n(rst_cam_n),
        .cam_vsync(b_vsync), .cam_in_frame(b_in_frame), .cam_in_line(b_in_line),
        .cam_pix(b_pix), .cam_pix_valid(b_valid),
        .cam_frame_good(b_good), .cam_frame_abort(1'b0),
        .prot_en(1'b0), .rel_tgl0(1'b0), .rel_tgl1(1'b0),
        .clk_fb(clk_fb), .rst_fb(wr_rst), .session_id(32'h1234_5678),
        .wr_frame_seq(b_seq), .wr_base(b_base), .wr_status(b_status), .wr_len(b_len),
        .dbg_lines_per_frame(b_lines), .dbg_max_grp_per_line(b_grp),
        .dbg_anomaly(b_anom), .dbg_drop(),
        .clk_ddr(clk_ddr), .rst_ddr(wr_rst), .ddr_cal_done(1'b1), .arm(1'b1),
        .axi_busy(),
        .m_axi_awaddr(b_awaddr), .m_axi_awlen(b_awlen), .m_axi_awsize(b_awsize),
        .m_axi_awburst(b_awburst), .m_axi_awvalid(b_awvalid), .m_axi_awready(b_awready),
        .m_axi_wdata(b_wdata), .m_axi_wstrb(b_wstrb), .m_axi_wlast(b_wlast),
        .m_axi_wvalid(b_wvalid), .m_axi_wready(b_wready),
        .m_axi_bresp(b_bresp), .m_axi_bvalid(b_bvalid), .m_axi_bready(b_bready)
    );

    // ========================================================================
    //  DUT3：1920×1080（正式几何）
    // ========================================================================
    localparam integer W3 = 1920, H3 = 1080, GPR3 = 480, PRE3 = 240, SKIP3 = 37;
    localparam [15:0] X03 = 16'd960, Y03 = 16'd540, SK3 = 16'd37;
    localparam integer PAY3 = 2592000, DMA3 = 2592768, BEATS3 = 81024;
    localparam [31:0] BASE0_3 = 32'h0010_0000, BASE1_3 = 32'h0090_0000;
    localparam [31:0] SES3 = 32'h2026_1017;
    localparam [31:0] EXP_PAYCRC3 = 32'hAC1B_6FE1;
    localparam [31:0] EXP_HDRCRC3 = 32'h56BA_381A;

    reg  c_vsync=0, c_in_frame=0, c_in_line=0, c_valid=0, c_good=0;
    reg  [39:0] c_pix=0;
    wire [31:0] c_seq, c_base, c_status, c_len;
    wire c_awvalid, c_awready, c_wvalid, c_wready, c_bvalid, c_bready, c_wlast;
    wire [28:0] c_awaddr; wire [7:0] c_awlen; wire [2:0] c_awsize; wire [1:0] c_awburst;
    wire [255:0] c_wdata; wire [31:0] c_wstrb; wire [1:0] c_bresp;
    integer  c_beats = 0, c_bursts = 0, c_4k_err = 0, c_addr_err = 0, c_strb_err = 0;
    reg [255:0] c_hdr_cap [0:3];
    reg [255:0] c_tail_cap [0:19];
    reg [255:0] c_spot0, c_spot1, c_spot2;
    reg [28:0]  c_base_q = 0;
    reg [28:0]  c_awaddr_q = 0;
    reg [7:0]   c_awlen_q = 0;
    reg [7:0]   c_bcnt3 = 0;
    integer     c_bib = 0;
    reg         c_bpend = 0;
    assign c_awready = wr_rst ? 1'b0 : 1'b1;
    assign c_wready  = wr_rst ? 1'b0 : 1'b1;
    assign c_bresp   = 2'b00;
    assign c_bvalid  = c_bpend && (c_bcnt3 == 8'd0);
    assign c_bready  = 1;

    function [7:0] c_hdr_byte;
        input integer b;
        begin
            c_hdr_byte = c_hdr_cap[b/32][(b%32)*8 +: 8];
        end
    endfunction

    always @(posedge clk_ddr) begin
        if (c_awvalid && c_awready) begin
            c_awaddr_q <= c_awaddr;
            c_base_q   <= c_awaddr;
            c_bib       = 0;
            c_awlen_q  <= c_awlen;
            c_bursts    = c_bursts + 1;
            if (((c_awaddr & 29'd4095) + (c_awlen + 29'd1)*29'd32) > 29'd4096) c_4k_err = c_4k_err + 1;
            c_bcnt3 <= c_awlen + 8'd1;
            c_bpend <= 1'b1;
        end
        if (c_wvalid && c_wready) begin
            if (c_awlen_q == 8'd127) begin
                if ((c_base_q + 29'd32*c_bib[28:0]) != (BASE0_3[28:0] + 29'd32*c_beats[28:0])) begin
                    c_addr_err = c_addr_err + 1;
                    if (c_addr_err <= 5)
                        $display("  CADDR beat=%0d base=%08h bib=%0d exp=%08h len=%0d", c_beats,
                                 c_base_q, c_bib, BASE0_3[28:0] + 29'd32*c_beats[28:0], c_awlen_q);
                end
            end else begin
                if (c_base_q != (BASE0_3[28:0] + 29'd64)) c_addr_err = c_addr_err + 1;
                if (c_wstrb != 32'h0FFF_0000) c_strb_err = c_strb_err + 1;
                // 重写那一拍覆盖 header 字节 80..91 = beat 字节 16..27 = 位 [128..223]
                c_hdr_cap[2][159:128] <= c_wdata[159:128];
                c_hdr_cap[2][191:160] <= c_wdata[191:160];
                c_hdr_cap[2][223:192] <= c_wdata[223:192];
                $display("  P10 RW wdata=%08h_%08h_%08h_%08h_%08h_%08h_%08h_%08h strb=%08h",
                         c_wdata[255:224], c_wdata[223:192], c_wdata[191:160], c_wdata[159:128],
                         c_wdata[127:96], c_wdata[95:64], c_wdata[63:32], c_wdata[31:0], c_wstrb);
            end
            c_bib = c_bib + 1;
            if (c_beats < 4)  c_hdr_cap[c_beats] <= c_wdata;
            if (c_beats == 4) c_spot0 <= c_wdata;
            if ((c_beats >= (BEATS3-20)) && (c_beats < BEATS3)) c_tail_cap[c_beats-(BEATS3-20)] <= c_wdata;
            if (c_beats == 1000)  c_spot1 <= c_wdata;
            if (c_beats == 50000) c_spot2 <= c_wdata;
            c_beats = c_beats + 1;
            if (c_bcnt3 != 8'd0) c_bcnt3 <= c_bcnt3 - 8'd1;
        end
        if (c_bvalid && c_bready) c_bpend <= 1'b0;
    end

    cam_r10f_writer #(
        .W(W3), .H(H3), .X0(X03), .Y0(Y03), .SKIP_ROWS(SK3),
        .BASE0(BASE0_3), .BASE1(BASE1_3), .FIFO_AW(10), .BURST_BEATS(128),
        .CAMERA_ID(8'd0), .SRC_BAYER_PHASE(2'd0), .MODE_ID(32'd1)
    ) u_wr3 (
        .cam_clk(clk_cam), .cam_rst_n(rst_cam_n),
        .cam_vsync(c_vsync), .cam_in_frame(c_in_frame), .cam_in_line(c_in_line),
        .cam_pix(c_pix), .cam_pix_valid(c_valid),
        .cam_frame_good(c_good), .cam_frame_abort(1'b0),
        .prot_en(1'b0), .rel_tgl0(1'b0), .rel_tgl1(1'b0),
        .clk_fb(clk_fb), .rst_fb(wr_rst), .session_id(SES3),
        .wr_frame_seq(c_seq), .wr_base(c_base), .wr_status(c_status), .wr_len(c_len),
        .dbg_lines_per_frame(), .dbg_max_grp_per_line(), .dbg_anomaly(), .dbg_drop(),
        .clk_ddr(clk_ddr), .rst_ddr(wr_rst), .ddr_cal_done(1'b1), .arm(1'b1),
        .axi_busy(),
        .m_axi_awaddr(c_awaddr), .m_axi_awlen(c_awlen), .m_axi_awsize(c_awsize),
        .m_axi_awburst(c_awburst), .m_axi_awvalid(c_awvalid), .m_axi_awready(c_awready),
        .m_axi_wdata(c_wdata), .m_axi_wstrb(c_wstrb), .m_axi_wlast(c_wlast),
        .m_axi_wvalid(c_wvalid), .m_axi_wready(c_wready),
        .m_axi_bresp(c_bresp), .m_axi_bvalid(c_bvalid), .m_axi_bready(c_bready)
    );

    reg [31:0] hdr3_exp [0:31];
    reg        hdrpass_q3 = 0;
    always @(posedge clk_ddr) begin
        if (u_wr3.hdr_done_r && !hdrpass_q3)
            $display("  P10 HDRPASS crc=%08h pay=%08h @%0t", u_wr3.hdr_crc_r,
                     u_wr3.crc_pay_final, $time);
        hdrpass_q3 <= u_wr3.hdr_done_r;
    end
    initial begin
        hdr3_exp[0]=32'h46303152; hdr3_exp[1]=32'h00000001; hdr3_exp[2]=32'h00000080; hdr3_exp[3]=32'h00000000;
        hdr3_exp[4]=32'h20261017; hdr3_exp[5]=32'h00000001; hdr3_exp[6]=32'h00000001; hdr3_exp[7]=32'h04380780;
        hdr3_exp[8]=32'h00000960; hdr3_exp[9]=32'h021C03C0; hdr3_exp[10]=32'h000A0003; hdr3_exp[11]=32'h00278D00;
        hdr3_exp[12]=32'h00278D00; hdr3_exp[13]=32'h00000001; hdr3_exp[14]=32'h00000000; hdr3_exp[15]=32'h00000000;
        hdr3_exp[16]=32'h00000000; hdr3_exp[17]=32'h00000000; hdr3_exp[18]=32'h00000000; hdr3_exp[19]=32'h00000002;
        hdr3_exp[20]=32'hAC1B6FE1; hdr3_exp[21]=32'hAC1B6FE1; hdr3_exp[22]=32'h56BA381A; hdr3_exp[23]=32'h00000000;
        hdr3_exp[24]=32'h00000000; hdr3_exp[25]=32'h00000000; hdr3_exp[26]=32'h00000000; hdr3_exp[27]=32'h00000000;
        hdr3_exp[28]=32'h00000000; hdr3_exp[29]=32'h00000000; hdr3_exp[30]=32'h00000000; hdr3_exp[31]=32'h00000000;
    end

    function [7:0] hdr3_byte;
        input integer b;
        begin
            hdr3_byte = hdr3_exp[b/4][(b%4)*8 +: 8];
        end
    endfunction

    // DUT3 载荷第 b 字节模型（源坐标公式 value=(x*3+y*5)&0x3FF；x=960..2879、y=577..1656）
    function [7:0] exp3_byte;
        input integer b;
        integer row, rem, i, r;
        integer x0;
        reg [9:0] p0, p1, p2, p3;
        begin
            row = b / 2400;
            rem = b % 2400;
            i   = rem / 5;
            r   = rem % 5;
            x0  = 960 + i*4;
            p0 = (x0*3       + (row+577)*5) & 10'h3FF;
            p1 = ((x0+1)*3   + (row+577)*5) & 10'h3FF;
            p2 = ((x0+2)*3   + (row+577)*5) & 10'h3FF;
            p3 = ((x0+3)*3   + (row+577)*5) & 10'h3FF;
            case (r)
                0: exp3_byte = p0[9:2];
                1: exp3_byte = p1[9:2];
                2: exp3_byte = p2[9:2];
                3: exp3_byte = p3[9:2];
                default: exp3_byte = {p3[1:0], p2[1:0], p1[1:0], p0[1:0]};
            endcase
        end
    endfunction

    // ========================================================================
    //  帧驱动任务
    // ========================================================================
    task a_frame;
        input integer bad_mode;
        integer yy, gg;
        reg [9:0] q0, q1, q2, q3;
        begin
            @(negedge clk_cam); a_vsync = 1;
            @(negedge clk_cam); a_vsync = 0; a_in_frame = 1;
            for (yy = 0; yy < H1; yy = yy + 1) begin
                @(negedge clk_cam); a_in_line = 1;
                @(negedge clk_cam); a_in_line = 0;
                for (gg = 0; gg < GPQ1; gg = gg + 1) begin
                    if (!((bad_mode == 3) && (yy == 2) && (gg == 1))) begin
                        q0 = pix1(gg*4+0, yy); q1 = pix1(gg*4+1, yy);
                        q2 = pix1(gg*4+2, yy); q3 = pix1(gg*4+3, yy);
                        @(negedge clk_cam);
                        a_pix = {q3, q2, q1, q0}; a_valid = 1;
                        @(negedge clk_cam); a_valid = 0;
                    end
                end
                if ((bad_mode == 1) && (yy == 2)) begin
                    @(negedge clk_cam); a_abort = 1;
                    @(negedge clk_cam); a_abort = 0;
                end
            end
            if (bad_mode != 4) begin
                @(negedge clk_cam); if (bad_mode != 2) a_good = 1;
                @(negedge clk_cam); a_in_frame = 0;
                @(negedge clk_cam); a_good = 0;
            end
            // bad_mode==4：保持 in_frame=1（主流程等 TMO 收口后再收边沿）
        end
    endtask

    task b_frame;
        integer yy, gg, xv;
        begin
            @(negedge clk_cam); b_vsync = 1;
            @(negedge clk_cam); b_vsync = 0; b_in_frame = 1;
            for (yy = 0; yy < H2; yy = yy + 1) begin
                @(negedge clk_cam); b_in_line = 1;
                @(negedge clk_cam); b_in_line = 0;
                for (gg = 0; gg < GPQ2; gg = gg + 1) begin
                    @(negedge clk_cam); b_pix = 40'h0123456789; b_valid = 1;
                    @(negedge clk_cam); b_valid = 0;
                end
                // 行间空档：FIFO 只有 64 条，必须给 DDR 侧排空时间
                for (xv = 0; xv < 60; xv = xv + 1) @(negedge clk_cam);
            end
            @(negedge clk_cam); b_good = 1;
            @(negedge clk_cam); b_in_frame = 0;
            @(negedge clk_cam); b_good = 0;
        end
    endtask

    task c_frame;
        integer yy, gg;
        integer xv;
        reg [9:0] q0, q1, q2, q3;
        begin
            @(negedge clk_cam); c_vsync = 1;
            @(negedge clk_cam); c_vsync = 0; c_in_frame = 1;
            // 37 个物理哑行 + 有效图 y=540（ROI y 原点的物理行 = 577）之前的 540 行
            for (yy = 0; yy < (SKIP3 + Y03); yy = yy + 1) begin
                @(negedge clk_cam); c_in_line = 1;
                @(negedge clk_cam); c_in_line = 0;
            end
            for (yy = 0; yy < H3; yy = yy + 1) begin
                @(negedge clk_cam); c_in_line = 1;
                @(negedge clk_cam); c_in_line = 0;
                for (gg = 0; gg < PRE3; gg = gg + 1) begin
                    @(negedge clk_cam); c_pix = 40'h0; c_valid = 1;
                    @(negedge clk_cam); c_valid = 0;
                end
                for (gg = 0; gg < GPR3; gg = gg + 1) begin
                    q0 = ((960+gg*4)*3   + (577+yy)*5) & 10'h3FF;
                    q1 = ((960+gg*4+1)*3 + (577+yy)*5) & 10'h3FF;
                    q2 = ((960+gg*4+2)*3 + (577+yy)*5) & 10'h3FF;
                    q3 = ((960+gg*4+3)*3 + (577+yy)*5) & 10'h3FF;
                    @(negedge clk_cam);
                    c_pix = {q3, q2, q1, q0}; c_valid = 1;
                    @(negedge clk_cam); c_valid = 0;
                end
                for (xv = 0; xv < 1800; xv = xv + 1) @(negedge clk_cam);
            end
            @(negedge clk_cam); c_good = 1;
            @(negedge clk_cam); c_in_frame = 0;
            @(negedge clk_cam); c_good = 0;
        end
    endtask

    task a_wait_idle;
        input integer maxcyc;
        begin
            t1 = 0;
            while ((u_wr.s_state != 3'd0) && (t1 < maxcyc)) begin @(posedge clk_fb); t1 = t1 + 1; end
        end
    endtask
    task b_wait_idle;
        input integer maxcyc;
        begin
            t1 = 0;
            while ((u_wr2.s_state != 3'd0) && (t1 < maxcyc)) begin @(posedge clk_fb); t1 = t1 + 1; end
        end
    endtask

    // ========================================================================
    //  主流程
    // ========================================================================
    integer k, bb, fd, mismatch;
    integer frames_before, err_before, blk_par;
    reg [7:0]  hb;
    reg [31:0] hc32, pc32;

    initial begin
        // ---- P0 复位默认 ----
        rst_cam_n = 0; wr_rst = 1; a_prot = 0;
        #100; rst_cam_n = 1; #400; wr_rst = 0; #200;
        repeat (20) @(negedge clk_cam);
        $display("=== P0 复位默认：无发布/无 AXI ===");
        chk(a_seq == 0, "P0: seq != 0 after reset");
        chk(a_beats == 0, "P0: AXI activity after reset");

        // ---- P1 好帧 #1 ----
        $display("=== P1 好帧#1：4096B 逐字节 + 三 CRC + 发布 ===");
        for (k = 0; k < 128; k = k + 1) mem1[k] = 256'd0;
        a_beats = 0; a_bursts = 0;
        a_frame(0);
        repeat (300) @(negedge clk_cam);
        a_wait_idle(200000);
        repeat (80) @(posedge clk_fb);
        chk(a_seq == 1, "P1: good frame did not publish");
        chk(a_base == BASE0_1, "P1: base != BASE0");
        chk(a_len == DMA1, "P1: wr_len != 4096");
        chk(a_status[2] == 1'b0, "P1: published frame flagged err");
        chk(a_beats == BEATS1 + 1, "P1: beat count != 129 (128 main + 1 rewrite)");
        chk(a_bursts == 2, "P1: burst count != 2");
        chk(a_4k_err == 0, "P1: 4KiB burst rule violated");
        mismatch = 0;
        for (k = 0; k < 128; k = k + 1)
            if (mem1_byte(k) !== hdr1_byte(k)) mismatch = mismatch + 1;
        chk(mismatch == 0, "P1: header bytes mismatch");
        mismatch = 0;
        for (k = 0; k < PAY1; k = k + 1)
            if (mem1_byte(128+k) !== exp1_byte(k)) mismatch = mismatch + 1;
        chk(mismatch == 0, "P1: payload bytes mismatch");
        mismatch = 0;
        for (k = 128+PAY1; k < DMA1; k = k + 1)
            if (mem1_byte(k) !== 8'h00) mismatch = mismatch + 1;
        chk(mismatch == 0, "P1: tail bytes not zero");
        hc32 = CRC_INIT;
        for (k = 0; k < PAY1; k = k + 1) hc32 = crc32_b(hc32, mem1_byte(128+k));
        chk(~hc32 == 32'h97E69DE2, "P1: payload CRC != 0x97E69DE2 (TB recompute)");
        hc32 = CRC_INIT;
        for (k = 0; k < 128; k = k + 1)
            hc32 = crc32_b(hc32, ((k >= 8'h58) && (k <= 8'h5B)) ? 8'h00 : mem1_byte(k));
        chk(~hc32 == 32'h6E5C61EE, "P1: header CRC != 0x6E5C61EE (TB recompute)");
        fd = $fopen("t11_writer_small_content.bin", "wb");
        for (k = 0; k < DMA1; k = k + 1) $fwrite(fd, "%c", mem1_byte(k));
        $fclose(fd);
        $display("  P1 DBG beats=%0d bursts=%0d seq=%0d base=%06h status=%08h",
                 a_beats, a_bursts, a_seq, a_base[23:0], a_status);

        // ---- P2 好帧 #2（换块） ----
        $display("=== P2 好帧#2：换块 + 载荷逐字节 + seq=2 ===");
        for (k = 0; k < 128; k = k + 1) mem1[k] = 256'd0;
        a_frame(0);
        repeat (300) @(negedge clk_cam);
        a_wait_idle(200000);
        repeat (80) @(posedge clk_fb);
        chk(a_seq == 2, "P2: seq != 2");
        chk(a_base == BASE1_1, "P2: base != BASE1");
        mismatch = 0;
        for (k = 0; k < PAY1; k = k + 1)
            if (mem1_byte(128+k) !== exp1_byte(k)) begin
                if (mismatch < 4)
                    $display("  P2 PAYMIS k=%0d got=%02h exp=%02h", k, mem1_byte(128+k), exp1_byte(k));
                mismatch = mismatch + 1;
            end
        chk(mismatch == 0, "P2: payload bytes mismatch");
        if (mismatch != 0) begin
            $display("  P2 HDRDBG w4=%08h w5=%08h w20=%08h w21=%08h w22=%08h",
                     {mem1_byte(19),mem1_byte(18),mem1_byte(17),mem1_byte(16)},
                     {mem1_byte(23),mem1_byte(22),mem1_byte(21),mem1_byte(20)},
                     {mem1_byte(83),mem1_byte(82),mem1_byte(81),mem1_byte(80)},
                     {mem1_byte(87),mem1_byte(86),mem1_byte(85),mem1_byte(84)},
                     {mem1_byte(91),mem1_byte(90),mem1_byte(89),mem1_byte(88)});
        end
        chk(mem1_byte(8'h14) == 8'h02, "P2: capture_seq byte0 != 2");
        hc32 = CRC_INIT;
        for (k = 0; k < 128; k = k + 1)
            hc32 = crc32_b(hc32, ((k >= 8'h58) && (k <= 8'h5B)) ? 8'h00 : mem1_byte(k));
        chk(~hc32 == {mem1_byte(8'h5B), mem1_byte(8'h5A), mem1_byte(8'h59), mem1_byte(8'h58)},
            "P2: header CRC field != recompute");

        // ---- P3 abort ----
        $display("=== P3 坏帧：帧内 abort 不发布 ===");
        err_before = a_status[31:16];
        a_frame(1);
        repeat (300) @(negedge clk_cam);
        a_wait_idle(200000);
        repeat (80) @(posedge clk_fb);
        chk(a_seq == 2, "P3: abort frame published");
        chk(a_status[31:16] > err_before, "P3: err count did not rise");

        // ---- P4 无 good ----
        $display("=== P4 坏帧：FE 无 good 不发布 ===");
        err_before = a_status[31:16];
        a_frame(2);
        repeat (300) @(negedge clk_cam);
        a_wait_idle(200000);
        repeat (80) @(posedge clk_fb);
        chk(a_seq == 2, "P4: no-good frame published");
        chk(a_status[31:16] > err_before, "P4: err count did not rise");

        // ---- P5 短行 ----
        $display("=== P5 坏帧：短行不发布 ===");
        err_before = a_status[31:16];
        a_frame(3);
        repeat (300) @(negedge clk_cam);
        a_wait_idle(200000);
        repeat (80) @(posedge clk_fb);
        chk(a_seq == 2, "P5: short-line frame published");
        chk(a_status[31:16] > err_before, "P5: err count did not rise");

        // ---- P6 无 FE：TMO 兜底 ----
        $display("=== P6 无 FE：TMO 收口不发布 ===");
        err_before = a_status[31:16];
        a_frame(4);
        repeat (20000) @(posedge clk_ddr);
        a_wait_idle(2000000);
        repeat (80) @(posedge clk_fb);
        chk(a_seq == 2, "P6: no-FE fragment published");
        chk(a_status[31:16] > err_before, "P6: err count did not rise");
        @(negedge clk_cam); a_in_frame = 0;
        repeat (100) @(negedge clk_cam);

        // ---- P7 所有权 ----
        $display("=== P7 所有权：发布即锁块 / 跳过 / release ===");
        a_prot = 1;
        frames_before = a_seq;
        blk_par = u_wr.frame_idx[0];
        a_frame(0);
        repeat (300) @(negedge clk_cam);
        a_wait_idle(200000);
        repeat (80) @(posedge clk_fb);
        chk(a_seq == frames_before + 1, "P7a: frame after enable-prot did not publish");
        chk(a_base == (blk_par ? BASE1_1 : BASE0_1), "P7a: block base mismatch");
        a_frame(0);
        repeat (300) @(negedge clk_cam);
        a_wait_idle(200000);
        repeat (80) @(posedge clk_fb);
        chk(a_seq == frames_before + 2, "P7b: second frame did not publish");
        chk(a_base == (blk_par ? BASE0_1 : BASE1_1), "P7b: block base mismatch");
        err_before = a_status[31:16];
        a_beats = 0;
        a_frame(0);
        repeat (300) @(negedge clk_cam);
        a_wait_idle(200000);
        repeat (80) @(posedge clk_fb);
        chk(a_seq == frames_before + 2, "P7c: locked-block frame published");
        chk(a_beats == 0, "P7c: locked-block frame wrote DDR");
        chk(a_status[31:16] > err_before, "P7c: err count did not rise");
        // 释放两个块（P7a 锁的 = blk_par；P7b 锁的 = 另一块），下一帧（另一块）应可写
        @(negedge clk_ddr); a_rel0 = ~a_rel0; a_rel1 = ~a_rel1;
        repeat (60) @(posedge clk_ddr);
        a_frame(0);
        repeat (300) @(negedge clk_cam);
        a_wait_idle(200000);
        repeat (80) @(posedge clk_fb);
        chk(a_seq == frames_before + 3, "P7d: frame after release did not publish");
        chk(a_base == (blk_par ? BASE0_1 : BASE1_1), "P7d: expected released block");
        a_prot = 0;

        // ---- P8 复位隔离 ----
        $display("=== P8 复位隔离：残帧不发布，恢复后新帧发布 ===");
        @(negedge clk_cam); a_vsync = 1;
        @(negedge clk_cam); a_vsync = 0; a_in_frame = 1;
        @(negedge clk_cam); a_in_line = 1; @(negedge clk_cam); a_in_line = 0;
        @(negedge clk_cam); a_pix = 40'h0010004000; a_valid = 1;
        @(negedge clk_cam); a_valid = 0;
        repeat (40) @(negedge clk_cam);
        wr_rst = 1;
        repeat (60) @(negedge clk_cam);
        a_in_frame = 0;
        wr_rst = 0;
        repeat (600) @(negedge clk_cam);
        a_wait_idle(200000);
        repeat (100) @(posedge clk_fb);
        chk(a_seq == 0, "P8: fragment published after reset");
        a_frame(0);
        repeat (300) @(negedge clk_cam);
        a_wait_idle(200000);
        repeat (80) @(posedge clk_fb);
        chk(a_seq == 1, "P8: recovery frame did not publish (seq=1)");

        // ---- P9 FIFO 溢出（u_wr2） ----
        $display("=== P9 FIFO 溢出：停摆 AXI + 连发 ⇒ 不发布 ===");
        b_slave_stall = 1;
        frames_before = b_seq;
        err_before = b_status[31:16];
        b_frame();
        repeat (4000) @(negedge clk_cam);
        b_slave_stall = 0;
        repeat (500) @(negedge clk_cam);
        b_wait_idle(4000000);
        repeat (120) @(posedge clk_fb);
        chk(b_seq == frames_before, "P9: overflowed frame published");
        chk(b_status[31:16] > err_before, "P9: err count did not rise");
        repeat (400) @(posedge clk_fb);
        chk(b_anom == 1'b1, "P9: anomaly (drop/ovf) flag not set");
        $display("  P9 DBG1 s=%0d gcnt=%0d pbad=%0b eof=%0b bc=%0d payw=%0d drop=%0d status=%08h",
                 u_wr2.s_state, u_wr2.gcnt, u_wr2.p_bad, u_wr2.p_eof_seen, u_wr2.beat_cnt,
                 u_wr2.pay_written, u_wr2.drop_cnt, b_status);
        b_frame();
        repeat (400) @(negedge clk_cam);
        b_wait_idle(4000000);
        repeat (120) @(posedge clk_fb);
        chk(b_seq == frames_before + 1, "P9: recovery good frame did not publish");
        $display("  P9 DBG2 s=%0d gcnt=%0d pbad=%0b eof=%0b bc=%0d payw=%0d seq=%0d status=%08h",
                 u_wr2.s_state, u_wr2.gcnt, u_wr2.p_bad, u_wr2.p_eof_seen, u_wr2.beat_cnt,
                 u_wr2.pay_written, b_seq, b_status);

        // ---- P10 1080p 边界 ----
        $display("=== P10 1080p：81,024 拍 / 633+1 突发 / 尾零 / 头字段+CRC / 抽拍 ===");
        c_frame();
        t1 = 0;
        while ((u_wr3.s_state != 3'd0) && (t1 < 3000000)) begin @(posedge clk_fb); t1 = t1 + 1; end
        repeat (200) @(posedge clk_fb);
        chk(c_seq == 1, "P10: 1080p frame did not publish");
        chk(c_base == BASE0_3, "P10: base != BASE0");
        chk(c_len == DMA3, "P10: wr_len != 2592768");
        chk(c_beats == BEATS3 + 1, "P10: beat count != 81025");
        chk(c_bursts == 634, "P10: burst count != 634 (633 main + 1 rewrite)");
        chk(c_4k_err == 0, "P10: 4KiB burst rule violated");
        chk(c_addr_err == 0, "P10: address sequence mismatch");
        chk(c_strb_err == 0, "P10: rewrite strb != 0x0FFF0000");
        mismatch = 0;
        for (k = 0; k < 128; k = k + 1)
            if (c_hdr_byte(k) !== hdr3_byte(k)) begin
                if (mismatch < 6)
                    $display("  P10 HDRMIS k=%0d got=%02h exp=%02h", k, c_hdr_byte(k), hdr3_byte(k));
                mismatch = mismatch + 1;
            end
        chk(mismatch == 0, "P10: header bytes mismatch");
        mismatch = 0;
        for (k = 1000*32; k < 1000*32 + 32; k = k + 1)
            if (c_spot1[(k - 1000*32)*8 +: 8] !== exp3_byte(k-128)) mismatch = mismatch + 1;
        chk(mismatch == 0, "P10: spot beat #1000 payload mismatch");
        mismatch = 0;
        for (k = 50000*32; k < 50000*32 + 32; k = k + 1)
            if (c_spot2[(k - 50000*32)*8 +: 8] !== exp3_byte(k-128)) mismatch = mismatch + 1;
        chk(mismatch == 0, "P10: spot beat #50000 payload mismatch");
        mismatch = 0;
        for (k = 0; k < 20*32; k = k + 1)
            if (c_tail_cap[k/32][(k%32)*8 +: 8] !== 8'h00) mismatch = mismatch + 1;
        chk(mismatch == 0, "P10: tail 640B not zero");
        hc32 = CRC_INIT;
        for (k = 0; k < 128; k = k + 1)
            hc32 = crc32_b(hc32, ((k >= 8'h58) && (k <= 8'h5B)) ? 8'h00 : c_hdr_byte(k));
        chk(~hc32 == EXP_HDRCRC3, "P10: header CRC != EXP_HDRCRC3 (0x56BA381A, TB recompute)");
        chk(c_hdr_cap[2][191:160] == EXP_PAYCRC3, "P10: payload CRC field != 0xAC1B6FE1");
        $display("  P10 PAYDBG got %08h %08h %08h %08h", c_spot0[31:0], c_spot0[63:32],
                 c_spot0[95:64], c_spot0[127:96]);
        $display("  P10 PAYEXP exp %02h%02h%02h%02h %02h%02h%02h%02h %02h%02h%02h%02h %02h%02h%02h%02h",
                 exp3_byte(3), exp3_byte(2), exp3_byte(1), exp3_byte(0),
                 exp3_byte(7), exp3_byte(6), exp3_byte(5), exp3_byte(4),
                 exp3_byte(11), exp3_byte(10), exp3_byte(9), exp3_byte(8),
                 exp3_byte(15), exp3_byte(14), exp3_byte(13), exp3_byte(12));
        $display("  P10 DBG beats=%0d bursts=%0d seq=%0d base=%06h", c_beats, c_bursts, c_seq, c_base[23:0]);
        fd = $fopen("t11_writer_1080p_header.bin", "wb");
        for (k = 0; k < 128; k = k + 1) $fwrite(fd, "%c", c_hdr_byte(k));
        $fclose(fd);
        fd = $fopen("t11_writer_1080p_tail.bin", "wb");
        for (k = 0; k < 640; k = k + 1) $fwrite(fd, "%c", c_tail_cap[k/32][(k%32)*8 +: 8]);
        $fclose(fd);

        // ---- 汇总 ----
        repeat (100) @(posedge clk_fb);
        if (errors == 0) $display("ALL PASS");
        else             $display("FAIL: %0d errors", errors);
        $finish;
    end

    initial begin
        #120_000_000;
        $display("FAIL: watchdog timeout");
        $finish;
    end

endmodule
