"""One-time, checked-anchor derivation of the RGB565 regression benches."""
from pathlib import Path
import re
import zlib

ROOT=Path(__file__).resolve().parents[2]
def once(s,a,b):
    assert s.count(a)==1,a
    return s.replace(a,b)

s=(ROOT/'fpga/csi2/tb/tb_bayer332_capture.sv').read_text()
s=s[:s.index('`ifdef BASELINE_GRAY')]
s=s.replace('332','565').replace('wire[7:0] data','wire[15:0] data')
s=re.sub(r'\$fatal\(1,([^;]+)\);',r'fail($sformatf(\1));',s)
s=once(s,' integer p;',' task fail(input string message);begin $display("%s",message);$finish;end endtask\n integer p;')
s=once(s,'reg clk=0,rst_n=0,frame=0,line=0,pv=0;',
       'reg clk=0,rst_n=0,frame=0,line=0,pv=0,fe=0,fg=0,abort_frame=0;\n wire[31:0] sa[0:3],sb[0:3],sc[0:3],sd[0:3],sn[0:3],seq[0:3];wire[3:0] stats_valid;')
s=once(s,'.out_valid(valid[phase]),.out_last(last[phase]),.out_data(data[phase]));',
       '.out_valid(valid[phase]),.out_last(last[phase]),.out_data(data[phase]),\n   .frame_end(fe),.frame_good(fg),.frame_abort(abort_frame),\n   .stat_a(sa[phase]),.stat_b(sb[phase]),.stat_c(sc[phase]),.stat_d(sd[phase]),\n   .stat_count(sn[phase]),.stat_sequence(seq[phase]),.stat_valid(stats_valid[phase]));')
start=s.index(' function[7:0] want(');end=s.index(' endfunction',start)+len(' endfunction')
s=s[:start]+''' function[15:0] want(input integer n);
  case(n%8) 0:want=16'hf800;1:want=16'h07e0;2:want=16'h001f;3:want=16'hffff;
   4:want=0;5:want=16'h0400;6:want=16'h03e0;7:want=16'hc110;endcase
 endfunction'''+s[end:]
s=once(s,' task source;', ''' task check_stats;
  integer sums[0:3];integer rr,cc,pp,aa,bb,cv,dv;
  begin
   for(pp=0;pp<4;pp++)begin
    for(cc=0;cc<4;cc++)sums[cc]=0;
    for(rr=0;rr<SH;rr++)for(cc=0;cc<SW;cc++)begin
     case(pp)
      0:begin aa=0;bb=1;cv=2;dv=3;end
      1:begin aa=3;bb=1;cv=2;dv=0;end
      2:begin aa=1;bb=0;cv=3;dv=2;end
      3:begin aa=1;bb=3;cv=0;dv=2;end
     endcase
     sums[0]+=component(cc+rr,aa);sums[1]+=component(cc+rr,bb);
     sums[2]+=component(cc+rr,cv);sums[3]+=component(cc+rr,dv);
    end
    if(!stats_valid[pp]||sn[pp]!=SW*SH||sa[pp]!==sums[0]||sb[pp]!==sums[1]||sc[pp]!==sums[2]||sd[pp]!==sums[3])
     $fatal(1,"RGB565_CAPTURE_FAIL raw statistics phase=%0d got=%0d,%0d,%0d,%0d count=%0d",pp,sa[pp],sb[pp],sc[pp],sd[pp],sn[pp]);
   end
  end
 endtask
 task source;''')
s=once(s,'@(negedge clk);frame=0;idle(3);',
       '@(negedge clk);fe=1;fg=1;@(negedge clk);fe=0;fg=0;idle(2);check_stats();\n   @(negedge clk);frame=0;idle(3);')
s=once(s,'  $display("RGB565_CAPTURE_PASS',
       '  @(negedge clk);abort_frame=1;idle(2);if(stats_valid!==0)$fatal(1,"RGB565_CAPTURE_FAIL abort stats");\n  $display("RGB565_CAPTURE_PASS')
s=once(s,' task source;', ''' reg[31:0] held_a[0:3],held_b[0:3],held_c[0:3],held_d[0:3],held_n[0:3],held_seq[0:3];
 reg[3:0] held_valid;
 task snapshot_stats;
  begin
   held_valid=stats_valid;
   for(integer z=0;z<4;z++)begin
    held_a[z]=sa[z];held_b[z]=sb[z];held_c[z]=sc[z];held_d[z]=sd[z];held_n[z]=sn[z];held_seq[z]=seq[z];
   end
  end
 endtask
 task unchanged_stats;
  begin
   for(integer z=0;z<4;z++)
    if(sa[z]!==held_a[z]||sb[z]!==held_b[z]||sc[z]!==held_c[z]||sd[z]!==held_d[z]||sn[z]!==held_n[z]||seq[z]!==held_seq[z])
     fail("RGB565_CAPTURE_FAIL premature/invalid statistics publication");
  end
 endtask
 task source(input integer verdict);''')
s=once(s,'@(negedge clk);frame=1;line=0;pv=0;idle(3);',
       'snapshot_stats();@(negedge clk);frame=1;line=0;pv=0;idle(3);')
