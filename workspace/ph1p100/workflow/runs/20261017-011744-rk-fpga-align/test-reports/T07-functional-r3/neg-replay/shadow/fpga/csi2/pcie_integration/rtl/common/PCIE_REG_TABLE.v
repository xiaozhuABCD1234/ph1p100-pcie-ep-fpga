//////////////////////////////////////////////////////////////
//  Copyright(c) 2011-2022 Anlogic Inc.
//  All Right Reserved.
//////////////////////////////////////////////////////////////
//  Company       : Anlogic
//  Filename      : PCIE_REG_TABLE.v
//  Author        : Dexin - dexin.guo@anlogic.com
//  Last Modified : 2023-02-02 14:00:57
//  Create        : 2022-06-17 09:51:30
//  Description   : 
//   
///////////////////////////////////////////////////////////////

`ifndef PH2_PCIE_REG_TABLE___H
`define PH2_PCIE_REG_TABLE___H

// -----------------------------------------------------------------
// Base address for PF0/1 VF1
// -----------------------------------------------------------------
// 
    `define BASE_ADDR_PF0         32'h0000_0000
    `define BASE_ADDR_PF1         32'h0001_0000
    `define BASE_ADDR_VF1_PF0     32'h0020_0000
    `define BASE_ADDR_VF1_PF1     32'h0021_0000
// -----------------------------------------------------------------
// Offset address for PF0/1
// -----------------------------------------------------------------
// Capability
    `define ADDR_PF_TYPE0_HDR     32'h0000_0000
    `define ADDR_PF_FBP_CAP       32'h0000_005C
    `define ADDR_PF_PCIE_CAP      32'h0000_0080
    `define ADDR_PF_MSIX_CAP      32'h0000_00D0
    `define ADDR_PF_MSI_CAP       32'h0000_00E0
    `define ADDR_PF_SRIOV_CAP     32'h0000_0140

    `define ADDR_PF_PM_CAP        32'h0000_0040
    `define ADDR_PF_AER_CAP       32'h0000_0100
    `define ADDR_PF_SN_CAP        32'h0000_0148
    `define ADDR_PF_ARI_CAP       32'h0000_0158
    `define ADDR_PF_SPCIE_CAP     32'h0000_0168
    `define ADDR_PF_TPH_CAP       32'h0000_01EC
    `define ADDR_PF_ATS_CAP       32'h0000_0278
    `define ADDR_PF_ACS_CAP       32'h0000_0288
    `define ADDR_PF_PRS_EXT_CAP   32'h0000_0294
    `define ADDR_PF_LTR_CAP       32'h0000_02A4
    `define ADDR_PF_L1SUB_CAP     32'h0000_02AC
    `define ADDR_PF_DPA_CAP       32'h0000_02BC
    `define ADDR_PF_FRSQ_CAP      32'h0000_02EC
    `define ADDR_PF_RTR_CAP       32'h0000_02FC
    `define ADDR_PF_RAS_DES_CAP   32'h0000_0308
    `define ADDR_PF_DLINK_CAP     32'h0000_0408
    `define ADDR_PF_PORT_LOGIC    32'h0000_0700
// PF0_TYPE1_HDR
    `define RC_ADDR_TYPE1_DEV_ID_VEND_ID_REG                32'h0000_0000
    `define RC_ADDR_TYPE1_STATUS_COMMAND_REG                32'h0000_0004
    `define RC_ADDR_TYPE1_CLASS_CODE_REV_ID_REG             32'h0000_0008
    `define RC_TYPE1_BIST_HDR_TYPE_LAT_CACHE_LINE_SIZE_REG  32'h0000_000C
    `define RC_BAR0_REG                                     32'h0000_0010
    `define RC_BAR1_REG                                     32'h0000_0014
    `define RC_SEC_LAT_TIMER_SUB_BUS_SEC_BUS_PRI_BUS_REG    32'h0000_0018
    `define RC_SEC_STAT_IO_LIMIT_IO_BASE_REG                32'h0000_001C
    `define RC_MEM_LIMIT_MEM_BASE_REG                       32'h0000_0020
    `define RC_PREF_MEM_LIMIT_PREF_MEM_BASE_REG             32'h0000_0024
    `define RC_PREF_BASE_UPPER_REG                          32'h0000_0028
    `define RC_PREF_LIMIT_UPPER_REG                         32'h0000_002C
    `define RC_IO_LIMIT_UPPER_IO_BASE_UPPER_REG             32'h0000_0030
    `define RC_TYPE1_CAP_PTR_REG                            32'h0000_0034
    `define RC_TYPE1_EXP_ROM_BASE_REG                       32'h0000_0038
    `define RC_BRIDGE_CTRL_INT_PIN_INT_LINE_REG             32'h0000_003C
    `define EP_DEVICE_ID_VENDOR_ID_REG                                 32'h0000_0000
    `define EP_STATUS_COMMAND_REG                                      32'h0000_0004
    `define EP_CLASS_CODE_REVISION_ID                                  32'h0000_0008
    `define EP_BIST_HEADER_TYPE_LATENCY_CACHE_LINE_SIZE_REG            32'h0000_000C
    `define EP_BAR0_REG                                                32'h0000_0010
    `define EP_BAR1_REG                                                32'h0000_0014
    `define EP_BAR2_REG                                                32'h0000_0018
    `define EP_BAR3_REG                                                32'h0000_001C
    `define EP_BAR4_REG                                                32'h0000_0020
    `define EP_BAR5_REG                                                32'h0000_0024
    `define EP_CARDBUS_CIS_PTR_REG                                     32'h0000_0028
    `define EP_SUBSYSTEM_ID_SUBSYSTEM_VENDOR_ID_REG                    32'h0000_002C
    `define EP_EXP_ROM_BASE_ADDR_REG                                   32'h0000_0030
    `define EP_PCI_CAP_PTR_REG                                         32'h0000_0034
    `define EP_MAX_LATENCY_MIN_GRANT_INTERRUPT_PIN_INTERRUPT_LINE_REG  32'h0000_003C
