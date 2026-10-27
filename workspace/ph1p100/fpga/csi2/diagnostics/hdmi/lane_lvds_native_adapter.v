// PH1P-only adapter for isolated diagnostic builds; do not compile with legacy lane module.
module lane_lvds_10_1 #(parameter DEVICE="PH1P")(
    input wire I_pixel_clk,I_serial_clk,I_rst,
    input wire [9:0] I_data_in,
    output wire O_serial_out
);
    lane_lvds_native_x5 native_lane(.I_pixel_clk(I_pixel_clk),.I_serial_clk(I_serial_clk),
        .I_rst(I_rst),.I_data_in(I_data_in),.O_serial_out(O_serial_out));
endmodule
