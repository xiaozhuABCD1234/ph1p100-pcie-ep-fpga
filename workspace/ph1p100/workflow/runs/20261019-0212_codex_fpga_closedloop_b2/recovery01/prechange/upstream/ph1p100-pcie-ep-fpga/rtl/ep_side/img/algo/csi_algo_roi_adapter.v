// Non-backpressurable CSI -> checked ROI stream. Same x/y origin as RAW writer.
// Only the final ROI beat is held for FE/good. Thus a bad source frame cannot
// publish an algorithm EOF/LUT. Busy/overflow rejects only this algorithm frame.
module csi_algo_roi_adapter #(
    parameter integer W=1920,H=1080,X0=960,Y0=540,SKIP_ROWS=37,
    parameter integer FIFO_AW=10,
    parameter [31:0] WAIT_LIMIT=32'h00200000
)(
    input wire clk,rst_n,
    input wire cam_vsync,cam_in_frame,cam_in_line,
    input wire [39:0] cam_pix,
    input wire cam_pix_valid,cam_good,cam_abort,
    input wire configured, outputs_done,
    output reg s_valid, input wire s_ready,
    output reg [39:0] s_data,
    output reg s_sof,s_eol,s_eof,s_abort,
    output reg [31:0] accepted_frames,rejected_frames,overflow_frames,
    output reg [31:0] accepted_beats,
    output reg busy
);
    localparam integer DEPTH=1<<FIFO_AW, TOTAL=W*H/4, GPQ=W/4;
    reg vs_d,fr_d,line_d,first_line,collect,good_seen,bad_seen;
    reg [15:0] x,y,line_groups;
    reg [31:0] groups,wait_count;
    reg verdict_ready,verdict_good,abort_pending;
    reg [42:0] fifo[0:DEPTH-1];
    reg [FIFO_AW-1:0] wp,rp;
    reg [FIFO_AW:0] used;
    wire sof=cam_vsync&&!vs_d, fe=!cam_in_frame&&fr_d, le=cam_in_line&&!line_d;
    wire line_roi=(y>=Y0+SKIP_ROWS)&&(y<Y0+SKIP_ROWS+H);
    wire in_roi=line_roi&&(x>=X0)&&(x<X0+W);
    wire pixel=collect&&cam_pix_valid&&in_roi&&!sof&&!fe&&!le;
    wire push=pixel&&(used<DEPTH);
    wire take=s_valid&&s_ready;
    // s_valid itself stays asserted while stalled; the final beat is not loaded
    // into the output register until the source's complete-frame verdict.
    wire can_load=!s_valid||s_ready;
    wire head_final=(used!=0)&&fifo[rp][42];
    wire pop=can_load&&(used!=0)&&(!head_final||verdict_ready)&&!abort_pending;
    wire bad_end=fe&&collect&&(!(cam_good||good_seen)||cam_abort||bad_seen||groups!=TOTAL||(line_roi&&line_groups!=GPQ));
    wire timed_out=busy&&(wait_count>=WAIT_LIMIT);
    wire poison=(pixel&&used==DEPTH)||bad_end||(collect&&cam_abort)||timed_out;
    always @(posedge clk) if(push) fifo[wp]<={groups==TOTAL-1,(x==X0+W-4),groups==0,cam_pix};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            vs_d<=0;fr_d<=0;line_d<=0;first_line<=1;collect<=0;good_seen<=0;bad_seen<=0;
            x<=0;y<=0;line_groups<=0;groups<=0;wp<=0;rp<=0;used<=0;
            verdict_ready<=0;verdict_good<=0;abort_pending<=0;wait_count<=0;
            s_valid<=0;s_data<=0;s_sof<=0;s_eol<=0;s_eof<=0;s_abort<=0;
            accepted_frames<=0;rejected_frames<=0;overflow_frames<=0;accepted_beats<=0;busy<=0;
        end else begin
            vs_d<=cam_vsync;fr_d<=cam_in_frame;line_d<=cam_in_line;
            if(cam_good&&collect) good_seen<=1;
            if(cam_abort&&collect) bad_seen<=1;
            if(sof) begin
                x<=0;y<=0;first_line<=1;line_groups<=0;
                if(!busy&&configured) begin
                    busy<=1;collect<=1;groups<=0;good_seen<=0;bad_seen<=0;
                    verdict_ready<=0;verdict_good<=0;wait_count<=0;
                    accepted_frames<=accepted_frames+1'b1;
                end else begin collect<=0;rejected_frames<=rejected_frames+1'b1;end
            end else if(le) begin
                x<=0;line_groups<=0;
                if(collect&&!first_line&&line_roi&&line_groups!=GPQ) bad_seen<=1;
                if(first_line) first_line<=0;else y<=y+1'b1;
            end else if(cam_pix_valid) begin
                x<=x+4;
                if(pixel) begin groups<=groups+1'b1;line_groups<=line_groups+1'b1;end
            end
            if(fe&&collect) begin
                collect<=0;verdict_ready<=1;verdict_good<=!bad_end;
            end
            if(busy) begin
                if(push||take||fe) wait_count<=0;else wait_count<=wait_count+1'b1;
            end else wait_count<=0;
            if(push) wp<=wp+1'b1;
            if(pop) rp<=rp+1'b1;
            case({push,pop})
                2'b10:used<=used+1'b1;
                2'b01:used<=used-1'b1;
                default:begin end
            endcase
            if(take&&!s_abort) accepted_beats<=accepted_beats+1'b1;
            if(can_load) begin
                s_valid<=0;s_abort<=0;
                if(abort_pending) begin
                    s_valid<=1;s_abort<=1;s_sof<=0;s_eol<=0;s_eof<=0;s_data<=0;
                    abort_pending<=0;
                end else if(pop) begin
                    s_valid<=1;{s_eof,s_eol,s_sof,s_data}<=fifo[rp];
                end
            end
            if(outputs_done) begin busy<=0;wait_count<=0;end
            if(poison) begin
                collect<=0;wp<=0;rp<=0;used<=0;abort_pending<=1;
                verdict_ready<=1;verdict_good<=0;wait_count<=0;
                rejected_frames<=rejected_frames+1'b1;
                if(pixel&&used==DEPTH) overflow_frames<=overflow_frames+1'b1;
                // A loaded stalled beat is preserved. A not-yet-presented final
                // beat remains in FIFO, which is discarded before publication.
            end
        end
    end
endmodule
