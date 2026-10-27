module prbs_chk_pcie
#(
    parameter  PRBS_PLOY = 15'h6000 ,
    parameter  DAT_W     = 64       ,
    parameter  PRBS_WIDTH= 67       
)
(
    input   rst,
    input   clk                     ,
    input   i_en                    ,
    input   [DAT_W -1:0]    i_dat   ,
    output  o_alm
    
);

function [DAT_W + PRBS_WIDTH- 1 :0] PRBS_ANY        ;
input    [PRBS_WIDTH - 1 : 0]           seed        ;
input    [PRBS_WIDTH - 1 : 0]           poly        ;
reg      [PRBS_WIDTH - 1 : 0]           prbs        ;
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

reg     alm;
wire    [PRBS_WIDTH + DAT_W - 1 : 0]    prbs_temp   ;
reg     [DAT_W - 1              : 0]    data_prbs   =0;
reg     [DAT_W - 1              : 0]    data_dly    =0;
reg     [PRBS_WIDTH - 1         : 0]    data_seed   =0;

assign prbs_temp =  PRBS_ANY( (data_seed == 0) ? {{(PRBS_WIDTH -1){1'b0}},1'b1}:data_seed,PRBS_PLOY); 

always @(posedge clk or posedge rst ) 
begin 
    if ( rst )
    begin
        data_prbs <= 0;
        data_seed <= 0;
        data_dly  <= 0;
    end
    else if( i_en )
    begin    
        data_prbs <= prbs_temp[PRBS_WIDTH + DAT_W - 1 : PRBS_WIDTH];
        data_seed <= {prbs_temp[PRBS_WIDTH - 1 : DAT_W],i_dat};
        data_dly  <= i_dat ;
    end
end 

always @(posedge clk or posedge rst )
begin 
    if ( rst )
        alm <= 1'b0;
    else    
    alm <= ~(data_prbs == data_dly) ;
end 
assign o_alm = alm ;

endmodule 
