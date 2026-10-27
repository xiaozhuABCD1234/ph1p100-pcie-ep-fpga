// Minimal reproduction: one preview bank, synthesis only.
module probe_camera_ram(input wclk, rclk, we, input [17:0] wa, ra,
 input [7:0] din, output reg [7:0] dout);
 (* ram_style = "bram" *) reg [7:0] mem [0:129599];
 always @(posedge wclk) if (we) mem[wa] <= din;
 always @(posedge rclk) dout <= mem[ra];
endmodule
