//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic, Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : TLP_FMT_TYPE.v
//  Author        : Dexin - dexin.guo@anlogic.com
//  Last Modified : 2023-02-02 14:06:57
//  Create        : 2022-06-06 10:09:35
//  Description   : 
//   
///////////////////////////////////////////////////////////////

`ifndef PH2_PCIE_TLP_FMT_TYPE___H
`define PH2_PCIE_TLP_FMT_TYPE___H

// Fmt
`define FMT_3DW       3'b000
`define FMT_4DW       3'b001
`define FMT_3DW_DATA  3'b010
`define FMT_4DW_DATA  3'b011  
`define FMT_TLP_PRFX  3'b100

// --------------------------------------------------------------------
// Type
// --------------------------------------------------------------------
// Memory Read Request
`define MRD_FMT_3DW  3'b000
`define MRD_FMT_4DW  3'b001
`define MRD_TYPE     5'b0_0000

// Memory Read Request-Locked
`define MRDLK_FMT  3'b000
`define MRDLK_TYPE  5'b0_0001

// Memory Write Request
`define MWR_FMT_3DW  3'b010
`define MWR_FMT_4DW  3'b011
`define MWR_TYPE     5'b0_0000

// I/O Read Request
`define IORD_FMT  3'b000
`define IORD_TYPE  5'b0_0010

// I/O Write Request
`define IOWR_FMT  3'b010
`define IOWR_TYPE  5'b0_0010

// Configuration Read Type 0
`define CFGRD0_FMT  3'b000
`define CFGRD0_TYPE  5'b0_0100

// Configuration Write Type 0
`define CFGWR0_FMT  3'b010
`define CFGWR0_TYPE  5'b0_0100

// Configuration Read Type 1
`define CFGRD1_FMT  3'b000
`define CFGRD1_TYPE  5'b0_0101

// Configuration Write Type 1
`define CFGWR1_FMT  3'b010
`define CFGWR1_TYPE  5'b0_0101

// Deprecated TLP Type4
`define TCFGRD_FMT  3'b000
`define TCFGRD_TYPE  5'b1_1011

// Deprecated TLP Type5
`define TCFGWR_FMT  3'b010
`define TCFGWR_TYPE  5'b1_1011

// Message Request
`define MSG_FMT  3'b001
`define MSG_TYPE  5'b1_0xxx

// Message Request with data payload
`define MSGD_FMT  3'b011
`define MSGD_TYPE  5'b1_0xxx

// Completion without Data
`define CPL_FMT  3'b000
`define CPL_TYPE  5'b0_1010

// Completion with Data
`define CPLD_FMT  3'b010
`define CPLD_TYPE  5'b0_1010

// Completion for Locked Memory Read without Data (Used only in error case.)
`define CPLLK_FMT  3'b000
`define CPLLK_TYPE  5'b0_1011

// Completion for Locked Memory Read (Otherwise like CplD.)
`define CPLDLK_FMT  3'b010
`define CPLDLK_TYPE  5'b0_1011

// Fetch and Add AtomicOp Request
`define ATOMIC_FETCHADD_FMT_DATA  3'b01x
`define ATOMIC_FETCHADD_TYPE  5'b0_1100

// Unconditional Swap AtomicOp Request
`define ATOMIC_SWAP_FMT_DATA  3'b01x
`define ATOMIC_SWAP_TYPE  5'b0_1101

// Compare and Swap AtomicOp Request
`define ATOMIC_CAS_FMT_DATA  3'b01x
`define ATOMIC_CAS_TYPE  5'b0_1110

// Local TLP Prefix
`define LPRFX_FMT  3'b100
`define LPRFX_TYPE  5'b0_xxxx

// End-End TLP Prefix
`define EPRFX_FMT  3'b100
`define EPRFX_TYPE  5'b1_xxxx

`endif  // PH2_PCIE_TLP_FMT_TYPE___H
