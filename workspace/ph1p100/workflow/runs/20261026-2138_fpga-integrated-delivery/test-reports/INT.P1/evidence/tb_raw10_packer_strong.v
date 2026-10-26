`timescale 1ns/1ps
module tb_raw10_packer_strong;
  reg clk=0,rst_n=0;
  reg s_valid=0; wire s_ready;
  reg [39:0] s_data=0;
  reg s_sof=0,s_eol=0,s_eof=0,s_abort=0;
  reg m_ready=1;
  wire m_valid; wire [39:0] m_data;
  wire m_sof,m_eol,m_eof,m_abort;
  raw10_sample_vector_to_packed dut(.clk(clk),.rst_n(rst_n),.s_valid(s_valid),.s_ready(s_ready),.s_data(s_data),.s_sof(s_sof),.s_eol(s_eol),.s_eof(s_eof),.s_abort(s_abort),.m_ready(m_ready),.m_valid(m_valid),.m_data(m_data),.m_sof(m_sof),.m_eol(m_eol),.m_eof(m_eof),.m_abort(m_abort));
  always #5 clk=~clk;
  integer errors=0,i;
  initial begin
    rst_n=0; #20; rst_n=1;
    s_data = {10'd270,10'd989,10'd1004,10'd163};
    s_valid=1; s_sof=1; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h9343f7fb28) begin $display("DATA MISMATCH t=0 got=%h exp=9343f7fb28", m_data); errors=errors+1; end
    if (m_sof !== 1) begin $display("SOF MISMATCH t=0"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=0"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=0"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd305,10'd385,10'd199,10'd651};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h5f4c6031a2) begin $display("DATA MISMATCH t=1 got=%h exp=5f4c6031a2", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=1"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=1"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=1"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd815,10'd519,10'd108,10'd541};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hf1cb811b87) begin $display("DATA MISMATCH t=2 got=%h exp=f1cb811b87", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=2"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=2"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=2"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd552,10'd153,10'd823,10'd464};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h1c8a26cd74) begin $display("DATA MISMATCH t=3 got=%h exp=1c8a26cd74", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=3"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=3"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=3"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd381,10'd426,10'd409,10'd48};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h645f6a660c) begin $display("DATA MISMATCH t=4 got=%h exp=645f6a660c", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=4"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=4"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=4"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd954,10'd177,10'd337,10'd677};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h95ee2c54a9) begin $display("DATA MISMATCH t=5 got=%h exp=95ee2c54a9", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=5"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=5"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=5"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd952,10'd1023,10'd265,10'd753};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h35eeff42bc) begin $display("DATA MISMATCH t=6 got=%h exp=35eeff42bc", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=6"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=6"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=6"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd228,10'd497,10'd112,10'd30};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h12397c1c07) begin $display("DATA MISMATCH t=7 got=%h exp=12397c1c07", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=7"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=7"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=7"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd730,10'd561,10'd827,10'd473};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h9db68cce76) begin $display("DATA MISMATCH t=8 got=%h exp=9db68cce76", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=8"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=8"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=8"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd223,10'd929,10'd336,10'd86};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hd237e85415) begin $display("DATA MISMATCH t=9 got=%h exp=d237e85415", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=9"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=9"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=9"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd466,10'd429,10'd351,10'd873};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h9d746b57da) begin $display("DATA MISMATCH t=10 got=%h exp=9d746b57da", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=10"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=10"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=10"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd33,10'd425,10'd124,10'd209};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h51086a1f34) begin $display("DATA MISMATCH t=11 got=%h exp=51086a1f34", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=11"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=11"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=11"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd960,10'd503,10'd302,10'd577};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h39f07d4b90) begin $display("DATA MISMATCH t=12 got=%h exp=39f07d4b90", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=12"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=12"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=12"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd74,10'd203,10'd956,10'd693};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hb11232efad) begin $display("DATA MISMATCH t=13 got=%h exp=b11232efad", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=13"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=13"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=13"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd193,10'd772,10'd171,10'd839};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h4f30c12ad1) begin $display("DATA MISMATCH t=14 got=%h exp=4f30c12ad1", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=14"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=14"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=14"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd635,10'd778,10'd569,10'd117};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'he59ec28e1d) begin $display("DATA MISMATCH t=15 got=%h exp=e59ec28e1d", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=15"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=15"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=15"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd92,10'd957,10'd104,10'd1010};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h1217ef1afc) begin $display("DATA MISMATCH t=16 got=%h exp=1217ef1afc", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=16"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=16"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=16"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd217,10'd206,10'd939,10'd105};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h6d3633ea1a) begin $display("DATA MISMATCH t=17 got=%h exp=6d3633ea1a", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=17"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=17"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=17"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd1003,10'd204,10'd160,10'd514};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hc2fa332880) begin $display("DATA MISMATCH t=18 got=%h exp=c2fa332880", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=18"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=18"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=18"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd828,10'd889,10'd290,10'd641};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h19cfde48a0) begin $display("DATA MISMATCH t=19 got=%h exp=19cfde48a0", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=19"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=19"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=19"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd614,10'd80,10'd926,10'd342};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h8a9914e755) begin $display("DATA MISMATCH t=20 got=%h exp=8a9914e755", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=20"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=20"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=20"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd99,10'd926,10'd627,10'd218};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hee18e79c36) begin $display("DATA MISMATCH t=21 got=%h exp=ee18e79c36", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=21"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=21"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=21"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd461,10'd569,10'd1003,10'd287};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h5f738efa47) begin $display("DATA MISMATCH t=22 got=%h exp=5f738efa47", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=22"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=22"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=22"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd16,10'd1001,10'd68,10'd722};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h1204fa11b4) begin $display("DATA MISMATCH t=23 got=%h exp=1204fa11b4", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=23"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=23"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=23"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd708,10'd927,10'd848,10'd799};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h33b1e7d4c7) begin $display("DATA MISMATCH t=24 got=%h exp=33b1e7d4c7", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=24"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=24"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=24"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd442,10'd102,10'd715,10'd276};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hac6e19b245) begin $display("DATA MISMATCH t=25 got=%h exp=ac6e19b245", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=25"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=25"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=25"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd495,10'd724,10'd577,10'd912};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hc47bb590e4) begin $display("DATA MISMATCH t=26 got=%h exp=c47bb590e4", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=26"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=26"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=26"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd81,10'd1009,10'd732,10'd16};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h5014fcb704) begin $display("DATA MISMATCH t=27 got=%h exp=5014fcb704", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=27"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=27"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=27"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd818,10'd553,10'd572,10'd718};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h92cc8a8fb3) begin $display("DATA MISMATCH t=28 got=%h exp=92cc8a8fb3", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=28"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=28"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=28"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd83,10'd844,10'd688,10'd217};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hc114d3ac36) begin $display("DATA MISMATCH t=29 got=%h exp=c114d3ac36", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=29"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=29"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=29"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd816,10'd544,10'd803,10'd768};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h0ccc88c8c0) begin $display("DATA MISMATCH t=30 got=%h exp=ccc88c8c0", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=30"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=30"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=30"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd501,10'd100,10'd366,10'd660};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h487d195ba5) begin $display("DATA MISMATCH t=31 got=%h exp=487d195ba5", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=31"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=31"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=31"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd809,10'd600,10'd817,10'd56};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h44ca96cc0e) begin $display("DATA MISMATCH t=32 got=%h exp=44ca96cc0e", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=32"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=32"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=32"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd457,10'd703,10'd346,10'd656};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h7872af56a4) begin $display("DATA MISMATCH t=33 got=%h exp=7872af56a4", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=33"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=33"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=33"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd656,10'd380,10'd549,10'd223};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h07a45f8937) begin $display("DATA MISMATCH t=34 got=%h exp=7a45f8937", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=34"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=34"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=34"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd273,10'd441,10'd791,10'd7};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h5f446ec501) begin $display("DATA MISMATCH t=35 got=%h exp=5f446ec501", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=35"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=35"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=35"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd690,10'd373,10'd960,10'd565};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h91ac5df08d) begin $display("DATA MISMATCH t=36 got=%h exp=91ac5df08d", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=36"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=36"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=36"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd112,10'd272,10'd829,10'd538};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h061c44cf86) begin $display("DATA MISMATCH t=37 got=%h exp=61c44cf86", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=37"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=37"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=37"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd103,10'd325,10'd873,10'd866};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hd61951dad8) begin $display("DATA MISMATCH t=38 got=%h exp=d61951dad8", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=38"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=38"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=38"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd244,10'd887,10'd571,10'd810};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h3e3ddd8eca) begin $display("DATA MISMATCH t=39 got=%h exp=3e3ddd8eca", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=39"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=39"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=39"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd539,10'd784,10'd301,10'd145};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hc586c44b24) begin $display("DATA MISMATCH t=40 got=%h exp=c586c44b24", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=40"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=40"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=40"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd99,10'd253,10'd424,10'd115};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hd3183f6a1c) begin $display("DATA MISMATCH t=41 got=%h exp=d3183f6a1c", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=41"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=41"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=41"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd806,10'd272,10'd908,10'd736};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h80c944e3b8) begin $display("DATA MISMATCH t=42 got=%h exp=80c944e3b8", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=42"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=42"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=42"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd510,10'd305,10'd250,10'd335};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h9b7f4c3e53) begin $display("DATA MISMATCH t=43 got=%h exp=9b7f4c3e53", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=43"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=43"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=43"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd876,10'd119,10'd241,10'd51};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h37db1d3c0c) begin $display("DATA MISMATCH t=44 got=%h exp=37db1d3c0c", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=44"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=44"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=44"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd1010,10'd862,10'd739,10'd566};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'haefcd7b88d) begin $display("DATA MISMATCH t=45 got=%h exp=aefcd7b88d", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=45"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=45"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=45"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd525,10'd448,10'd482,10'd168};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h488370782a) begin $display("DATA MISMATCH t=46 got=%h exp=488370782a", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=46"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=46"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=46"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd986,10'd946,10'd604,10'd795};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'ha3f6ec97c6) begin $display("DATA MISMATCH t=47 got=%h exp=a3f6ec97c6", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=47"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=47"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=47"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd14,10'd336,10'd899,10'd280};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h8c0354e046) begin $display("DATA MISMATCH t=48 got=%h exp=8c0354e046", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=48"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=48"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=48"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd33,10'd865,10'd576,10'd221};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h5108d89037) begin $display("DATA MISMATCH t=49 got=%h exp=5108d89037", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=49"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=49"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=49"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd635,10'd148,10'd1022,10'd341};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hc99e25ff55) begin $display("DATA MISMATCH t=50 got=%h exp=c99e25ff55", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=50"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=50"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=50"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd8,10'd836,10'd624,10'd213};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h0102d19c35) begin $display("DATA MISMATCH t=51 got=%h exp=102d19c35", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=51"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=51"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=51"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd582,10'd217,10'd680,10'd615};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h939136aa99) begin $display("DATA MISMATCH t=52 got=%h exp=939136aa99", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=52"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=52"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=52"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd409,10'd972,10'd596,10'd702};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h4266f395af) begin $display("DATA MISMATCH t=53 got=%h exp=4266f395af", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=53"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=53"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=53"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd262,10'd148,10'd529,10'd944};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h84412584ec) begin $display("DATA MISMATCH t=54 got=%h exp=84412584ec", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=54"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=54"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=54"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd353,10'd349,10'd603,10'd505};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h5d5857967e) begin $display("DATA MISMATCH t=55 got=%h exp=5d5857967e", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=55"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=55"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=55"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd11,10'd1004,10'd429,10'd642};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hc602fb6ba0) begin $display("DATA MISMATCH t=56 got=%h exp=c602fb6ba0", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=56"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=56"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=56"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd774,10'd158,10'd445,10'd910};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'ha6c1276fe3) begin $display("DATA MISMATCH t=57 got=%h exp=a6c1276fe3", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=57"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=57"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=57"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd498,10'd98,10'd182,10'd506};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'haa7c182d7e) begin $display("DATA MISMATCH t=58 got=%h exp=aa7c182d7e", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=58"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=58"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=58"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd599,10'd577,10'd408,10'd20};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hd095906605) begin $display("DATA MISMATCH t=59 got=%h exp=d095906605", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=59"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=59"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=59"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd888,10'd583,10'd197,10'd454};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h36de913171) begin $display("DATA MISMATCH t=60 got=%h exp=36de913171", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=60"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=60"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=60"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd553,10'd27,10'd759,10'd898};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h7e8a06bde0) begin $display("DATA MISMATCH t=61 got=%h exp=7e8a06bde0", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=61"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=61"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=61"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd636,10'd728,10'd914,10'd573};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h099fb6e48f) begin $display("DATA MISMATCH t=62 got=%h exp=99fb6e48f", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=62"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=62"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=62"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd315,10'd1013,10'd210,10'd703};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hdb4efd34af) begin $display("DATA MISMATCH t=63 got=%h exp=db4efd34af", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=63"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=63"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=63"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd755,10'd156,10'd827,10'd682};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hcebc27ceaa) begin $display("DATA MISMATCH t=64 got=%h exp=cebc27ceaa", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=64"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=64"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=64"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd631,10'd490,10'd264,10'd892};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'he09d7a42df) begin $display("DATA MISMATCH t=65 got=%h exp=e09d7a42df", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=65"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=65"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=65"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd141,10'd453,10'd910,10'd225};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h592371e338) begin $display("DATA MISMATCH t=66 got=%h exp=592371e338", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=66"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=66"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=66"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd972,10'd1020,10'd619,10'd229};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h0df3ff9a39) begin $display("DATA MISMATCH t=67 got=%h exp=df3ff9a39", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=67"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=67"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=67"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd524,10'd663,10'd213,10'd408};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h3483a53566) begin $display("DATA MISMATCH t=68 got=%h exp=3483a53566", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=68"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=68"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=68"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd640,10'd634,10'd388,10'd954};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h22a09e61ee) begin $display("DATA MISMATCH t=69 got=%h exp=22a09e61ee", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=69"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=69"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=69"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd604,10'd464,10'd185,10'd432};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h0497742e6c) begin $display("DATA MISMATCH t=70 got=%h exp=497742e6c", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=70"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=70"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=70"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd297,10'd571,10'd180,10'd672};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h704a8e2da8) begin $display("DATA MISMATCH t=71 got=%h exp=704a8e2da8", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=71"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=71"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=71"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd425,10'd146,10'd75,10'd63};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h6f6a24120f) begin $display("DATA MISMATCH t=72 got=%h exp=6f6a24120f", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=72"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=72"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=72"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd334,10'd344,10'd382,10'd412};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h8853565f67) begin $display("DATA MISMATCH t=73 got=%h exp=8853565f67", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=73"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=73"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=73"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd491,10'd256,10'd899,10'd943};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hcf7a40e0eb) begin $display("DATA MISMATCH t=74 got=%h exp=cf7a40e0eb", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=74"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=74"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=74"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd713,10'd26,10'd758,10'd525};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h69b206bd83) begin $display("DATA MISMATCH t=75 got=%h exp=69b206bd83", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=75"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=75"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=75"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd763,10'd840,10'd995,10'd210};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hcebed2f834) begin $display("DATA MISMATCH t=76 got=%h exp=cebed2f834", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=76"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=76"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=76"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd364,10'd376,10'd92,10'd970};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h025b5e17f2) begin $display("DATA MISMATCH t=77 got=%h exp=25b5e17f2", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=77"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=77"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=77"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd814,10'd294,10'd936,10'd988};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'ha0cb49eaf7) begin $display("DATA MISMATCH t=78 got=%h exp=a0cb49eaf7", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=78"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=78"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=78"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd794,10'd807,10'd192,10'd107};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hb3c6c9301a) begin $display("DATA MISMATCH t=79 got=%h exp=b3c6c9301a", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=79"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=79"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=79"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd728,10'd14,10'd800,10'd231};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h23b603c839) begin $display("DATA MISMATCH t=80 got=%h exp=23b603c839", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=80"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=80"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=80"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd844,10'd107,10'd332,10'd637};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h31d31a539f) begin $display("DATA MISMATCH t=81 got=%h exp=31d31a539f", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=81"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=81"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=81"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd373,10'd475,10'd811,10'd699};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h7f5d76caae) begin $display("DATA MISMATCH t=82 got=%h exp=7f5d76caae", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=82"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=82"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=82"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd65,10'd73,10'd259,10'd192};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h5c10124030) begin $display("DATA MISMATCH t=83 got=%h exp=5c10124030", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=83"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=83"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=83"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd131,10'd136,10'd715,10'd569};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hcd2022b28e) begin $display("DATA MISMATCH t=84 got=%h exp=cd2022b28e", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=84"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=84"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=84"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd375,10'd523,10'd986,10'd914};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hfa5d82f6e4) begin $display("DATA MISMATCH t=85 got=%h exp=fa5d82f6e4", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=85"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=85"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=85"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd485,10'd676,10'd621,10'd968};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h4479a99bf2) begin $display("DATA MISMATCH t=86 got=%h exp=4479a99bf2", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=86"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=86"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=86"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd27,10'd643,10'd358,10'd126};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hfa06a0591f) begin $display("DATA MISMATCH t=87 got=%h exp=fa06a0591f", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=87"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=87"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=87"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd748,10'd486,10'd991,10'd324};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h2cbb79f751) begin $display("DATA MISMATCH t=88 got=%h exp=2cbb79f751", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=88"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=88"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=88"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd813,10'd632,10'd43,10'd999};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h4fcb9e0af9) begin $display("DATA MISMATCH t=89 got=%h exp=4fcb9e0af9", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=89"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=89"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=89"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd10,10'd876,10'd189,10'd778};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h8602db2fc2) begin $display("DATA MISMATCH t=90 got=%h exp=8602db2fc2", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=90"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=90"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=90"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd337,10'd30,10'd433,10'd397};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h6554076c63) begin $display("DATA MISMATCH t=91 got=%h exp=6554076c63", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=91"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=91"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=91"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd148,10'd119,10'd245,10'd114};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h36251d3d1c) begin $display("DATA MISMATCH t=92 got=%h exp=36251d3d1c", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=92"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=92"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=92"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd44,10'd222,10'd379,10'd420};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h2c0b375e69) begin $display("DATA MISMATCH t=93 got=%h exp=2c0b375e69", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=93"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=93"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=93"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd438,10'd272,10'd110,10'd456};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h886d441b72) begin $display("DATA MISMATCH t=94 got=%h exp=886d441b72", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=94"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=94"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=94"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd227,10'd11,10'd596,10'd635};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hf33802959e) begin $display("DATA MISMATCH t=95 got=%h exp=f33802959e", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=95"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=95"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=95"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd0,10'd375,10'd629,10'd830};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h36005d9dcf) begin $display("DATA MISMATCH t=96 got=%h exp=36005d9dcf", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=96"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=96"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=96"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd30,10'd986,10'd203,10'd969};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'had07f632f2) begin $display("DATA MISMATCH t=97 got=%h exp=ad07f632f2", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=97"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=97"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=97"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd236,10'd245,10'd422,10'd1003};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h1b3b3d69fa) begin $display("DATA MISMATCH t=98 got=%h exp=1b3b3d69fa", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=98"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=98"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=98"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd866,10'd666,10'd945,10'd908};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'ha4d8a6ece3) begin $display("DATA MISMATCH t=99 got=%h exp=a4d8a6ece3", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=99"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=99"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=99"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd178,10'd200,10'd533,10'd923};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h872c3285e6) begin $display("DATA MISMATCH t=100 got=%h exp=872c3285e6", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=100"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=100"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=100"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd589,10'd764,10'd231,10'd72};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h4c93bf3912) begin $display("DATA MISMATCH t=101 got=%h exp=4c93bf3912", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=101"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=101"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=101"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd308,10'd796,10'd272,10'd95};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h034dc74417) begin $display("DATA MISMATCH t=102 got=%h exp=34dc74417", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=102"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=102"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=102"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd677,10'd507,10'd813,10'd132};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h74a97ecb21) begin $display("DATA MISMATCH t=103 got=%h exp=74a97ecb21", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=103"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=103"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=103"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd315,10'd903,10'd513,10'd341};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hf54ee18055) begin $display("DATA MISMATCH t=104 got=%h exp=f54ee18055", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=104"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=104"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=104"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd416,10'd829,10'd573,10'd629};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h1568cf8f9d) begin $display("DATA MISMATCH t=105 got=%h exp=1568cf8f9d", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=105"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=105"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=105"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd152,10'd164,10'd367,10'd675};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h0f26295ba8) begin $display("DATA MISMATCH t=106 got=%h exp=f26295ba8", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=106"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=106"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=106"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd729,10'd778,10'd373,10'd281};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h65b6c25d46) begin $display("DATA MISMATCH t=107 got=%h exp=65b6c25d46", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=107"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=107"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=107"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd824,10'd188,10'd1019,10'd815};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h0fce2ffecb) begin $display("DATA MISMATCH t=108 got=%h exp=fce2ffecb", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=108"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=108"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=108"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd278,10'd7,10'd17,10'd981};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hb5450104f5) begin $display("DATA MISMATCH t=109 got=%h exp=b5450104f5", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=109"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=109"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=109"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd235,10'd104,10'd427,10'd935};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hcf3a1a6ae9) begin $display("DATA MISMATCH t=110 got=%h exp=cf3a1a6ae9", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=110"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=110"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=110"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd269,10'd98,10'd733,10'd99};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h674318b718) begin $display("DATA MISMATCH t=111 got=%h exp=674318b718", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=111"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=111"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=111"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd635,10'd1000,10'd728,10'd372};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hc09efab65d) begin $display("DATA MISMATCH t=112 got=%h exp=c09efab65d", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=112"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=112"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=112"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd768,10'd973,10'd224,10'd689};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h11c0f338ac) begin $display("DATA MISMATCH t=113 got=%h exp=11c0f338ac", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=113"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=113"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=113"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd493,10'd605,10'd200,10'd1018};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h527b9732fe) begin $display("DATA MISMATCH t=114 got=%h exp=527b9732fe", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=114"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=114"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=114"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd970,10'd593,10'd164,10'd222};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h92f2942937) begin $display("DATA MISMATCH t=115 got=%h exp=92f2942937", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=115"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=115"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=115"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd850,10'd827,10'd301,10'd144};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hb4d4ce4b24) begin $display("DATA MISMATCH t=116 got=%h exp=b4d4ce4b24", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=116"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=116"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=116"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd15,10'd793,10'd454,10'd52};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hd803c6710d) begin $display("DATA MISMATCH t=117 got=%h exp=d803c6710d", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=117"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=117"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=117"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd392,10'd1017,10'd376,10'd573};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h1162fe5e8f) begin $display("DATA MISMATCH t=118 got=%h exp=1162fe5e8f", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=118"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=118"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=118"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd1000,10'd445,10'd116,10'd302};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h12fa6f1d4b) begin $display("DATA MISMATCH t=119 got=%h exp=12fa6f1d4b", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=119"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=119"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=119"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd274,10'd676,10'd357,10'd79};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h8744a95913) begin $display("DATA MISMATCH t=120 got=%h exp=8744a95913", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=120"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=120"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=120"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd904,10'd202,10'd730,10'd185};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h29e232b62e) begin $display("DATA MISMATCH t=121 got=%h exp=29e232b62e", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=121"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=121"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=121"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd50,10'd984,10'd655,10'd597};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h8d0cf6a395) begin $display("DATA MISMATCH t=122 got=%h exp=8d0cf6a395", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=122"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=122"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=122"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd951,10'd729,10'd117,10'd758};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hd6edb61dbd) begin $display("DATA MISMATCH t=123 got=%h exp=d6edb61dbd", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=123"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=123"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=123"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd377,10'd912,10'd421,10'd800};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h445ee469c8) begin $display("DATA MISMATCH t=124 got=%h exp=445ee469c8", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=124"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=124"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=124"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd908,10'd846,10'd222,10'd849};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h29e3d337d4) begin $display("DATA MISMATCH t=125 got=%h exp=29e3d337d4", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=125"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=125"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=125"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd539,10'd137,10'd225,10'd674};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hd6862238a8) begin $display("DATA MISMATCH t=126 got=%h exp=d6862238a8", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=126"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=126"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=126"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd756,10'd783,10'd599,10'd475};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h3fbdc39576) begin $display("DATA MISMATCH t=127 got=%h exp=3fbdc39576", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=127"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=127"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=127"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd600,10'd214,10'd375,10'd975};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h2f96355df3) begin $display("DATA MISMATCH t=128 got=%h exp=2f96355df3", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=128"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=128"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=128"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd889,10'd578,10'd244,10'd795};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h63de903dc6) begin $display("DATA MISMATCH t=129 got=%h exp=63de903dc6", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=129"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=129"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=129"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd378,10'd167,10'd680,10'd432};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hb05e29aa6c) begin $display("DATA MISMATCH t=130 got=%h exp=b05e29aa6c", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=130"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=130"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=130"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd406,10'd44,10'd158,10'd158};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h8a650b2727) begin $display("DATA MISMATCH t=131 got=%h exp=8a650b2727", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=131"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=131"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=131"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd667,10'd274,10'd299,10'd450};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'heea6444a70) begin $display("DATA MISMATCH t=132 got=%h exp=eea6444a70", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=132"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=132"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=132"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd940,10'd42,10'd364,10'd819};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h23eb0a5bcc) begin $display("DATA MISMATCH t=133 got=%h exp=23eb0a5bcc", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=133"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=133"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=133"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd629,10'd42,10'd920,10'd225};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h619d0ae638) begin $display("DATA MISMATCH t=134 got=%h exp=619d0ae638", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=134"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=134"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=134"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd341,10'd472,10'd916,10'd448};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h405576e570) begin $display("DATA MISMATCH t=135 got=%h exp=405576e570", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=135"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=135"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=135"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd366,10'd679,10'd644,10'd239};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hb35ba9a13b) begin $display("DATA MISMATCH t=136 got=%h exp=b35ba9a13b", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=136"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=136"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=136"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd106,10'd429,10'd533,10'd979};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h971a6b85f4) begin $display("DATA MISMATCH t=137 got=%h exp=971a6b85f4", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=137"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=137"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=137"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd609,10'd119,10'd638,10'd45};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h79981d9f0b) begin $display("DATA MISMATCH t=138 got=%h exp=79981d9f0b", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=138"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=138"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=138"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd216,10'd611,10'd228,10'd571};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h333698398e) begin $display("DATA MISMATCH t=139 got=%h exp=333698398e", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=139"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=139"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=139"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd96,10'd270,10'd529,10'd75};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h2718438412) begin $display("DATA MISMATCH t=140 got=%h exp=2718438412", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=140"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=140"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=140"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd192,10'd615,10'd841,10'd70};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h363099d211) begin $display("DATA MISMATCH t=141 got=%h exp=363099d211", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=141"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=141"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=141"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd117,10'd693,10'd173,10'd1023};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h571dad2bff) begin $display("DATA MISMATCH t=142 got=%h exp=571dad2bff", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=142"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=142"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=142"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd888,10'd645,10'd988,10'd905};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h11dea1f7e2) begin $display("DATA MISMATCH t=143 got=%h exp=11dea1f7e2", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=143"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=143"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=143"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd315,10'd798,10'd1022,10'd335};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'heb4ec7ff53) begin $display("DATA MISMATCH t=144 got=%h exp=eb4ec7ff53", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=144"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=144"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=144"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd703,10'd47,10'd981,10'd101};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hf5af0bf519) begin $display("DATA MISMATCH t=145 got=%h exp=f5af0bf519", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=145"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=145"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=145"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd191,10'd924,10'd246,10'd957};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hc92fe73def) begin $display("DATA MISMATCH t=146 got=%h exp=c92fe73def", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=146"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=146"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=146"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd580,10'd153,10'd209,10'd202};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h1691263432) begin $display("DATA MISMATCH t=147 got=%h exp=1691263432", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=147"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=147"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=147"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd387,10'd37,10'd594,10'd626};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hda6009949c) begin $display("DATA MISMATCH t=148 got=%h exp=da6009949c", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=148"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=148"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=148"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd62,10'd127,10'd479,10'd227};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hbf0f1f7738) begin $display("DATA MISMATCH t=149 got=%h exp=bf0f1f7738", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=149"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=149"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=149"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd340,10'd980,10'd637,10'd473};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h0555f59f76) begin $display("DATA MISMATCH t=150 got=%h exp=555f59f76", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=150"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=150"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=150"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd530,10'd820,10'd746,10'd185};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h8984cdba2e) begin $display("DATA MISMATCH t=151 got=%h exp=8984cdba2e", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=151"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=151"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=151"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd939,10'd540,10'd96,10'd952};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hc0ea8718ee) begin $display("DATA MISMATCH t=152 got=%h exp=c0ea8718ee", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=152"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=152"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=152"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd265,10'd150,10'd436,10'd587};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h6342256d92) begin $display("DATA MISMATCH t=153 got=%h exp=6342256d92", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=153"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=153"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=153"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd529,10'd139,10'd887,10'd150};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h7e8422dd25) begin $display("DATA MISMATCH t=154 got=%h exp=7e8422dd25", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=154"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=154"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=154"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd263,10'd79,10'd831,10'd764};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hfc4113cfbf) begin $display("DATA MISMATCH t=155 got=%h exp=fc4113cfbf", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=155"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=155"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=155"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd243,10'd890,10'd979,10'd65};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hed3cdef410) begin $display("DATA MISMATCH t=156 got=%h exp=ed3cdef410", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=156"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=156"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=156"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd925,10'd315,10'd865,10'd769};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h75e74ed8c0) begin $display("DATA MISMATCH t=157 got=%h exp=75e74ed8c0", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=157"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=157"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=157"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd11,10'd305,10'd310,10'd800};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hd8024c4dc8) begin $display("DATA MISMATCH t=158 got=%h exp=d8024c4dc8", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=158"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=158"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=158"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd507,10'd797,10'd305,10'd206};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hd67ec74c33) begin $display("DATA MISMATCH t=159 got=%h exp=d67ec74c33", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=159"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=159"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=159"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd634,10'd579,10'd262,10'd482};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hba9e904178) begin $display("DATA MISMATCH t=160 got=%h exp=ba9e904178", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=160"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=160"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=160"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd196,10'd375,10'd855,10'd719};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h3f315dd5b3) begin $display("DATA MISMATCH t=161 got=%h exp=3f315dd5b3", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=161"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=161"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=161"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd680,10'd362,10'd513,10'd924};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h24aa5a80e7) begin $display("DATA MISMATCH t=162 got=%h exp=24aa5a80e7", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=162"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=162"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=162"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd432,10'd982,10'd31,10'd704};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h2c6cf507b0) begin $display("DATA MISMATCH t=163 got=%h exp=2c6cf507b0", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=163"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=163"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=163"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd35,10'd878,10'd928,10'd208};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'he008dbe834) begin $display("DATA MISMATCH t=164 got=%h exp=e008dbe834", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=164"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=164"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=164"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd592,10'd796,10'd589,10'd215};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h0794c79335) begin $display("DATA MISMATCH t=165 got=%h exp=794c79335", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=165"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=165"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=165"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd1019,10'd665,10'd162,10'd883};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hdbfea628dc) begin $display("DATA MISMATCH t=166 got=%h exp=dbfea628dc", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=166"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=166"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=166"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd165,10'd568,10'd35,10'd317};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h4d298e084f) begin $display("DATA MISMATCH t=167 got=%h exp=4d298e084f", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=167"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=167"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=167"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd247,10'd632,10'd341,10'd781};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hc53d9e55c3) begin $display("DATA MISMATCH t=168 got=%h exp=c53d9e55c3", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=168"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=168"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=168"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd165,10'd116,10'd186,10'd939};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h4b291d2eea) begin $display("DATA MISMATCH t=169 got=%h exp=4b291d2eea", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=169"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=169"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=169"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd397,10'd664,10'd903,10'd680};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h4c63a6e1aa) begin $display("DATA MISMATCH t=170 got=%h exp=4c63a6e1aa", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=170"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=170"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=170"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd355,10'd258,10'd294,10'd770};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hea584049c0) begin $display("DATA MISMATCH t=171 got=%h exp=ea584049c0", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=171"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=171"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=171"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd587,10'd938,10'd149,10'd413};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'he592ea2567) begin $display("DATA MISMATCH t=172 got=%h exp=e592ea2567", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=172"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=172"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=172"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd861,10'd844,10'd542,10'd579};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h4bd7d38790) begin $display("DATA MISMATCH t=173 got=%h exp=4bd7d38790", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=173"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=173"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=173"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd459,10'd636,10'd262,10'd290};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hca729f4148) begin $display("DATA MISMATCH t=174 got=%h exp=ca729f4148", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=174"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=174"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=174"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd403,10'd26,10'd560,10'd827};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'he364068cce) begin $display("DATA MISMATCH t=175 got=%h exp=e364068cce", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=175"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=175"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=175"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd460,10'd686,10'd771,10'd177};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h2d73abc02c) begin $display("DATA MISMATCH t=176 got=%h exp=2d73abc02c", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=176"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=176"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=176"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd448,10'd787,10'd834,10'd528};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h3870c4d084) begin $display("DATA MISMATCH t=177 got=%h exp=3870c4d084", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=177"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=177"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=177"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd866,10'd544,10'd403,10'd270};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h8ed8886443) begin $display("DATA MISMATCH t=178 got=%h exp=8ed8886443", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=178"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=178"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=178"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd278,10'd564,10'd724,10'd469};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h81458db575) begin $display("DATA MISMATCH t=179 got=%h exp=81458db575", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=179"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=179"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=179"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd224,10'd255,10'd652,10'd389};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h31383fa361) begin $display("DATA MISMATCH t=180 got=%h exp=31383fa361", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=180"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=180"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=180"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd607,10'd751,10'd762,10'd604};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hf897bbbe97) begin $display("DATA MISMATCH t=181 got=%h exp=f897bbbe97", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=181"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=181"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=181"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd811,10'd202,10'd244,10'd203};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'he3ca323d32) begin $display("DATA MISMATCH t=182 got=%h exp=e3ca323d32", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=182"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=182"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=182"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd158,10'd709,10'd32,10'd506};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h9227b1087e) begin $display("DATA MISMATCH t=183 got=%h exp=9227b1087e", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=183"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=183"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=183"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd406,10'd97,10'd278,10'd924};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h98651845e7) begin $display("DATA MISMATCH t=184 got=%h exp=98651845e7", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=184"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=184"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=184"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd666,10'd608,10'd351,10'd805};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h8da69857c9) begin $display("DATA MISMATCH t=185 got=%h exp=8da69857c9", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=185"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=185"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=185"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd920,10'd568,10'd637,10'd196};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h04e68e9f31) begin $display("DATA MISMATCH t=186 got=%h exp=4e68e9f31", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=186"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=186"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=186"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd884,10'd192,10'd640,10'd392};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h00dd30a062) begin $display("DATA MISMATCH t=187 got=%h exp=dd30a062", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=187"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=187"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=187"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd371,10'd411,10'd356,10'd175};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hf35c66592b) begin $display("DATA MISMATCH t=188 got=%h exp=f35c66592b", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=188"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=188"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=188"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd966,10'd829,10'd507,10'd401};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h9df1cf7e64) begin $display("DATA MISMATCH t=189 got=%h exp=9df1cf7e64", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=189"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=189"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=189"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd374,10'd217,10'd53,10'd421};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h955d360d69) begin $display("DATA MISMATCH t=190 got=%h exp=955d360d69", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=190"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=190"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=190"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd315,10'd896,10'd20,10'd765};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hc14ee005bf) begin $display("DATA MISMATCH t=191 got=%h exp=c14ee005bf", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=191"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=191"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=191"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd584,10'd991,10'd866,10'd533};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h3992f7d885) begin $display("DATA MISMATCH t=192 got=%h exp=3992f7d885", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=192"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=192"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=192"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd648,10'd291,10'd131,10'd559};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h3fa248208b) begin $display("DATA MISMATCH t=193 got=%h exp=3fa248208b", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=193"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=193"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=193"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd421,10'd360,10'd217,10'd32};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h44695a3608) begin $display("DATA MISMATCH t=194 got=%h exp=44695a3608", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=194"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=194"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=194"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd319,10'd557,10'd923,10'd356};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hdc4f8be659) begin $display("DATA MISMATCH t=195 got=%h exp=dc4f8be659", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=195"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=195"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=195"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd51,10'd97,10'd630,10'd839};
    s_valid=1; s_sof=0; s_eol=1; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'hdb0c189dd1) begin $display("DATA MISMATCH t=196 got=%h exp=db0c189dd1", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=196"); errors=errors+1; end
    if (m_eol !== 1) begin $display("EOL MISMATCH t=196"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=196"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd21,10'd434,10'd721,10'd326};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h66056cb451) begin $display("DATA MISMATCH t=197 got=%h exp=66056cb451", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=197"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=197"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=197"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd49,10'd833,10'd972,10'd328};
    s_valid=1; s_sof=0; s_eol=0; s_eof=0; s_abort=0; #10;
    if (m_data !== 40'h500cd0f352) begin $display("DATA MISMATCH t=198 got=%h exp=500cd0f352", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=198"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=198"); errors=errors+1; end
    if (m_eof !== 0) begin $display("EOF MISMATCH t=198"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_data = {10'd359,10'd274,10'd975,10'd456};
    s_valid=1; s_sof=0; s_eol=0; s_eof=1; s_abort=0; #10;
    if (m_data !== 40'hec5944f372) begin $display("DATA MISMATCH t=199 got=%h exp=ec5944f372", m_data); errors=errors+1; end
    if (m_sof !== 0) begin $display("SOF MISMATCH t=199"); errors=errors+1; end
    if (m_eol !== 0) begin $display("EOL MISMATCH t=199"); errors=errors+1; end
    if (m_eof !== 1) begin $display("EOF MISMATCH t=199"); errors=errors+1; end
    if (s_ready !== m_ready) begin $display("READY MISMATCH"); errors=errors+1; end
    s_valid=0; s_sof=0; s_eol=0; s_eof=0;
    #20;
    if (errors==0) $display("TB_RAW10_PACK_STRONG PASS");
    else $display("TB_RAW10_PACK_STRONG FAIL errors=%0d", errors);
    $finish;
  end
endmodule