//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : pcie_rc_int_handle.v
//  Author        : Gehong - hong.ge@anlogic.com
//  Last Modified : 2024-07-10 20:58:31
//  Create        : 2023-05-11 16:09:09
//  Description   : 
//   
///////////////////////////////////////////////////////////////

`timescale  1ns/1ps
`include "../common/ph1p_pcie_case_param.v"
module  pcie_rc_int_handle(

    // Clock and Reset
     input       wire                tl_clk_user    
    ,input       wire                tl_rst_user    

    // INT
    ,input       wire                legacy_int_clear
    ,output      reg                 inta           
    ,output      reg                 intb           
    ,output      reg                 intc           
    ,output      reg                 intd           
 
`ifdef PH1P_PCIE_LEGACY_INT_ENABLE  
    ,output      wire   [1:0]        tl_int_status
    ,output      wire   [3:0]        tl_int_pincontrol
    ,input       wire   [3:0]        tl_int_pinstate
`endif
      
`ifdef PH1P_PCIE_MSI_INT_ENABLE
    ,output      wire   [1:0]        tl_int_status
    ,output      wire   [1:0]        tl_int_msireq
    ,output      wire   [9:0]        tl_int_msinum
    ,input       wire   [1:0]        tl_int_msiack
    ,input       wire   [1:0]        tl_int_msi_enable
    ,input       wire   [5:0]        tl_int_msi_multi_enable
    ,output      wire   [31:0]       tl_int_pf0_msi_pending
    ,output      wire   [31:0]       tl_int_pf1_msi_pending
    ,input       wire   [31:0]       tl_int_pf0_msi_mask
    ,input       wire   [31:0]       tl_int_pf1_msi_mask
`endif 

`ifdef PH1P_PCIE_MSIX_INT_ENABLE
    ,input       wire   [1:0]        tl_cfg_msix_enable       
    ,input       wire   [1:0]        tl_cfg_msix_function_mask
`endif


);

// ====================================================================
// LEGACY_INT
// ====================================================================
`ifdef PH1P_PCIE_LEGACY_INT_ENABLE

    reg           legacy_int_clear_ff;
    reg   [3:0]   tl_int_pinstate_ff;
    reg   [3:0]   tl_int_pinstate_2ff;

    assign  tl_int_pincontrol = 4'b0; // rc not send legacy int      
    assign  tl_int_status     = 2'b0; // rc not send legacy int      

    always@(posedge tl_clk_user or posedge tl_rst_user) begin 
          if(tl_rst_user) 
            legacy_int_clear_ff <= 1'b0;
          else 
            legacy_int_clear_ff <= legacy_int_clear ;
    end

    always@(posedge tl_clk_user or posedge tl_rst_user) begin 
          if(tl_rst_user)begin 
            tl_int_pinstate_ff  <= 4'b0;
            tl_int_pinstate_2ff <= 4'b0;
          end else begin  
            tl_int_pinstate_ff  <= tl_int_pinstate;
            tl_int_pinstate_2ff <= tl_int_pinstate_ff;
          end
    end

    always@(posedge tl_clk_user or posedge tl_rst_user) begin 
          if(tl_rst_user) begin
            inta <= 1'b0;           
            intb <= 1'b0;           
            intc <= 1'b0;           
            intd <= 1'b0;           
          end else if(legacy_int_clear_ff) begin 
            inta <= 1'b0;           
            intb <= 1'b0;           
            intc <= 1'b0;           
            intd <= 1'b0;           
          end else if(!tl_int_pinstate_2ff[0] & tl_int_pinstate_ff[0]) begin 
            inta <= 1'b1;
            //pragma translate_off
            $display("tb info : rc get legacy inta interrput");
            //pragma translate_on
          end else if(!tl_int_pinstate_2ff[1] & tl_int_pinstate_ff[1]) begin 
            intb <= 1'b1; 
            //pragma translate_off
            $display("tb info : rc get legacy intb interrput");
            //pragma translate_on
          end else if(!tl_int_pinstate_2ff[2] & tl_int_pinstate_ff[2]) begin 
            intc <= 1'b1;
            //pragma translate_off
            $display("tb info : rc get legacy intc interrput");
            //pragma translate_on
          end else if(!tl_int_pinstate_2ff[3] & tl_int_pinstate_ff[3]) begin 
            intd <= 1'b1;
            //pragma translate_off
            $display("tb info : rc get legacy intd interrput");
            //pragma translate_on
          end
    end
    
// ====================================================================
// MSI_INT
// ====================================================================
`elsif PH1P_PCIE_MSI_INT_ENABLE

    assign     tl_int_status          = 2'b0;
    assign     tl_int_status          = 2'b0;
    assign     tl_int_msireq          = 2'b0;
    assign     tl_int_msinum          = 10'b0;
    assign     tl_int_pf0_msi_pending = 32'd0;
    assign     tl_int_pf1_msi_pending = 32'd0;

// ====================================================================
// MSIX_INT
// ====================================================================
`elsif PH1P_PCIE_MSIX_INT_ENABLE 


`endif


endmodule
