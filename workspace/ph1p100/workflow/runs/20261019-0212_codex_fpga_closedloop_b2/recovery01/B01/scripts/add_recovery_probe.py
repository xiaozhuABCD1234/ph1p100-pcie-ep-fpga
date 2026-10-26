"""Apply only after the active attempt has ended; preserve attempt1 inputs."""
import pathlib,hashlib,json
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道');P=ROOT/'upstream/ph1p100-pcie-ep-fpga';REC=pathlib.Path(__file__).resolve().parents[1]
assert (REC/'build/attempt1/execution-result.json').is_file(), 'active build must end first'
backup=REC/'before-recovery-probe';backup.mkdir(exist_ok=False)
paths=[P/'rtl/ep_side/ddr/closedloop/ddr_closedloop_readback.v',P/'sim/tb/tb_closedloop_raw_algo.v']
index=[]
for f in paths:
    assert f.resolve().is_relative_to(P.resolve())
    data=f.read_bytes();(backup/f.name).write_bytes(data);index.append({'path':str(f),'sha256':hashlib.sha256(data).hexdigest()})
(backup/'index.json').write_text(json.dumps(index,indent=2),encoding='utf-8')
f=paths[0];s=f.read_text(encoding='utf-8')
def sub(old,new):
    global s
    assert s.count(old)==1,old
    s=s.replace(old,new)
sub('reg current_slot;','reg current_slot;\n    reg [1:0] recovery_slot;\n    reg current_recovery,recovery_pending;\n    reg [31:0] writer_bad_seen;')
sub('reg [31:0] cl_pass_count,cl_fail_count;','reg [31:0] cl_pass_count,cl_fail_count,cl_recovery_count;')
sub('state<=WAIT; pending<=0; release_slot<=0; current_slot<=0;','state<=WAIT; pending<=0; release_slot<=0; current_slot<=0;\n            recovery_slot<=0;current_recovery<=0;recovery_pending<=0;writer_bad_seen<=0;cl_recovery_count<=0;')
sub('release_slot<=0;\n            if(c_arvalid','release_slot<=0;\n            // Tag the first good publication after one or more writer rejections.\n            // Count recovery only after that exact tuple passes full DDR checking.\n            writer_bad_seen<=writer_bad;\n            if(writer_bad!=writer_bad_seen) recovery_pending<=1;\n            if(c_arvalid')
sub('pending[0]<=1;seq0<=pub_seq;len0<=pub_len;session0<=pub_session;','pending[0]<=1;seq0<=pub_seq;len0<=pub_len;session0<=pub_session;\n                    recovery_slot[0]<=recovery_pending||(writer_bad!=writer_bad_seen);recovery_pending<=0;')
sub('pending[1]<=1;seq1<=pub_seq;len1<=pub_len;session1<=pub_session;','pending[1]<=1;seq1<=pub_seq;len1<=pub_len;session1<=pub_session;\n                    recovery_slot[1]<=recovery_pending||(writer_bad!=writer_bad_seen);recovery_pending<=0;')
sub('current_slot<=!pending[0];','current_slot<=!pending[0];\n                    current_recovery<=pending[0]?recovery_slot[0]:recovery_slot[1];')
sub("cl_flags<={16'd0,c_error,4'd0,c_length,c_payload,c_header,c_magic};","cl_flags<={1'b1,15'd0,c_error,4'd0,c_length,c_payload,c_header,c_magic};")
sub("if(c_error==0 && c_magic&&c_header&&c_payload&&c_length)\n                        cl_pass_count<=cl_pass_count+1'b1;\n                    else cl_fail_count<=cl_fail_count+1'b1;","if(c_error==0 && c_magic&&c_header&&c_payload&&c_length) begin\n                        cl_pass_count<=cl_pass_count+1'b1;\n                        if(current_recovery) cl_recovery_count<=cl_recovery_count+1'b1;\n                    end else begin\n                        cl_fail_count<=cl_fail_count+1'b1;\n                        if(current_recovery) recovery_pending<=1;\n                    end")
sub('pending[current_slot]<=0;state<=WAIT;','pending[current_slot]<=0;recovery_slot[current_slot]<=0;state<=WAIT;')
f.write_text(s,encoding='utf-8')
f=paths[1];s=f.read_text(encoding='utf-8');old='if(errors==0)$display("RAW_ALGO_PASS';assert s.count(old)==1
s=s.replace(old,'chk(reader.cl_recovery_count==2,"post-rejection full-readback recovery counter");\n        chk(reader.cl_flags[31],"completed result snapshot valid bit");\n        '+old)
f.write_text(s,encoding='utf-8')
print('Added exact-publication recovery tags/count and sticky completed snapshot bit; test expects two verified recoveries.')
