`timescale 1ns/1ps
module tb_csi2_raw12_unpack;
  reg clk=0, reset_n=0, enable=1, valid=0, sop=0, eop=0;
  reg [31:0] data=0;
  reg [2:0] nbytes=0;
  wire [47:0] pixels;
  wire [2:0] count;
  wire done, error;
  reg [11:0] expected [0:99999];
  reg [7:0] bytes [0:5999];
  integer written=0, read_index=0, cycles=0, packets=0, seed=91;
  integer k, n;
  csi2_raw12_unpack dut(clk, reset_n, enable, data, nbytes, valid,
                        sop, eop, pixels, count, done, error);
  always #5 clk=~clk;

  task drive(input [31:0] d, input integer nb, input bit v,
             input bit s, input bit e, input bit want_done, input bit want_error);
    integer j;
    begin
      @(negedge clk); data=d; nbytes=nb; valid=v; sop=s; eop=e;
      @(posedge clk); #1; cycles=cycles+1;
      if (done !== want_done || error !== want_error)
        $fatal(1,"RAW12_FAIL flags cycle=%0d done=%b error=%b expected=%b/%b",
               cycles,done,error,want_done,want_error);
      if (count !== 0 && count !== 2 && count !== 4)
        $fatal(1,"RAW12_FAIL count cycle=%0d count=%b",cycles,count);
      if ((!v || !enable || !reset_n) && count !== 0)
        $fatal(1,"RAW12_FAIL stale pixels cycle=%0d",cycles);
      for(j=0;j<count;j=j+1) begin
        if(read_index>=written || pixels[j*12+:12] !== expected[read_index])
          $fatal(1,"RAW12_FAIL pixel index=%0d got=%h want=%h",
                 read_index,pixels[j*12+:12],expected[read_index]);
        read_index=read_index+1;
      end
    end
  endtask

  // Encoder starts from independently chosen pixels, never DUT internals.
  task packet(input integer groups, input integer tail, input integer split_mode,
              input integer base);
    integer i, size, pos, chunk, j, r;
    reg [11:0] a,b;
    reg [31:0] d;
    begin
      for(i=0;i<groups;i=i+1) begin
        a=(base+2*i)&4095; b=4095-((base+2*i+1)&4095);
        expected[written]=a; expected[written+1]=b; written=written+2;
        bytes[3*i]=a>>4; bytes[3*i+1]=b>>4;
        bytes[3*i+2]=((b&15)<<4)|(a&15);
      end
      size=3*groups+tail;
      for(i=3*groups;i<size;i=i+1) bytes[i]=8'hED;
      pos=0;
      while(pos<size) begin
        r=$random(seed)&32'h7fffffff;
        chunk=(split_mode==0)?(1+r%4):split_mode;
        if(chunk>size-pos) chunk=size-pos;
        d=32'hA5A5A5A5;
        for(j=0;j<chunk;j=j+1) d[j*8+:8]=bytes[pos+j];
        drive(d,chunk,1,pos==0,pos+chunk==size,pos+chunk==size,
              (pos+chunk==size)&&(tail!=0));
        pos=pos+chunk;
        if(split_mode==0 && (r%3==0)) drive(32'hdeadbeef,7,0,1,1,0,0);
      end
      if(read_index!=written) $fatal(1,"RAW12_FAIL missing pixels %0d/%0d",read_index,written);
      packets=packets+1;
    end
  endtask

  initial begin
    drive(0,0,0,0,0,0,0); reset_n=1;
    // Fixed asymmetric nibble vector 12 34 56 -> 126,345.
    expected[written]=12'h126; expected[written+1]=12'h345; written=written+2;
    drive(32'hde563412,3,1,1,1,1,0);
    expected[written]=12'habf; expected[written+1]=12'hcde; written=written+2;
    drive(32'h000000ab,1,1,1,0,0,0);
    drive(0,7,0,1,1,0,0);
    drive(32'h0000efcd,2,1,0,1,1,0);
    expected[written]=12'ha01; expected[written+1]=12'hc0b; written=written+2;
    drive(32'h000000a0,1,1,1,0,0,0);
    drive(32'h0000b1c0,2,1,0,1,1,0);
    // Every value 0..4095 appears in both pixel positions; all split sizes.
    for(k=1;k<=4;k=k+1) begin
      packet(1024,0,k,0); packet(1024,0,k,2048);
    end
    for(k=0;k<180;k=k+1) packet(1+(k%31),k%3,0,k*37);
    packet(0,1,1,0); packet(0,2,2,0);
    packet(960,0,4,19); // 2880-byte recording-area row.
    packet(972,0,4,73); // 2916-byte candidate row including margins.
    // Interrupted SOP reports lost packet and starts a fresh one.
    drive(32'h0000bbaa,2,1,1,0,0,0);
    expected[written]=12'h126; expected[written+1]=12'h345; written=written+2;
    drive(32'h00563412,3,1,1,1,1,1);
    // Payload outside packet must not create pixels.
    drive(32'h00563412,3,1,0,1,0,1);
    drive(0,0,1,1,1,0,1); drive(0,5,1,1,1,0,1);
    // Disable and reset during a partial group discard residue.
    drive(32'h0000bbaa,2,1,1,0,0,0);
    enable=0; drive(0,0,0,0,0,0,0);
    enable=1; packet(2,0,3,91);
    drive(32'h000000aa,1,1,1,0,0,0);
    reset_n=0; drive(0,0,0,0,0,0,0);
    reset_n=1; packet(2,0,1,117);
    drive(0,0,0,0,0,0,0);
    if(read_index!=written) $fatal(1,"RAW12_FAIL pending pixels");
    $display("RAW12_PASS pixels=%0d packets=%0d cycles=%0d",read_index,packets,cycles);
    $finish;
  end
  initial begin #10000000; $fatal(1,"RAW12_FAIL watchdog"); end
endmodule
