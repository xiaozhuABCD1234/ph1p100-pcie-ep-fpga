import pathlib
ROOT=pathlib.Path('C:/Users/czz/OneDrive/桌面/实验室/竞赛/嵌入式/FPGA创新设计赛道');RUN=ROOT/'workflow/runs/20261019-0212_codex_fpga_closedloop_b2';REC=pathlib.Path(__file__).resolve().parents[1]
s=(RUN/'scripts/run_algo_g1.py').read_text(encoding='utf-8')
old='ROOT = Path(__file__).resolve().parents[4]';assert s.count(old)==1
s=s.replace(old,'ROOT = Path('+repr(str(ROOT))+')')
old='OUTROOT = Path(__file__).resolve().parents[1] / "algo-integration/g1"';assert s.count(old)==1
s=s.replace(old,'OUTROOT = Path(__file__).resolve().parents[1] / "algo-g1"')
(REC/'scripts/run_algo_g1.py').write_text(s,encoding='utf-8')