// PF0_PM_CAP
    `define CAP_ID_NXT_PTR_REG                           32'h0000_0000
    `define CON_STATUS_REG                               32'h0000_0004
// PF0_MSI_CAP
    `define PCI_MSI_CAP_ID_NEXT_CTRL_REG                 32'h0000_0000
    `define MSI_CAP_OFF_04H_REG                          32'h0000_0004
    `define MSI_CAP_OFF_08H_REG                          32'h0000_0008
    `define MSI_CAP_OFF_0CH_REG                          32'h0000_000C
    `define MSI_CAP_OFF_10H_REG                          32'h0000_0010
    `define MSI_CAP_OFF_14H_REG                          32'h0000_0014
// PF0_PCIE_CAP
    `define PCIE_CAP_ID_PCIE_NEXT_CAP_PTR_PCIE_CAP_REG   32'h0000_0000
    `define DEVICE_CAPABILITIES_REG                      32'h0000_0004
    `define DEVICE_CONTROL_DEVICE_STATUS                 32'h0000_0008
    `define LINK_CAPABILITIES_REG                        32'h0000_000C
    `define LINK_CONTROL_LINK_STATUS_REG                 32'h0000_0010
    `define SLOT_CAPABILITIES_REG                        32'h0000_0014
    `define SLOT_CONTROL_SLOT_STATUS                     32'h0000_0018
    `define ROOT_CONTROL_ROOT_CAPABILITIES_REG           32'h0000_001C
    `define ROOT_STATUS_REG                              32'h0000_0020
    `define DEVICE_CAPABILITIES2_REG                     32'h0000_0024
    `define DEVICE_CONTROL2_DEVICE_STATUS2_REG           32'h0000_0028
    `define LINK_CAPABILITIES2_REG                       32'h0000_002C
    `define LINK_CONTROL2_LINK_STATUS2_REG               32'h0000_0030
// PF0_MSIX_CAP
    `define PCI_MSIX_CAP_ID_NEXT_CTRL_REG 	             32'h0000_0000
    `define MSIX_TABLE_OFFSET_REG                        32'h0000_0004
    `define MSIX_PBA_OFFSET_REG                          32'h0000_0008
