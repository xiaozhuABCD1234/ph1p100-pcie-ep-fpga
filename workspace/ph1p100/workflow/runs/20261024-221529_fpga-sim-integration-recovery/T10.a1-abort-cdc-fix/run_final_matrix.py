import sys,pathlib,concurrent.futures,json
sys.dont_write_bytecode=True
p=pathlib.Path(r'D:\fpga\ph1p100\workflow\runs\20261024-221529_fpga-sim-integration-recovery\T10.a1-abort-cdc-fix');sys.path.insert(0,str(p));import run_abort
jobs=[(n,r+'-final') for r in ('slow','fast') for n in run_abort.CASES if (n,r)!=('sof-abort','fast')]
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
 futures=[pool.submit(run_abort.run,'corrected',n,r) for n,r in jobs]
 results=[f.result() for f in futures]
assert len(results)==19 and all(r['status']=='PASS' for r in results)
(p/'final-matrix-results.json').write_text(json.dumps(dict(status='LOCAL_PASS',final_TB_results=results,fast_sof_final_equivalence=str(p/'corrected/sof-abort-fast-retry/result.json')),indent=2))
print('FINAL_MATRIX_19_PASS + fast SOF corrected retry PASS',flush=True)
