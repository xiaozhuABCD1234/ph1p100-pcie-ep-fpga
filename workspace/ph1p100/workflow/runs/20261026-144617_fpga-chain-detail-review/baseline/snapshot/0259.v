module prbs_gen_pcie
#(
    parameter  PRBS_PLOY = 15'h6000 ,
    parameter  DAT_W     = 32       ,
    parameter  PRBS_WIDTH= 35       
)
(
    input   clk     ,
    input   rst     ,
    input   ena     ,
    input   i_err   ,
    output  reg [DAT_W -1:0]    o_dat 
);

function [DAT_W + PRBS_WIDTH- 1 :0] PRBS_ANY        ;
input    [PRBS_WIDTH - 1 : 0]           seed        ;
input    [PRBS_WIDTH - 1 : 0]           poly        ;
reg      [PRBS_WIDTH - 1 : 0]           prbs;
integer                             i               ;
begin 
    prbs = seed ;
    for(i = 0 ; i < DAT_W ; i = i + 1)
    begin 
    
        prbs = {prbs[PRBS_WIDTH-2:0],^(prbs & poly)}    ;
        PRBS_ANY[DAT_W + PRBS_WIDTH - 1 - i] = prbs[0]  ;
        PRBS_ANY[PRBS_WIDTH - 1 : 0]         = prbs     ;
    end 

end 
endfunction

reg     [DAT_W - 1      : 0]    data_prbs = 0   ;
reg     [PRBS_WIDTH - 1 : 0]    data_seed = 0   ;
always @( posedge clk or posedge rst )
begin 
    if( rst ) begin 
    data_prbs <= 'd0;
    data_seed <= 'd0;
   end  else if ( ena )
    {data_prbs,data_seed} <=  PRBS_ANY( (data_seed == 0) ? {{(PRBS_WIDTH -1){1'b0}},1'b1}:data_seed,PRBS_PLOY); 
end 

always @( posedge clk or posedge rst )
begin 
    if ( rst )
        o_dat <= 0;
    else if ( ena )
        o_dat <= data_prbs | {{(DAT_W - 1){1'b0}},i_err} ;
end 

endmodule 
