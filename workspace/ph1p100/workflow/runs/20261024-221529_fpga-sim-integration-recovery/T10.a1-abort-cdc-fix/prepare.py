import pathlib,json,hashlib,subprocess
root=pathlib.Path(r'D:\fpga\ph1p100'); run=root/'workflow/runs/20261024-221529_fpga-sim-integration-recovery'; out=run/'T10.a1-abort-cdc-fix'
dispatch=json.loads((run/'dispatch-abort-cdc-fix-r0.json').read_text(encoding='utf-8-sig')); records=[]
for name in dispatch['input_paths']:
 p=pathlib.Path(name); b=p.read_bytes(); records.append(dict(path=str(p),bytes=len(b),sha256=hashlib.sha256(b).hexdigest()))
status=subprocess.run(['git','status','--porcelain','-uno'],cwd=root,capture_output=True,encoding='utf-8',errors='replace',timeout=60)
(out/'preexisting-worktree.txt').write_text(status.stdout,encoding='utf-8')
old=run/'T10.a1-recovery-sim/resume01'
for name in ['planning-input-manifest.json','T10.a1-recovery-sim/resume01/manifest-resume01.json']:
 d=json.loads((run/name).read_text(encoding='utf-8-sig')); print(name,'keys',list(d),'file_count',len(d.get('files',[])))
protected=json.loads((run/'planning-input-manifest.json').read_text(encoding='utf-8-sig'))['files']
for x in protected:
 assert hashlib.sha256(pathlib.Path(x['frozen']).read_bytes()).hexdigest()==x['sha256']
(out/'protection-before.json').write_text(json.dumps(dict(inputs=records,planning_frozen=protected),indent=2),encoding='utf-8')
for name in ['ddr_recovery_model.sv','tb_recovery.sv','check_recovery.py']:
 (out/name).write_bytes((old/name).read_bytes())
s=(run/'inputs/a1-r5/src/camera_a1_uart_top.v').read_text()
start=s.index('    capture_async_fifo #(.WIDTH(43)'); end=s.index('    wire [39:0] e_pix',start)
s=s[:start]+'''    // CSI cannot stop. One holding token preserves valid/data under FIFO stall;
    // the first lost beat closes this interval and reserves an ordered abort.
    // Repeated errors while dropping coalesce into one abort event, not a
    // purported exact per-frame loss count. Resume only on a fresh SOF after
    // the abort has actually entered the FIFO (never on that same edge).
    reg         cam_hold_valid, cam_abort_pending, cam_drop, cam_loss;
    reg  [42:0] cam_hold_data;
    wire        cam_fifo_ready;
    wire        cam_room = !cam_hold_valid || cam_fifo_ready;
    wire        cam_abort_held = cam_hold_valid && cam_hold_data[42];

    always @(posedge clk_cam or negedge rst_n) begin
        if (!rst_n) begin
            cam_hold_valid <= 1'b0; cam_hold_data <= 43'd0;
            cam_abort_pending <= 1'b0; cam_drop <= 1'b1; cam_loss <= 1'b0;
        end else begin
            if (cam_hold_valid && cam_fifo_ready) cam_hold_valid <= 1'b0;
            if (cam_abort_pending && cam_room) begin
                cam_hold_valid <= 1'b1;
                cam_hold_data <= {1'b1, 2'b00, 40'd0};
                cam_abort_pending <= 1'b0;
            end
            if (crop_abort) begin
                cam_drop <= 1'b1;
                if (!cam_loss) begin
                    cam_abort_pending <= 1'b1;
                    cam_loss <= 1'b1;
                end
            end else if (crop_valid && !cam_abort_pending && !cam_abort_held) begin
                if (cam_drop) begin
                    if (crop_sof && cam_room) begin
                        cam_hold_valid <= 1'b1;
                        cam_hold_data <= {1'b0, crop_last, crop_sof, crop_pix};
                        cam_drop <= 1'b0; cam_loss <= 1'b0;
                    end
                end else if (cam_room) begin
                    cam_hold_valid <= 1'b1;
                    cam_hold_data <= {1'b0, crop_last, crop_sof, crop_pix};
                end else begin
                    cam_abort_pending <= 1'b1;
                    cam_drop <= 1'b1; cam_loss <= 1'b1;
                end
            end
        end
    end

    capture_async_fifo #(.WIDTH(43), .ADDR_BITS(FIFO_AW)) u_cam_fifo (
        .rst_n   (rst_n),
        .wclk    (clk_cam),
        .w_valid (cam_hold_valid),
        .w_data  (cam_hold_data),
        .w_ready (cam_fifo_ready),
        .rclk    (clk_a1),
        .r_valid (fifo_valid),
        .r_data  (fifo_dout),
        .r_ready (fifo_ready)
    );

'''+s[end:]
s=s.replace('    wire skid_take = skid_valid && raw_wr_ready;', '''    // Abort wins before the store's combinational acceptance, including a
    // last token stalled in skid. Keep ownership until the last STORE take;
    // an e_last arriving from the FIFO alone does not complete a session.
    wire abort_head = fifo_valid && e_abort;
    wire raw_store_valid = skid_valid && !abort_head && !raw_abort;
    wire skid_take = raw_store_valid && raw_wr_ready;
    reg [31:0] raw_abort_events;''')
s=s.replace('else if (e_sof)    fifo_ready = skid_free && !raw_active && raw_begin_ready;', 'else if (e_sof)    fifo_ready = skid_free && !raw_active && !raw_begin && !raw_abort && raw_begin_ready;')
s=s.replace("raw_active <= 1'b0; raw_drop <= 1'b0;", "raw_active <= 1'b0; raw_drop <= 1'b1;\n            raw_abort_events <= 32'd0;")
s=s.replace("if (skid_take) skid_valid <= 1'b0;", "if (skid_take) begin\n                skid_valid <= 1'b0;\n                if (skid_last) raw_active <= 1'b0;\n            end")
s=s.replace("if (raw_active) raw_abort <= 1'b1;", "if (raw_active || raw_begin || skid_valid) raw_abort <= 1'b1;\n                    raw_abort_events <= raw_abort_events + 32'd1;")
s=s.replace("                    if (e_last) raw_active <= 1'b0;", "                    // Completion follows the real store acceptance above.")
s=s.replace('.wr_valid (skid_valid), .wr_last (skid_last)', '.wr_valid (raw_store_valid), .wr_last (skid_last)')
s=s.replace('raw_st_err + cmp_st_err + exp_err;', 'raw_st_err + cmp_st_err + exp_err + raw_abort_events;')
(out/'candidate/camera_a1_uart_top.v').write_text(s,encoding='utf-8',newline='\n')
print('PREPARED',len(records),'dispatch inputs; protected',len(protected),'candidate',len(s))
