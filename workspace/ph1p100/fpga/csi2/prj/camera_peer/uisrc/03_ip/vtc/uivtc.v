/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.1
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/

/*************uivtc(video timing controller)视频时序控制器*************
--版本号1.1
--以下是米联客设计的uivtc(video timing controller)视频时序控制器
--1.代码简洁，占用极少逻辑资源，代码结构清晰，逻辑设计严谨
--2.使用方便，只需要输入6个参数既可以实现对不同视频分辨率时序的控制
--3.该视频时序控制，一个时钟对应一个像素
--4.通常我们说的像素，比如1080P代表了1920*1080是指视频的有效显示区域，实际的视频还包含不能显示的区域，比如行同步，场同步时间
--5.通常我们说的行视频信号，也称之为视频的水平像素信号；场视频信号，也称之为视频的垂直像素信号；
*********************************************************************/

`timescale 1ns/1ps
// All coordinates start at the first active pixel. Control outputs share two stages.
module uivtc #(
    parameter H_ActiveSize=1920,H_FrameSize=2200,H_SyncStart=2008,H_SyncEnd=2052,
    parameter V_ActiveSize=1080,V_FrameSize=1125,V_SyncStart=1084,V_SyncEnd=1089
)(input I_vtc_rstn,input I_vtc_clk,
  output O_vtc_vs,output O_vtc_hs,output O_vtc_de_valid,output O_vtc_user,output O_vtc_last);
    reg [2:0] rst_pipe=0;
    always @(posedge I_vtc_clk or negedge I_vtc_rstn)
        if(!I_vtc_rstn) rst_pipe<=0; else rst_pipe<={rst_pipe[1:0],1'b1};
    reg [11:0] hcnt=0,vcnt=0;
    wire active=(hcnt<H_ActiveSize && vcnt<V_ActiveSize);
    reg [1:0] hs_pipe=0,vs_pipe=0,de_pipe=0,user_pipe=0,last_pipe=0;
    always @(posedge I_vtc_clk) begin
        if(!rst_pipe[2]) begin
            hcnt<=0;vcnt<=0;
            hs_pipe<=0;vs_pipe<=0;de_pipe<=0;user_pipe<=0;last_pipe<=0;
        end else begin
            if(hcnt==H_FrameSize-1) begin
                hcnt<=0;
                vcnt<=(vcnt==V_FrameSize-1) ? 12'd0 : vcnt+1'b1;
            end else hcnt<=hcnt+1'b1;
            hs_pipe<={hs_pipe[0],(hcnt>=H_SyncStart && hcnt<H_SyncEnd)};
            vs_pipe<={vs_pipe[0],(vcnt>=V_SyncStart && vcnt<V_SyncEnd)};
            de_pipe<={de_pipe[0],active};
            user_pipe<={user_pipe[0],(hcnt==0 && vcnt==0)};
            last_pipe<={last_pipe[0],(hcnt==H_ActiveSize-1 && vcnt<V_ActiveSize)};
        end
    end
    assign O_vtc_hs=hs_pipe[1];assign O_vtc_vs=vs_pipe[1];
    assign O_vtc_de_valid=de_pipe[1];assign O_vtc_user=user_pipe[1];assign O_vtc_last=last_pipe[1];
endmodule
