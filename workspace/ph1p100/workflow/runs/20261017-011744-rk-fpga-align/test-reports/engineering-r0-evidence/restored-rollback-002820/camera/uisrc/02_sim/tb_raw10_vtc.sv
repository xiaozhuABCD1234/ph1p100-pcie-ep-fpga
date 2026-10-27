`timescale 1ns/1ps
module tb_raw10_vtc;
    parameter CASE_ID=0;
    reg clk=0, rstn=0;
    always #5 clk=~clk;
    wire hs,vs,de,user,last;
    uivtc #(.H_ActiveSize(1920),.H_FrameSize(2200),.H_SyncStart(2008),.H_SyncEnd(2052),
            .V_ActiveSize(1080),.V_FrameSize(1125),.V_SyncStart(1084),.V_SyncEnd(1089)) dut
        (.I_vtc_clk(clk),.I_vtc_rstn(rstn),.O_vtc_hs(hs),.O_vtc_vs(vs),
         .O_vtc_de_valid(de),.O_vtc_user(user),.O_vtc_last(last));
    integer x,y,n,checks=0,active=0,users=0,lasts=0;
    initial begin
        repeat(8) @(negedge clk);
        rstn=1;
        // Synchronize on a complete frame after vertical sync, using only outputs.
        wait(vs===1); wait(vs===0); wait(de===1); @(negedge clk);
        x=0;y=0;
        for(n=0;n<2200*1125;n=n+1) begin
            if(de !== (x<1920 && y<1080) ||
               hs !== (x>=2008 && x<2052) || vs !== (y>=1084 && y<1089) ||
               user !== (x==0 && y==0) || last !== (x==1919 && y<1080)) begin
                $display("STABLE_FAIL VTC x=%0d y=%0d de/hs/vs/user/last=%b%b%b%b%b",x,y,de,hs,vs,user,last);
                $finish;
            end
            checks=checks+1; active=active+de; users=users+user; lasts=lasts+last;
            if(x==2199) begin x=0;y=y+1;end else x=x+1;
            @(negedge clk);
        end
        if(active!=2073600 || users!=1 || lasts!=1080) begin
            $display("STABLE_FAIL VTC frame totals");$finish;
        end
        rstn=0;repeat(8) @(negedge clk);
        if({de,hs,vs,user,last}!==0) begin $display("STABLE_FAIL VTC reset");$finish;end
        $display("STABLE_PASS VTC checks=%0d active=%0d users=%0d lasts=%0d",checks,active,users,lasts);
        $finish;
    end
    initial begin #60000000; $display("STABLE_FAIL VTC timeout");$finish;end
endmodule
