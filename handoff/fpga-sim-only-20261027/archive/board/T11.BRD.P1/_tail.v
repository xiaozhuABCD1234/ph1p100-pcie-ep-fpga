
// ====================================================================
//  T11.BRD.P1 board datapath
//
//  2x CSI checked front end (kept from the board proven reference) ->
//  a1_raw_crop ROI -> 43b CDC -> integrated_delivery_top (P4 r2, read-only)
//  -> p2_ddr_bridge -> DDR3 AXI4 write
//  -> ddr_frame_pusher 4KB burst read (tl_clk_user) + brd_ddr_rd_arb
//  -> MWr + doorbell to the PCIe EP transmit port.
//
//  The reference cam_r10f_writer x2 / ddr_wr_arb / img_frame_src
//  instantiations are removed (guide 3.S2): the P4 core owns the DDR slot
//  write path and the ERAM test-frame source is not used on the board.
// ====================================================================

// ---- core clock (150.000 MHz) and its reset synchroniser ----
wire clk_core;
wire core_pll_lock;

brd_a1_core_pll u_core_pll (
    .refclk  (sys_clk           ),
    .reset   (power_on_rst_dly  ),
    .clk_out (clk_core          ),
    .lock    (core_pll_lock     )
);

// asynchronous assert / synchronous release, one release flop chain per domain
// (guide 4 "复位：异步置位、同步释放；每域一个 rst_*_n")
reg [3:0] r_core_rst_cnt;
always @(posedge clk_core or negedge pcie_power_on_rst) begin
    if (!pcie_power_on_rst)        r_core_rst_cnt <= 4'd0;
    else if (core_pll_lock)        r_core_rst_cnt <= {r_core_rst_cnt[2:0], 1'b1};
end
wire rst_core_n = r_core_rst_cnt[3] & core_pll_lock;

// ---- retired reference blocks: keep their status buses defined ----
assign w_camddr_seq  = 32'd0;
assign w_camddr_base = 32'd0;
assign w_camddr_status = 32'd0;
assign w_camddr_len  = 32'd0;
assign w_camddr_b_seq    = 32'd0;
assign w_camddr_b_base   = 32'd0;
assign w_camddr_b_status = 32'd0;
assign w_camddr_b_len    = 32'd0;
assign w_camddr_lines    = 16'd0;
assign w_camddr_grp      = 16'd0;
assign w_camddr_b_lines  = 16'd0;
assign w_camddr_b_grp    = 16'd0;
assign w_camddr_anom     = 1'b0;
assign w_camddr_b_anom   = 1'b0;
assign w_camddr_drop_a   = 96'd0;
assign w_camw_busy       = 1'b0;
assign w_camw_busy_b     = 1'b0;
assign w_wr_grant        = 1'b0;

wire [127:0] p4_st_bus;

brd_board_datapath #(
    .W                 (1920                    ),
    .H                 (1080                    ),
    .MAX_WORDS         (512                     ),
    .SLOT_WORDS        (81920                   ),
    .SLOT_BASE_WORD    (32'd2048                ),
    .FIFO_AW           (10                      )
) u_datapath (
    .cam_a_clk        (w_a_byte_clk             ),
    .cam_a_rst_n      (w_a_rst_out              ),
    .cam_a_pix        (w_a_pixel                ),
    .cam_a_pix_valid  (w_a_pixel_valid          ),
    .cam_a_in_line    (w_a_in_line              ),
    .cam_a_in_frame   (w_a_in_frame             ),
    .cam_a_vsync      (w_a_vsync                ),

    .cam_b_clk        (w_b_byte_clk             ),
    .cam_b_rst_n      (w_b_rst_out              ),
    .cam_b_pix        (w_b_pixel                ),
    .cam_b_pix_valid  (w_b_pixel_valid          ),
    .cam_b_in_line    (w_b_in_line              ),
    .cam_b_in_frame   (w_b_in_frame             ),
    .cam_b_vsync      (w_b_vsync                ),

    .clk_core         (clk_core                 ),
    .rst_core_n       (rst_core_n               ),

    .usr_clk          (w_ddr_dhi_clk            ),
    .rst_usr_n        (w_ddrphy_rst_n           ),
    .ddr_rdy          (w_ddrphy_rdy             ),

    .tl_clk           (tl_clk_user              ),
    .tl_rst_n         (~power_on_rst_dly        ),
    .cfg_cap_bytes    (w_tx_cap_bytes           ),
    .cfg_session_id   (w_tx_session_id          ),
    .cfg_dst_lo       (img_push_dst_lo          ),
    .cfg_dst_hi       (img_push_dst_hi          ),
    .cfg_db_lo        (img_push_db_lo           ),
    .cfg_db_hi        (img_push_db_hi           ),
    .cfg_push_en      (img_push_en              ),
    .cfg_a_enable     (1'b0                     ),   // CTRL[9] a_enable, default 0
    .cfg_trigger_mode (1'b0                     ),   // CTRL[10], default 0 = every good frame
    .cfg_p4_desc_owner(1'b1                     ),   // CTRL[11], default 1 = P4 owns the slot
    .cfg_mode         (3'd0                     ),
    .cfg_prep         (1'b1                     ),   // b18 board-proven A+ prep
    .cfg_pred         (1'b1                     ),   // b18 board-proven A+ pred
    .cfg_phase        (2'd0                     ),
    .link_up          (w_link_up                ),
    .mps_code         (tl_cfg_max_payload_size  ),

    .tx_arm           (w_tx_cmd_arm             ),
    .tx_ack           (w_tx_cmd_ack             ),
    .tx_cancel        (w_tx_cmd_cancel          ),
    .tx_cap_bytes     (w_tx_cap_bytes           ),
    .tx_session_id    (w_tx_session_id          ),
    .tx_ack_seq       (w_tx_ack_seq             ),
    .tx_ack_session   (w_tx_ack_session         ),

    .tl_tx_wait       (tl_tx_wait               ),
    .utx_sel          (utx_sel                  ),
    .utx_req          (utx_req                  ),
    .utx_data         (utx_data                 ),
    .utx_sop          (utx_sop                  ),
    .utx_eop          (utx_eop                  ),
    .utx_valid        (utx_valid                ),

    .o_push_done      (img_push_done            ),
    .o_push_status    (img_push_status          ),
    .o_push_tlp       (img_push_tlp             ),
    .o_push_err       (img_push_err             ),
    .o_tx_status      (w_tx_status              ),
    .o_tx_block_cfg   (w_tx_block_cfg           ),
    .o_p4_st          (p4_st_bus                ),

    .ddr_awaddr       (w_ddr_awaddr             ),
    .ddr_wdata        (w_ddr_wdata              ),
    .ddr_wstrb        (w_ddr_wstrb              ),
    .ddr_awvalid      (w_ddr_awvalid            ),
    .ddr_wvalid       (w_ddr_wvalid             ),
    .ddr_wlast        (w_ddr_wlast              ),
    .ddr_awready      (w_ddr_awready            ),
    .ddr_wready       (w_ddr_wready             ),
    .ddr_bready       (w_ddr_bready             ),

    .ddr_arid         (w_ddr_arid               ),
    .ddr_araddr       (w_ddr_araddr             ),
    .ddr_arlen        (w_ddr_arlen              ),
    .ddr_arsize       (w_ddr_arsize             ),
    .ddr_arburst      (w_ddr_arburst            ),
    .ddr_arvalid      (w_ddr_arvalid            ),
    .ddr_arready      (w_ddr_arready            ),
    .ddr_rid          (w_ddr_rid                ),
    .ddr_rdata        (w_ddr_rdata              ),
    .ddr_rresp        (w_ddr_rresp              ),
    .ddr_rlast        (w_ddr_rlast              ),
    .ddr_rvalid       (w_ddr_rvalid             ),
    .ddr_rready       (w_ddr_rready             ),

    .o_arb_owner      (                         ),
    .o_arb_late       (                         ),
    .o_arb_switch     (                         ),
    .o_p4_desc_active (                         ),
    .o_slot_busy      (                         )
);

// TL transmit port mux: while the pusher owns the port the engine's own
// transmit registers are idle (reference top, unchanged behaviour).
assign tl_tx_data  = utx_sel ? utx_data  : e_tl_tx_data ;
assign tl_tx_sop   = utx_sel ? utx_sop   : e_tl_tx_sop  ;
assign tl_tx_eop   = utx_sel ? utx_eop   : e_tl_tx_eop  ;
assign tl_tx_valid = utx_sel ? utx_valid : e_tl_tx_valid;

endmodule
