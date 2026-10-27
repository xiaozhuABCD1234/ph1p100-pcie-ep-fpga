// algo_rowwin_reader.v — sequential row-window reader for the 4px image pipeline.
// T09.rk-align-algo. Verilog-2001, async reset, synthesizable.
//
// Purpose: drive a line-buffer read port with the exact issue schedule required by
// algo_rowwin3 so that, at every production slot (y,j), the caller sees
//   d_in = word j+1, r1 = word j, r2 = word j-1   of the scanned row
// (word = 4 samples of DW bits; sample DW/4 bits each).
//
// Frozen schedule (see algo/change-report.md): the scan is event driven
// (en = one accepted input beat or one flush slot).  The caller asserts `start`
// two events before the first production slot of the scan row (centre reader:
// at input (row 0, last word); up reader: at input (row 1, last word)) and
// `rows_limit` selects how many rows are scanned (centre: H, up: H-1).
//
// Bank rotation: rd_bank starts at 0 for scan row 0 and rotates 0->2->1->0 at
// every scan row end, matching the caller's write-bank sequence W(r).
//
// No hardware or timing claims; G1 simulation only in this package.

module algo_rowwin_reader (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,       // 1-cycle: begin scan at row 0 word 0 (issue 0 now)
    input  wire        clr,         // 1-cycle: abort scan (deactivate, reset bank)
    input  wire        en,          // 1-cycle: advance scan one event
    input  wire [11:0] m_words,     // words per row (>= 2 in this package)
    input  wire [11:0] rows_limit,  // rows to scan (>= 1)
    output wire [11:0] rd_addr,     // issue address for this cycle
    output wire [1:0]  rd_bank,     // issue bank for this cycle
    output wire        active       // scan in progress
);
    reg        active_r;
    reg [11:0] word;   // next word to issue
    reg [11:0] row;    // rows already finished
    reg [1:0]  bank;   // bank of the row being scanned

    assign active  = active_r;
    assign rd_addr = active_r ? word : 12'd0;
    assign rd_bank = active_r ? bank : 2'd0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_r <= 1'b0;
            word     <= 12'd0;
            row      <= 12'd0;
            bank     <= 2'd0;
        end else if (clr) begin
            active_r <= 1'b0;
            word     <= 12'd0;
            row      <= 12'd0;
            bank     <= 2'd0;
        end else if (start) begin
            active_r <= 1'b1;
            bank     <= 2'd0;
            if (m_words == 12'd1) begin
                // single-word rows: row ends at this issue
                word     <= 12'd0;
                row      <= 12'd1;
                bank     <= 2'd2;
                if (rows_limit == 12'd1) active_r <= 1'b0;
            end else begin
                word     <= 12'd1;
                row      <= 12'd0;
            end
        end else if (en && active_r) begin
            if (word == m_words - 12'd1) begin
                word <= 12'd0;
                row  <= row + 12'd1;
                bank <= (bank == 2'd0) ? 2'd2 : (bank == 2'd2) ? 2'd1 : 2'd0;
                if (row == rows_limit - 12'd1) active_r <= 1'b0;
            end else begin
                word <= word + 12'd1;
            end
        end
    end
endmodule
