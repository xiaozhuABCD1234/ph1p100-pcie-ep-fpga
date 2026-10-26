


module lane_lvds_10_1 #(
    parameter DEVICE = "PH1P"
    )(
    input wire      I_pixel_clk,
    input wire      I_serial_clk,
    input wire      I_rst,

    input wire[9:0] I_data_in,

    output wire     O_serial_out
);

    // Independent reset release in pixel and serial clock domains.
    reg [2:0] pixel_reset_pipe=3'b111,serial_reset_pipe=3'b111;
    always @(posedge I_pixel_clk or posedge I_rst)
        if(I_rst) pixel_reset_pipe<=3'b111;else pixel_reset_pipe<={pixel_reset_pipe[1:0],1'b0};
    always @(posedge I_serial_clk or posedge I_rst)
        if(I_rst) serial_reset_pipe<=3'b111;else serial_reset_pipe<={serial_reset_pipe[1:0],1'b0};
    wire pixel_rst=pixel_reset_pipe[2],serial_rst=serial_reset_pipe[2];

    reg       S_odd_even;     
    reg       S_odd_even_1d;  
    reg       S_odd_even_2d;  
    reg       S_load_en;      
    reg       S_load_en_1d;   
    reg       S_load_en_2d;   
    reg [9:0] S_shift_data;   
    reg [1:0] S_oddr_data;    
    wire[1:0] S_idata;


    always @(posedge I_pixel_clk or posedge pixel_rst) begin
        if(pixel_rst)
            S_odd_even <= 1'b0;
        else
            S_odd_even <= ~S_odd_even;
    end

    always @(posedge I_serial_clk) begin
        S_odd_even_1d <= S_odd_even;
        S_odd_even_2d <= S_odd_even_1d;
    end

    always @(posedge I_serial_clk) begin
        S_load_en    <= S_odd_even_1d ^ S_odd_even_2d;
        S_load_en_1d <= S_load_en;
        S_load_en_2d <= S_load_en_1d;
    end

    always @(posedge I_serial_clk or posedge serial_rst) begin
        if(serial_rst)
            S_shift_data <= 'd0;
        else
            if(S_load_en_2d)
                S_shift_data <= I_data_in;
            else 
                S_shift_data <= S_shift_data << 2;
    end

    always @(posedge I_serial_clk) begin
        S_oddr_data <= S_shift_data[9:8];
    end
    
    
    assign	S_idata = {S_oddr_data[0] , S_oddr_data[1]};
    

    generate
        if(DEVICE == "EF2")
            begin
                EF2_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "EF3")
            begin
                EF3_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "EF4")
            begin
                EF4_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "SF1")
            begin
                SF1_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "EG")
            begin
                EG_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "PH1A_HR")
            begin
                PH1_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
        else if(DEVICE == "PH1A_HP")
            begin
				PH1_LOGIC_HP_OSERDES #(
				  .ODDRMODE     ( "DDRX1"    )  //  "DDRX1", "DDRX2", "DDRX3P5", "DDRX4", "DDRX5".  IDDR mode select.  
				)u_PH1_LOGIC_HP_OSERDES(                    
				  .sclk         ( I_serial_clk      ), //  1-Bit input.                                
				  .pclk         ( I_serial_clk      ), //  1-Bit input.                                
				  .rst          ( serial_rst        		), //  1-Bit input.
				  .idata        ( {8'b0,S_idata}      		), //  10-Bit input.
				  .odata        ( O_serial_out      )  //  1-Bit output.     
                );
            end			
        else if(DEVICE == "PH1P")
            begin: ph1p_native_x5
                // Wrapper supplies MSB-first words; this primitive shifts bit 0 first.
                wire [9:0] native_data = {I_data_in[0],I_data_in[1],I_data_in[2],I_data_in[3],I_data_in[4],
                                           I_data_in[5],I_data_in[6],I_data_in[7],I_data_in[8],I_data_in[9]};
                PH1P_LOGIC_HR_OSERDES #(.ODDRMODE("DDRX5")) u_PH1P_LOGIC_HR_OSERDES (
                    .sclk(I_serial_clk),.pclk(I_pixel_clk),.rst(pixel_rst),
                    .idata(native_data),.odata(O_serial_out));
            end
        else if(DEVICE == "DR1")
            begin
                DR1_LOGIC_ODDR U_EG4_ODDR(
                    .clk   ( I_serial_clk   ),
                    .rst   ( serial_rst          ),

                    .d1    ( S_oddr_data[0] ),
                    .d0    ( S_oddr_data[1] ),

                    .q     ( O_serial_out   )
                );
            end
    endgenerate
    
endmodule