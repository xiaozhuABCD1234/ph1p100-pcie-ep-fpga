`timescale 1ns/1ps
// Diagnostic only: keep the upstream camera/DDR consumer running continuously.
// Registered RGB and controls add exactly one common pixel-clock stage.
module gray_pattern_probe #(
    parameter H_ACTIVE=1920,V_ACTIVE=1080,FRAMES_PER_MODE=480
)(
    input clk,rst_n,input[23:0] in_rgb,input in_de,in_hs,in_vs,
    output reg[23:0] out_rgb,output reg out_de,out_hs,out_vs,
    output reg pattern_mode
);
    localparam COUNT_BITS=(FRAMES_PER_MODE>1)?$clog2(FRAMES_PER_MODE):1;
    reg[COUNT_BITS-1:0] frame_count;
    reg vs_d,de_d;
    reg[11:0] x,y;
    reg[7:0] gray;
    always @*begin
        if(y<V_ACTIVE/2)begin
            if(x<H_ACTIVE/2)gray=x[7:0];                 // repeated ramps
            else gray={8{x[0]^y[0]}};                   // one-pixel checker
        end else begin
            if(x<H_ACTIVE/2)gray={y[4:0],3'b000};        // horizontal levels
            else gray=x[7:0]^{y[3:0],y[7:4]};           // static fine texture
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            frame_count<=0;pattern_mode<=0;vs_d<=0;de_d<=0;x<=0;y<=0;
            out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;
        end else begin
            vs_d<=in_vs;de_d<=in_de;
            out_de<=in_de;out_hs<=in_hs;out_vs<=in_vs;
            out_rgb<=pattern_mode?{3{gray}}:in_rgb;
            if(in_vs&&!vs_d&&!in_de)begin
                x<=0;y<=0;
                if(frame_count==FRAMES_PER_MODE-1)begin
                    frame_count<=0;pattern_mode<=~pattern_mode;
                end else frame_count<=frame_count+1'b1;
            end else begin
                if(in_de)x<=x+1'b1;else x<=0;
                if(de_d&&!in_de)y<=y+1'b1;
            end
        end
    end
endmodule
