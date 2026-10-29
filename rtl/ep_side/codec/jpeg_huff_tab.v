// jpeg_huff_tab.v — JPEG 规范哈夫曼码表（亮度 DC/AC），ITU T.81 附录 K
//
// 两张 ROM：DC 12 项、AC 256 项（未定义符号填 0/0，运行时会走 EOB）。
// 输出 {code, len}，code 右对齐。
module jpeg_huff_tab (
    input  wire [7:0]  sym,      // DC: 0..11；AC: (run<<4)|cat
    input  wire        is_ac,
    output reg  [15:0] code,
    output reg  [4:0]  len
);
    always @(*) begin
        code = 16'd0; len = 5'd0;
        if (!is_ac) begin
            case (sym)
                8'd0: begin code = 16'h0000; len = 5'd2; end
                8'd1: begin code = 16'h0002; len = 5'd3; end
                8'd2: begin code = 16'h0003; len = 5'd3; end
                8'd3: begin code = 16'h0004; len = 5'd3; end
                8'd4: begin code = 16'h0005; len = 5'd3; end
                8'd5: begin code = 16'h0006; len = 5'd3; end
                8'd6: begin code = 16'h000e; len = 5'd4; end
                8'd7: begin code = 16'h001e; len = 5'd5; end
                8'd8: begin code = 16'h003e; len = 5'd6; end
                8'd9: begin code = 16'h007e; len = 5'd7; end
                8'd10: begin code = 16'h00fe; len = 5'd8; end
                8'd11: begin code = 16'h01fe; len = 5'd9; end
                default: begin code = 16'd0; len = 5'd0; end
            endcase
        end else begin
            case (sym)
                8'd0: begin code = 16'h000a; len = 5'd4; end
                8'd1: begin code = 16'h0000; len = 5'd2; end
                8'd2: begin code = 16'h0001; len = 5'd2; end
                8'd3: begin code = 16'h0004; len = 5'd3; end
                8'd4: begin code = 16'h000b; len = 5'd4; end
                8'd5: begin code = 16'h001a; len = 5'd5; end
                8'd6: begin code = 16'h0078; len = 5'd7; end
                8'd7: begin code = 16'h00f8; len = 5'd8; end
                8'd8: begin code = 16'h03f6; len = 5'd10; end
                8'd9: begin code = 16'hff82; len = 5'd16; end
                8'd10: begin code = 16'hff83; len = 5'd16; end
                8'd17: begin code = 16'h000c; len = 5'd4; end
                8'd18: begin code = 16'h001b; len = 5'd5; end
                8'd19: begin code = 16'h0079; len = 5'd7; end
                8'd20: begin code = 16'h01f6; len = 5'd9; end
                8'd21: begin code = 16'h07f6; len = 5'd11; end
                8'd22: begin code = 16'hff84; len = 5'd16; end
                8'd23: begin code = 16'hff85; len = 5'd16; end
                8'd24: begin code = 16'hff86; len = 5'd16; end
                8'd25: begin code = 16'hff87; len = 5'd16; end
                8'd26: begin code = 16'hff88; len = 5'd16; end
                8'd33: begin code = 16'h001c; len = 5'd5; end
                8'd34: begin code = 16'h00f9; len = 5'd8; end
                8'd35: begin code = 16'h03f7; len = 5'd10; end
                8'd36: begin code = 16'h0ff4; len = 5'd12; end
                8'd37: begin code = 16'hff89; len = 5'd16; end
                8'd38: begin code = 16'hff8a; len = 5'd16; end
                8'd39: begin code = 16'hff8b; len = 5'd16; end
                8'd40: begin code = 16'hff8c; len = 5'd16; end
                8'd41: begin code = 16'hff8d; len = 5'd16; end
                8'd42: begin code = 16'hff8e; len = 5'd16; end
                8'd49: begin code = 16'h003a; len = 5'd6; end
                8'd50: begin code = 16'h01f7; len = 5'd9; end
                8'd51: begin code = 16'h0ff5; len = 5'd12; end
                8'd52: begin code = 16'hff8f; len = 5'd16; end
                8'd53: begin code = 16'hff90; len = 5'd16; end
                8'd54: begin code = 16'hff91; len = 5'd16; end
                8'd55: begin code = 16'hff92; len = 5'd16; end
                8'd56: begin code = 16'hff93; len = 5'd16; end
                8'd57: begin code = 16'hff94; len = 5'd16; end
                8'd58: begin code = 16'hff95; len = 5'd16; end
                8'd65: begin code = 16'h003b; len = 5'd6; end
                8'd66: begin code = 16'h03f8; len = 5'd10; end
                8'd67: begin code = 16'hff96; len = 5'd16; end
                8'd68: begin code = 16'hff97; len = 5'd16; end
                8'd69: begin code = 16'hff98; len = 5'd16; end
                8'd70: begin code = 16'hff99; len = 5'd16; end
                8'd71: begin code = 16'hff9a; len = 5'd16; end
                8'd72: begin code = 16'hff9b; len = 5'd16; end
                8'd73: begin code = 16'hff9c; len = 5'd16; end
                8'd74: begin code = 16'hff9d; len = 5'd16; end
                8'd81: begin code = 16'h007a; len = 5'd7; end
                8'd82: begin code = 16'h07f7; len = 5'd11; end
                8'd83: begin code = 16'hff9e; len = 5'd16; end
                8'd84: begin code = 16'hff9f; len = 5'd16; end
                8'd85: begin code = 16'hffa0; len = 5'd16; end
                8'd86: begin code = 16'hffa1; len = 5'd16; end
                8'd87: begin code = 16'hffa2; len = 5'd16; end
                8'd88: begin code = 16'hffa3; len = 5'd16; end
                8'd89: begin code = 16'hffa4; len = 5'd16; end
                8'd90: begin code = 16'hffa5; len = 5'd16; end
                8'd97: begin code = 16'h007b; len = 5'd7; end
                8'd98: begin code = 16'h0ff6; len = 5'd12; end
                8'd99: begin code = 16'hffa6; len = 5'd16; end
                8'd100: begin code = 16'hffa7; len = 5'd16; end
                8'd101: begin code = 16'hffa8; len = 5'd16; end
                8'd102: begin code = 16'hffa9; len = 5'd16; end
                8'd103: begin code = 16'hffaa; len = 5'd16; end
                8'd104: begin code = 16'hffab; len = 5'd16; end
                8'd105: begin code = 16'hffac; len = 5'd16; end
                8'd106: begin code = 16'hffad; len = 5'd16; end
                8'd113: begin code = 16'h00fa; len = 5'd8; end
                8'd114: begin code = 16'h0ff7; len = 5'd12; end
                8'd115: begin code = 16'hffae; len = 5'd16; end
                8'd116: begin code = 16'hffaf; len = 5'd16; end
                8'd117: begin code = 16'hffb0; len = 5'd16; end
                8'd118: begin code = 16'hffb1; len = 5'd16; end
                8'd119: begin code = 16'hffb2; len = 5'd16; end
                8'd120: begin code = 16'hffb3; len = 5'd16; end
                8'd121: begin code = 16'hffb4; len = 5'd16; end
                8'd122: begin code = 16'hffb5; len = 5'd16; end
                8'd129: begin code = 16'h01f8; len = 5'd9; end
                8'd130: begin code = 16'h7fc0; len = 5'd15; end
                8'd131: begin code = 16'hffb6; len = 5'd16; end
                8'd132: begin code = 16'hffb7; len = 5'd16; end
                8'd133: begin code = 16'hffb8; len = 5'd16; end
                8'd134: begin code = 16'hffb9; len = 5'd16; end
                8'd135: begin code = 16'hffba; len = 5'd16; end
                8'd136: begin code = 16'hffbb; len = 5'd16; end
                8'd137: begin code = 16'hffbc; len = 5'd16; end
                8'd138: begin code = 16'hffbd; len = 5'd16; end
                8'd145: begin code = 16'h01f9; len = 5'd9; end
                8'd146: begin code = 16'hffbe; len = 5'd16; end
                8'd147: begin code = 16'hffbf; len = 5'd16; end
                8'd148: begin code = 16'hffc0; len = 5'd16; end
                8'd149: begin code = 16'hffc1; len = 5'd16; end
                8'd150: begin code = 16'hffc2; len = 5'd16; end
                8'd151: begin code = 16'hffc3; len = 5'd16; end
                8'd152: begin code = 16'hffc4; len = 5'd16; end
                8'd153: begin code = 16'hffc5; len = 5'd16; end
                8'd154: begin code = 16'hffc6; len = 5'd16; end
                8'd161: begin code = 16'h01fa; len = 5'd9; end
                8'd162: begin code = 16'hffc7; len = 5'd16; end
                8'd163: begin code = 16'hffc8; len = 5'd16; end
                8'd164: begin code = 16'hffc9; len = 5'd16; end
                8'd165: begin code = 16'hffca; len = 5'd16; end
                8'd166: begin code = 16'hffcb; len = 5'd16; end
                8'd167: begin code = 16'hffcc; len = 5'd16; end
                8'd168: begin code = 16'hffcd; len = 5'd16; end
                8'd169: begin code = 16'hffce; len = 5'd16; end
                8'd170: begin code = 16'hffcf; len = 5'd16; end
                8'd177: begin code = 16'h03f9; len = 5'd10; end
                8'd178: begin code = 16'hffd0; len = 5'd16; end
                8'd179: begin code = 16'hffd1; len = 5'd16; end
                8'd180: begin code = 16'hffd2; len = 5'd16; end
                8'd181: begin code = 16'hffd3; len = 5'd16; end
                8'd182: begin code = 16'hffd4; len = 5'd16; end
                8'd183: begin code = 16'hffd5; len = 5'd16; end
                8'd184: begin code = 16'hffd6; len = 5'd16; end
                8'd185: begin code = 16'hffd7; len = 5'd16; end
                8'd186: begin code = 16'hffd8; len = 5'd16; end
                8'd193: begin code = 16'h03fa; len = 5'd10; end
                8'd194: begin code = 16'hffd9; len = 5'd16; end
                8'd195: begin code = 16'hffda; len = 5'd16; end
                8'd196: begin code = 16'hffdb; len = 5'd16; end
                8'd197: begin code = 16'hffdc; len = 5'd16; end
                8'd198: begin code = 16'hffdd; len = 5'd16; end
                8'd199: begin code = 16'hffde; len = 5'd16; end
                8'd200: begin code = 16'hffdf; len = 5'd16; end
                8'd201: begin code = 16'hffe0; len = 5'd16; end
                8'd202: begin code = 16'hffe1; len = 5'd16; end
                8'd209: begin code = 16'h07f8; len = 5'd11; end
                8'd210: begin code = 16'hffe2; len = 5'd16; end
                8'd211: begin code = 16'hffe3; len = 5'd16; end
                8'd212: begin code = 16'hffe4; len = 5'd16; end
                8'd213: begin code = 16'hffe5; len = 5'd16; end
                8'd214: begin code = 16'hffe6; len = 5'd16; end
                8'd215: begin code = 16'hffe7; len = 5'd16; end
                8'd216: begin code = 16'hffe8; len = 5'd16; end
                8'd217: begin code = 16'hffe9; len = 5'd16; end
                8'd218: begin code = 16'hffea; len = 5'd16; end
                8'd225: begin code = 16'hffeb; len = 5'd16; end
                8'd226: begin code = 16'hffec; len = 5'd16; end
                8'd227: begin code = 16'hffed; len = 5'd16; end
                8'd228: begin code = 16'hffee; len = 5'd16; end
                8'd229: begin code = 16'hffef; len = 5'd16; end
                8'd230: begin code = 16'hfff0; len = 5'd16; end
                8'd231: begin code = 16'hfff1; len = 5'd16; end
                8'd232: begin code = 16'hfff2; len = 5'd16; end
                8'd233: begin code = 16'hfff3; len = 5'd16; end
                8'd234: begin code = 16'hfff4; len = 5'd16; end
                8'd240: begin code = 16'h07f9; len = 5'd11; end
                8'd241: begin code = 16'hfff5; len = 5'd16; end
                8'd242: begin code = 16'hfff6; len = 5'd16; end
                8'd243: begin code = 16'hfff7; len = 5'd16; end
                8'd244: begin code = 16'hfff8; len = 5'd16; end
                8'd245: begin code = 16'hfff9; len = 5'd16; end
                8'd246: begin code = 16'hfffa; len = 5'd16; end
                8'd247: begin code = 16'hfffb; len = 5'd16; end
                8'd248: begin code = 16'hfffc; len = 5'd16; end
                8'd249: begin code = 16'hfffd; len = 5'd16; end
                8'd250: begin code = 16'hfffe; len = 5'd16; end
                default: begin code = 16'd0; len = 5'd4; end
            endcase
        end
    end
endmodule