s=once(s,'@(negedge clk);fe=1;fg=1;@(negedge clk);fe=0;fg=0;idle(2);check_stats();',
       '''unchanged_stats();if(stats_valid!==held_valid)fail("RGB565_CAPTURE_FAIL valid changed before FE");
   if(verdict>=0)begin @(negedge clk);fe=1;fg=(verdict==1);@(negedge clk);fe=0;fg=0;idle(2);end
   if(verdict==1)begin
    check_stats();for(integer z=0;z<4;z++)if(seq[z]!=held_seq[z]+1)fail("RGB565_CAPTURE_FAIL accepted sequence");
   end else begin unchanged_stats();if(verdict==0&&stats_valid!==0)fail("RGB565_CAPTURE_FAIL bad FE valid");end''')
s=s.replace('source();','source(1);')
s=once(s,'source(1);source(1);','source(1);source(1);source(0);source(-1);')
s=once(s,'  @(negedge clk);abort_frame=1;idle(2);', '''  // A nominally good but early FE cannot publish a partial preview.
  snapshot_stats();@(negedge clk);frame=1;idle(3);drive_row(0);drive_row(1);idle(3);
  @(negedge clk);fe=1;fg=1;@(negedge clk);fe=0;fg=0;idle(2);
  unchanged_stats();if(stats_valid!==0)fail("RGB565_CAPTURE_FAIL early FE valid");
  @(negedge clk);abort_frame=1;idle(2);unchanged_stats();''')
s=s.replace('complete_frames=3','complete_previews=5 good_frames=3 bad_missing_early_FE_checked=1')
s=re.sub(r'\$fatal\(1,([^;]+)\);',r'fail($sformatf(\1));',s)
(ROOT/'fpga/csi2/tb/tb_bayer565_capture.sv').write_bytes(s.encode())

s=(ROOT/'fpga/csi2/tb/tb_ddr_display.sv').read_text()
s=s.replace('tb_ddr_display','tb_rgb565_ddr_display').replace('FRAME_BYTES=SW*SH,','FRAME_BYTES=SW*SH*2,')
s=s.replace('reg[7:0] pixel=0;','reg[15:0] pixel=0;').replace('reg[7:0] expected;','reg[15:0] expected;')
s=s.replace('camera_ddr_display_guarded','camera_rgb565_display_guarded')
s=s.replace('function[7:0] value','function[15:0] value')
s=s.replace('value=(id*19+offset*3+(offset>>8)*29+(offset>>16)*101)&255;',
 '''// Distinct R/G/B fields and high offset dependence reveal byte swaps and aliasing.
  value=((id*7919+offset*131+(offset>>8)*997+(offset>>16)*1237)^16'ha639)&65535;''')
s=s.replace('k<FRAME_BYTES;k=k+1','k<SW*SH;k=k+1').replace('k==FRAME_BYTES-1','k==SW*SH-1')
s=s.replace('rgb!=={expected,expected,expected}','rgb!==color_expected(expected)')
s=once(s,' task show_frame(',''' function[23:0] color_expected(input[15:0] code);
  integer r,g,b;
  begin
   r=(code/2048)*8+(code/8192);
   g=((code/32)%64)*4+((code/512)%4);
   b=(code%32)*8+((code/4)%8);
   color_expected={r[7:0],g[7:0],b[7:0]};
  end
 endfunction
 task show_frame(''')
s=s.replace('DDR_DISPLAY_','RGB565_DDR_')
s=once(s,' task send_frame(input integer id);begin',
       ' task send_frame(input integer id);begin\n  expected_publish_crc=golden_crc[id];')
s=once(s,' integer cycles=', ' reg[31:0] golden_crc[1:6];reg[31:0] expected_publish_crc;\n initial $readmemh("golden_crc.txt",golden_crc);\n integer cycles=')
s=once(s,'memory[paxi_awaddr>>3]<=paxi_wdata;',
       '''if((paxi_awaddr>>3)%WORDS==WORDS-1)begin
     if(paxi_wdata[31:0]!==32'h43524331||paxi_wdata[95:64]!==expected_publish_crc||paxi_wdata[127:96]!=FRAME_BYTES)
      fail("independent zlib footer CRC/length");
    end
    memory[paxi_awaddr>>3]<=paxi_wdata;''')
(ROOT/'fpga/csi2/tb/tb_rgb565_ddr_display.sv').write_bytes(s.encode())

s=(ROOT/'fpga/csi2/tb/tb_guarded_pack.sv').read_text()
start=s.index('`ifdef BASELINE');end=s.index('`endif',start)+len('`endif')
s=s[:start]+' rgb565_frame_pack_guarded #(.FRAME_BYTES(256)) dut(.*);'+s[end:]
s=s.replace('tb_guarded_pack','tb_rgb565_guarded_pack').replace('reg[7:0] pixel','reg[15:0] pixel')
s=s.replace('j<32;j=j+1','j<16;j=j+1').replace('out_data[j*8+:8]','out_data[j*16+:16]')
s=s.replace('((words*32+j+(words*32+j)/128*17)&255)','code(words*16+j)')
s=s.replace('(i+i/128*17)&255','code(i)').replace('pixels(256)','pixels(128)').replace('i<256','i<128').replace('i==255','i==127')
s=s.replace('INTEGRITY_','RGB565_PACK_')
s=once(s,' task tick;', ''' function[15:0] code(input integer n);
  code=(n*257+(n/16)*1031+16'h1234)&65535;
 endfunction
 task tick;''')
raw=b''.join(((n*257+(n//16)*1031+0x1234)&65535).to_bytes(2,'little') for n in range(128))
s=once(s,"32'h1628db46",f"32'h{zlib.crc32(raw):08x}")
(ROOT/'fpga/csi2/tb/tb_rgb565_guarded_pack.sv').write_bytes(s.encode())
