`timescale 1ns/1ps
// Regression for RAM-read refactoring only. No camera, HDMI PHY, or frame ownership claim.
module tb_cam_preview_read #(parameter SW=4);
    reg pclk=0, bc_clk=0, rst_n=0, de=0, vs=0;
    always #5 pclk=~pclk;
    always #7 bc_clk=~bc_clk;
    wire [23:0] rgb, ref_rgb;
    wire out_de, ref_de, alive, ref_alive;
    integer failures=0, checks=0, i, f, y, x;
    reg [3:0] visited=0;
    cam_preview #(.SW(SW),.SH(4),.H_ACT(2*SW),.V_ACT(8),.DEC_LINE(4)) dut (
        .I_bc_clk(bc_clk),.I_bc_rst_n(rst_n),.I_pix_data(40'd0),.I_pix_valid(1'b0),
        .I_line(1'b0),.I_frame(1'b0),.I_pclk(pclk),.I_pclk_rst_n(rst_n),
        .I_de(de),.I_vs(vs),.O_rgb(rgb),.O_de(out_de),.O_cam_alive(alive));
    upstream_cam_preview #(.SW(SW),.SH(4),.H_ACT(2*SW),.V_ACT(8),.DEC_LINE(4)) ref_dut (
        .I_bc_clk(bc_clk),.I_bc_rst_n(rst_n),.I_pix_data(40'd0),.I_pix_valid(1'b0),
        .I_line(1'b0),.I_frame(1'b0),.I_pclk(pclk),.I_pclk_rst_n(rst_n),
        .I_de(de),.I_vs(vs),.O_rgb(ref_rgb),.O_de(ref_de),.O_cam_alive(ref_alive));
    always @(negedge pclk) begin
        checks=checks+1;
        if ({rgb,out_de,alive} !== {ref_rgb,ref_de,ref_alive}) begin
            failures=failures+1;
            if(failures<8) $display("READ_MISMATCH cycle=%0d rgb=%h ref=%h",checks,rgb,ref_rgb);
        end
        if(rst_n) visited[dut.r_rd_bank]=1;
    end
    initial begin
        // Initialize each bank distinctly, including first/last addresses.
        // Captured source RAM contents are compared at the public outputs.
        for(i=0;i<SW;i=i+1) begin
            dut.r_fb0[i]=10+i; ref_dut.r_fb0[i]=10+i;
            dut.r_fb1[i]=70+i; ref_dut.r_fb1[i]=70+i;
            dut.r_fb2[i]=130+i; ref_dut.r_fb2[i]=130+i;
            dut.r_fb3[i]=240+i; ref_dut.r_fb3[i]=240+i;
        end
        repeat(4) @(posedge pclk);
        #1; rst_n=1;
        for(f=0;f<4;f=f+1) begin
            @(posedge pclk); #1; vs=1;
            repeat(2) @(posedge pclk);
            #1; vs=0;
            for(y=0;y<8;y=y+1) begin
                for(x=0;x<2*SW;x=x+1) begin
                    @(posedge pclk); #1; de=1;
                end
                @(posedge pclk); #1; de=0;
                repeat(3) @(posedge pclk);
            end
            repeat(5) @(posedge pclk);
        end
        @(posedge pclk); #1;
        if(failures==0 && visited==4'b1111) $display("READ_PASS checks=%0d banks=%b",checks,visited);
        else $display("READ_FAIL failures=%0d banks=%b",failures,visited);
        $finish;
    end
endmodule
