// codec_roi_crop.v — 从 4K CSI 组流里裁出一块固定 ROI，喂给 a1_frame_top（LZ77）。
//
// 为什么裁：a1_frame_top 的 a1_deflate_core 吞吐 2.39 cycle/byte，4K30（311 MB/s）
// 需要 744 MHz，不可能；裁到 1920×1088 后是 78.3 MB/s，187.5 MHz 下刚好够，
// 所以这里带一个 keep_div 分频因子，默认隔帧送（15 fps）留余量。
//
// 与 ROI 适配器的区别：这里不做 Bayer 处理、不管 good/abort，只要「每帧恰好
// W/4 × H 组」——a1_frame_top 自己按 2 行一块拼块，少一组就整帧作废。
module codec_roi_crop #(
    parameter integer W  = 1920,
    parameter integer H  = 1088,
    parameter integer X0 = 972,     // 传感器全阵列坐标
    parameter integer Y0 = 552,
    parameter integer FIFO_AW = 9
)(
    input  wire        clk,
    input  wire        rst_n,
    // 源（CSI 组流，同 writer 的 cam 侧时序）
    input  wire        cam_vsync,
    input  wire        cam_in_frame,
    input  wire        cam_in_line,
    input  wire [39:0] cam_pix,
    input  wire        cam_pix_valid,
    // 控制
    input  wire        enable,      // 0 = 不喂（编码器空转）
    input  wire        keep_div,    // 0 = 每帧都送；1 = 隔帧送
    // 给 a1_frame_top
    output reg         o_valid,
    output reg  [39:0] o_pix,
    output reg         o_sof,
    input  wire        o_ready,
    // 观测
    output reg  [31:0] frames_fed,
    output reg  [31:0] frames_skipped,
    output reg         overflow
);
    localparam integer DEPTH = 1 << FIFO_AW;
    localparam integer TOTAL = W * H / 4;

    reg [42:0] mem [0:DEPTH-1];   // {sof, pix[39:0]}
    reg [FIFO_AW:0] wp, rp;
    wire empty = (wp == rp);
    wire full  = ((wp - rp) == DEPTH);

    reg        vs_d, fr_d, line_d;
    reg [15:0] x, y;
    reg        collect, first_line;
    reg [31:0] sent;              // 本帧已入队的组数
    reg        frame_parity;
    reg        pending_sof;   // 第一组要和 SOF 同拍送出（a1_frame_top 把 SOf 那拍当第一个采样）
    reg        skip_frame;

    wire sof = cam_vsync && !vs_d;
    wire le  = cam_in_line && !line_d;
    wire in_roi = (y >= Y0) && (y < Y0 + H) && (x >= X0) && (x < X0 + W);
    wire pixel  = collect && cam_pix_valid && in_roi;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_d <= 0; fr_d <= 0; line_d <= 0;
            x <= 0; y <= 0; collect <= 0; first_line <= 1;
            wp <= 0; rp <= 0; o_valid <= 0; o_pix <= 0; o_sof <= 0;
            sent <= 0; frame_parity <= 0; skip_frame <= 0; pending_sof <= 0;
            frames_fed <= 0; frames_skipped <= 0; overflow <= 0;
        end else begin
            vs_d <= cam_vsync; fr_d <= cam_in_frame; line_d <= cam_in_line;
            o_valid <= 1'b0;
            o_sof   <= 1'b0;

            if (sof) begin
                x <= 0; y <= 0; first_line <= 1; sent <= 0;
                // 隔帧：keep_div=1 时只有 parity=0 的帧喂编码器
                frame_parity <= ~frame_parity;
                skip_frame   <= keep_div && frame_parity;
                if (enable && !(keep_div && frame_parity)) begin
                    collect     <= 1'b1;
                    pending_sof <= 1'b1;
                    frames_fed  <= frames_fed + 1;
                end else begin
                    collect <= 1'b0;
                    if (enable) frames_skipped <= frames_skipped + 1;
                end
            end else if (le) begin
                x <= 0;
                if (first_line) first_line <= 1'b0; else y <= y + 16'd1;
            end else if (cam_pix_valid) begin
                x <= x + 16'd4;
                if (pixel && collect) begin
                    if (sent < TOTAL) begin
                        if (!full) begin
                            mem[wp[FIFO_AW-1:0]] <= {2'b00, pending_sof, cam_pix};  // sof 在 bit40
                            wp <= wp + 1'b1;
                            sent <= sent + 1;
                            pending_sof <= 1'b0;
                        end else begin
                            overflow <= 1'b1;
                            collect <= 1'b0;          // 本帧作废，等下一个 SOF
                            frames_skipped <= frames_skipped + 1;
                        end
                    end
                    if (sent == TOTAL - 1) collect <= 1'b0;
                end
            end

            // 出队：一帧恰好 1 个 sof + TOTAL 个数据
            if (!empty && (!o_valid || o_ready)) begin
                o_valid <= 1'b1;
                o_sof   <= mem[rp[FIFO_AW-1:0]][40];
                o_pix   <= mem[rp[FIFO_AW-1:0]][39:0];
                rp      <= rp + 1'b1;
            end
        end
    end
endmodule
