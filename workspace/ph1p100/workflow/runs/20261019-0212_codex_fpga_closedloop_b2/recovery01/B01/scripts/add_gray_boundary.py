import pathlib,hashlib,json,re
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道');P=ROOT/'upstream/ph1p100-pcie-ep-fpga';REC=pathlib.Path(__file__).resolve().parents[1]
assert (REC/'build/attempt1/execution-result.json').is_file()
f=(P/'rtl/ep_side/img/algo/img_algo_parallel_top.v').resolve();assert f.is_relative_to(P.resolve())
data=f.read_bytes();back=REC/'before-gray-boundary';back.mkdir(exist_ok=False);(back/f.name).write_bytes(data)
(back/'index.json').write_text(json.dumps({'path':str(f),'sha256':hashlib.sha256(data).hexdigest()},indent=2),encoding='utf-8')
s=data.decode('utf-8');marker='    // ---------------- 4 x rgb8_gray_stream (worktree candidate) ----------------';assert s.count(marker)==1
head,tail=s.split(marker)
for name in ['valid','r','g','b','sof','eol','eof','abort']:
    tail=re.sub(r'\bf_'+name+r'\b','p_'+name,tail)
pipeline='''    // Registered RGB/sideband boundary: the real placed critical path was
    // demosaic row arithmetic -> gray DSP inputs. All lanes and markers share
    // the gray pipeline enable, so a stall holds this complete beat atomically.
    reg p_valid,p_sof,p_eol,p_eof,p_abort;
    reg [31:0] p_r,p_g,p_b;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            p_valid<=0;p_sof<=0;p_eol<=0;p_eof<=0;p_abort<=0;
            p_r<=0;p_g<=0;p_b<=0;
        end else if(f_ready) begin
            p_valid<=f_valid;p_sof<=f_sof;p_eol<=f_eol;p_eof<=f_eof;p_abort<=f_abort;
            p_r<=f_r;p_g<=f_g;p_b<=f_b;
        end
    end

'''
f.write_text(head+pipeline+marker+tail,encoding='utf-8')
print('Inserted shared enabled RGB register before four gray units; arithmetic and clocks unchanged.')