// PF0_AER_CAP
    `define AER_EXT_CAP_HDR_OFF                          32'h0000_0000
    `define UNCORR_ERR_STATUS_OFF                        32'h0000_0004
    `define UNCORR_ERR_MASK_OFF                          32'h0000_0008
    `define UNCORR_ERR_SEV_OFF                           32'h0000_000C
    `define CORR_ERR_STATUS_OFF                          32'h0000_0010
    `define CORR_ERR_MASK_OFF                            32'h0000_0014
    `define ADV_ERR_CAP_CTRL_OFF                         32'h0000_0018
    `define HDR_LOG_0_OFF                                32'h0000_001C
    `define HDR_LOG_1_OFF                                32'h0000_0020
    `define HDR_LOG_2_OFF                                32'h0000_0024
    `define HDR_LOG_3_OFF                                32'h0000_0028
    `define ROOT_ERR_CMD_OFF                             32'h0000_002C
    `define ROOT_ERR_STATUS_OFF                          32'h0000_0030
    `define ERR_SRC_ID_OFF                               32'h0000_0034
    `define TLP_PREFIX_LOG_1_OFF                         32'h0000_0038
    `define TLP_PREFIX_LOG_2_OFF                         32'h0000_003C
    `define TLP_PREFIX_LOG_3_OFF                         32'h0000_0040
    `define TLP_PREFIX_LOG_4_OFF                         32'h0000_0044
// PF0_SN_CAP
    `define SN_BASE                                      32'h0000_0000
    `define SER_NUM_REG_DW_1 	                         32'h0000_0004
    `define SER_NUM_REG_DW_2                             32'h0000_0008
// PF0_ARI_CAP
    `define ARI_BASE                                     32'h0000_0000
    `define CAP_REG            	                         32'h0000_0004
// PF0_SPCIE_CAP
    `define SPCIE_CAP_HEADER_REG                         32'h0000_0000
    `define LINK_CONTROL3_REG                            32'h0000_0004
    `define LANE_ERR_STATUS_REG                          32'h0000_0008
    `define SPCIE_CAP_OFF_0CH_REG                        32'h0000_000C
// PF0_PL16G_CAP
// PF0_MARGIN_CAP
// PF0_SRIOV_CAP
    `define SRIOV_BASE_REG                               32'h0000_0000
    `define CAPABILITIES_REG                             32'h0000_0004
    `define STATUS_CONTROL_REG                           32'h0000_0008
    `define TOTAL_VFS_INITIAL_VFS_REG                    32'h0000_000C
    `define SRIOV_NUM_VFS                                32'h0000_0010
    `define SRIOV_VF_OFFSET_POSITION                     32'h0000_0014
    `define VF_DEVICE_ID_REG                             32'h0000_0018
    `define SUP_PAGE_SIZES_REG                           32'h0000_001C
    `define SYSTEM_PAGE_SIZE_REG                         32'h0000_0020
    `define SRIOV_BAR0_REG                               32'h0000_0024
    `define SRIOV_BAR1_REG                               32'h0000_0028
    `define SRIOV_BAR2_REG                               32'h0000_002C
    `define SRIOV_BAR3_REG                               32'h0000_0030
    `define SRIOV_BAR4_REG                               32'h0000_0034
    `define SRIOV_BAR5_REG                               32'h0000_0038
    `define VF_MIGRATION_STATE_ARRAY_REG                 32'h0000_003C
// PF0_TPH_CAP
    `define TPH_EXT_CAP_HDR_REG                          32'h0000_0000
    `define TPH_REQ_CAP_REG_REG                          32'h0000_0004
    `define TPH_REQ_CONTROL_REG_REG                      32'h0000_0008
    `define TPH_ST_TABLE_REG_0                           32'h0000_000C
// PF0_ATS_CAP
    `define ATS_CAP_HDR_REG                              32'h0000_0000
    `define ATS_CAPABILITIES_CTRL_REG                    32'h0000_0004
// PF0_ACS_CAP
    `define ACS_CAP_HDR_REG                              32'h0000_0000
    `define ACS_CAPABILITIES_CTRL_REG                    32'h0000_0004
    `define ACS_EGRESS_CTRL_VECTOR_REG0                  32'h0000_0008
