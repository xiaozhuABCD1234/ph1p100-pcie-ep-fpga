//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : BDF.v
//  Author        : Dexin - dexin.guo@anlogic.com
//  Last Modified : 2023-02-07 09:49:07
//  Create        : 2022-06-17 09:32:48
//  Description   : 
//                  ph2 pcie rc and ep bus/device/function define
///////////////////////////////////////////////////////////////

`ifndef PH2_PCIE_BDF___H
`define PH2_PCIE_BDF___H
  
    `define     BRIDGE_BA               32'hFFFFFF00

    `define     RC_BUS_NUM              8'h00
    `define     RC_DEV_NUM              5'h00
    `define     RC_FUN_NUM              3'h0
    `define     RC_BDF                  {RC_BUS_NUM RC_DEV_NUM RC_FUN_NUM}

    `define     EP_BUS_NUM              8'h01
    `define     EP_DEV_NUM              5'h00
    `define     EP_PF0_FUN_NUM          3'h0
    `define     EP_PF1_FUN_NUM          3'h1
    `define     EP_PF2_FUN_NUM          3'h2
    `define     EP_PF3_FUN_NUM          3'h3
                
    `define     EP_PF0_BDF              {`EP_BUS_NUM,`EP_DEV_NUM,`EP_PF0_FUN_NUM}
    `define     EP_PF1_BDF              {`EP_BUS_NUM,`EP_DEV_NUM,`EP_PF1_FUN_NUM}
    `define     EP_PF2_BDF              {`EP_BUS_NUM,`EP_DEV_NUM,`EP_PF2_FUN_NUM}
    `define     EP_PF3_BDF              {`EP_BUS_NUM,`EP_DEV_NUM,`EP_PF3_FUN_NUM}
    
    `define     ADDR_BAR0_BA            32'h8000_0000 // 32bit Memory
    `define     ADDR_BAR1_BA            32'ha000_0000 // 32bit io
    `define     ADDR_BAR2_BA            32'h0000_0000 // 64bit Memory
    `define     ADDR_BAR3_BA            32'h1000_0000 // 64bit Memory
    `define     ADDR_BAR4_BA            32'h0000_0000 // 64bit Memory
    `define     ADDR_BAR5_BA            32'h2000_0000 // 

    `define     MSI_CTRL_ADDRH          32'h2000_0000
    `define     MSI_CTRL_ADDRL          32'h0090_0000
    `define     MSI_CTRL_DATA           16'h0500
    `define     MSI_CTRL_INT_0_EN_OFF   32'hFFFF_FFFF
    `define     MSI_CTRL_INT_0_MASK_OFF 32'h0000_0000                
                  
    `define     MSIX_SIZE               11'h3        //d128
    `define     MSIX_TABLE_BIR          3'b100
    `define     MSIX_TABLE_OFFSET       28'h1000
    `define     MSIX_PBA_BIR            3'b000
    `define     MSIX_PBA_OFFSET         28'h1080

    `define     MSIX_MSG_ADDR0          64'h2000_0000_0090_0000 
    `define     MSIX_MSG_ADDR1          64'h2000_0000_00A0_0000 
    `define     MSIX_MSG_ADDR2          64'h2000_0000_00B0_0000 
    `define     MSIX_MSG_ADDR3          64'h2000_0000_00C0_0000 
    `define     MSIX_MSG_DATA0          32'h0000_0001 
    `define     MSIX_MSG_DATA1          32'h0000_0010 
    `define     MSIX_MSG_DATA2          32'h0000_0100 
    `define     MSIX_MSG_DATA3          32'h0000_1000

`endif// PH2_PCIE_BDF___H

