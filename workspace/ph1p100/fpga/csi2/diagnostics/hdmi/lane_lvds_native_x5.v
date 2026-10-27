// Isolated PH1P experiment. Internal timing closure does not establish board IO rate capability.
// Contract matches lane_lvds_10_1: I_data_in[9] is transmitted first.
module lane_lvds_native_x5(
    input wire I_pixel_clk,I_serial_clk,I_rst,
    input wire [9:0] I_data_in,
    output wire O_serial_out
);
    reg [2:0] reset_pipe=3'b111;
    always @(posedge I_pixel_clk or posedge I_rst)
        if(I_rst) reset_pipe<=3'b111;
        else reset_pipe<={reset_pipe[1:0],1'b0};
    wire [9:0] data_lsb_first;
    genvar b;
    generate for(b=0;b<10;b=b+1) begin: reverse_word
        assign data_lsb_first[b]=I_data_in[9-b];
    end endgenerate
    PH1P_LOGIC_HR_OSERDES #(.ODDRMODE("DDRX5")) serializer
        (.sclk(I_serial_clk),.pclk(I_pixel_clk),.rst(reset_pipe[2]),
         .idata(data_lsb_first),.odata(O_serial_out));
endmodule
