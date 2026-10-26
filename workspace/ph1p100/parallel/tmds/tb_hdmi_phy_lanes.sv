`timescale 1ps/1fs
// 明文 hdmi_tx_phy_wrapper 的 4 lane 组合校验（真实 vendor IO 模型）。
// 关注两点：
//   1) wrapper 的位反转 + lane_lvds_10_1(PH1P) 的位反转 组合后，每 lane 仍是 MSB-first；
//      现有 tb_hdmi_native_stream 只直连 lane、绕过 wrapper，覆盖不到这一层组合。
//   2) 4 个 lane 相互独立，不共用错位/串流。
module tb_hdmi_phy_lanes;
parameter integer PHASE_PS=0;
reg pclk=0,sclk=0,rst=1;
always #1000 sclk=~sclk;
initial begin #(PHASE_PS); forever #5000 pclk=~pclk; end

function [9:0] pat0(input integer n); pat0=(n*73)^(n>>2)^10'h2d3; endfunction
function [9:0] pat1(input integer n); pat1=(n*29)^(n>>3)^10'h1a5; endfunction
function [9:0] pat2(input integer n); pat2=(n*17)^(n>>1)^10'h0f0; endfunction
function [9:0] pat3(input integer n); pat3=(n*7)^10'h155; endfunction

reg [9:0] d0,d1,d2,d3;
integer wi=0;
always @(negedge pclk) begin
    if(rst) begin wi=0; d0=pat0(0); d1=pat1(0); d2=pat2(0); d3=pat3(0); end
    else begin wi=wi+1; d0=pat0(wi); d1=pat1(wi); d2=pat2(wi); d3=pat3(wi); end
end

wire q0,q1,q2,q3;
hdmi_tx_phy_wrapper #(.DEVICE("PH1P")) dut(
    .I_pixel_clk(pclk),.I_serial_clk(sclk),.I_rst(rst),
    .I_tmds_channel_0(d0),.I_tmds_channel_1(d1),
    .I_tmds_channel_2(d2),.I_tmds_channel_clk(d3),
    .O_tmds_ch0_p(q0),.O_tmds_ch1_p(q1),.O_tmds_ch2_p(q2),.O_tmds_clk_p(q3));

reg a0[0:1799],a1[0:1799],a2[0:1799],a3[0:1799];
integer i,j,start,found,bad,checks=0;

function [9:0] pat(input integer lane,input integer n);
    begin
        if(lane==0) pat=pat0(n);
        else if(lane==1) pat=pat1(n);
        else if(lane==2) pat=pat2(n);
        else pat=pat3(n);
    end
endfunction

task check_lane(input integer lane);
    begin
        found=-1;
        for(start=0;start<300;start=start+1) begin
            bad=0;
            for(j=0;j<1200;j=j+1) begin
                // 组合后 line 上的顺序：wrapper 反转 + lane 反转，先出 bus 的 bit0。
                // 即线上第 j 位 == 输入总线码的 bit(j%10)。
                case(lane)
                    0: if(a0[start+j]!==pat(0,8+j/10)[j%10]) bad=1;
                    1: if(a1[start+j]!==pat(1,8+j/10)[j%10]) bad=1;
                    2: if(a2[start+j]!==pat(2,8+j/10)[j%10]) bad=1;
                    default: if(a3[start+j]!==pat(3,8+j/10)[j%10]) bad=1;
                endcase
            end
            if(!bad && found<0) found=start;
        end
        if(found<0) begin $display("PHY_LANES_FAIL lane=%0d phase=%0d no expected bit-order stream",lane,PHASE_PS); $finish; end
        checks=checks+1200;
    end
endtask

integer restart;
initial begin
    for(restart=0;restart<2;restart=restart+1) begin
        rst=1; #40750; rst=0;
        @(posedge sclk); #500;
        for(i=0;i<1800;i=i+1) begin a0[i]=q0;a1[i]=q1;a2[i]=q2;a3[i]=q3;#1000; end
        check_lane(0);check_lane(1);check_lane(2);check_lane(3);
    end
    $display("PHY_LANES_PASS phase=%0d bits=%0d lanes=4 restarts=2",PHASE_PS,checks);
    $finish;
end
initial begin #20000000; $display("PHY_LANES_FAIL timeout"); $finish; end
endmodule