// PF0_PRS_EXT_CAP
    `define PRS_EXT_CAP_HDR_REG                          32'h0000_0000
    `define PRS_CONTROL_STATUS_REG                       32'h0000_0004
    `define PRS_REQ_CAPACITY_REG                         32'h0000_0008
    `define PRS_REQ_ALLOCATION_REG                       32'h0000_000C
// PF0_LTR_CAP
    `define LTR_CAP_HDR_REG                              32'h0000_0000
    `define LTR_LATENCY_REG                              32'h0000_0004
// PF0_L1SUB_CAP
    `define L1SUB_CAP_HEADER_REG                         32'h0000_0000
    `define L1SUB_CAPABILITY_REG                         32'h0000_0004
    `define L1SUB_CONTROL1_REG                           32'h0000_0008
    `define L1SUB_CONTROL2_REG                           32'h0000_000C
// PF0_DPA_CAP
    `define DPA_EXT_CAP_HDR_REG                          32'h0000_0000
    `define DPA_CAP_REG                                  32'h0000_0004
    `define DPA_LAT_IND_REG                              32'h0000_0008
    `define DPA_STATUS_CNTRL_REG                         32'h0000_000C
    `define DPA_PWR_ALLOC_ARRAY0                         32'h0000_0010
    `define DPA_PWR_ALLOC_ARRAY4                         32'h0000_0014
    `define DPA_PWR_ALLOC_ARRAY8                         32'h0000_0018
    `define DPA_PWR_ALLOC_ARRAY12                        32'h0000_001C
    `define DPA_PWR_ALLOC_ARRAY16                        32'h0000_0020
    `define DPA_PWR_ALLOC_ARRAY20 	                     32'h0000_0024
    `define DPA_PWR_ALLOC_ARRAY24                        32'h0000_0028
    `define DPA_PWR_ALLOC_ARRAY28                        32'h0000_002C
// PF0_FRSQ_CAP
    `define FRSQ_EXT_CAP_HDR_OFF                         32'h0000_0000
    `define FRSQ_CAP_OFF                                 32'h0000_0004
    `define FRSQ_CONTROL_FRSQ_STATUS_OFF                 32'h0000_0008
    `define FRS_MESSAGE_QUEUE_OFF                        32'h0000_000C
