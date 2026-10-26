  PH1P_PHY_LSLICE #(
    //.LUT5B("(E*D)"),
    .INIT_LUT5B(32'b11111111000000000000000000000001),
    .LUT5B_SD2("IMB"),
    .LUTMODE("DLUT5"),
    .OFB_SD("LUTX"))
    \u_ddrmc_test_top/u_capture/u_fifo/wq1_rgray_b[7]_syn_2  (
    .ie(\u_ddrmc_test_top/u_capture/u_pack/rst_n_dup_2668 ),
    .imb(\u_ddrmc_test_top/u_capture/u_fifo/rgray [7]),
    .ofb(\u_ddrmc_test_top/u_capture/u_fifo/wq1_rgray_b [7]));