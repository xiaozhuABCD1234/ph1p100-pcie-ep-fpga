`timescale 1ns/1ps
// =============================================================================
// cam_diag_mailbox.v -- generic "stable hold + toggle" data mailbox (T10.b7).
//
// One slow producer domain (clk_slow) hands a W-bit word to one fast consumer
// domain (clk_fast).  No asynchronous FIFO, no multi-bit Gray code, no new
// clock: the slow side latches the data into r_hold and flips r_tgl every
// 2**DIV_BITS slow clocks, the fast side synchronises the single toggle bit
// with 3 flops, detects the edge, waits one more flop for the metastability
// window to close and only then samples the (long-stable) data bus.
//
//   DIV_BITS = 12 -> 82 us @ 50 MHz, 37 us @ 111.375 MHz
//   fast side sample latency after the edge: 3 sync flops + 1 settle flop
//                    = 4 clk_fast cycles (~21 ns @ 187.5 MHz)
//   data is stable for >= 37 us -> margin > 1700x
//
// Contract notes (see fpga-design-guide.md section 5):
//   1. every i_data bit is latched on the same clk_slow edge (r_hold <= i_data)
//   2. o_data only ever changes one clk_fast cycle after a synchronised toggle
//      edge, i.e. while the slow-domain data bus has been frozen for >= 37 us
//   3. if clk_slow stops, r_tgl stops and o_data keeps the last value captured
//      (0 after power-on).  Nothing on the fast side waits for the mailbox, so
//      a dead camera byte clock can never block the status packet or the A1
//      chain.
//   4. the slow-side reset only clears the slow-side counter/toggle; the
//      fast-side reset only clears the fast-side synchroniser and snapshot.
// =============================================================================
module cam_diag_mailbox #(
    parameter integer W        = 256,
    parameter integer DIV_BITS = 12
) (
    // slow producer domain
    input  wire                 clk_slow,
    input  wire                 rst_slow_n,
    input  wire [W-1:0]         i_data,
    // fast consumer domain
    input  wire                 clk_fast,
    input  wire                 rst_fast_n,
    output reg  [W-1:0]         o_data
);
    localparam [DIV_BITS-1:0] DIV_LAST = {DIV_BITS{1'b1}};

    reg [DIV_BITS-1:0] r_cnt;
    reg [W-1:0]        r_hold;
    reg                r_tgl;

    // ---------------------------------------------------------- slow side
    // Asynchronous assert so that a clock domain whose clock is still (or
    // permanently) stopped comes out of configuration with a defined state,
    // and so simulation matches silicon when clk_slow starts after reset.
    always @(posedge clk_slow or negedge rst_slow_n) begin
        if (!rst_slow_n) begin
            r_cnt  <= {DIV_BITS{1'b0}};
            r_hold <= {W{1'b0}};
            r_tgl  <= 1'b0;
        end else begin
            if (r_cnt == DIV_LAST) begin
                r_cnt  <= {DIV_BITS{1'b0}};
                r_hold <= i_data;       // whole word latched on one edge
                r_tgl  <= ~r_tgl;       // published by the toggle, not by the bus
            end else begin
                r_cnt  <= r_cnt + 1'b1;
            end
        end
    end

    // ---------------------------------------------------------- fast side
    (* ASYNC_REG = "TRUE" *) reg [2:0] r_tgl_s;   // 3-stage synchroniser
    reg [1:0] r_settle;                          // edge + settle window
    wire      w_edge = r_tgl_s[2] ^ r_tgl_s[1];

    always @(posedge clk_fast or negedge rst_fast_n) begin
        if (!rst_fast_n) begin
            r_tgl_s  <= 3'b000;
            r_settle <= 2'b00;
            o_data   <= {W{1'b0}};
        end else begin
            r_tgl_s  <= {r_tgl_s[1:0], r_tgl};
            r_settle <= {r_settle[0], w_edge};
            // r_settle[0] = edge, r_settle[1] = edge one cycle later: sample
            // here, i.e. 4 clk_fast cycles after the synchroniser first saw it.
            if (r_settle[1]) o_data <= r_hold;
        end
    end
endmodule
