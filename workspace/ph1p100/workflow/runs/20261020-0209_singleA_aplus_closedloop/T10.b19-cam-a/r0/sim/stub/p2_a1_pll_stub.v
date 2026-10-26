// T10.b19-cam-a structural stub of p2_a1_pll (ports copied verbatim)
module p2_a1_pll (
    input         refclk,
    input         reset,
    output        clk_out,
    output        lock
);
    assign clk_out = refclk;
    assign lock = 1'b1;
endmodule
