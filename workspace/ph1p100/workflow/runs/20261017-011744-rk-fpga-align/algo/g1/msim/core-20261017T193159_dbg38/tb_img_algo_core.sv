`timescale 1ns/1ps
// tb_img_algo_core.sv — T09.rk-align-algo G1 core testbench (vector driven).
// This is a testbench, not production RTL.  Expected streams come from the
// independent Python oracle (tools/algo/oracle_algo.py, cross-checked against
// parallel/algorithms/image_algorithms_ref.py); no DUT internals are used.
//
// Checks: per-beat data + sof/eol/eof for the three branches in order, abort
// markers for aborted frames (outputs before the marker must be a prefix of the
// frame's expected sequence), stall hold stability, frame counters, three-way
// concurrent production coverage, and a dump of the final published HE LUT
// (compared by the runner against the oracle's final LUT).
// Marker: ALGO_CORE_PASS / ALGO_CORE_FAIL.
module tb_img_algo_core;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;

    reg         cfg_valid = 0;
    reg  [11:0] cfg_width = 0, cfg_height = 0;
    reg  [1:0]  cfg_phase = 0;
    wire        cfg_ready, cfg_error;

    reg         s_valid = 0;
    wire        s_ready;
    reg  [39:0] s_data = 0;
    reg         s_sof = 0, s_eol = 0, s_eof = 0, s_abort = 0;

    wire        y8_valid, gau_valid, he_valid;
    reg         y8_ready = 1, gau_ready = 1, he_ready = 1;
    wire [31:0] y8_data, gau_data, he_data;
    wire        y8_sof, y8_eol, y8_eof, y8_abort;
    wire        gau_sof, gau_eol, gau_eof, gau_abort;
    wire        he_sof, he_eol, he_eof, he_abort;
    wire [15:0] st_good, st_abort, st_he_pub, st_he_rej, st_gau_ab;
    reg  [7:0]  he_lut_addr = 0;
    wire [7:0]  he_lut_data;

    img_algo_parallel_top #(.MAX_WORDS(512)) dut (
        .clk(clk), .rst_n(rst_n),
        .cfg_valid(cfg_valid), .cfg_ready(cfg_ready),
        .cfg_width(cfg_width), .cfg_height(cfg_height), .cfg_phase(cfg_phase),
        .cfg_error(cfg_error),
        .s_valid(s_valid), .s_ready(s_ready), .s_data(s_data),
        .s_sof(s_sof), .s_eol(s_eol), .s_eof(s_eof), .s_abort(s_abort),
        .y8_valid(y8_valid), .y8_ready(y8_ready), .y8_data(y8_data),
        .y8_sof(y8_sof), .y8_eol(y8_eol), .y8_eof(y8_eof), .y8_abort(y8_abort),
        .gau_valid(gau_valid), .gau_ready(gau_ready), .gau_data(gau_data),
        .gau_sof(gau_sof), .gau_eol(gau_eol), .gau_eof(gau_eof), .gau_abort(gau_abort),
        .he_valid(he_valid), .he_ready(he_ready), .he_data(he_data),
        .he_sof(he_sof), .he_eol(he_eol), .he_eof(he_eof), .he_abort(he_abort),
        .st_frames_good(st_good), .st_frames_abort(st_abort),
        .st_he_published(st_he_pub), .st_he_rejected(st_he_rej),
        .st_gau_abort(st_gau_ab),
        .he_lut_addr(he_lut_addr), .he_lut_data(he_lut_data)
    );

    // ------------------------------------------------------------------
    // vector storage (pre-parsed before driving)
    // ------------------------------------------------------------------
    reg [39:0] in_data [0:8191];
    integer    in_sb   [0:8191];   // {abort, eof, eol, sof}
    integer    in_pre  [0:8191];   // 0 none, 1 gap, 2 stall
    integer    in_arg1 [0:8191];
    integer    in_arg2 [0:8191];
    integer    n_in = 0;

    integer sc_kind  [0:255];
    integer sc_abort [0:255];
    integer sc_start [0:255];
    integer sc_nbeats[0:255];
    integer sc_reset [0:255];
    integer sc_cfgw  [0:255];
    integer sc_cfgh  [0:255];
    integer sc_cfgp  [0:255];
    integer n_scen = 0;

    reg [31:0] exp_data [0:2][0:8191];
    integer    exp_sb   [0:2][0:8191];
    integer    exp_fill [0:2];
    integer    seg_mode [0:2][0:511];
    integer    seg_start[0:2][0:511];
    integer    seg_cnt  [0:2][0:511];
    integer    n_seg_b  [0:2];

    integer    tot_good_exp = 0, tot_abort_exp = 0, tot_pub_exp = 0;
    integer    tot_rej_exp = 0, tot_gauab_exp = 0;

    // ------------------------------------------------------------------
    // checker state
    // ------------------------------------------------------------------
    integer chk_seg [0:2];
    integer chk_ptr [0:2];
    integer out_beats[0:2];
    integer markers [0:2];
    integer errs = 0;
    integer errs_seen = 0;
    integer cycles = 0;
    integer cyc_all3 = 0, cyc_ge2 = 0;
    integer hold_checked = 0;
    integer gap_cycles = 0, stall_cycles = 0;

    reg [31:0] held_data [0:2];
    integer    held_sb   [0:2];
    reg        held      [0:2];

    integer stall_y8 = 0, stall_gau = 0, stall_he = 0;
    always @(posedge clk) begin
        if (stall_y8  > 0) stall_y8  <= stall_y8  - 1;
        if (stall_gau > 0) stall_gau <= stall_gau - 1;
        if (stall_he  > 0) stall_he  <= stall_he  - 1;
    end
    always @* begin
        y8_ready  = (stall_y8  == 0);
        gau_ready = (stall_gau == 0);
        he_ready  = (stall_he  == 0);
    end

    task fail(input string msg);
        begin
            errs = errs + 1;
            if (errs_seen < 40) begin
                $display("ALGO_CORE_MISMATCH cycle=%0d %s", cycles, msg);
                errs_seen = errs_seen + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // output checker (negedge = stable post-posedge state)
    // ------------------------------------------------------------------
    integer b, s, p;
    reg [31:0] cdata [0:2];
    integer    csb   [0:2];
    reg        cvalid[0:2];
    reg        cready[0:2];
    reg        cabort[0:2];

    always @(negedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            cdata[0] = y8_data;  csb[0] = {y8_eof,y8_eol,y8_sof}; cvalid[0] = y8_valid;
            cready[0] = y8_ready; cabort[0] = y8_abort;
            cdata[1] = gau_data; csb[1] = {gau_eof,gau_eol,gau_sof}; cvalid[1] = gau_valid;
            cready[1] = gau_ready; cabort[1] = gau_abort;
            cdata[2] = he_data;  csb[2] = {he_eof,he_eol,he_sof}; cvalid[2] = he_valid;
            cready[2] = he_ready; cabort[2] = he_abort;

            if (cvalid[0] && cvalid[1] && cvalid[2]) cyc_all3 = cyc_all3 + 1;
            else if (((cvalid[0]?1:0)+(cvalid[1]?1:0)+(cvalid[2]?1:0)) >= 2) cyc_ge2 = cyc_ge2 + 1;

            for (b = 0; b < 3; b = b + 1) begin
                if (cabort[b]) begin
                    if (cvalid[b]) fail($sformatf("branch %0d marker with valid", b));
                    if (chk_seg[b] >= n_seg_b[b]) fail($sformatf("branch %0d unexpected marker", b));
                    else if (seg_mode[b][chk_seg[b]] != 1) fail($sformatf("branch %0d marker during exact seg", b));
                    else begin
                        chk_seg[b] = chk_seg[b] + 1;
                        chk_ptr[b] = 0;
                        markers[b] = markers[b] + 1;
                    end
                end
                if (cvalid[b]) begin
                    if (!cready[b]) begin
                        if (held[b] && ((cdata[b] !== held_data[b]) || (csb[b] !== held_sb[b])))
                            fail($sformatf("branch %0d output changed while stalled", b));
                        held[b] = 1'b1; held_data[b] = cdata[b]; held_sb[b] = csb[b];
                        hold_checked = hold_checked + 1;
                    end else begin
                        held[b] = 1'b0;
                        if (chk_seg[b] >= n_seg_b[b]) begin
                            fail($sformatf("branch %0d extra beat data=%08x", b, cdata[b]));
                        end else begin
                            s = chk_seg[b];
                            if (chk_ptr[b] >= seg_cnt[b][s]) begin
                                fail($sformatf("branch %0d beat beyond seg end (seg=%0d)", b, s));
                            end else begin
                                p = seg_start[b][s] + chk_ptr[b];
                                if (cdata[b] !== exp_data[b][p])
                                    fail($sformatf("branch %0d data mismatch idx=%0d got=%08x exp=%08x",
                                                   b, p, cdata[b], exp_data[b][p]));
                                if (csb[b] !== exp_sb[b][p])
                                    fail($sformatf("branch %0d sideband mismatch idx=%0d got=%x exp=%x",
                                                   b, p, csb[b], exp_sb[b][p]));
                                chk_ptr[b] = chk_ptr[b] + 1;
                                out_beats[b] = out_beats[b] + 1;
                                if ((seg_mode[b][s] == 0) && (chk_ptr[b] == seg_cnt[b][s])) begin
                                    chk_seg[b] = chk_seg[b] + 1;
                                    chk_ptr[b] = 0;
                                end
                            end
                        end
                    end
                end else begin
                    held[b] = 1'b0;
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // driver
    // ------------------------------------------------------------------
    integer fd, rc, i, k, gi;
    string  vector_path;
    string  cmd;
    integer a1, a2, a3, a4, a5;
    reg [39:0] h40;
    integer nread;
    reg [8*256-1:0] line;
    integer pend_reset, pend_cfg, pend_w, pend_h, pend_p;
    integer exp_branch = 0;   // most recent SEG branch (EXP lines follow it)

    task do_reset;
        begin
            rst_n = 0;
            s_valid = 0; s_sof = 0; s_eol = 0; s_eof = 0; s_abort = 0;
            cfg_valid = 0;
            stall_y8 = 0; stall_gau = 0; stall_he = 0;
            repeat (4) @(negedge clk);
            rst_n = 1;
            repeat (2) @(negedge clk);
            for (i = 0; i < 3; i = i + 1) begin
                chk_seg[i] = 0; chk_ptr[i] = 0;
            end
        end
    endtask

    task do_cfg(input integer w, input integer h, input integer ph);
        begin
            // confirm ready BEFORE asserting valid (the latch consumes readiness)
            @(negedge clk);
            while (!cfg_ready) @(negedge clk);
            cfg_width = w[11:0]; cfg_height = h[11:0]; cfg_phase = ph[1:0];
            cfg_valid = 1;
            @(posedge clk);
            #1 cfg_valid = 0;
            @(negedge clk);
        end
    endtask

    task drive_beat(input [39:0] data, input integer sof, eol, eof, ab);
        begin
            @(negedge clk);
            s_data = data; s_sof = sof[0]; s_eol = eol[0]; s_eof = eof[0]; s_abort = ab[0];
            s_valid = 1;
            while (!s_ready) @(negedge clk);
            @(posedge clk);
            #1 s_valid = 0;
        end
    endtask

    task do_gap(input integer n);
        begin
            @(negedge clk);
            s_valid = 0;
            for (gi = 0; gi < n; gi = gi + 1) begin
                @(negedge clk);
                gap_cycles = gap_cycles + 1;
            end
        end
    endtask

    task do_stall(input integer br, input integer n);
        begin
            if (br == 0) stall_y8 = n;
            else if (br == 1) stall_gau = n;
            else stall_he = n;
            stall_cycles = stall_cycles + n;
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s", vector_path)) begin
            $display("ALGO_CORE_FAIL no +VECTORS");
            $finish;
        end
        fd = $fopen(vector_path, "r");
        if (!fd) begin
            $display("ALGO_CORE_FAIL cannot open %s", vector_path);
            $finish;
        end

        for (i = 0; i < 3; i = i + 1) begin
            n_seg_b[i] = 0; exp_fill[i] = 0;
            chk_seg[i] = 0; chk_ptr[i] = 0;
            out_beats[i] = 0; markers[i] = 0;
            held[i] = 0;
        end
        cyc_all3 = 0; cyc_ge2 = 0; hold_checked = 0; gap_cycles = 0; stall_cycles = 0;
        pend_reset = 0; pend_cfg = 0; pend_w = 0; pend_h = 0; pend_p = 0;

        // ---------------- pre-parse ----------------
        while (!$feof(fd)) begin
            nread = $fgets(line, fd);
            if (nread > 0) begin
                if ($sscanf(line, "%s", cmd) == 1) begin
                    if (cmd == "RESET") begin
                        pend_reset = 1;
                    end else if (cmd == "CFG") begin
                        nread = $sscanf(line, "%s %d %d %d", cmd, a1, a2, a3);
                        pend_cfg = 1; pend_w = a1; pend_h = a2; pend_p = a3;
                    end else if (cmd == "SCEN") begin
                        nread = $sscanf(line, "%s %d %d %d", cmd, a1, a2, a3);
                        sc_kind[n_scen]   = a1;
                        sc_abort[n_scen]  = a2;
                        sc_start[n_scen]  = n_in;
                        sc_nbeats[n_scen] = a3;
                        sc_reset[n_scen]  = pend_reset;
                        sc_cfgw[n_scen]   = pend_w;
                        sc_cfgh[n_scen]   = pend_h;
                        sc_cfgp[n_scen]   = pend_p;
                        pend_reset = 0;
                        n_scen = n_scen + 1;
                    end else if (cmd == "IN") begin
                        nread = $sscanf(line, "%s %h %d %d %d %d", cmd, h40, a2, a3, a4, a5);
                        in_data[n_in] = h40;
                        in_sb[n_in]   = (a5<<3) | (a4<<2) | (a3<<1) | a2;
                        n_in = n_in + 1;
                    end else if (cmd == "GAP") begin
                        nread = $sscanf(line, "%s %d", cmd, a1);
                        in_pre[n_in] = 1; in_arg1[n_in] = a1;
                    end else if (cmd == "STALL") begin
                        nread = $sscanf(line, "%s %d %d", cmd, a1, a2);
                        in_pre[n_in] = 2; in_arg1[n_in] = a1; in_arg2[n_in] = a2;
                    end else if (cmd == "SEG") begin
                        nread = $sscanf(line, "%s %d %d %d", cmd, a1, a2, a3);
                        exp_branch = a1;
                        seg_mode[a1][n_seg_b[a1]]  = a2;
                        seg_start[a1][n_seg_b[a1]] = exp_fill[a1];
                        seg_cnt[a1][n_seg_b[a1]]   = a3;
                        n_seg_b[a1] = n_seg_b[a1] + 1;
                    end else if (cmd == "EXP") begin
                        nread = $sscanf(line, "%s %h %d %d %d", cmd, h40, a2, a3, a4);
                        // EXP lines follow the SEG of the matching branch: use the
                        // most recent SEG branch
                        exp_data[exp_branch][exp_fill[exp_branch]] = h40[31:0];
                        exp_sb[exp_branch][exp_fill[exp_branch]] = (a4<<2) | (a3<<1) | a2;
                        exp_fill[exp_branch] = exp_fill[exp_branch] + 1;
                    end else if (cmd == "TOTALS") begin
                        nread = $sscanf(line, "%s %d %d %d %d %d", cmd, a1, a2, a3, a4, a5);
                        tot_good_exp = a1; tot_abort_exp = a2;
                        tot_pub_exp = a3; tot_rej_exp = a4; tot_gauab_exp = a5;
                    end
                end
            end
        end
        $fclose(fd);

        // ---------------- run ----------------
        rst_n = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;
        for (i = 0; i < 3; i = i + 1) begin
            chk_seg[i] = 0; chk_ptr[i] = 0;
        end
        for (k = 0; k < n_scen; k = k + 1) begin
            if (sc_reset[k]) begin
                do_reset();
                do_cfg(sc_cfgw[k], sc_cfgh[k], sc_cfgp[k]);
            end
            for (i = 0; i < sc_nbeats[k]; i = i + 1) begin
                if (in_pre[sc_start[k] + i] == 1) do_gap(in_arg1[sc_start[k] + i]);
                else if (in_pre[sc_start[k] + i] == 2)
                    do_stall(in_arg1[sc_start[k] + i], in_arg2[sc_start[k] + i]);
                drive_beat(in_data[sc_start[k] + i],
                           in_sb[sc_start[k] + i] & 1,
                           (in_sb[sc_start[k] + i] >> 1) & 1,
                           (in_sb[sc_start[k] + i] >> 2) & 1,
                           (in_sb[sc_start[k] + i] >> 3) & 1);
            end
        end
        // drain: wait until all segments consumed
        for (i = 0; i < 2000000; i = i + 1) begin
            @(negedge clk);
            if ((chk_seg[0] >= n_seg_b[0]) && (chk_seg[1] >= n_seg_b[1]) &&
                (chk_seg[2] >= n_seg_b[2])) i = 3000000;
        end
        repeat (20) @(negedge clk);

        // ---------------- final checks ----------------
        for (b = 0; b < 3; b = b + 1) begin
            if (chk_seg[b] < n_seg_b[b])
                fail($sformatf("branch %0d segments incomplete (%0d/%0d)", b, chk_seg[b], n_seg_b[b]));
        end
        if (errs == 0 && (st_good !== tot_good_exp[15:0])) fail($sformatf("frames_good %0d != %0d", st_good, tot_good_exp));
        if (errs == 0 && (st_abort !== tot_abort_exp[15:0])) fail($sformatf("frames_abort %0d != %0d", st_abort, tot_abort_exp));
        if (errs == 0 && (st_he_pub !== tot_pub_exp[15:0])) fail($sformatf("he_published %0d != %0d", st_he_pub, tot_pub_exp));
        if (errs == 0 && (st_he_rej !== tot_rej_exp[15:0])) fail($sformatf("he_rejected %0d != %0d", st_he_rej, tot_rej_exp));
        if (errs == 0 && (st_gau_ab !== tot_gauab_exp[15:0])) fail($sformatf("gau_abort %0d != %0d", st_gau_ab, tot_gauab_exp));
        if (errs == 0 && cfg_error !== 1'b0) fail("cfg_error set for supported geometry");
        if (!hold_checked) fail("no stalled-output coverage");
        if (!gap_cycles) fail("no input gap coverage");
        if (!cyc_all3) fail("no three-way concurrent production observed");

        // ---------------- HE LUT dump (final published LUT) ----------------
        begin
            integer lfd, la;
            lfd = $fopen("he_lut_dump.hex", "w");
            for (la = 0; la < 256; la = la + 1) begin
                @(negedge clk);
                he_lut_addr = la[7:0];
                @(negedge clk);
                if (lfd) $fwrite(lfd, "%02x\n", he_lut_data);
            end
            if (lfd) $fclose(lfd);
        end

        if (errs != 0) begin
            $display("ALGO_CORE_FAIL errs=%0d cycles=%0d beats=%0d/%0d/%0d markers=%0d/%0d/%0d",
                     errs, cycles, out_beats[0], out_beats[1], out_beats[2],
                     markers[0], markers[1], markers[2]);
        end else begin
            $display("ALGO_CORE_PASS cycles=%0d all3=%0d ge2=%0d beats=%0d/%0d/%0d markers=%0d/%0d/%0d hold=%0d stalls=%0d gaps=%0d frames=%0d/%0d",
                     cycles, cyc_all3, cyc_ge2,
                     out_beats[0], out_beats[1], out_beats[2],
                     markers[0], markers[1], markers[2],
                     hold_checked, stall_cycles, gap_cycles,
                     st_good, st_abort);
        end
        $finish;
    end

    // temporary debug: y8 port trace around the abort scenario
    always @(negedge clk) begin
        if (rst_n && (cycles > 3590) && (cycles < 3625))
            $display("ALGO_CORE_DBG y8 t=%0t v=%b r=%b ab=%b d=%h cs=%0d cp=%0d ob=%0d cnt=%0d rdp=%0d",
                     $time, y8_valid, y8_ready, y8_abort, y8_data,
                     chk_seg[0], chk_ptr[0], out_beats[0],
                     dut.u_obuf_y8.count, dut.u_obuf_y8.rd_ptr);
    end

    // temporary debug: compact state trace in the abort-scenario window
    reg [2:0] dbg_st_p = 7;
    always @(posedge clk) begin
        if (rst_n && (cycles > 3590) && (cycles < 3625) && (dut.u_front.u_row.state !== dbg_st_p))
            $display("ALGO_CORE_DBG st %0d->%0d t=%0t row=%0d w=%0d fl=%0d mw=%0d mm1=%0d srdy=%b",
                     dbg_st_p, dut.u_front.u_row.state, $time,
                     dut.u_front.u_row.in_row, dut.u_front.u_row.in_w,
                     dut.u_front.u_row.fl_cnt, dut.u_front.u_row.m_words,
                     dut.u_front.u_row.mm1, s_ready);
        dbg_st_p = dut.u_front.u_row.state;
        if (rst_n && (cycles > 3590) && (cycles < 3625) && dut.u_front.u_row.prod_valid)
            $display("ALGO_CORE_DBG pv t=%0t y=%0d j=%0d ab=%b", $time,
                     dut.u_front.u_row.prod_y, dut.u_front.u_row.prod_j,
                     dut.u_front.u_row.prod_abort);
    end

    // temporary debug: marker path probe in the abort-scenario window
    always @(negedge clk) begin
        if (rst_n && (cycles > 3600) && (cycles < 3612))
            $display("ALGO_CORE_DBG mk t=%0t g0v=%b abr=%b xfer=%b cnt=%0d rv=%b ra=%b wrdy=%b",
                     $time, dut.g0_valid, dut.y8_abort_r, dut.y8_xfer,
                     dut.u_obuf_y8.count, dut.y8_valid, dut.y8_abort, dut.y8_fifo_ready);
    end

    initial begin
        #20000000;
        $display("ALGO_CORE_FAIL timeout cycles=%0d seg=%0d/%0d/%0d s_ready=%b cfg_ready=%b cfg_err=%b st_good=%0d",
                 cycles, chk_seg[0], chk_seg[1], chk_seg[2], s_ready, cfg_ready, cfg_error, st_good);
        $finish;
    end
endmodule
