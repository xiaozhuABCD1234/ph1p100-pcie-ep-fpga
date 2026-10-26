// algo_obuf.v — small output buffer (elastic FIFO with sidebands) for the T09
// parallel top.  Verilog-2001, async reset, synthesizable.
//
// Why: the three algorithm outputs share one front-end stream, but each output
// port must honour its own ready/valid handshake (a beat presented with
// r_valid=1 and r_ready=1 must be transferred on the next clock edge).  This
// buffer decouples a port from internal stalls: the port drains the FIFO and
// presents bubbles when the FIFO is empty.
//
// Abort marker convention: a marker is written as an entry with w_valid=0 and
// w_abort=1.  At the read side it is presented as r_valid=0 with r_abort=1 for
// one cycle (control event, popped regardless of r_ready so it cannot block
// data behind it).  Data entries carry data + sof/eol/eof and always wait for
// r_ready.
//
// No hardware/timing claims in this package.

module algo_obuf #(
    parameter DW    = 32,
    parameter DEPTH = 8
)(
    input  wire          clk,
    input  wire          rst_n,
    // write side (pipeline)
    input  wire          w_valid,
    output wire          w_ready,
    input  wire [DW-1:0] w_data,
    input  wire          w_sof,
    input  wire          w_eol,
    input  wire          w_eof,
    input  wire          w_abort,   // marker: write a marker entry
    // read side (port)
    output wire          r_valid,
    input  wire          r_ready,
    output wire [DW-1:0] r_data,
    output wire          r_sof,
    output wire          r_eol,
    output wire          r_eof,
    output wire          r_abort
);
    localparam AW = 3;   // pointer width: DEPTH must be 2**AW (8 here)

    reg [DW+4:0] mem [0:DEPTH-1];   // {marker, eof, eol, sof, data}
    reg [AW-1:0] wr_ptr, rd_ptr;
    reg [AW:0]   count;

    wire full  = (count == DEPTH[AW:0]);
    wire empty = (count == {AW+1{1'b0}});
    // a marker is written as a valid entry with w_abort=1, so the push is a
    // normal transfer (w_valid && !full) - never level-triggered by w_abort
    wire push  = w_valid && !full;
    wire head_marker = mem[rd_ptr][DW+4];
    wire pop   = !empty && (head_marker || r_ready);

    assign w_ready = !full;
    assign r_valid = !empty && !head_marker;
    assign r_data  = mem[rd_ptr][DW-1:0];
    assign r_sof   = mem[rd_ptr][DW];
    assign r_eol   = mem[rd_ptr][DW+1];
    assign r_eof   = mem[rd_ptr][DW+2];
    assign r_abort = !empty && head_marker;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= {AW{1'b0}};
            rd_ptr <= {AW{1'b0}};
            count  <= {(AW+1){1'b0}};
        end else begin
            if (push) begin
                mem[wr_ptr] <= {w_abort, w_eof, w_eol, w_sof, w_data};
                wr_ptr <= wr_ptr + {{(AW-1){1'b0}}, 1'b1};
            end
            if (pop) begin
                rd_ptr <= rd_ptr + {{(AW-1){1'b0}}, 1'b1};
            end
            case ({push, pop})
                2'b10: count <= count + {{AW{1'b0}}, 1'b1};
                2'b01: count <= count - {{AW{1'b0}}, 1'b1};
                default: count <= count;
            endcase
        end
    end
endmodule
