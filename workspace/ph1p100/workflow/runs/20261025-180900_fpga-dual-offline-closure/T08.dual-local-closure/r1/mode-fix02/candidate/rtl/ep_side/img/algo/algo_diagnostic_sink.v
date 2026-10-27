// Only complete EOF publishes CRC/count; an abort discards partial statistics.
module algo_diagnostic_sink (
    input wire clk,rst_n,valid,
    input wire [31:0] data,
    input wire sof,eol,eof,abort,
    output reg terminal,
    output reg [31:0] completed,rejected,last_crc,last_beats
);
    `include "../../ddr/crc32_upd4.v"
    reg [31:0] crc,beats;
    wire [31:0] cnext=crc32_upd4(sof?32'hffffffff:crc,data[7:0],data[15:8],data[23:16],data[31:24]);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin terminal<=0;completed<=0;rejected<=0;last_crc<=0;last_beats<=0;crc<=32'hffffffff;beats<=0;end
        else begin
            terminal<=0;
            if(abort) begin rejected<=rejected+1'b1;terminal<=1;crc<=32'hffffffff;beats<=0;end
            else if(valid) begin
                crc<=cnext;beats<=sof?1:beats+1'b1;
                if(eof) begin completed<=completed+1'b1;last_crc<=~cnext;last_beats<=sof?1:beats+1'b1;terminal<=1;end
            end
        end
    end
endmodule
