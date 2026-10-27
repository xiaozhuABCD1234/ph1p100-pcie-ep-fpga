// dual_channel_capture_scheduler.v — INT.P3 dual A/B capture identity & scheduling.
// Frame-granular, identity-preserving scheduler for two camera channels.
// - Channel A is camera_id 0, channel B is camera_id 1.
// - A channel can be gated (a_enable) while B continues (B-first / A pending b20).
// - Only one selected descriptor is presented at a time (o_valid/o_ready).
// - A channel cannot accept a new descriptor until its previous frame is released
//   with a matching identity (camera_id, slot_id, epoch, session, capture_seq).
// - Release identity mismatch is counted (st_rejected) and does not clear ownership.
// - Fairness: round-robin between A and B when both are pending (B first on tie);
//   b_priority forces B whenever B is pending.

module dual_channel_capture_scheduler #(
    parameter CNT_WIDTH = 16
)(
    input  wire         clk,
    input  wire         rst_n,

    // Channel A descriptor input (camera_id must be 0)
    input  wire         a_desc_valid,
    output wire         a_desc_ready,
    input  wire         a_desc_camera_id,
    input  wire         a_desc_slot_id,
    input  wire [31:0]  a_desc_epoch,
    input  wire [31:0]  a_desc_session,
    input  wire [31:0]  a_desc_capture_seq,

    // Channel B descriptor input (camera_id must be 1)
    input  wire         b_desc_valid,
    output wire         b_desc_ready,
    input  wire         b_desc_camera_id,
    input  wire         b_desc_slot_id,
    input  wire [31:0]  b_desc_epoch,
    input  wire [31:0]  b_desc_session,
    input  wire [31:0]  b_desc_capture_seq,

    // Selected descriptor output
    output reg          o_valid,
    input  wire         o_ready,
    output reg          o_camera_id,
    output reg          o_slot_id,
    output reg [31:0]   o_epoch,
    output reg [31:0]   o_session,
    output reg [31:0]   o_capture_seq,

    // Release handshake (consumer completion)
    input  wire         rel_valid,
    output reg          rel_ready,
    input  wire         rel_camera_id,
    input  wire         rel_slot_id,
    input  wire [31:0]  rel_epoch,
    input  wire [31:0]  rel_session,
    input  wire [31:0]  rel_capture_seq,
    input  wire [2:0]   rel_status,

    // Control
    input  wire         a_enable,
    input  wire         b_priority,

    // Status
    output reg [CNT_WIDTH-1:0] st_accepted,
    output reg [CNT_WIDTH-1:0] st_completed,
    output reg [CNT_WIDTH-1:0] st_failed,
    output reg [CNT_WIDTH-1:0] st_rejected,
    output reg                st_busy,
    output reg                st_a_busy,
    output reg                st_b_busy,
    output reg                st_last_camera
);

    // Per-channel inflight identity storage
    reg a_busy, b_busy;
    reg [0:0] a_inf_camera, b_inf_camera;
    reg a_inf_slot, b_inf_slot;
    reg [31:0] a_inf_epoch, b_inf_epoch;
    reg [31:0] a_inf_session, b_inf_session;
    reg [31:0] a_inf_seq, b_inf_seq;

    reg last_sel; // 0=A, 1=B

    // Combinational selection
    reg chosenA, chosenB;
    wire a_id_ok = (a_desc_camera_id == 1'b0);
    wire b_id_ok = (b_desc_camera_id == 1'b1);
    // Hold accept while output is valid and not ready (valid/ready stall preservation).
    wire out_stall = o_valid && !o_ready;
    wire a_can   = a_desc_valid && !a_busy && a_enable && a_id_ok && !out_stall;
    wire b_can   = b_desc_valid && !b_busy && b_id_ok && !out_stall;

    always @(*) begin
        chosenA = 1'b0;
        chosenB = 1'b0;
        if (b_can && (b_priority || !a_can || (last_sel == 1'b0 && a_can))) begin
            chosenB = 1'b1;
        end else if (a_can) begin
            chosenA = 1'b1;
        end
    end

    assign a_desc_ready = chosenA;
    assign b_desc_ready = chosenB;

    // Accept and release bookkeeping
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_busy <= 1'b0; b_busy <= 1'b0;
            a_inf_camera <= 1'b0; b_inf_camera <= 1'b1;
            a_inf_slot <= 1'b0; b_inf_slot <= 1'b0;
            a_inf_epoch <= 32'd0; b_inf_epoch <= 32'd0;
            a_inf_session <= 32'd0; b_inf_session <= 32'd0;
            a_inf_seq <= 32'd0; b_inf_seq <= 32'd0;
            last_sel <= 1'b0;

            o_valid <= 1'b0;
            o_camera_id <= 1'b0;
            o_slot_id <= 1'b0;
            o_epoch <= 32'd0;
            o_session <= 32'd0;
            o_capture_seq <= 32'd0;

            rel_ready <= 1'b1;

            st_accepted <= {CNT_WIDTH{1'b0}};
            st_completed <= {CNT_WIDTH{1'b0}};
            st_failed <= {CNT_WIDTH{1'b0}};
            st_rejected <= {CNT_WIDTH{1'b0}};
            st_busy <= 1'b0;
            st_a_busy <= 1'b0;
            st_b_busy <= 1'b0;
            st_last_camera <= 1'b0;
        end else begin
            rel_ready <= 1'b1;

            // Release handling (may free a channel)
            if (rel_valid) begin
                if (rel_camera_id == 1'b0 && a_busy &&
                    (a_inf_slot == rel_slot_id) &&
                    (a_inf_epoch == rel_epoch) &&
                    (a_inf_session == rel_session) &&
                    (a_inf_seq == rel_capture_seq)) begin
                    a_busy <= 1'b0;
                    if (rel_status == 3'd0) begin
                        if (st_completed != {CNT_WIDTH{1'b1}}) st_completed <= st_completed + 1'b1;
                    end else begin
                        if (st_failed != {CNT_WIDTH{1'b1}}) st_failed <= st_failed + 1'b1;
                    end
                end else if (rel_camera_id == 1'b1 && b_busy &&
                    (b_inf_slot == rel_slot_id) &&
                    (b_inf_epoch == rel_epoch) &&
                    (b_inf_session == rel_session) &&
                    (b_inf_seq == rel_capture_seq)) begin
                    b_busy <= 1'b0;
                    if (rel_status == 3'd0) begin
                        if (st_completed != {CNT_WIDTH{1'b1}}) st_completed <= st_completed + 1'b1;
                    end else begin
                        if (st_failed != {CNT_WIDTH{1'b1}}) st_failed <= st_failed + 1'b1;
                    end
                end else begin
                    if (st_rejected != {CNT_WIDTH{1'b1}}) st_rejected <= st_rejected + 1'b1;
                end
            end

            // Consume output if ready
            if (o_valid && o_ready) begin
                o_valid <= 1'b0;
            end

            // Accept new descriptor
            if (chosenA) begin
                a_busy <= 1'b1;
                a_inf_camera <= 1'b0;
                a_inf_slot <= a_desc_slot_id;
                a_inf_epoch <= a_desc_epoch;
                a_inf_session <= a_desc_session;
                a_inf_seq <= a_desc_capture_seq;

                o_valid <= 1'b1;
                o_camera_id <= 1'b0;
                o_slot_id <= a_desc_slot_id;
                o_epoch <= a_desc_epoch;
                o_session <= a_desc_session;
                o_capture_seq <= a_desc_capture_seq;

                last_sel <= 1'b0;
                if (st_accepted != {CNT_WIDTH{1'b1}}) st_accepted <= st_accepted + 1'b1;
            end else if (chosenB) begin
                b_busy <= 1'b1;
                b_inf_camera <= 1'b1;
                b_inf_slot <= b_desc_slot_id;
                b_inf_epoch <= b_desc_epoch;
                b_inf_session <= b_desc_session;
                b_inf_seq <= b_desc_capture_seq;

                o_valid <= 1'b1;
                o_camera_id <= 1'b1;
                o_slot_id <= b_desc_slot_id;
                o_epoch <= b_desc_epoch;
                o_session <= b_desc_session;
                o_capture_seq <= b_desc_capture_seq;

                last_sel <= 1'b1;
                if (st_accepted != {CNT_WIDTH{1'b1}}) st_accepted <= st_accepted + 1'b1;
            end

            // Status
            st_busy <= o_valid || chosenA || chosenB;
            st_a_busy <= a_busy;
            st_b_busy <= b_busy;
            st_last_camera <= last_sel;
        end
    end

endmodule