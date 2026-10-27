import pathlib,shutil,json,hashlib,pymupdf
N=pathlib.Path(__file__).resolve().parents[1];ROOT=next(p for p in N.parents if (p/'AGENTS.md').exists());P=ROOT/'upstream/ph1p100-pcie-ep-fpga';D=N/'attempt5-source-snapshot';D.mkdir(exist_ok=False);entries=[]
for rel in ['rtl/ep_side/img/algo/algo_rowwin3.v','rtl/ep_side/img/algo/img_algo_parallel_top.v','rtl/ep_side/img/algo/rgb8_gray_stream.v','rtl/ep_side/img/algo/bayer_raw10_demosaic4.v','rtl/ep_side/img/algo/PROVENANCE-production.md','tools/pcie_integration/td/00_all_closedloop.tcl']:
    src=(P/rel).resolve();dst=(D/rel).resolve();assert src.is_relative_to(ROOT) and dst.is_relative_to(N);dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst);entries.append({'path':str(src),'snapshot':str(dst),'sha256':hashlib.sha256(src.read_bytes()).hexdigest()})
(D/'index.json').write_text(json.dumps(entries,indent=2),encoding='utf-8')
p=pathlib.Path('D:/anlogic/TD_Release_2026.2/doc/SWUG/SWUG106_HDL_Coding_Synthesis_User_Guide.pdf');doc=pymupdf.open(p)
(N/'native-ram-inference-documentation.json').write_text(json.dumps({'source':str(p),'sha256':hashlib.sha256(p.read_bytes()).hexdigest(),'pages':[{'pdf_page':i+1,'text':doc[i].get_text()} for i in [58,59,60,138,139]],'applied':'ram_style="bram(fast)" to production banks; remove asynchronous reset on read-data-only registers; state/valid reset unchanged; same-clock synchronous read timing retained'},indent=2),encoding='utf-8')
print('ATTEMPT5_SOURCE_SNAPSHOT',len(entries))