// PF0_RTR_CAP
    `define RTR_EXT_CAP_HDR_OFF                          32'h0000_0000
    `define READI_TIME_REPORTING1_OFF                    32'h0000_0004
    `define READI_TIME_REPORTING2_OFF                    32'h0000_0008
// PF0_RAS_DES_CAP
    `define RAS_DES_CAP_HEADER_REG                       32'h0000_0000
    `define VENDOR_SPECIFIC_HEADER_REG                   32'h0000_0004
    `define EVENT_COUNTER_CONTROL_REG                    32'h0000_0008
    `define EVENT_COUNTER_DATA_REG                       32'h0000_000C
    `define TIME_BASED_ANALYSIS_CONTROL_REG              32'h0000_0010
    `define TIME_BASED_ANALYSIS_DATA_REG                 32'h0000_0014
    `define TIME_BASED_ANALYSIS_DATA_63_32_REG           32'h0000_0018
    `define EINJ_ENABLE_REG                              32'h0000_0030
    `define EINJ0_CRC_REG                                32'h0000_0034
    `define EINJ1_SEQNUM_REG                             32'h0000_0038
    `define EINJ2_DLLP_REG                               32'h0000_003C
    `define EINJ3_SYMBOL_REG                             32'h0000_0040
    `define EINJ4_FC_REG                                 32'h0000_0044
    `define EINJ5_SP_TLP_REG                             32'h0000_0048
    `define EINJ6_COMPARE_POINT_H0_REG                   32'h0000_004C
    `define EINJ6_COMPARE_POINT_H1_REG                   32'h0000_0050
    `define EINJ6_COMPARE_POINT_H2_REG                   32'h0000_0054
    `define EINJ6_COMPARE_POINT_H3_REG                   32'h0000_0058
    `define EINJ6_COMPARE_VALUE_H0_REG                   32'h0000_005C
    `define EINJ6_COMPARE_VALUE_H1_REG                   32'h0000_0060
    `define EINJ6_COMPARE_VALUE_H2_REG                   32'h0000_0064
    `define EINJ6_COMPARE_VALUE_H3_REG                   32'h0000_0068
    `define EINJ6_CHANGE_POINT_H0_REG                    32'h0000_006C
    `define EINJ6_CHANGE_POINT_H1_REG                    32'h0000_0070
    `define EINJ6_CHANGE_POINT_H2_REG                    32'h0000_0074
    `define EINJ6_CHANGE_POINT_H3_REG                    32'h0000_0078
    `define EINJ6_CHANGE_VALUE_H0_REG                    32'h0000_007C
    `define EINJ6_CHANGE_VALUE_H1_REG                    32'h0000_0080
    `define EINJ6_CHANGE_VALUE_H2_REG                    32'h0000_0084
    `define EINJ6_CHANGE_VALUE_H3_REG                    32'h0000_0088
    `define EINJ6_TLP_REG                                32'h0000_008C
    `define SD_CONTROL1_REG                              32'h0000_00A0
    `define SD_CONTROL2_REG                              32'h0000_00A4
    `define SD_STATUS_L1LANE_REG                         32'h0000_00B0
    `define SD_STATUS_L1LTSSM_REG                        32'h0000_00B4
    `define SD_STATUS_PM_REG                             32'h0000_00B8
    `define SD_STATUS_L2_REG                             32'h0000_00BC
    `define SD_STATUS_L3FC_REG                           32'h0000_00C0
    `define SD_STATUS_L3_REG                             32'h0000_00C4
    `define SD_EQ_CONTROL1_REG                           32'h0000_00D0
    `define SD_EQ_CONTROL2_REG                           32'h0000_00D4
    `define SD_EQ_CONTROL3_REG                           32'h0000_00D8
    `define SD_EQ_STATUS1_REG                            32'h0000_00E0
    `define SD_EQ_STATUS2_REG                            32'h0000_00E4
    `define SD_EQ_STATUS3_REG                            32'h0000_00E8
