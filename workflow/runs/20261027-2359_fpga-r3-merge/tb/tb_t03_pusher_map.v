`timescale 1ns/1ps
// =============================================================================
// tb_t03_pusher_map.v -- T03 70 B oracle through slot store + ddr_frame_pusher
//
// Purpose (r3, task A/B):
//   * PRODUCED_LEN=70, BYTE_DIFF=0, FIRST8=78 9c ... on the store read-back
//     (the frozen T03 oracle) with the RTL under test;
//   * drive the same stored 70 B through ddr_frame_pusher and decode the TLP
//     payload with the *project's documented* host model
//     (lane 7 -> lane 0, MSB first inside each DW: the push_beat() used by
//      sim_do/tb_ddr_frame_pusher.v, sim/tb/tb_ddr_frame_pusher_rka1.v and
//      sim/tb/tb_t11_r10f_e2e.v);
//   * evaluate three candidate data-beat mappings from the SAME captured beats
//     so no mapping is guessed:
//        MAP_A = RTL as-is (bswap256)
//        MAP_B = what "remove bswap256" would produce
//        MAP_C = what "reverse only the 32-bit DW order" would produce
//     Only MAP_A/B/C are compared; the RTL is not modified by this TB.
//   * address check: store AW word must be 2048 (byte 0x10000), pusher AR must
//     be 0x10000, and 0x40000 must never appear.
//
// Outputs (CWD):
//   t03_store_read.bin   store read-back bytes (first 70)
//   t03_host_A.bin       pusher payload, MAP_A decode (first 70)
//   t03_host_B.bin       pusher payload, MAP_B decode (first 70)
//   t03_host_C.bin       pusher payload, MAP_C decode (first 70)
//   t03_map.txt          machine-readable summary for the Python verifier
// =============================================================================
module tb_t03_pusher_map;

    localparam integer N_BYTES   = 70;
    localparam integer FRAME     = 4096;
    localparam [31:0]  SLOT_WORD = 32'd2048;
    localparam [31:0]  SLOT_BYTE = 32'h0001_0000;

    reg clk_ddr = 0;
    reg clk_fb  = 0;
    always #5 clk_ddr = ~clk_ddr;   // 100 MHz
    always #8 clk_fb  = ~clk_fb;    // 62.5 MHz

    reg rst_ddr = 1, rst_fb = 1;
    initial begin
        repeat (8) @(posedge clk_ddr);
        rst_ddr <= 0;
        repeat (8) @(posedge clk_fb);
        rst_fb <= 0;
    end

    // ------------------------------------------------------------------
    // DDR model (256-bit words).  The store addresses words, the pusher
    // addresses bytes; both resolve to mem[byte_addr >> 5].
    // ------------------------------------------------------------------
    reg [255:0] mem [0:16383];
    integer mi;
    initial for (mi = 0; mi < 16384; mi = mi + 1) mem[mi] = 256'd0;

    // ---------------- store side ----------------
    reg         wr_begin = 0, wr_valid = 0, wr_last = 0;
    reg  [39:0] wr_data = 0;
    reg  [3:0]  wr_keep = 0;
    reg         rd_open = 0, rd_close = 0;
    wire        wr_begin_ready, wr_ready, rd_open_ready, rd_valid;
    wire [31:0] rd_id, rd_len, s_awaddr, s_araddr, s_pubs, s_errs, s_reads;
    wire        s_awvalid, s_wvalid, s_arvalid, s_rready;
    wire [255:0] s_wdata, s_rdata;
    reg  [255:0] s_rdata_r = 0;
    reg         s_rvalid = 0;
    reg  [31:0] s_awaddr_first = 32'hFFFF_FFFF;
    reg         s_aw_seen = 0;

    assign s_rdata  = s_rdata_r;

    a1_ddr_slot_store #(.MODE(1), .SLOT_WORDS(128), .BASE_WORD(SLOT_WORD), .AWB(8)) store (
        .clk(clk_fb), .rst_n(~rst_fb), .ddr_ready(1'b1),
        .wr_begin(wr_begin), .wr_begin_ready(wr_begin_ready),
        .wr_id(32'd123), .wr_data(wr_data), .wr_keep(wr_keep),
        .wr_valid(wr_valid), .wr_last(wr_last), .wr_ready(wr_ready),
        .wr_abort(1'b0),
        .rd_open(rd_open), .rd_open_ready(rd_open_ready),
        .rd_id(rd_id), .rd_len_bytes(rd_len), .rd_close(rd_close),
        .rd_data(), .rd_valid(rd_valid), .rd_take(1'b1),
        .ddr_awaddr(s_awaddr), .ddr_awvalid(s_awvalid), .ddr_awready(1'b1),
        .ddr_wdata(s_wdata), .ddr_wvalid(s_wvalid), .ddr_wready(1'b1),
        .ddr_araddr(s_araddr), .ddr_arvalid(s_arvalid), .ddr_arready(1'b1),
        .ddr_rdata(s_rdata), .ddr_rvalid(s_rvalid), .ddr_rready(s_rready),
        .st_published(s_pubs), .st_dropped(), .st_errors(s_errs), .st_last_bytes(),
        .st_read_words(s_reads), .st_dup_words()
    );

    // store write into the shared memory (word address)
    always @(posedge clk_fb)
        if (s_awvalid && s_wvalid) begin
            mem[s_awaddr[13:0]] <= s_wdata;
            if (!s_aw_seen) begin
                s_aw_seen     <= 1'b1;
                s_awaddr_first<= s_awaddr;
            end
        end

    // store read responder
    always @(posedge clk_fb) begin
        s_rvalid <= 1'b0;
        if (s_arvalid) begin
            s_rdata_r <= mem[s_araddr[13:0]];
            s_rvalid  <= 1'b1;
        end
    end

    always @(posedge clk_fb)
        if (rd_open)
            $display("T03_DBG rd_open sampled state=%0d ready=%b rst_n=%b arvalid=%b",
                     store.rd_state, rd_open_ready, ~rst_fb, s_arvalid);

    // store read-back capture
    reg  [7:0] store_bytes [0:255];
    integer    store_n = 0;
    integer    k;
    always @(posedge clk_fb)
        if (!rst_fb && rd_valid) begin
            for (k = 0; k < 32; k = k + 1) begin
                if (store_n < 256) store_bytes[store_n] = store.rd_data[k*8 +: 8];
                store_n = store_n + 1;
            end
        end

    // ------------------------------------------------------------------
    // pusher side
    // ------------------------------------------------------------------
    reg         push_en = 1;
    reg  [31:0] dst_lo = 32'h0010_0000, dst_hi = 32'd0;
    reg  [31:0] db_lo  = 32'h0080_0000, db_hi  = 32'd0;
    reg  [31:0] frame_bytes = FRAME;
    reg  [31:0] ddr_seq = 0, ddr_base = SLOT_BYTE, ddr_status = 0;
    reg         arm_pulse = 0, ack_pulse = 0, cancel_pulse = 0;
    reg  [31:0] cap_bytes = 32'h0010_0000, session_id = 32'd7;
    reg  [31:0] ack_seq_w = 0, ack_session_w = 0;
    reg         link_up = 1;
    reg  [2:0]  mps_code = 3'd0;
    reg  [31:0] ddr_cap_bytes = 32'h1000_0000;
    reg         cam_sel_live = 0;
    reg         utx_sel = 1;
    reg         tl_tx_wait = 0;

    wire [31:0] p_done, p_status, p_tlp;
    wire [7:0]  p_err;
    wire        p_block_cfg, p_src_act, p_fb_hold, p_src_lock;
    wire        p_rel0, p_rel1, p_rel2, p_rel3;
    wire        utx_req, utx_sop, utx_eop;
    wire [255:0] utx_data;
    wire [7:0]  utx_valid;

    wire        p_arvalid, p_arready, p_rvalid, p_rlast, p_rready;
    wire [28:0] p_araddr;
    wire [7:0]  p_arlen;
    wire [2:0]  p_arsize;
    wire [1:0]  p_arburst;
    wire [3:0]  p_arid, p_rid;
    wire [255:0] p_rdata;
    wire [1:0]  p_rresp;

    reg  [28:0] pr_addr = 0;
    reg  [7:0]  pr_left = 0;
    reg  [28:0] ar_first = 29'h1FFF_FFFF;
    reg         ar_seen = 0;
    reg         saw_40000 = 0;

    assign p_arready = (pr_left == 8'd0);
    assign p_rvalid  = (pr_left != 8'd0);
    assign p_rdata   = mem[pr_addr[17:5]];
    assign p_rlast   = (pr_left == 8'd1);

    always @(posedge clk_ddr) begin
        if (rst_ddr) begin
            pr_addr <= 0; pr_left <= 0;
        end else if (p_arvalid && p_arready) begin
            pr_addr <= p_araddr;
            pr_left <= p_arlen + 8'd1;
            if (!ar_seen) begin
                ar_seen  <= 1'b1;
                ar_first <= p_araddr;
            end
            if (p_araddr == 29'h0004_0000) saw_40000 <= 1'b1;
        end else if (p_rvalid && p_rready) begin
            pr_addr <= pr_addr + 29'd32;
            pr_left <= pr_left - 8'd1;
        end
    end

    ddr_frame_pusher #(
        .W(64), .H(64), .PAY_DW(32), .MAX_FRAME_BYTES(3840*2160),
        .FIFO_AW(7), .BURST_BEATS(128), .WAIT_LIMIT(16'hFFFF),
        .BASE0(SLOT_BYTE), .BASE1(SLOT_BYTE + 32'd4096),
        .BASE0B(SLOT_BYTE), .BASE1B(SLOT_BYTE + 32'd4096)
    ) pusher (
        .clk_fb(clk_fb), .rst_fb(rst_fb),
        .push_en(push_en),
        .dst_lo(dst_lo), .dst_hi(dst_hi), .db_lo(db_lo), .db_hi(db_hi),
        .st_done(p_done), .st_status(p_status), .st_err(p_err), .st_tlp_cnt(p_tlp),
        .frame_bytes(frame_bytes),
        .ddr_seq(ddr_seq), .ddr_base(ddr_base), .ddr_status(ddr_status),
        .src_sel(1'b0), .fb_frame_cnt(32'd0),
        .fb_rd_addr(), .fb_rd_data(32'd0), .fb_req(), .fb_grant(1'b1),
        .src_act(p_src_act), .fb_hold(p_fb_hold),
        .utx_sel(utx_sel), .tl_tx_wait(tl_tx_wait),
        .utx_req(utx_req), .utx_data(utx_data), .utx_sop(utx_sop),
        .utx_eop(utx_eop), .utx_valid(utx_valid),
        .arm_pulse(arm_pulse), .ack_pulse(ack_pulse), .cancel_pulse(cancel_pulse),
        .cap_bytes(cap_bytes), .session_id(session_id),
        .ack_seq_w(ack_seq_w), .ack_session_w(ack_session_w),
        .cfg_reject(1'b0), .link_up(link_up), .mps_code(mps_code),
        .ddr_cap_bytes(ddr_cap_bytes), .cam_sel_live(cam_sel_live),
        .tx_status(), .tx_block_cfg(p_block_cfg),
        .rel_tgl0(p_rel0), .rel_tgl1(p_rel1), .rel_tgl2(p_rel2), .rel_tgl3(p_rel3),
        .tx_src_lock(p_src_lock),
        .clk_ddr(clk_ddr), .rst_ddr(rst_ddr),
        .m_axi_arid(p_arid), .m_axi_araddr(p_araddr), .m_axi_arlen(p_arlen),
        .m_axi_arsize(p_arsize), .m_axi_arburst(p_arburst),
        .m_axi_arvalid(p_arvalid), .m_axi_arready(p_arready),
        .m_axi_rid(p_rid), .m_axi_rdata(p_rdata), .m_axi_rresp(p_rresp),
        .m_axi_rlast(p_rlast), .m_axi_rvalid(p_rvalid), .m_axi_rready(p_rready)
    );

    // capture accepted TL beats (raw, no interpretation)
    reg [255:0] beats [0:511];
    reg [7:0]   bvalid [0:511];
    integer     nbeats = 0;
    always @(posedge clk_fb)
        if (!rst_fb && utx_sel && !tl_tx_wait && (|utx_valid)) begin
            if (nbeats < 512) begin
                beats[nbeats]  = utx_data;
                bvalid[nbeats] = utx_valid;
                nbeats = nbeats + 1;
            end
        end

    // ------------------------------------------------------------------
    // mapping helpers
    // ------------------------------------------------------------------
    function [255:0] bswap256;
        input [255:0] x;
        begin
            bswap256 = {x[7:0],   x[15:8],  x[23:16], x[31:24],
                        x[39:32], x[47:40], x[55:48], x[63:56],
                        x[71:64], x[79:72], x[87:80], x[95:88],
                        x[103:96],x[111:104],x[119:112],x[127:120],
                        x[135:128],x[143:136],x[151:144],x[159:152],
                        x[167:160],x[175:168],x[183:176],x[191:184],
                        x[199:192],x[207:200],x[215:208],x[223:216],
                        x[231:224],x[239:232],x[247:240],x[255:248]};
        end
    endfunction

    function [255:0] dwrev256;   // reverse the 32-bit DW order, keep bytes in DW
        input [255:0] x;
        begin
            dwrev256 = {x[31:0],   x[63:32],  x[95:64],   x[127:96],
                        x[159:128],x[191:160],x[223:192], x[255:224]};
        end
    endfunction

    // documented host model: lane 7 first, MSB first inside the DW
    function [7:0] dec_byte;
        input [255:0] x;
        input integer p;          // 0..31 inside the beat
        integer lane, off;
        begin
            lane = 7 - (p / 4);
            off  = 3 - (p % 4);
            dec_byte = x[32*lane + 8*off +: 8];
        end
    endfunction

    reg [7:0] hostA [0:4095];
    reg [7:0] hostB [0:4095];
    reg [7:0] hostC [0:4095];

    integer bi, d, pp, hostn;
    reg [255:0] xf;
    initial begin
        for (bi = 0; bi < 4096; bi = bi + 1) begin
            hostA[bi] = 8'h00; hostB[bi] = 8'h00; hostC[bi] = 8'h00;
        end
    end

    // ------------------------------------------------------------------
    // files / summary
    // ------------------------------------------------------------------
    integer fA, fB, fC, fS, fM;
    integer errors = 0;
    reg [31:0] rd_len_snap = 32'd0;
    reg [7:0] stim [0:N_BYTES-1];

    task write70;
        input integer fd;
        input integer which;
        integer q;
        begin
            for (q = 0; q < N_BYTES; q = q + 1)
                if (which == 0)      $fwrite(fd, "%c", hostA[q]);
                else if (which == 1) $fwrite(fd, "%c", hostB[q]);
                else                 $fwrite(fd, "%c", hostC[q]);
        end
    endtask

    initial begin
        $readmemh("t03_stream.mem", stim);
        fA = $fopen("t03_host_A.bin", "wb");
        fB = $fopen("t03_host_B.bin", "wb");
        fC = $fopen("t03_host_C.bin", "wb");
        fS = $fopen("t03_store_read.bin", "wb");
        fM = $fopen("t03_map.txt", "w");
    end

    // ------------------------------------------------------------------
    // stimulus
    // ------------------------------------------------------------------
    integer i, j;
    integer wguard;
    initial begin
        wait (rst_ddr === 1'b0 && rst_fb === 1'b0);
        repeat (10) @(posedge clk_fb);
        $display("T03_DBG reset released rst_ddr=%b rst_fb=%b begin_ready=%b wr_active=%b slot0=%0d slot1=%0d",
                 rst_ddr, rst_fb, wr_begin_ready, store.wr_active, store.slot_st[0], store.slot_st[1]);

        // ---- store the frozen T03 70 B stream ----
        @(negedge clk_fb); wr_begin = 1;
        $display("T03_DBG begin pulse begin_ready=%b", wr_begin_ready);
        @(negedge clk_fb); wr_begin = 0;
        for (i = 0; i < N_BYTES; i = i + 4) begin
            wr_data = 0; wr_keep = 0;
            for (j = 0; j < 4; j = j + 1)
                if (i + j < N_BYTES) begin
                    wr_data[j*8 +: 8] = stim[i+j];
                    wr_keep[j] = 1'b1;
                end
            wr_last  = (i + 4 >= N_BYTES);
            wr_valid = 1'b1;
            @(posedge clk_fb);
            wguard = 0;
            while (!wr_ready && (wguard < 10000)) begin
                @(posedge clk_fb); wguard = wguard + 1;
            end
            if (i < 8)
                $display("T03_DBG wr i=%0d ready=%b guard=%0d active=%b awaddr=%0d",
                         i, wr_ready, wguard, store.wr_active, s_awaddr);
            @(negedge clk_fb);
        end
        wr_valid = 0; wr_last = 0;
        repeat (4) @(posedge clk_fb);
        $display("T03_DBG after write published=%0d errors=%0d rd_len=%0d aw_first=%0d",
                 s_pubs, s_errs, rd_len, s_awaddr_first);
        rd_len_snap = rd_len;

        // ---- store read-back (T03 oracle part 1) ----
        wguard = 0;
        while (!rd_open_ready && (wguard < 200000)) begin
            @(posedge clk_fb); wguard = wguard + 1;
        end
        $display("T03_DBG rd_open_ready=%b guard=%0d slot0=%0d slot1=%0d",
                 rd_open_ready, wguard, store.slot_st[0], store.slot_st[1]);
        @(negedge clk_fb); rd_open = 1;
        @(negedge clk_fb); rd_open = 0;
        $display("T03_DBG rd_open issued");
        wguard = 0;
        while ((store_n < N_BYTES) && (wguard < 200000)) begin
            @(posedge clk_fb); wguard = wguard + 1;
        end
        $display("T03_DBG readback store_n=%0d guard=%0d rd_state=%0d", store_n, wguard, store.rd_state);
        @(negedge clk_fb); rd_close = 1; @(negedge clk_fb); rd_close = 0;

        $display("T03_STORE published=%0d errors=%0d rd_len=%0d aw_word=%0d aw_byte=%h",
                 s_pubs, s_errs, rd_len_snap, s_awaddr_first, s_awaddr_first * 32);

        // ---- pusher one-shot ----
        // ddr_frame_pusher latches last_seq := ddr_seq at ARM, so the frame
        // event must be a *new* sequence after the ARM (the board sequencer
        // does exactly this: ARM at seq N, event at seq N+1).
        ddr_seq    = 32'd0;
        ddr_status = 32'd1;
        @(negedge clk_fb); arm_pulse = 1;
        @(negedge clk_fb); arm_pulse = 0;
        repeat (4) @(negedge clk_fb);
        ddr_seq = 32'd1;
        $display("T03_DBG pusher armed, seq event issued");

        wguard = 0;
        while ((p_done != 32'd1) && (wguard < 200000)) begin
            @(posedge clk_fb); wguard = wguard + 1;
        end
        $display("T03_DBG pusher wait done=%0d guard=%0d g_st=%0d p_st=%0d ar_hs=%b",
                 p_done, wguard, pusher.g_st, pusher.p_st, ar_seen);
        repeat (20) @(posedge clk_fb);
        $display("T03_PUSH done=%0d tlp=%0d err=%0d status=%h beats=%0d ar_first=%h",
                 p_done, p_tlp, p_err, p_status, nbeats, ar_first);

        // ---- decode the payload with the three candidate mappings ----
        d = 0; hostn = 0;
        for (bi = 0; bi < nbeats; bi = bi + 1) begin
            if (bvalid[bi] == 8'hFF) begin
                for (pp = 0; pp < 32; pp = pp + 1) begin
                    hostA[d*32 + pp] = dec_byte(beats[bi], pp);
                    hostB[d*32 + pp] = dec_byte(bswap256(beats[bi]), pp);
                    hostC[d*32 + pp] = dec_byte(dwrev256(beats[bi]), pp);
                end
                d = d + 1;
            end
        end
        hostn = d * 32;
        $display("T03_DECODE data_beats=%0d payload_bytes=%0d", d, hostn);

        for (i = 0; i < N_BYTES; i = i + 1) $fwrite(fS, "%c", store_bytes[i]);
        write70(fA, 0); write70(fB, 1); write70(fC, 2);

        $fdisplay(fM, "store_aw_word=%0d", s_awaddr_first);
        $fdisplay(fM, "store_aw_byte=%h", s_awaddr_first * 32);
        $fdisplay(fM, "push_ar_first=%h", ar_first);
        $fdisplay(fM, "saw_40000=%0d", saw_40000);
        $fdisplay(fM, "tlp=%0d", p_tlp);
        $fdisplay(fM, "done=%0d", p_done);
        $fdisplay(fM, "err=%0d", p_err);
        $fdisplay(fM, "data_beats=%0d", d);

        if (s_pubs != 1 || s_errs != 0 || rd_len_snap != N_BYTES) errors = errors + 1;
        if (p_done != 1 || p_tlp != 32 || p_err != 0) errors = errors + 1;
        if (s_awaddr_first * 32 != SLOT_BYTE) errors = errors + 1;
        if (ar_first != SLOT_BYTE[28:0]) errors = errors + 1;
        if (saw_40000 != 0) errors = errors + 1;

        $display("T03_TB_ERRORS=%0d", errors);
        $fclose(fA); $fclose(fB); $fclose(fC); $fclose(fS); $fclose(fM);
        $finish;
    end

    initial begin
        #20_000_000;
        $display("T03_TB FAIL watchdog nbeats=%0d tlp=%0d done=%0d", nbeats, p_tlp, p_done);
        $finish;
    end

endmodule
