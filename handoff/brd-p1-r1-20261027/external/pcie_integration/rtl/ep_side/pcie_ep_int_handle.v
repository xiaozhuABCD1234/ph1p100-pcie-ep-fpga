//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2024 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : pcie_ep_int_handle.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2024-07-10 18:20:56
//  Create        : 2023-05-11 16:06:26
//  Description   : 
//   
///////////////////////////////////////////////////////////////

`timescale  1ns/1ps
`include "../common/ph1p_pcie_case_param.v" 
module  pcie_ep_int_handle(

    // Clock and Reset
     input       wire                tl_clk_user
    ,input       wire                tl_rst_user
    ,input       wire                user_int_trigger

`ifdef PH1P_PCIE_LEGACY_INT_ENABLE  
    ,output      reg   [1:0]         tl_int_status
    ,output      reg   [3:0]         tl_int_pincontrol
    ,input       wire  [3:0]         tl_int_pinstate
`elsif PH1P_PCIE_MSI_INT_ENABLE
    ,output      reg   [1:0]         tl_int_status
    ,output      reg   [1:0]         tl_int_msireq
    ,output      wire  [9:0]         tl_int_msinum
    ,input       wire  [1:0]         tl_int_msiack
    ,input       wire  [1:0]         tl_int_msi_enable
    ,input       wire  [5:0]         tl_int_msi_multi_enable
    ,output      wire  [31:0]        tl_int_pf0_msi_pending
    ,output      wire  [31:0]        tl_int_pf1_msi_pending
    ,input       wire  [31:0]        tl_int_pf0_msi_mask
    ,input       wire  [31:0]        tl_int_pf1_msi_mask
`elsif PH1P_PCIE_MSIX_INT_ENABLE
    ,output      reg   [3:0]         tl_int_msix_trigger
`endif

);

// ====================================================================
// Parameter/wire/reg
// ====================================================================

    reg   [1:0]      user_int_trigger_ff;

    always@(posedge tl_clk_user or posedge tl_rst_user) begin 
          if(tl_rst_user) 
            user_int_trigger_ff <= 2'b0;
          else 
            user_int_trigger_ff <= {user_int_trigger_ff[0],user_int_trigger};
    end

// ====================================================================
// PH1P_PCIE_LEGACY_INT_ENABLE
// ====================================================================
`ifdef PH1P_PCIE_LEGACY_INT_ENABLE

      reg   [3:0]   tl_int_pincontrol_ff;
        
      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) 
                tl_int_pincontrol_ff <= 4'b1;
            else if(!user_int_trigger_ff[1] & user_int_trigger_ff[0]) // posedge detect
                tl_int_pincontrol_ff <= {tl_int_pincontrol_ff[2:0],tl_int_pincontrol_ff[3]};
      end

      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) begin
                tl_int_pincontrol <= 4'b0;
                tl_int_status     <= 2'b0;
            end else if(!user_int_trigger_ff[1] & user_int_trigger_ff[0]) begin // posedge detect
                tl_int_pincontrol <= tl_int_pincontrol_ff;
                tl_int_status     <= 2'b1;
               //pragma translate_off
                $display("tb info : ep send legacy int to rc");
               //pragma translate_on 
            end else begin 
                tl_int_pincontrol <= 4'b0;
                tl_int_status     <= 2'b0;
            end
      end

// ====================================================================
// PH1P_PCIE_MSI_INT_ENABLE
// ====================================================================
`elsif PH1P_PCIE_MSI_INT_ENABLE

      reg   [1:0]   tl_int_msiack_ff;
      reg   [1:0]   tl_int_msinum_cnt;
      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) 
                tl_int_msiack_ff <= 2'b0;
            else 
                tl_int_msiack_ff <= tl_int_msiack;
      end

      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) begin
                tl_int_status     <= 2'b0;
            end else if(!user_int_trigger_ff[1] & user_int_trigger_ff[0]) begin // posedge detect
                tl_int_status     <= 2'b1;
            end else if(tl_int_msiack_ff[0]) begin 
                tl_int_status     <= 2'b0;
                $display("tb info : ep send msi int to rc");
            end
      end

      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) begin
                tl_int_msireq     <= 2'b0;
            end else if(!user_int_trigger_ff[1] & user_int_trigger_ff[0]) begin // posedge detect
                tl_int_msireq     <= 2'b1;
            end else begin 
                tl_int_msireq     <= 2'b0;
            end
      end

      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) begin
                tl_int_msinum_cnt     <=2'd0;
            end else if(tl_int_msiack_ff[0] & tl_int_status[0] ) begin // posedge detect
                tl_int_msinum_cnt     <= tl_int_msinum_cnt + 1'b1;
            end
      end

    assign  tl_int_pf0_msi_pending = 32'b0; 
    assign  tl_int_pf1_msi_pending = 32'b0; 
    assign  tl_int_msinum = {8'd0,tl_int_msinum_cnt};
// ====================================================================
// PH1P_PCIE_MSIX_INT_ENABLE
// ====================================================================
 `elsif PH1P_PCIE_MSIX_INT_ENABLE

      reg   [3:0]   tl_int_msix_trigger_ff;
        
      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) 
                tl_int_msix_trigger_ff <= 4'b1;
            else if(!user_int_trigger_ff[1] & user_int_trigger_ff[0]) // posedge detect
                tl_int_msix_trigger_ff <= {tl_int_msix_trigger_ff[2:0],tl_int_msix_trigger_ff[3]};
      end

      always@(posedge tl_clk_user or posedge tl_rst_user) begin 
            if(tl_rst_user) begin
                tl_int_msix_trigger <= 4'b0;
            end else if(!user_int_trigger_ff[1] & user_int_trigger_ff[0]) begin // posedge detect
                tl_int_msix_trigger <= tl_int_msix_trigger_ff;
                $display("tb info : ep send msix to rc");
            end else begin 
                tl_int_msix_trigger <= 4'b0;
            end
      end
`endif

endmodule