// PF0_DLINK_CAP
    `define DATA_LINK_FEATURE_EXT_HDR_OFF                32'h0000_0000
    `define DATA_LINK_FEATURE_CAP_OFF                    32'h0000_0004
    `define DATA_LINK_FEATURE_STATUS_OFF                 32'h0000_0008
// PF0_PORT_LOGIC
    `define ACK_LATENCY_TIMER_OFF                        32'h0000_0000
    `define VENDOR_SPEC_DLLP_OFF                         32'h0000_0004
    `define PORT_FORCE_OFF                               32'h0000_0008
    `define ACK_F_ASPM_CTRL_OFF                          32'h0000_000C
    `define PORT_LINK_CTRL_OFF                           32'h0000_0010
    `define LANE_SKEW_OFF                                32'h0000_0014
    `define TIMER_CTRL_MAX_FUNC_NUM_OFF                  32'h0000_0018
    `define SYMBOL_TIMER_FILTER_1_OFF                    32'h0000_001C
    `define FILTER_MASK_2_OFF                            32'h0000_0020
    `define PL_DEBUG0_OFF                                32'h0000_0028
    `define PL_DEBUG1_OFF                                32'h0000_002C
    `define TX_P_FC_CREDIT_STATUS_OFF                    32'h0000_0030
    `define TX_NP_FC_CREDIT_STATUS_OFF                   32'h0000_0034
    `define TX_CPL_FC_CREDIT_STATUS_OFF                  32'h0000_0038
    `define QUEUE_STATUS_OFF                             32'h0000_003C
    `define VC_TX_ARBI_1_OFF                             32'h0000_0040
    `define VC_TX_ARBI_2_OFF                             32'h0000_0044
    `define VC0_P_RX_Q_CTRL_OFF                          32'h0000_0048
    `define VC0_NP_RX_Q_CTRL_OFF                         32'h0000_004C
    `define VC0_CPL_RX_Q_CTRL_OFF                        32'h0000_0050
    `define GEN2_CTRL_OFF                                32'h0000_010C
    `define PHY_STATUS_OFF                               32'h0000_0110
    `define PHY_CONTROL_OFF                              32'h0000_0114
    `define TRGT_MAP_CTRL_OFF                            32'h0000_011C
    `define CLOCK_GATING_CTRL_OFF                        32'h0000_018C
    `define GEN3_RELATED_OFF                             32'h0000_0190
    `define GEN3_EQ_CONTROL_OFF                          32'h0000_01A8
    `define GEN3_EQ_FB_MODE_DIR_CHANGE_OFF               32'h0000_01AC
    `define ORDER_RULE_CTRL_OFF                          32'h0000_01B4
    `define PIPE_LOOPBACK_CONTROL_OFF                    32'h0000_01B8
    `define MISC_CONTROL_1_OFF                           32'h0000_01BC
    `define MULTI_LANE_CONTROL_OFF                       32'h0000_01C0
    `define PHY_INTEROP_CTRL_OFF                         32'h0000_01C4
    `define TRGT_CPL_LUT_DELETE_ENTRY_OFF                32'h0000_01C8
    `define PCIE_VERSION_NUMBER_OFF                      32'h0000_01F8
    `define PCIE_VERSION_TYPE_OFF                        32'h0000_01FC
    `define PL_APP_BUS_DEV_NUM_STATUS_OFF                32'h0000_0410
    `define PCIPM_TRAFFIC_CTRL_OFF                       32'h0000_041C
    `define PL_LTR_LATENCY_OFF                           32'h0000_0430
    `define AUX_CLK_FREQ_OFF                             32'h0000_0440
    `define L1_SUBSTATES_OFF                             32'h0000_0444
    `define POWERDOWN_CTRL_STATUS_OFF                    32'h0000_0448
    `define GEN4_LANE_MARGINING_1_OFF                    32'h0000_0480
    `define GEN4_LANE_MARGINING_2_OFF                    32'h0000_0484
    `define PIPE_RELATED_OFF                             32'h0000_0490

// -----------------------------------------------------------------
// Offset address for VF1
// -----------------------------------------------------------------
    `define ADDR_VF1_PF_TYPE0_HDR  32'h0000_0000
    `define ADDR_VF1_PF_PCIE_CAP   32'h0000_0070
    `define ADDR_VF1_PF_MSIX_CAP   32'h0000_00B0
    `define ADDR_VF1_PF_ARI_CAP    32'h0000_0100
    `define ADDR_VF1_PF_ACS_CAP    32'h0000_0110
    `define ADDR_VF1_PF_RTR_CAP    32'h0000_011C

// Offset address for PF0 Shadow
    `define ADDR_PF_TYPE0_HDR_DBI2   32'h0000_0000
    `define ADDR_PF_PCIE_CAP_DBI2    32'h0000_0070
    `define ADDR_PF_MSIX_CAP_DBI2    32'h0000_00B0
    `define ADDR_PF_SRIOV_CAP_DBI2   32'h0000_01AC
    `define ADDR_PF_TPH_CAP_DBI2     32'h0000_01EC
    `define ADDR_PF_RTR_CAP_DBI2     32'h0000_02FC


`endif  // PH2_PCIE_REG_TABLE___H
