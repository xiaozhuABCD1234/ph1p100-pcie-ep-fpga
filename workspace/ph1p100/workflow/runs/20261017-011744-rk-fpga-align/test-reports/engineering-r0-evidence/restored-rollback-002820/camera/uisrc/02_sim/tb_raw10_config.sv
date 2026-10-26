`timescale 1ns/1ps
// Real ui_i2c master connected to a pin-level, open-drain sensor model.
module tb_raw10_config;
    parameter CASE_ID=0; // 0: normal; 1: NACK; 2: readback corruption; 3: timeout budget; 4: fixed-bit corruption; 5: production 100 kHz timing.
    reg clk=0,rstn=0;
    always #10 clk=~clk;
    tri1 sda;
    wire scl,done,ae_done,err;
    reg slave_low=0;
    assign sda=slave_low ? 1'b0 : 1'bz;
    ui_cfg_imx415 #(.CLK_DIV(CASE_ID==5 ? 499 : 7),.START_WAIT_CYCLES(32),
                    .STANDBY_WAIT_CYCLES(80),.TRANSACTION_TIMEOUT_CYCLES(CASE_ID==3 ? 32 : (CASE_ID==5 ? 200000 : 20000))) dut
      (.I_clk(clk),.I_rst_n(rstn),.I_cam_mode(2'd1),.I_ae_req(1'b0),.I_ae_data(8'd100),
       .O_cam_scl(scl),.IO_cam_sda(sda),.O_cfg_done(done),.O_ae_cfg_done(ae_done),.O_bus_error(err));
    reg [7:0] mem[0:65535];
    integer state=0,bits=0,bytepos=0,reads=0,writes=0,starts=0;
    reg [7:0] shift=0,addr_hi=0,tx=0;
    reg [15:0] pointer=0;
    reg reading=0;
    time standby_time=0,master_time=0;
    // 0 wait; 1 receive; 2 drive ACK; 3 hold ACK; 4 transmit; 5 release; 6 master ACK.
    always @(negedge sda) if(scl===1'b1 && rstn) begin
        state=1;bits=0;bytepos=0;reading=0;shift=0;starts=starts+1;
    end
    always @(posedge sda) if(scl===1'b1) begin state=0;slave_low=0;end
    always @(posedge scl) if(rstn) begin
        if(state==1) begin
            shift={shift[6:0],sda};
            if(bits==7) begin
                bits=0;state=2;
                case(bytepos)
                    0: begin
                        if(shift!=8'h34 && shift!=8'h35) begin
                            $display("STABLE_FAIL I2C address %h",shift);$finish;
                        end
                        reading=shift[0];
                        if(reading) begin
                            tx=mem[pointer];
                            if(CASE_ID==2 && pointer==16'h3033) tx=tx^8'h01;
                            if(CASE_ID==4 && pointer==16'h300B) tx=tx^8'h80;
                            reads=reads+1;
                        end
                    end
                    1:addr_hi=shift;
                    2:pointer={addr_hi,shift};
                    3:begin
                        mem[pointer]=shift;writes=writes+1;
                        if(pointer==16'h3000 && shift==0) standby_time=$time;
                        if(pointer==16'h3002 && shift==0) begin
                            master_time=$time;
                            if(standby_time==0 || $time-standby_time<1600) begin
                                $display("STABLE_FAIL missing standby wait delta=%0t",$time-standby_time);$finish;
                            end
                        end
                    end
                endcase
                bytepos=bytepos+1;
            end else bits=bits+1;
        end else if(state==4) begin
            if(bits==7) state=5; else bits=bits+1;
        end else if(state==6) begin
            if(sda!==1'b1) begin $display("STABLE_FAIL missing final read NACK");$finish;end
            state=0;
        end
    end
    always @(negedge scl) if(rstn) begin
        case(state)
            2:begin slave_low=(CASE_ID!=1);state=3;end
            3:begin
                slave_low=0;bits=0;shift=0;
                if(reading) begin state=4;slave_low=~tx[7];end else state=1;
            end
            4:slave_low=~tx[7-bits];
            5:begin slave_low=0;state=6;end
        endcase
    end
    // Measure external SCL phases after the first completed data write.
    time last_rise=0,last_fall=0;
    localparam HALF_SCL_NS=(CASE_ID==5 ? 5000 : 80);
    always @(posedge scl) if(rstn && writes>0) begin
        if(last_fall!=0 && $time-last_fall<HALF_SCL_NS) begin
            $display("STABLE_FAIL short SCL low phase %0t",$time-last_fall);$finish;
        end
        last_rise=$time;
    end
    always @(negedge scl) if(rstn && writes>0) begin
        if(last_rise!=0 && $time-last_rise<HALF_SCL_NS) begin
            $display("STABLE_FAIL short SCL high phase %0t",$time-last_rise);$finish;
        end
        last_fall=$time;
    end
    task check_reg(input [15:0] address,input [7:0] expected);
        if(mem[address]!==expected) begin
            $display("STABLE_FAIL register %h expected=%h got=%h",address,expected,mem[address]);$finish;
        end
    endtask
    integer n;
    initial begin
        for(n=0;n<65536;n=n+1) mem[n]=0;
        repeat(12) @(negedge clk);rstn=1;
        if(CASE_ID==0 || CASE_ID==5) begin
            wait(done===1);@(negedge clk);
            if(err || reads!=49 || master_time==0 || writes!=203) begin
                $display("STABLE_FAIL premature done err=%b reads=%0d writes=%0d master=%0t",err,reads,writes,master_time);$finish;
            end
            check_reg('h3008,'h5d);check_reg('h300a,'h42);check_reg('h300b,'ha0);
            check_reg('h3024,'hca);check_reg('h3025,'h08);check_reg('h3028,'h4c);check_reg('h3029,'h04);
            check_reg('h3031,0);check_reg('h3032,0);check_reg('h3033,5);
            check_reg('h3118,'hc6);check_reg('h311a,'he7);check_reg('h4004,'hc0);
            check_reg('h400c,0);check_reg('h4018,'h7f);check_reg('h401e,'hf7);check_reg('h401f,0);
            check_reg('h4026,'h5f);check_reg('h4074,1);
            // No periodic standby writes after initialization.
            repeat(10000) @(negedge clk);
            if(writes!=203 || !done) begin $display("STABLE_FAIL repeated config");$finish;end
        end else begin
            wait(err===1);repeat(3000) @(negedge clk);
            if(!err || done || master_time!=0) begin
                $display("STABLE_FAIL failure must latch and stop err=%b done=%b",err,done);$finish;
            end
        end
        $display("STABLE_PASS CONFIG case=%0d writes=%0d readbacks=%0d starts=%0d",CASE_ID,writes,reads,starts);
        $finish;
    end
    initial begin #150000000;$display("STABLE_FAIL CONFIG timeout case=%0d writes=%0d reads=%0d",CASE_ID,writes,reads);$finish;end
endmodule
