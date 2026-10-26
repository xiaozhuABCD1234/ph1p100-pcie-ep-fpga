`timescale 1ns/1ps
// Arithmetic regression only: it does not certify CSI line/frame sequencing.
module tb_cam_preview_math;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, valid = 0, line_pulse = 0;
    reg [39:0] pixels = 0;
    integer failures = 0, checks = 0;
    integer p0, p1, expected;
    cam_preview #(.SW(4), .SH(4), .H_ACT(8), .V_ACT(8),
                  .DEC_LINE(4), .DEC_CYC(1)) dut (
        .I_bc_clk(clk), .I_bc_rst_n(rst_n), .I_pix_data(pixels),
        .I_pix_valid(valid), .I_line(line_pulse), .I_frame(1'b0),
        .I_pclk(clk), .I_pclk_rst_n(rst_n), .I_de(1'b0), .I_vs(1'b0),
        .O_rgb(), .O_de(), .O_cam_alive()
    );

    task check_value(input integer got, input integer want, input integer tag);
        begin
            checks = checks + 1;
            if (got !== want) begin
                if (failures < 12) $display("MISMATCH tag=%0d got=%0d expected=%0d", tag, got, want);
                failures = failures + 1;
            end
        end
    endtask

    task vertical(input integer a, input integer b);
        begin
            // Start in store phase 0, then advance to write phase 1.
            // No force/deposit: exercise real registered write data and RAM port.
            @(negedge clk); rst_n = 0; valid = 0; line_pulse = 0;
            @(negedge clk); rst_n = 1;
            // Real interface: a line-start pulse precedes the first payload.
            line_pulse = 1;
            @(negedge clk); line_pulse = 0;
            pixels = {20'd0, 10'(a*4), 10'(a*4)}; valid = 1;
            @(negedge clk); valid = 0; line_pulse = 1;
            @(negedge clk); line_pulse = 0;
            pixels = {20'd0, 10'(b*4), 10'(b*4)}; valid = 1;
            @(negedge clk); valid = 0;
            @(negedge clk);
            check_value(dut.r_fb0[0], (a+b)/2, 2000000+a*256+b);
        end
    endtask

    initial begin
        // Exhaustive RAW10 pair sweep: covers wraps, odd sums and endpoints.
        for (p0 = 0; p0 < 1024; p0 = p0 + 1)
            for (p1 = 0; p1 < 1024; p1 = p1 + 1) begin
                pixels = {20'd0, 10'(p1), 10'(p0)};
                #1;
                expected = (p0+p1)/8;
                check_value(dut.w_havg, expected, p0*1024+p1);
            end
        vertical(0,0);
        vertical(127,127);
        vertical(128,128);
        vertical(200,200);
        vertical(255,255);
        vertical(255,0);
        vertical(1,0);
        if (failures == 0) $display("MATH_PASS checks=%0d", checks);
        else $display("MATH_FAIL checks=%0d failures=%0d", checks, failures);
        $finish;
    end
endmodule
