// 临时调试台（不属于交付 freeze 清单；仅定位 cam_r10f_writer 的流控问题）
`timescale 1ns/1ps
module tb_t11_dbg1;
    reg clk_cam = 0, clk_fb = 0, clk_ddr = 0;
    always #3  clk_cam = ~clk_cam;
    always #8  clk_fb  = ~clk_fb;
    always #5  clk_ddr = ~clk_ddr;
    reg rst_cam_n = 0, wr_rst = 1;
    reg a_vsync=0, a_in_frame=0, a_in_line=0, a_valid=0, a_good=0, a_abort=0;
    reg [39:0] a_pix=0;
    wire [31:0] a_seq, a_base, a_status, a_len;
    wire a_awvalid, a_awready, a_wvalid, a_wready, a_bvalid, a_bready, a_wlast;
    wire [28:0] a_awaddr; wire [7:0] a_awlen; wire [2:0] a_awsize; wire [1:0] a_awburst;
    wire [255:0] a_wdata; wire [31:0] a_wstrb; wire [1:0] a_bresp;
    assign a_awready = 1'b1; assign a_wready = 1'b1; assign a_bresp = 2'b00;
    assign a_bvalid = 1'b1;  assign a_bready = 1'b1;

    cam_r10f_writer #(
        .W(8), .H(4), .X0(16'd0), .Y0(16'd0), .SKIP_ROWS(16'd0),
        .BASE0(32'h0010_0000), .BASE1(32'h0090_0000), .FIFO_AW(10), .BURST_BEATS(128),
        .CAMERA_ID(8'd0), .SRC_BAYER_PHASE(2'd3), .MODE_ID(32'd1), .TMO_LIMIT(21'd4095)
    ) u_wr (
        .cam_clk(clk_cam), .cam_rst_n(rst_cam_n),
        .cam_vsync(a_vsync), .cam_in_frame(a_in_frame), .cam_in_line(a_in_line),
        .cam_pix(a_pix), .cam_pix_valid(a_valid),
        .cam_frame_good(a_good), .cam_frame_abort(a_abort),
        .prot_en(1'b0), .rel_tgl0(1'b0), .rel_tgl1(1'b0),
        .clk_fb(clk_fb), .rst_fb(wr_rst), .session_id(32'h2026_1017),
        .wr_frame_seq(a_seq), .wr_base(a_base), .wr_status(a_status), .wr_len(a_len),
        .dbg_lines_per_frame(), .dbg_max_grp_per_line(), .dbg_anomaly(), .dbg_drop(),
        .clk_ddr(clk_ddr), .rst_ddr(wr_rst), .ddr_cal_done(1'b1), .arm(1'b1),
        .axi_busy(),
        .m_axi_awaddr(a_awaddr), .m_axi_awlen(a_awlen), .m_axi_awsize(a_awsize),
        .m_axi_awburst(a_awburst), .m_axi_awvalid(a_awvalid), .m_axi_awready(a_awready),
        .m_axi_wdata(a_wdata), .m_axi_wstrb(a_wstrb), .m_axi_wlast(a_wlast),
        .m_axi_wvalid(a_wvalid), .m_axi_wready(a_wready),
        .m_axi_bresp(a_bresp), .m_axi_bvalid(a_bvalid), .m_axi_bready(a_bready)
    );

    // 状态变化打印
    reg [2:0] prev_s = 3'd7;
    always @(posedge clk_ddr)
        if (u_wr.s_state !== prev_s) begin
            prev_s <= u_wr.s_state;
            $display("S=%0d @%0t cpos=%0d bcnt=%0d apos=%0d hcnt=%0d payw=%0d ep=%0d gcnt=%0d beatt=%0d hdrdone=%0b rwdone=%0b ast=%0d",
                     u_wr.s_state, $time, u_wr.cpos, u_wr.bcnt, u_wr.apos, u_wr.hcnt,
                     u_wr.pay_written, u_wr.pay_ep, u_wr.gcnt, u_wr.beat_cnt,
                     u_wr.hdr_done_r, u_wr.rw_done_r, u_wr.a_st);
        end

    integer fd, k;
    reg [7:0] hb;
    initial begin
        rst_cam_n = 0; #100; rst_cam_n = 1; #400; wr_rst = 0; #200;
        repeat (20) @(negedge clk_cam);
        // 一帧 8×4
        @(negedge clk_cam); a_vsync = 1;
        @(negedge clk_cam); a_vsync = 0; a_in_frame = 1;
        for (k = 0; k < 4; k = k + 1) begin
            @(negedge clk_cam); a_in_line = 1;
            @(negedge clk_cam); a_in_line = 0;
            @(negedge clk_cam); a_pix = 40'h0000_0000; a_valid = 1;
            @(negedge clk_cam); a_valid = 0;
            @(negedge clk_cam); a_pix = 40'h0FF3_FFFC; a_valid = 1;
            @(negedge clk_cam); a_valid = 0;
        end
        @(negedge clk_cam); a_good = 1;
        @(negedge clk_cam); a_in_frame = 0;
        @(negedge clk_cam); a_good = 0;
        repeat (5000) @(posedge clk_ddr);
        $display("FINAL s=%0d cpos=%0d bcnt=%0d apos=%0d beatt=%0d hdr=%0b rw=%0b ast=%0d seq=%0d",
                 u_wr.s_state, u_wr.cpos, u_wr.bcnt, u_wr.apos, u_wr.beat_cnt,
                 u_wr.hdr_done_r, u_wr.rw_done_r, u_wr.a_st, a_seq);
        $finish;
    end
endmodule
